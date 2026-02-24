import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../../core/constants/theme_constants.dart';
import '../../../../core/services/recent_photos_service.dart';
import '../../../../core/services/saved_outfits_service.dart';
import '../../../browse/presentation/widgets/share_outfit_dialog.dart';

/// Helper widget that loads image from URL or local file path
class SmartImage extends StatelessWidget {
  final String path;
  final BoxFit fit;
  final double? width;
  final double? height;

  const SmartImage({
    super.key,
    required this.path,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return Image.network(
        path,
        fit: fit,
        width: width,
        height: height,
        errorBuilder: (_, __, ___) => _buildPlaceholder(),
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Center(
            child: CircularProgressIndicator(
              strokeWidth: 2,
              value: loadingProgress.expectedTotalBytes != null
                  ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                  : null,
            ),
          );
        },
      );
    } else {
      return Image.file(
        File(path),
        fit: fit,
        width: width,
        height: height,
        errorBuilder: (_, __, ___) => _buildPlaceholder(),
      );
    }
  }

  Widget _buildPlaceholder() {
    return Container(
      color: const Color(0xFFEDE8E3),
      child: const Center(
        child: Icon(
          Icons.broken_image_outlined,
          color: Color(0xFF8B7355),
        ),
      ),
    );
  }
}

class WardrobeScreen extends StatefulWidget {
  const WardrobeScreen({super.key});

  @override
  State<WardrobeScreen> createState() => _WardrobeScreenState();
}

class _WardrobeScreenState extends State<WardrobeScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _unsyncedCount = 0;
  bool _isSyncing = false;
  bool _autoSyncEnabled = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadUnsyncedCount();
  }

  Future<void> _loadUnsyncedCount() async {
    final service = await SavedOutfitsService.getInstance();
    final count = await service.getUnsyncedCount();
    final autoSync = await SavedOutfitsService.isAutoSyncEnabled();
    if (mounted) {
      setState(() {
        _unsyncedCount = count;
        _autoSyncEnabled = autoSync;
      });
    }
  }

  Future<void> _toggleAutoSync() async {
    final newValue = !_autoSyncEnabled;
    await SavedOutfitsService.setAutoSyncEnabled(newValue);
    setState(() => _autoSyncEnabled = newValue);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(newValue ? 'Auto-sync enabled' : 'Auto-sync disabled'),
        backgroundColor: newValue ? const Color(0xFF10B981) : const Color(0xFF6B7280),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  Future<void> _handleSyncTap() async {
    await _toggleAutoSync();

    // If turning on auto-sync, sync any unsynced items
    if (_autoSyncEnabled && _unsyncedCount > 0) {
      await _performSync();
    }
  }

  Future<bool?> _showSyncPermissionDialog() async {
    bool autoSync = false;

    return showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF667EEA).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.cloud_upload_outlined, color: Color(0xFF667EEA)),
              ),
              const SizedBox(width: 12),
              const Text('Sync to Cloud', style: TextStyle(fontSize: 18)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Syncing backs up your outfits and articles to the cloud, so you can access them on any device.',
                style: TextStyle(color: Color(0xFF6B7280), height: 1.4),
              ),
              const SizedBox(height: 20),
              GestureDetector(
                onTap: () => setDialogState(() => autoSync = !autoSync),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        autoSync ? Icons.check_box : Icons.check_box_outline_blank,
                        color: autoSync ? const Color(0xFF667EEA) : const Color(0xFF9CA3AF),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Auto-sync', style: TextStyle(fontWeight: FontWeight.w600)),
                            Text(
                              'Automatically sync when saving',
                              style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Color(0xFF6B7280))),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, autoSync),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF667EEA),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Sync Now'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _performSync() async {
    setState(() => _isSyncing = true);

    try {
      final service = await SavedOutfitsService.getInstance();
      final synced = await service.syncToCloud();

      if (mounted) {
        setState(() {
          _isSyncing = false;
          _unsyncedCount = 0;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(synced > 0 ? 'Synced $synced items to cloud!' : 'Everything is up to date'),
            backgroundColor: const Color(0xFF10B981),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSyncing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sync failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Custom header
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 4),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'My Wardrobe',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.5,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Your saved styles & outfits',
                          style: TextStyle(
                            fontSize: 14,
                            color: Color(0xFF6B7280),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Auto-sync toggle with slider
                  Container(
                    padding: const EdgeInsets.only(left: 8),
                    decoration: BoxDecoration(
                      color: _autoSyncEnabled
                          ? const Color(0xFF10B981).withOpacity(0.1)
                          : const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.cloud_outlined,
                          color: _autoSyncEnabled
                              ? const Color(0xFF10B981)
                              : const Color(0xFF9CA3AF),
                          size: 18,
                        ),
                        const SizedBox(width: 4),
                        if (_isSyncing)
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF10B981),
                              ),
                            ),
                          )
                        else
                          Transform.scale(
                            scale: 0.8,
                            child: Switch(
                              value: _autoSyncEnabled,
                              onChanged: (value) => _handleSyncTap(),
                              activeColor: const Color(0xFF10B981),
                              activeTrackColor: const Color(0xFF10B981).withOpacity(0.3),
                              inactiveThumbColor: const Color(0xFF9CA3AF),
                              inactiveTrackColor: const Color(0xFFE5E7EB),
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Custom tab bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TabBar(
                  controller: _tabController,
                  indicator: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: Colors.transparent,
                  labelColor: const Color(0xFF1F2937),
                  unselectedLabelColor: const Color(0xFF6B7280),
                  labelStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  unselectedLabelStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  tabs: const [
                    Tab(text: 'Outfits'),
                    Tab(text: 'Articles'),
                    Tab(text: 'Selfies'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Tab content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: const [
                  _CreatedOutfitsTab(),
                  _MyArticlesTab(),
                  _MySelfiesTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CreatedOutfitsTab extends StatefulWidget {
  const _CreatedOutfitsTab();

  @override
  State<_CreatedOutfitsTab> createState() => _CreatedOutfitsTabState();
}

class _CreatedOutfitsTabState extends State<_CreatedOutfitsTab> {
  List<SavedOutfit>? _outfits;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadOutfits();
  }

  Future<void> _loadOutfits() async {
    final service = await SavedOutfitsService.getInstance();
    final outfits = await service.getSavedOutfits();
    if (mounted) {
      setState(() {
        _outfits = outfits;
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleFavorite(SavedOutfit outfit) async {
    final service = await SavedOutfitsService.getInstance();
    await service.toggleOutfitFavorite(outfit.id);
    _loadOutfits();
  }

  Future<void> _saveToGallery(SavedOutfit outfit) async {
    try {
      // Request permission - use photosAddOnly for iOS 14+ (write-only access)
      var status = await Permission.photosAddOnly.request();
      if (!status.isGranted) {
        // Fallback to full photos permission
        status = await Permission.photos.request();
      }
      if (!status.isGranted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Photo library permission required'),
              backgroundColor: Colors.orange,
              action: SnackBarAction(
                label: 'Settings',
                textColor: Colors.white,
                onPressed: () => openAppSettings(),
              ),
            ),
          );
        }
        return;
      }

      final file = File(outfit.imagePath);
      final bytes = await file.readAsBytes();
      final result = await ImageGallerySaver.saveImage(
        bytes,
        quality: 100,
        name: 'wardrobe_outfit_${outfit.id}',
      );

      if (mounted) {
        if (result['isSuccess'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Saved to camera roll!'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to save image'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _shareOutfit(SavedOutfit outfit) {
    ShareOutfitDialog.show(context, outfit.imagePath);
  }

  Future<void> _deleteOutfit(SavedOutfit outfit) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Outfit'),
        content: const Text('Are you sure you want to delete this outfit?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final service = await SavedOutfitsService.getInstance();
      await service.deleteOutfit(outfit.id);
      _loadOutfits();
    }
  }

  Future<void> _syncOutfit(SavedOutfit outfit) async {
    final service = await SavedOutfitsService.getInstance();
    final success = await service.syncSingleOutfit(outfit.id);
    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Outfit synced to cloud!'),
            backgroundColor: Color(0xFF10B981),
            duration: Duration(seconds: 1),
          ),
        );
        _loadOutfits();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to sync outfit'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_outfits == null || _outfits!.isEmpty) {
      return _buildEmptyState(
        icon: Icons.collections_outlined,
        title: 'No Created Outfits',
        subtitle: 'Your AI-generated outfits will appear here',
      );
    }

    return RefreshIndicator(
      onRefresh: _loadOutfits,
      child: GridView.builder(
        padding: const EdgeInsets.all(ThemeConstants.spacingMedium),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: ThemeConstants.spacingMedium,
          mainAxisSpacing: ThemeConstants.spacingMedium,
          childAspectRatio: 0.75,
        ),
        itemCount: _outfits!.length,
        itemBuilder: (context, index) {
          final outfit = _outfits![index];
          return _OutfitCard(
            outfit: outfit,
            onTap: () => _showOutfitDetail(outfit),
            onDelete: () => _deleteOutfit(outfit),
            onFavorite: () => _toggleFavorite(outfit),
            onSave: () => _saveToGallery(outfit),
            onShare: () => _shareOutfit(outfit),
            onSync: () => _syncOutfit(outfit),
          );
        },
      ),
    );
  }

  void _showOutfitDetail(SavedOutfit outfit) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.75,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                  child: SmartImage(
                    path: outfit.imagePath,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(ThemeConstants.spacingMedium),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (outfit.description != null)
                      Text(
                        outfit.description!,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    const SizedBox(height: ThemeConstants.spacingSmall),
                    Text(
                      'Created ${_formatDate(outfit.createdAt)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: ThemeConstants.textSecondaryColor,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inDays == 0) return 'today';
    if (diff.inDays == 1) return 'yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return '${date.month}/${date.day}/${date.year}';
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(ThemeConstants.spacingXLarge),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: ThemeConstants.primaryColor.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 64,
                color: ThemeConstants.primaryColor.withOpacity(0.5),
              ),
            ),
            const SizedBox(height: ThemeConstants.spacingLarge),
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: ThemeConstants.spacingSmall),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 15,
                color: ThemeConstants.textSecondaryColor,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _OutfitCard extends StatelessWidget {
  final SavedOutfit outfit;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onFavorite;
  final VoidCallback onSave;
  final VoidCallback onShare;
  final VoidCallback? onSync;

  const _OutfitCard({
    required this.outfit,
    required this.onTap,
    required this.onDelete,
    required this.onFavorite,
    required this.onSave,
    required this.onShare,
    this.onSync,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.white,
            width: 3,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF667EEA).withOpacity(0.15),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(13),
          child: Stack(
            fit: StackFit.expand,
            children: [
              SmartImage(
                path: outfit.imagePath,
                fit: BoxFit.cover,
              ),
              // Gradient overlay at top
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 50,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withOpacity(0.4),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              // Top row: delete and favorite
              Positioned(
                top: 8,
                left: 8,
                child: GestureDetector(
                  onTap: onDelete,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.9),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.delete_outline_rounded,
                      color: Color(0xFFEF4444),
                      size: 18,
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: GestureDetector(
                  onTap: onFavorite,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.9),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      outfit.isFavorite ? Icons.favorite : Icons.favorite_border,
                      color: outfit.isFavorite ? const Color(0xFFEF4444) : const Color(0xFF9CA3AF),
                      size: 18,
                    ),
                  ),
                ),
              ),
              // Cloud sync indicator
              Positioned(
                top: 8,
                right: 44,
                child: GestureDetector(
                  onTap: outfit.isSynced ? null : onSync,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.9),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      outfit.isSynced ? Icons.cloud_done : Icons.cloud_off,
                      color: outfit.isSynced ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                      size: 16,
                    ),
                  ),
                ),
              ),
              // Bottom info
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withOpacity(0.6),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.auto_awesome,
                        color: Colors.white,
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'AI Created',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.9),
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: onShare,
                        child: const Icon(
                          Icons.share_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: onSave,
                        child: const Icon(
                          Icons.download_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MyArticlesTab extends StatefulWidget {
  const _MyArticlesTab();

  @override
  State<_MyArticlesTab> createState() => _MyArticlesTabState();
}

class _MyArticlesTabState extends State<_MyArticlesTab> {
  String _selectedCategory = 'all';
  List<SavedArticle>? _articles;
  bool _isLoading = true;
  final _imagePicker = ImagePicker();

  final List<Map<String, dynamic>> _categories = [
    {'id': 'all', 'label': 'All', 'icon': Icons.grid_view},
    {'id': 'tops', 'label': 'Tops', 'icon': Icons.dry_cleaning},
    {'id': 'bottoms', 'label': 'Bottoms', 'icon': Icons.straighten},
    {'id': 'dresses', 'label': 'Dresses', 'icon': Icons.checkroom},
  ];

  @override
  void initState() {
    super.initState();
    _loadArticles();
  }

  Future<void> _loadArticles() async {
    final service = await SavedOutfitsService.getInstance();
    final articles = await service.getSavedArticles(
      category: _selectedCategory == 'all' ? null : _selectedCategory,
    );
    if (mounted) {
      setState(() {
        _articles = articles;
        _isLoading = false;
      });
    }
  }

  Future<void> _addArticle() async {
    final category = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(ThemeConstants.spacingMedium),
              child: Text(
                'Select Category',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.dry_cleaning),
              title: const Text('Top'),
              onTap: () => Navigator.pop(context, 'tops'),
            ),
            ListTile(
              leading: const Icon(Icons.straighten),
              title: const Text('Bottom'),
              onTap: () => Navigator.pop(context, 'bottoms'),
            ),
            ListTile(
              leading: const Icon(Icons.checkroom),
              title: const Text('Dress'),
              onTap: () => Navigator.pop(context, 'dresses'),
            ),
            const SizedBox(height: ThemeConstants.spacingMedium),
          ],
        ),
      ),
    );

    if (category == null || !mounted) return;

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Take Photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from Gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            const SizedBox(height: ThemeConstants.spacingMedium),
          ],
        ),
      ),
    );

    if (source == null || !mounted) return;

    try {
      final pickedFile = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (pickedFile == null) return;

      final service = await SavedOutfitsService.getInstance();
      await service.saveArticleFromFile(
        File(pickedFile.path),
        category: category,
      );

      _loadArticles();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Article saved!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save article: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _toggleArticleFavorite(SavedArticle article) async {
    final service = await SavedOutfitsService.getInstance();
    await service.toggleArticleFavorite(article.id);
    _loadArticles();
  }

  Future<void> _deleteArticle(SavedArticle article) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Article'),
        content: const Text('Are you sure you want to delete this article?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final service = await SavedOutfitsService.getInstance();
      await service.deleteArticle(article.id);
      _loadArticles();
    }
  }

  Future<void> _syncArticle(SavedArticle article) async {
    final service = await SavedOutfitsService.getInstance();
    final success = await service.syncSingleArticle(article.id);
    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Article synced to cloud!'),
            backgroundColor: Color(0xFF10B981),
            duration: Duration(seconds: 1),
          ),
        );
        _loadArticles();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to sync article'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Column(
          children: [
            // Category filter
            Container(
              height: 44,
              margin: const EdgeInsets.symmetric(vertical: 8),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _categories.length,
                itemBuilder: (context, index) {
                  final category = _categories[index];
                  final isSelected = _selectedCategory == category['id'];
                  return Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedCategory = category['id'] as String;
                          _isLoading = true;
                        });
                        _loadArticles();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          gradient: isSelected
                              ? const LinearGradient(
                                  colors: [Color(0xFF11998E), Color(0xFF38EF7D)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                )
                              : null,
                          color: isSelected ? null : const Color(0xFFF3F4F6),
                          borderRadius: BorderRadius.circular(20),
                          border: isSelected
                              ? null
                              : Border.all(color: const Color(0xFFE5E7EB)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              category['icon'] as IconData,
                              size: 16,
                              color: isSelected ? Colors.white : const Color(0xFF6B7280),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              category['label'] as String,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: isSelected ? Colors.white : const Color(0xFF374151),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            // Articles grid
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _articles == null || _articles!.isEmpty
                      ? _buildEmptyState()
                      : RefreshIndicator(
                          onRefresh: _loadArticles,
                          child: GridView.builder(
                            padding: const EdgeInsets.all(ThemeConstants.spacingMedium),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              crossAxisSpacing: ThemeConstants.spacingSmall,
                              mainAxisSpacing: ThemeConstants.spacingSmall,
                              childAspectRatio: 0.75,
                            ),
                            itemCount: _articles!.length,
                            itemBuilder: (context, index) {
                              final article = _articles![index];
                              return _ArticleCard(
                                article: article,
                                onTap: () => _showArticleDetail(article),
                                onDelete: () => _deleteArticle(article),
                                onFavorite: () => _toggleArticleFavorite(article),
                                onSync: () => _syncArticle(article),
                              );
                            },
                          ),
                        ),
            ),
          ],
        ),
        // Add button
        Positioned(
          right: 16,
          bottom: 16,
          child: GestureDetector(
            onTap: _addArticle,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF11998E), Color(0xFF38EF7D)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF11998E).withOpacity(0.4),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(Icons.add_rounded, color: Colors.white, size: 26),
            ),
          ),
        ),
      ],
    );
  }

  void _showArticleDetail(SavedArticle article) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              child: SmartImage(
                path: article.imagePath,
                fit: BoxFit.cover,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(ThemeConstants.spacingMedium),
              child: Column(
                children: [
                  Text(
                    _getCategoryLabel(article.category),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: ThemeConstants.spacingSmall),
                  Text(
                    'Saved ${_formatDate(article.createdAt)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: ThemeConstants.textSecondaryColor,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getCategoryLabel(String category) {
    switch (category) {
      case 'tops':
        return 'Top';
      case 'bottoms':
        return 'Bottom';
      case 'dresses':
        return 'Dress';
      default:
        return category;
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inDays == 0) return 'today';
    if (diff.inDays == 1) return 'yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return '${date.month}/${date.day}/${date.year}';
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(ThemeConstants.spacingXLarge),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: ThemeConstants.primaryColor.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.checkroom_outlined,
                size: 64,
                color: ThemeConstants.primaryColor.withOpacity(0.5),
              ),
            ),
            const SizedBox(height: ThemeConstants.spacingLarge),
            Text(
              'No Articles Saved',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: ThemeConstants.spacingSmall),
            Text(
              'Save individual clothing items to build your virtual wardrobe',
              style: TextStyle(
                fontSize: 15,
                color: ThemeConstants.textSecondaryColor,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ArticleCard extends StatelessWidget {
  final SavedArticle article;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onFavorite;
  final VoidCallback? onSync;

  const _ArticleCard({
    required this.article,
    required this.onTap,
    required this.onDelete,
    required this.onFavorite,
    this.onSync,
  });

  IconData _getCategoryIcon() {
    switch (article.category) {
      case 'tops':
        return Icons.dry_cleaning;
      case 'bottoms':
        return Icons.straighten;
      case 'dresses':
        return Icons.checkroom;
      default:
        return Icons.checkroom;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onDelete,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0xFFE5E7EB),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(11),
          child: Stack(
            fit: StackFit.expand,
            children: [
              SmartImage(
                path: article.imagePath,
                fit: BoxFit.cover,
              ),
              // Favorite heart
              Positioned(
                top: 4,
                right: 4,
                child: GestureDetector(
                  onTap: onFavorite,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.9),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      article.isFavorite ? Icons.favorite : Icons.favorite_border,
                      color: article.isFavorite ? const Color(0xFFEF4444) : const Color(0xFF9CA3AF),
                      size: 14,
                    ),
                  ),
                ),
              ),
              // Cloud sync indicator
              Positioned(
                top: 4,
                left: 4,
                child: GestureDetector(
                  onTap: article.isSynced ? null : onSync,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.9),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      article.isSynced ? Icons.cloud_done : Icons.cloud_off,
                      color: article.isSynced ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                      size: 12,
                    ),
                  ),
                ),
              ),
              // Category badge
              Positioned(
                bottom: 6,
                left: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    _getCategoryIcon(),
                    size: 12,
                    color: const Color(0xFF14B8A6),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MySelfiesTab extends StatefulWidget {
  const _MySelfiesTab();

  @override
  State<_MySelfiesTab> createState() => _MySelfiesTabState();
}

class _MySelfiesTabState extends State<_MySelfiesTab> {
  List<String> _selfies = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSelfies();
  }

  Future<void> _loadSelfies() async {
    final photos = await RecentPhotosService.getAllPhotos();
    if (mounted) {
      setState(() {
        _selfies = photos;
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteSelfie(String photoPath) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Selfie'),
        content: const Text('Are you sure you want to remove this photo?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await RecentPhotosService.removePhoto(photoPath);
      _loadSelfies();
    }
  }

  Future<void> _addSelfie() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Add Selfie',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF4A3F35),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context, ImageSource.camera),
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8F6F4),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFD4C4B5)),
                        ),
                        child: const Column(
                          children: [
                            Icon(Icons.camera_alt_outlined, size: 32, color: Color(0xFF8B7355)),
                            SizedBox(height: 8),
                            Text('Camera', style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF4A3F35))),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context, ImageSource.gallery),
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8F6F4),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFD4C4B5)),
                        ),
                        child: const Column(
                          children: [
                            Icon(Icons.photo_library_outlined, size: 32, color: Color(0xFF8B7355)),
                            SizedBox(height: 8),
                            Text('Gallery', style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF4A3F35))),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );

    if (source == null) return;

    final imagePicker = ImagePicker();
    final XFile? photo = await imagePicker.pickImage(
      source: source,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
      preferredCameraDevice: CameraDevice.front,
    );

    if (photo != null) {
      await RecentPhotosService.addPhoto(photo.path);
      _loadSelfies();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF8B7355)),
      );
    }

    if (_selfies.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(ThemeConstants.spacingXLarge),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: const Color(0xFF8B7355).withOpacity(0.08),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.person_outline,
                  size: 64,
                  color: const Color(0xFF8B7355).withOpacity(0.5),
                ),
              ),
              const SizedBox(height: ThemeConstants.spacingLarge),
              Text(
                'No Selfies Yet',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: ThemeConstants.spacingSmall),
              Text(
                'Photos you use for try-ons will appear here',
                style: TextStyle(
                  fontSize: 15,
                  color: ThemeConstants.textSecondaryColor,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _loadSelfies,
          color: const Color(0xFF8B7355),
          child: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: _selfies.length,
        itemBuilder: (context, index) {
          final photoPath = _selfies[index];
          final file = File(photoPath);
          final exists = file.existsSync();

          return Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFD4C4B5)),
                ),
                clipBehavior: Clip.antiAlias,
                child: exists
                    ? SmartImage(
                        path: photoPath,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                      )
                    : _buildPlaceholder(),
              ),
              // Delete button
              Positioned(
                top: 4,
                right: 4,
                child: GestureDetector(
                  onTap: () => _deleteSelfie(photoPath),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close,
                      size: 16,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
        ),
        // Add button
        Positioned(
          right: 16,
          bottom: 16,
          child: GestureDetector(
            onTap: _addSelfie,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF8B7355),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF8B7355).withOpacity(0.4),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(Icons.add_rounded, color: Colors.white, size: 26),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: const Color(0xFFEDE8E3),
      child: const Icon(
        Icons.broken_image_outlined,
        color: Color(0xFF8B7355),
      ),
    );
  }
}
