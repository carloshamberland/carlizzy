import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/constants/theme_constants.dart';
import '../../../../core/services/recent_photos_service.dart';

class RecentPhotosGallery extends StatefulWidget {
  final ValueChanged<String> onPhotoSelected;

  const RecentPhotosGallery({
    super.key,
    required this.onPhotoSelected,
  });

  @override
  State<RecentPhotosGallery> createState() => _RecentPhotosGalleryState();
}

class _RecentPhotosGalleryState extends State<RecentPhotosGallery> {
  List<String> _recentPhotos = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRecentPhotos();
  }

  Future<void> _loadRecentPhotos() async {
    final photos = await RecentPhotosService.getRecentPhotos();
    setState(() {
      _recentPhotos = photos;
      _isLoading = false;
    });
  }

  void _showAllPhotos(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AllPhotosScreen(
          onPhotoSelected: (path) {
            Navigator.of(context).pop();
            widget.onPhotoSelected(path);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SizedBox(
        height: 80,
        child: Center(
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    if (_recentPhotos.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(
              Icons.history,
              size: 18,
              color: ThemeConstants.textSecondaryColor,
            ),
            const SizedBox(width: ThemeConstants.spacingSmall),
            Text(
              'Recent Photos',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: ThemeConstants.textSecondaryColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: ThemeConstants.spacingSmall),
        SizedBox(
          height: 80,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _recentPhotos.length + 1, // +1 for "See All" button
            itemBuilder: (context, index) {
              // Last item is "See All" button
              if (index == _recentPhotos.length) {
                return Padding(
                  padding: const EdgeInsets.only(left: ThemeConstants.spacingSmall),
                  child: _SeeAllTile(
                    onTap: () => _showAllPhotos(context),
                  ),
                );
              }
              final photoPath = _recentPhotos[index];
              return Padding(
                padding: EdgeInsets.only(
                  right: ThemeConstants.spacingSmall,
                ),
                child: _RecentPhotoTile(
                  photoPath: photoPath,
                  onTap: () => widget.onPhotoSelected(photoPath),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _RecentPhotoTile extends StatelessWidget {
  final String photoPath;
  final VoidCallback onTap;

  const _RecentPhotoTile({
    required this.photoPath,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final file = File(photoPath);
    final exists = file.existsSync();

    return GestureDetector(
      onTap: exists ? onTap : null,
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(ThemeConstants.radiusSmall),
          border: Border.all(color: ThemeConstants.borderColor),
        ),
        clipBehavior: Clip.antiAlias,
        child: exists
            ? Image.file(
                file,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _buildPlaceholder(),
              )
            : _buildPlaceholder(),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: ThemeConstants.backgroundColor,
      child: Icon(
        Icons.broken_image_outlined,
        color: ThemeConstants.textHintColor,
      ),
    );
  }
}

class _SeeAllTile extends StatelessWidget {
  final VoidCallback onTap;

  const _SeeAllTile({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(ThemeConstants.radiusSmall),
          border: Border.all(color: const Color(0xFFD4C4B5)),
          color: const Color(0xFFF8F6F4),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.grid_view_rounded,
              size: 22,
              color: const Color(0xFF8B7355),
            ),
            const SizedBox(height: 2),
            Text(
              'See All',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF8B7355),
              ),
            ),
            Text(
              'Selfies',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF8B7355),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AllPhotosScreen extends StatefulWidget {
  final ValueChanged<String> onPhotoSelected;

  const AllPhotosScreen({super.key, required this.onPhotoSelected});

  @override
  State<AllPhotosScreen> createState() => _AllPhotosScreenState();
}

class _AllPhotosScreenState extends State<AllPhotosScreen> {
  List<String> _allPhotos = [];
  bool _isLoading = true;
  final _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadPhotos();
  }

  Future<void> _loadPhotos() async {
    final photos = await RecentPhotosService.getAllPhotos();
    setState(() {
      _allPhotos = photos;
      _isLoading = false;
    });
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
                        child: Column(
                          children: [
                            Icon(Icons.camera_alt_outlined, size: 32, color: const Color(0xFF8B7355)),
                            const SizedBox(height: 8),
                            const Text('Camera', style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF4A3F35))),
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
                        child: Column(
                          children: [
                            Icon(Icons.photo_library_outlined, size: 32, color: const Color(0xFF8B7355)),
                            const SizedBox(height: 8),
                            const Text('Gallery', style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF4A3F35))),
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

    final XFile? photo = await _imagePicker.pickImage(
      source: source,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
      preferredCameraDevice: CameraDevice.front,
    );

    if (photo != null) {
      await RecentPhotosService.addPhoto(photo.path);
      _loadPhotos();
    }
  }

  Future<void> _confirmDelete(String photoPath) async {
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
      _loadPhotos(); // Refresh the list
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F6F4),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(
              Icons.arrow_back_ios_new,
              size: 18,
              color: Color(0xFF4A3F35),
            ),
          ),
        ),
        title: const Text(
          'My Selfies',
          style: TextStyle(
            color: Color(0xFF4A3F35),
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: _addSelfie,
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF8B7355),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.add,
                size: 18,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF8B7355)))
          : _allPhotos.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.photo_library_outlined,
                        size: 64,
                        color: const Color(0xFF8B7355).withOpacity(0.5),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No photos yet',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF4A3F35).withOpacity(0.7),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Photos you use for try-ons will appear here',
                        style: TextStyle(
                          fontSize: 14,
                          color: const Color(0xFF4A3F35).withOpacity(0.5),
                        ),
                      ),
                    ],
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: _allPhotos.length,
                  itemBuilder: (context, index) {
                    final photoPath = _allPhotos[index];
                    final file = File(photoPath);
                    final exists = file.existsSync();

                    return GestureDetector(
                      onTap: exists ? () => widget.onPhotoSelected(photoPath) : null,
                      child: Stack(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFD4C4B5)),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: exists
                                ? Image.file(
                                    file,
                                    fit: BoxFit.cover,
                                    width: double.infinity,
                                    height: double.infinity,
                                    errorBuilder: (_, __, ___) => _buildPlaceholder(),
                                  )
                                : _buildPlaceholder(),
                          ),
                          // Delete button
                          Positioned(
                            top: 4,
                            right: 4,
                            child: GestureDetector(
                              onTap: () => _confirmDelete(photoPath),
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
                      ),
                    );
                  },
                ),
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
