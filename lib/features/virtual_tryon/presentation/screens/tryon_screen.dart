import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../../core/ai_providers/ai_provider.dart';
import '../../../../core/constants/theme_constants.dart';
import '../../../../core/services/saved_outfits_service.dart';
import '../bloc/tryon_bloc.dart';
import '../bloc/tryon_event.dart';
import '../bloc/tryon_state.dart';
import '../widgets/ai_provider_selector.dart';
import '../widgets/recent_photos_gallery.dart';

class TryOnScreen extends StatefulWidget {
  final String? initialPhotoPath;
  final String? initialClothingPath;

  const TryOnScreen({super.key, this.initialPhotoPath, this.initialClothingPath});

  @override
  State<TryOnScreen> createState() => _TryOnScreenState();
}

class _TryOnScreenState extends State<TryOnScreen> {
  bool _initialDataSet = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialDataSet) {
      _initialDataSet = true;
      if (widget.initialPhotoPath != null) {
        context.read<TryonBloc>().add(SetPersonImagePathEvent(widget.initialPhotoPath!));
      }
      if (widget.initialClothingPath != null) {
        // Default to upper_body category for camera-taken clothing
        context.read<TryonBloc>().add(SetClothingPathEvent(widget.initialClothingPath!, category: 'upper_body'));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFF8F6F4),
              Color(0xFFEDE8E3),
            ],
          ),
        ),
        child: Stack(
          children: [
            // Fitting room ambient pattern
            Positioned.fill(
              child: CustomPaint(
                painter: _FittingRoomPatternPainter(),
              ),
            ),
            // Main content
            SafeArea(
              child: BlocConsumer<TryonBloc, TryonState>(
                listener: (context, state) {
                  if (state is TryonErrorState) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(state.message),
                        backgroundColor: ThemeConstants.errorColor,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(ThemeConstants.radiusSmall),
                        ),
                      ),
                    );
                  }
                },
                builder: (context, state) {
                  return _buildBody(context, state);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, TryonState state) {
    if (state is ProcessingTryOnState) {
      return _ProcessingView(state: state);
    }

    if (state is TryonSuccessState) {
      return _ResultView(state: state);
    }

    return _MainView(state: state);
  }
}

class _MainView extends StatefulWidget {
  final TryonState state;

  const _MainView({required this.state});

  @override
  State<_MainView> createState() => _MainViewState();
}

class _MainViewState extends State<_MainView> {
  @override
  Widget build(BuildContext context) {
    final hasPersonImage = widget.state is PersonSelectedState ||
        widget.state is TryonReadyState;

    String? personImagePath;
    bool isPersonUrl = false;
    Map<String, ClothingSelection> clothingItems = {};
    AIProviderType selectedProvider = AIProviderType.fitroom;
    List<AIProviderType> availableProviders = [];
    int credits = 0;

    if (widget.state is TryonInitial) {
      final s = widget.state as TryonInitial;
      selectedProvider = s.selectedProvider;
      availableProviders = s.availableProviders;
      credits = s.credits;
      clothingItems = s.clothingItems;
    } else if (widget.state is PersonSelectedState) {
      final s = widget.state as PersonSelectedState;
      personImagePath = s.personImage.path;
      isPersonUrl = s.isPersonUrl;
      selectedProvider = s.selectedProvider;
      availableProviders = s.availableProviders;
      credits = s.credits;
    } else if (widget.state is TryonReadyState) {
      final s = widget.state as TryonReadyState;
      personImagePath = s.personImage.path;
      isPersonUrl = s.isPersonUrl;
      clothingItems = s.clothingItems;
      selectedProvider = s.selectedProvider;
      availableProviders = s.availableProviders;
      credits = s.credits;
    }

    final hasClothing = clothingItems.isNotEmpty;
    final clothingCount = clothingItems.length;

    return Column(
      children: [
        // Header
        _Header(
          selectedProvider: selectedProvider,
          availableProviders: availableProviders,
          credits: credits,
        ),

        // Fitting Room Mirror Area (top)
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: ThemeConstants.spacingMedium),
            child: _FittingRoomMirror(
              personImagePath: personImagePath,
              isPersonUrl: isPersonUrl,
              hasPersonImage: hasPersonImage,
              onTapMirror: () => _showPersonImagePicker(context),
              onClearPerson: hasPersonImage
                  ? () => context.read<TryonBloc>().add(const ResetTryonEvent())
                  : null,
            ),
          ),
        ),

        const SizedBox(height: ThemeConstants.spacingSmall),

        // Clothing Sections (horizontal at bottom)
        _ClothingSectionPanel(
          clothingItems: clothingItems,
          onSectionTap: (category) {
            _showClothingOptions(context, category);
          },
          onClearClothing: (category) {
            context.read<TryonBloc>().add(ClearClothingEvent(category: category));
          },
        ),

        // Bottom section with Try On Button and Help
        Container(
          padding: const EdgeInsets.fromLTRB(
            ThemeConstants.spacingMedium,
            ThemeConstants.spacingSmall,
            ThemeConstants.spacingMedium,
            ThemeConstants.spacingSmall,
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hasClothing)
                  _TryOnButton(
                    onPressed: () {
                      context.read<TryonBloc>().add(const StartTryOnEvent());
                    },
                    provider: selectedProvider,
                    itemCount: clothingCount,
                  ),
                if (hasClothing) const SizedBox(height: 8),
                // Help button
                _HelpButton(onTap: () => _showHelpBubble(context)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _showHelpBubble(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => const _HelpBubble(),
    );
  }

  String _mapCategoryToApi(String category) {
    switch (category) {
      case 'tops':
        return 'upper_body';
      case 'bottoms':
        return 'lower_body';
      case 'dresses':
        return 'full_body';
      case 'shoes':
        return 'shoes';
      case 'accessories':
        return 'accessories';
      default:
        return 'upper_body';
    }
  }

  void _showPersonImagePicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PersonImagePickerSheet(
        onCameraTap: () {
          Navigator.pop(context);
          context.read<TryonBloc>().add(
                const SelectPersonPhotoEvent(ImageSource.camera),
              );
        },
        onGalleryTap: () {
          Navigator.pop(context);
          context.read<TryonBloc>().add(
                const SelectPersonPhotoEvent(ImageSource.gallery),
              );
        },
        onRecentSelected: (path) {
          Navigator.pop(context);
          context.read<TryonBloc>().add(SetPersonImagePathEvent(path));
        },
      ),
    );
  }

  void _showClothingOptions(BuildContext context, String category) {
    final apiCategory = _mapCategoryToApi(category);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ClothingOptionsSheet(
        category: category,
        onCameraTap: () {
          Navigator.pop(context);
          context.read<TryonBloc>().add(
                SelectClothingImageEvent(ImageSource.camera, category: apiCategory),
              );
        },
        onGalleryTap: () {
          Navigator.pop(context);
          context.read<TryonBloc>().add(
                SelectClothingImageEvent(ImageSource.gallery, category: apiCategory),
              );
        },
        onArticleSelected: (path) {
          context.read<TryonBloc>().add(SetClothingUrlEvent(path, category: apiCategory));
        },
        onBrowseWardrobe: () {
          Navigator.pop(context);
          _showWardrobeBrowser(context, apiCategory);
        },
      ),
    );
  }

  void _showWardrobeBrowser(BuildContext context, String apiCategory) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _WardrobeBrowserSheet(
        onArticleSelected: (path, selectedCategory) {
          Navigator.pop(context);
          context.read<TryonBloc>().add(SetClothingUrlEvent(path, category: selectedCategory));
        },
      ),
    );
  }
}

// Fitting Room Mirror Widget
class _FittingRoomMirror extends StatelessWidget {
  final String? personImagePath;
  final bool isPersonUrl;
  final bool hasPersonImage;
  final VoidCallback onTapMirror;
  final VoidCallback? onClearPerson;

  const _FittingRoomMirror({
    required this.personImagePath,
    required this.isPersonUrl,
    required this.hasPersonImage,
    required this.onTapMirror,
    this.onClearPerson,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTapMirror,
      child: Container(
        decoration: BoxDecoration(
          // Wooden frame effect
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: const Color(0xFF8B7355),
            width: 8,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF4A3F35).withOpacity(0.3),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
            BoxShadow(
              color: const Color(0xFF8B7355).withOpacity(0.2),
              blurRadius: 4,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: const Color(0xFFD4C4B5),
              width: 3,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Mirror background
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        const Color(0xFFF5F0EB),
                        const Color(0xFFE8E0D8),
                        const Color(0xFFF0EBE6),
                      ],
                    ),
                  ),
                ),
                // Subtle mirror reflection effect
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: 100,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.white.withOpacity(0.4),
                          Colors.white.withOpacity(0.0),
                        ],
                      ),
                    ),
                  ),
                ),
                // Person image or placeholder
                if (hasPersonImage && personImagePath != null)
                  isPersonUrl
                      ? CachedNetworkImage(
                          imageUrl: personImagePath!,
                          fit: BoxFit.contain,
                          placeholder: (_, __) => const Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : Image.file(
                          File(personImagePath!),
                          fit: BoxFit.contain,
                        )
                else
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: const Color(0xFF8B7355).withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.person_add_alt_1_outlined,
                            size: 48,
                            color: const Color(0xFF8B7355).withOpacity(0.6),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Tap to add your photo',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: const Color(0xFF8B7355).withOpacity(0.8),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Stand in the mirror',
                          style: TextStyle(
                            fontSize: 13,
                            color: const Color(0xFFA69585),
                          ),
                        ),
                      ],
                    ),
                  ),
                // Clear button
                if (hasPersonImage && onClearPerson != null)
                  Positioned(
                    top: 12,
                    right: 12,
                    child: GestureDetector(
                      onTap: onClearPerson,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF4A3F35).withOpacity(0.8),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close,
                          size: 18,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Clothing Section Panel (horizontal at bottom)
class _ClothingSectionPanel extends StatelessWidget {
  final Map<String, ClothingSelection> clothingItems;
  final Function(String) onSectionTap;
  final Function(String) onClearClothing;

  const _ClothingSectionPanel({
    required this.clothingItems,
    required this.onSectionTap,
    required this.onClearClothing,
  });

  // Map UI category to API category for lookup
  String _mapToApiCategory(String uiCategory) {
    switch (uiCategory) {
      case 'tops':
        return 'upper_body';
      case 'bottoms':
        return 'lower_body';
      case 'dresses':
        return 'full_body';
      case 'shoes':
        return 'shoes';
      case 'accessories':
        return 'accessories';
      default:
        return 'upper_body';
    }
  }

  @override
  Widget build(BuildContext context) {
    final sections = [
      _ClothingSection('tops', 'shirt', 'Tops', isSupported: true),
      _ClothingSection('bottoms', 'pants', 'Bottoms', isSupported: true),
      _ClothingSection('dresses', 'dress', 'Dresses', isSupported: true),
      _ClothingSection('shoes', 'shoe', 'Shoes', isSupported: false),
      _ClothingSection('accessories', 'accessory', 'Accs', isSupported: false),
    ];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: ThemeConstants.spacingMedium),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFD4C4B5)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF8B7355).withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          ...sections.map((section) {
            final apiCategory = _mapToApiCategory(section.id);
            final clothing = clothingItems[apiCategory];
            final hasClothing = clothing != null;
            return Expanded(
              child: _ClothingSectionButton(
                section: section,
                isSelected: hasClothing,
                hasClothing: hasClothing,
                clothingImage: clothing?.imagePath,
                isClothingUrl: clothing?.isUrl ?? false,
                onTap: section.isSupported
                    ? () => onSectionTap(section.id)
                    : () => _showComingSoon(context, section.label),
                onClear: hasClothing ? () => onClearClothing(apiCategory) : null,
              ),
            );
          }),
        ],
      ),
    );
  }

  void _showComingSoon(BuildContext context, String category) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$category coming soon!'),
        backgroundColor: const Color(0xFF8B7355),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

class _ClothingSection {
  final String id;
  final dynamic icon; // Can be IconData or String for custom
  final String label;
  final bool isSupported;

  _ClothingSection(this.id, this.icon, this.label, {this.isSupported = true});
}

// Custom shirt icon
class _ShirtIcon extends StatelessWidget {
  final Color color;
  final double size;

  const _ShirtIcon({required this.color, this.size = 24});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _ShirtPainter(color),
      ),
    );
  }
}

class _ShirtPainter extends CustomPainter {
  final Color color;
  _ShirtPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    // Left shoulder
    path.moveTo(size.width * 0.1, size.height * 0.25);
    // Left sleeve
    path.lineTo(size.width * 0.0, size.height * 0.45);
    path.lineTo(size.width * 0.15, size.height * 0.45);
    path.lineTo(size.width * 0.15, size.height * 0.35);
    // Left body down
    path.lineTo(size.width * 0.2, size.height * 0.35);
    path.lineTo(size.width * 0.2, size.height * 0.9);
    // Bottom hem
    path.lineTo(size.width * 0.8, size.height * 0.9);
    // Right body up
    path.lineTo(size.width * 0.8, size.height * 0.35);
    path.lineTo(size.width * 0.85, size.height * 0.35);
    // Right sleeve
    path.lineTo(size.width * 0.85, size.height * 0.45);
    path.lineTo(size.width * 1.0, size.height * 0.45);
    path.lineTo(size.width * 0.9, size.height * 0.25);
    // Collar/neckline
    path.lineTo(size.width * 0.6, size.height * 0.1);
    path.lineTo(size.width * 0.5, size.height * 0.18);
    path.lineTo(size.width * 0.4, size.height * 0.1);
    path.lineTo(size.width * 0.1, size.height * 0.25);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// Custom pants icon
class _PantsIcon extends StatelessWidget {
  final Color color;
  final double size;

  const _PantsIcon({required this.color, this.size = 24});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _PantsPainter(color),
      ),
    );
  }
}

class _PantsPainter extends CustomPainter {
  final Color color;
  _PantsPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    // Waistband
    path.moveTo(size.width * 0.2, size.height * 0.1);
    path.lineTo(size.width * 0.8, size.height * 0.1);
    // Right leg outer
    path.lineTo(size.width * 0.75, size.height * 0.9);
    // Right leg inner (crotch area)
    path.lineTo(size.width * 0.55, size.height * 0.9);
    path.lineTo(size.width * 0.5, size.height * 0.4);
    // Left leg inner
    path.lineTo(size.width * 0.45, size.height * 0.9);
    path.lineTo(size.width * 0.25, size.height * 0.9);
    // Left leg outer back to waist
    path.lineTo(size.width * 0.2, size.height * 0.1);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// Custom shoe icon
class _ShoeIcon extends StatelessWidget {
  final Color color;
  final double size;

  const _ShoeIcon({required this.color, this.size = 24});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _ShoePainter(color),
      ),
    );
  }
}

class _ShoePainter extends CustomPainter {
  final Color color;
  _ShoePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    // Boot shaft (tall ankle)
    path.moveTo(size.width * 0.25, size.height * 0.1);
    path.lineTo(size.width * 0.25, size.height * 0.55);
    // Heel
    path.lineTo(size.width * 0.2, size.height * 0.55);
    path.lineTo(size.width * 0.2, size.height * 0.85);
    // Sole
    path.lineTo(size.width * 0.85, size.height * 0.85);
    // Toe curve
    path.quadraticBezierTo(
      size.width * 0.95, size.height * 0.75,
      size.width * 0.85, size.height * 0.55,
    );
    // Top of foot to shaft
    path.lineTo(size.width * 0.55, size.height * 0.55);
    path.lineTo(size.width * 0.55, size.height * 0.1);
    // Top opening
    path.lineTo(size.width * 0.25, size.height * 0.1);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// Custom dress icon
class _DressIcon extends StatelessWidget {
  final Color color;
  final double size;

  const _DressIcon({required this.color, this.size = 24});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _DressPainter(color),
      ),
    );
  }
}

class _DressPainter extends CustomPainter {
  final Color color;
  _DressPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    // Left strap
    path.moveTo(size.width * 0.35, size.height * 0.05);
    path.lineTo(size.width * 0.3, size.height * 0.2);
    // Neckline left
    path.quadraticBezierTo(
      size.width * 0.4, size.height * 0.25,
      size.width * 0.5, size.height * 0.2,
    );
    // Neckline right
    path.quadraticBezierTo(
      size.width * 0.6, size.height * 0.25,
      size.width * 0.7, size.height * 0.2,
    );
    // Right strap
    path.lineTo(size.width * 0.65, size.height * 0.05);

    // Draw straps
    canvas.drawPath(path, paint);

    // Body of dress
    final bodyPath = Path();
    bodyPath.moveTo(size.width * 0.3, size.height * 0.2);
    // Waist
    bodyPath.lineTo(size.width * 0.35, size.height * 0.45);
    // Skirt left
    bodyPath.lineTo(size.width * 0.15, size.height * 0.95);
    // Hem
    bodyPath.lineTo(size.width * 0.85, size.height * 0.95);
    // Skirt right
    bodyPath.lineTo(size.width * 0.65, size.height * 0.45);
    // Back to neckline
    bodyPath.lineTo(size.width * 0.7, size.height * 0.2);

    canvas.drawPath(bodyPath, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// Custom accessory icon (watch/bracelet)
class _AccessoryIcon extends StatelessWidget {
  final Color color;
  final double size;

  const _AccessoryIcon({required this.color, this.size = 24});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _AccessoryPainter(color),
      ),
    );
  }
}

class _AccessoryPainter extends CustomPainter {
  final Color color;
  _AccessoryPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Draw a watch/bracelet shape
    // Watch face (circle)
    canvas.drawCircle(
      Offset(size.width * 0.5, size.height * 0.5),
      size.width * 0.25,
      paint,
    );

    // Watch band top
    final bandPath = Path();
    bandPath.moveTo(size.width * 0.35, size.height * 0.3);
    bandPath.lineTo(size.width * 0.35, size.height * 0.08);
    bandPath.lineTo(size.width * 0.65, size.height * 0.08);
    bandPath.lineTo(size.width * 0.65, size.height * 0.3);

    // Watch band bottom
    bandPath.moveTo(size.width * 0.35, size.height * 0.7);
    bandPath.lineTo(size.width * 0.35, size.height * 0.92);
    bandPath.lineTo(size.width * 0.65, size.height * 0.92);
    bandPath.lineTo(size.width * 0.65, size.height * 0.7);

    canvas.drawPath(bandPath, paint);

    // Small detail on watch face
    canvas.drawLine(
      Offset(size.width * 0.5, size.height * 0.5),
      Offset(size.width * 0.5, size.height * 0.35),
      paint..strokeWidth = 1.5,
    );
    canvas.drawLine(
      Offset(size.width * 0.5, size.height * 0.5),
      Offset(size.width * 0.6, size.height * 0.5),
      paint..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ClothingSectionButton extends StatelessWidget {
  final _ClothingSection section;
  final bool isSelected;
  final bool hasClothing;
  final String? clothingImage;
  final bool isClothingUrl;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  const _ClothingSectionButton({
    required this.section,
    required this.isSelected,
    required this.hasClothing,
    required this.clothingImage,
    required this.isClothingUrl,
    required this.onTap,
    this.onClear,
  });

  Widget _buildIcon(dynamic icon, Color color) {
    if (icon is IconData) {
      return Icon(icon, size: 18, color: color);
    } else if (icon == 'shirt') {
      return _ShirtIcon(color: color, size: 20);
    } else if (icon == 'pants') {
      return _PantsIcon(color: color, size: 20);
    } else if (icon == 'dress') {
      return _DressIcon(color: color, size: 20);
    } else if (icon == 'shoe') {
      return _ShoeIcon(color: color, size: 20);
    } else if (icon == 'accessory') {
      return _AccessoryIcon(color: color, size: 20);
    }
    return Icon(Icons.checkroom, size: 18, color: color);
  }

  @override
  Widget build(BuildContext context) {
    final isSupported = section.isSupported;
    final displayLabel = section.label;

    // Greyed out colors for unsupported
    final iconColor = !isSupported
        ? const Color(0xFFBBBBBB)
        : hasClothing
            ? const Color(0xFFD4C4B5)
            : (isSelected ? const Color(0xFF6B5B4F) : const Color(0xFF8B7355));

    final labelColor = !isSupported
        ? const Color(0xFFBBBBBB)
        : hasClothing
            ? const Color(0xFFD4C4B5)
            : (isSelected ? const Color(0xFF4A3F35) : const Color(0xFF8B7355));

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        height: 62,
        decoration: BoxDecoration(
          color: !isSupported
              ? const Color(0xFFF0F0F0)
              : isSelected
                  ? const Color(0xFF8B7355).withOpacity(0.12)
                  : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: !isSupported
                ? const Color(0xFFDDDDDD)
                : isSelected
                    ? const Color(0xFF8B7355)
                    : const Color(0xFFD4C4B5),
            width: isSelected && isSupported ? 2 : 1,
          ),
          boxShadow: isSelected && isSupported
              ? [
                  BoxShadow(
                    color: const Color(0xFF8B7355).withOpacity(0.2),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Stack(
          children: [
            // Background icon (always visible, faded when has clothing)
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildIcon(section.icon, iconColor),
                  const SizedBox(height: 2),
                  Text(
                    displayLabel,
                    style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w600,
                      color: labelColor,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (!isSupported)
                    Text(
                      'Soon',
                      style: TextStyle(
                        fontSize: 6,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF999999),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                ],
              ),
            ),
            // Clothing image overlay (centered, with padding)
            if (hasClothing && clothingImage != null)
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: isClothingUrl
                            ? CachedNetworkImage(
                                imageUrl: clothingImage!,
                                fit: BoxFit.contain,
                                placeholder: (_, __) => const Center(
                                  child: SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  ),
                                ),
                              )
                            : Image.file(
                                File(clothingImage!),
                                fit: BoxFit.contain,
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            // Add indicator (when no clothing)
            if (!hasClothing)
              Positioned(
                top: 4,
                right: 4,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF8B7355), Color(0xFF6B5B4F)],
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF8B7355).withOpacity(0.3),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.add,
                    size: 11,
                    color: Colors.white,
                  ),
                ),
              ),
            // Clear button for clothing
            if (hasClothing && onClear != null)
              Positioned(
                top: 2,
                right: 2,
                child: GestureDetector(
                  onTap: onClear,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4A3F35),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.close,
                      size: 10,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// Welcome prompt for bottom panel
class _WelcomePrompt extends StatelessWidget {
  final VoidCallback onTap;

  const _WelcomePrompt({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFF8B7355).withOpacity(0.1),
              const Color(0xFF6B5B4F).withOpacity(0.05),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFD4C4B5)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF8B7355).withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.camera_alt_outlined,
                color: Color(0xFF6B5B4F),
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Step into the fitting room',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF4A3F35),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Add your photo to start trying on clothes',
                    style: TextStyle(
                      fontSize: 13,
                      color: const Color(0xFF8B7355),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios,
              size: 16,
              color: Color(0xFF8B7355),
            ),
          ],
        ),
      ),
    );
  }
}

// Select clothing prompt
class _SelectClothingPrompt extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F0EB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD4C4B5)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF8B7355).withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.touch_app_outlined,
              color: Color(0xFF6B5B4F),
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Now pick something to wear',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF4A3F35),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Tap a clothing section on the right',
                  style: TextStyle(
                    fontSize: 13,
                    color: const Color(0xFF8B7355),
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.arrow_forward,
            size: 20,
            color: Color(0xFF8B7355),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final AIProviderType selectedProvider;
  final List<AIProviderType> availableProviders;
  final int credits;

  const _Header({
    required this.selectedProvider,
    required this.availableProviders,
    required this.credits,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ThemeConstants.spacingSmall,
        vertical: ThemeConstants.spacingSmall,
      ),
      child: Row(
        children: [
          // Back button
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(
                Icons.arrow_back_ios_new,
                size: 22,
                color: ThemeConstants.textPrimaryColor,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.door_sliding_outlined,
                      size: 20,
                      color: Color(0xFF8B7355),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Fitting Room',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: const Color(0xFF4A3F35),
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'Try on clothes virtually',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF8B7355),
                      ),
                ),
              ],
            ),
          ),
          AIProviderSelector(
            selected: selectedProvider,
            available: availableProviders,
            credits: credits,
            onChanged: (provider) {
              context.read<TryonBloc>().add(ChangeProviderEvent(provider));
            },
          ),
        ],
      ),
    );
  }
}

class _ImageCard extends StatelessWidget {
  final String label;
  final String? imagePath;
  final bool isUrl;
  final IconData icon;
  final VoidCallback? onTap;
  final VoidCallback? onClear;
  final bool disabled;

  const _ImageCard({
    required this.label,
    required this.imagePath,
    required this.isUrl,
    required this.icon,
    required this.onTap,
    this.onClear,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context) {
    final hasImage = imagePath != null && imagePath!.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: disabled
                    ? const Color(0xFFB5A090)
                    : const Color(0xFF6B5B4F),
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: ThemeConstants.spacingSmall),
        GestureDetector(
          onTap: disabled ? null : onTap,
          child: Container(
            height: 180,
            decoration: BoxDecoration(
              color: disabled
                  ? const Color(0xFFE8E0D8)
                  : Colors.white,
              borderRadius: BorderRadius.circular(ThemeConstants.radiusMedium),
              border: Border.all(
                color: hasImage
                    ? const Color(0xFF8B7355)
                    : const Color(0xFFD4C4B5),
                width: hasImage ? 3 : 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF8B7355).withOpacity(0.15),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Inner frame effect
                Container(
                  margin: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(ThemeConstants.radiusMedium - 3),
                    border: Border.all(
                      color: const Color(0xFFE8E0D8),
                      width: 1,
                    ),
                  ),
                ),
                if (hasImage)
                  Padding(
                    padding: const EdgeInsets.all(4),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(ThemeConstants.radiusMedium - 4),
                      child: isUrl
                          ? CachedNetworkImage(
                              imageUrl: imagePath!,
                              fit: BoxFit.cover,
                              placeholder: (_, __) => const Center(
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                              errorWidget: (_, __, ___) => _EmptyContent(
                                icon: Icons.broken_image_outlined,
                                label: 'Failed to load',
                                disabled: disabled,
                              ),
                            )
                          : Image.file(
                              File(imagePath!),
                              fit: BoxFit.cover,
                            ),
                    ),
                  )
                else
                  _EmptyContent(
                    icon: icon,
                    label: disabled ? 'Select photo first' : 'Tap to select',
                    disabled: disabled,
                  ),
                if (hasImage && onClear != null)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: GestureDetector(
                      onTap: onClear,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF4A3F35).withOpacity(0.8),
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
          ),
        ),
      ],
    );
  }
}

class _EmptyContent extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool disabled;

  const _EmptyContent({
    required this.icon,
    required this.label,
    required this.disabled,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 40,
            color: disabled
                ? const Color(0xFFCDC1B4)
                : const Color(0xFFA69585),
          ),
          const SizedBox(height: ThemeConstants.spacingSmall),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: disabled
                      ? const Color(0xFFCDC1B4)
                      : const Color(0xFFA69585),
                ),
          ),
        ],
      ),
    );
  }
}

class _TryOnButton extends StatelessWidget {
  final VoidCallback onPressed;
  final AIProviderType provider;
  final int itemCount;

  const _TryOnButton({
    required this.onPressed,
    required this.provider,
    this.itemCount = 1,
  });

  @override
  Widget build(BuildContext context) {
    final buttonText = itemCount > 1
        ? 'Try On Outfit ($itemCount items)'
        : 'Try It On';

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(ThemeConstants.radiusMedium),
        gradient: const LinearGradient(
          colors: [
            Color(0xFF6B5B4F),
            Color(0xFF8B7355),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6B5B4F).withOpacity(0.4),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(vertical: 18),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.auto_awesome, size: 20),
            const SizedBox(width: ThemeConstants.spacingSmall),
            Text(
              buttonText,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HelpButton extends StatelessWidget {
  final VoidCallback onTap;

  const _HelpButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F0EB),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFD4C4B5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.lightbulb_outline,
              size: 16,
              color: const Color(0xFF8B7355),
            ),
            const SizedBox(width: 6),
            Text(
              'Tips for best results',
              style: TextStyle(
                fontSize: 12,
                color: const Color(0xFF6B5B4F),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HelpBubble extends StatelessWidget {
  const _HelpBubble();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 20,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF8B7355),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(
              children: [
                const Icon(Icons.tips_and_updates, color: Colors.white, size: 24),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Tips for Best Results',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Icon(Icons.close, color: Colors.white70, size: 22),
                ),
              ],
            ),
          ),
          // Tips content
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                _TipItem(
                  icon: Icons.person_outline,
                  title: 'Your Photo',
                  description: 'Use a clear, full-body photo with good lighting. Stand facing the camera with arms slightly away from your body.',
                ),
                const SizedBox(height: 16),
                _TipItem(
                  icon: Icons.checkroom,
                  title: 'Clothing Items',
                  description: 'Use photos of individual items only. For example, pants should show just the pants - not pants with shoes or other items.',
                ),
                const SizedBox(height: 16),
                _TipItem(
                  icon: Icons.crop_free,
                  title: 'Image Quality',
                  description: 'Front-facing, flat-lay or mannequin photos work best. Avoid heavily styled or angled shots.',
                ),
              ],
            ),
          ),
          // Close button
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  backgroundColor: const Color(0xFFF5F0EB),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Got it!',
                  style: TextStyle(
                    color: Color(0xFF6B5B4F),
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TipItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const _TipItem({
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF8B7355).withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: const Color(0xFF8B7355), size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                  color: Color(0xFF4A3F35),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: TextStyle(
                  fontSize: 13,
                  color: const Color(0xFF6B5B4F).withOpacity(0.85),
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InstructionsCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(ThemeConstants.spacingMedium),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.7),
        borderRadius: BorderRadius.circular(ThemeConstants.radiusMedium),
        border: Border.all(color: const Color(0xFFD4C4B5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.lightbulb_outline,
                size: 20,
                color: const Color(0xFF8B7355),
              ),
              const SizedBox(width: ThemeConstants.spacingSmall),
              Text(
                'How it works',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: const Color(0xFF4A3F35),
                    ),
              ),
            ],
          ),
          const SizedBox(height: ThemeConstants.spacingMedium),
          _InstructionStep(
            number: '1',
            text: 'Upload a photo of yourself',
          ),
          _InstructionStep(
            number: '2',
            text: 'Select or upload clothing to try on',
          ),
          _InstructionStep(
            number: '3',
            text: 'AI generates you wearing the outfit',
          ),
        ],
      ),
    );
  }
}

class _InstructionStep extends StatelessWidget {
  final String number;
  final String text;

  const _InstructionStep({
    required this.number,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: ThemeConstants.spacingSmall),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: const Color(0xFF8B7355).withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                number,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF6B5B4F),
                ),
              ),
            ),
          ),
          const SizedBox(width: ThemeConstants.spacingSmall),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF6B5B4F),
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PersonImagePickerSheet extends StatelessWidget {
  final VoidCallback onCameraTap;
  final VoidCallback onGalleryTap;
  final ValueChanged<String> onRecentSelected;

  const _PersonImagePickerSheet({
    required this.onCameraTap,
    required this.onGalleryTap,
    required this.onRecentSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(ThemeConstants.spacingLarge),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: ThemeConstants.borderColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: ThemeConstants.spacingLarge),
          Text(
            'Select Your Photo',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: ThemeConstants.spacingLarge),
          Row(
            children: [
              Expanded(
                child: _OptionButton(
                  icon: Icons.camera_alt_outlined,
                  label: 'Camera',
                  onTap: onCameraTap,
                ),
              ),
              const SizedBox(width: ThemeConstants.spacingMedium),
              Expanded(
                child: _OptionButton(
                  icon: Icons.photo_library_outlined,
                  label: 'Gallery',
                  onTap: onGalleryTap,
                ),
              ),
            ],
          ),
          const SizedBox(height: ThemeConstants.spacingLarge),
          RecentPhotosGallery(
            onPhotoSelected: onRecentSelected,
          ),
          const SizedBox(height: ThemeConstants.spacingMedium),
        ],
      ),
    );
  }
}

class _ClothingOptionsSheet extends StatefulWidget {
  final String category;
  final VoidCallback onCameraTap;
  final VoidCallback onGalleryTap;
  final ValueChanged<String> onArticleSelected;
  final VoidCallback? onBrowseWardrobe;

  const _ClothingOptionsSheet({
    required this.category,
    required this.onCameraTap,
    required this.onGalleryTap,
    required this.onArticleSelected,
    this.onBrowseWardrobe,
  });

  @override
  State<_ClothingOptionsSheet> createState() => _ClothingOptionsSheetState();
}

class _ClothingOptionsSheetState extends State<_ClothingOptionsSheet> {
  List<SavedArticle>? _savedArticles;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSavedArticles();
  }

  Future<void> _loadSavedArticles() async {
    final service = await SavedOutfitsService.getInstance();
    final articles = await service.getSavedArticles(category: widget.category);
    // Sort by most recent and take only 4
    articles.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final recentFour = articles.take(4).toList();
    if (mounted) {
      setState(() {
        _savedArticles = recentFour;
        _isLoading = false;
      });
    }
  }

  String get _categoryTitle {
    switch (widget.category) {
      case 'tops':
        return 'Top';
      case 'bottoms':
        return 'Bottom';
      case 'dresses':
        return 'Dress';
      case 'shoes':
        return 'Shoes';
      case 'accessories':
        return 'Accessory';
      default:
        return 'Clothing';
    }
  }

  dynamic get _categoryIcon {
    switch (widget.category) {
      case 'tops':
        return 'shirt';
      case 'bottoms':
        return 'pants';
      case 'dresses':
        return 'dress';
      case 'shoes':
        return 'shoe';
      case 'accessories':
        return 'accessory';
      default:
        return Icons.checkroom;
    }
  }

  Widget _buildCategoryIcon(Color color) {
    final icon = _categoryIcon;
    if (icon is IconData) {
      return Icon(icon, size: 24, color: color);
    } else if (icon == 'shirt') {
      return _ShirtIcon(color: color, size: 26);
    } else if (icon == 'pants') {
      return _PantsIcon(color: color, size: 26);
    } else if (icon == 'dress') {
      return _DressIcon(color: color, size: 26);
    } else if (icon == 'shoe') {
      return _ShoeIcon(color: color, size: 26);
    } else if (icon == 'accessory') {
      return _AccessoryIcon(color: color, size: 26);
    }
    return Icon(Icons.checkroom, size: 24, color: color);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          padding: const EdgeInsets.all(ThemeConstants.spacingLarge),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD4C4B5),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: ThemeConstants.spacingLarge),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF8B7355).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: _buildCategoryIcon(const Color(0xFF6B5B4F)),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Add $_categoryTitle',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: const Color(0xFF4A3F35),
                        ),
                  ),
                ],
              ),
              const SizedBox(height: ThemeConstants.spacingLarge),
              Row(
                children: [
                  Expanded(
                    child: _OptionButton(
                      icon: Icons.camera_alt_outlined,
                      label: 'Camera',
                      onTap: widget.onCameraTap,
                    ),
                  ),
                  const SizedBox(width: ThemeConstants.spacingMedium),
                  Expanded(
                    child: _OptionButton(
                      icon: Icons.photo_library_outlined,
                      label: 'Gallery',
                      onTap: widget.onGalleryTap,
                    ),
                  ),
                ],
              ),
              if (widget.onBrowseWardrobe != null) ...[
                const SizedBox(height: ThemeConstants.spacingMedium),
                OutlinedButton.icon(
                  onPressed: widget.onBrowseWardrobe,
                  icon: const Icon(Icons.checkroom_outlined),
                  label: const Text('Browse Wardrobe'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ],
              // Saved articles section
              if (!_isLoading && _savedArticles != null && _savedArticles!.isNotEmpty) ...[
                const SizedBox(height: ThemeConstants.spacingLarge),
                Row(
                  children: [
                    const Expanded(child: Divider()),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: ThemeConstants.spacingMedium,
                      ),
                      child: Text(
                        'from My Wardrobe',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    const Expanded(child: Divider()),
                  ],
                ),
                const SizedBox(height: ThemeConstants.spacingMedium),
                SizedBox(
                  height: 100,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _savedArticles!.length,
                    itemBuilder: (context, index) {
                      final article = _savedArticles![index];
                      return Padding(
                        padding: EdgeInsets.only(
                          right: index < _savedArticles!.length - 1 ? 8 : 0,
                        ),
                        child: GestureDetector(
                          onTap: () {
                            Navigator.pop(context);
                            widget.onArticleSelected(article.imagePath);
                          },
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.file(
                              File(article.imagePath),
                              width: 75,
                              height: 100,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(height: ThemeConstants.spacingMedium),
            ],
          ),
        ),
      ),
    );
  }
}

class _OptionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _OptionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 20),
      ),
      child: Column(
        children: [
          Icon(icon, size: 28),
          const SizedBox(height: ThemeConstants.spacingSmall),
          Text(label),
        ],
      ),
    );
  }
}

class _ProcessingView extends StatefulWidget {
  final ProcessingTryOnState state;

  const _ProcessingView({required this.state});

  @override
  State<_ProcessingView> createState() => _ProcessingViewState();
}

class _ProcessingViewState extends State<_ProcessingView>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  String _getCategoryDisplayName(String? category) {
    switch (category) {
      case 'upper_body':
        return 'Top';
      case 'lower_body':
        return 'Bottom';
      case 'full_body':
        return 'Dress';
      case 'shoes':
        return 'Shoes';
      case 'accessories':
        return 'Accessory';
      default:
        return 'Item';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMultiStep = widget.state.totalSteps > 1;
    final overallProgress = widget.state.overallProgress;
    final progress = isMultiStep ? overallProgress : widget.state.progress;
    final percentage = (progress * 100).toInt();

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFF8F6F4),
            Color(0xFFEDE8E3),
            Color(0xFFF8F6F4),
          ],
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              // Animated progress ring
              ScaleTransition(
                scale: _pulseAnimation,
                child: Container(
                  width: 180,
                  height: 180,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        const Color(0xFF8B7355).withOpacity(0.1),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Background ring
                      SizedBox(
                        width: 150,
                        height: 150,
                        child: CircularProgressIndicator(
                          value: 1,
                          strokeWidth: 8,
                          backgroundColor: Colors.transparent,
                          valueColor: AlwaysStoppedAnimation(
                            const Color(0xFFD4C4B5).withOpacity(0.5),
                          ),
                        ),
                      ),
                      // Progress ring
                      SizedBox(
                        width: 150,
                        height: 150,
                        child: CircularProgressIndicator(
                          value: progress,
                          strokeWidth: 8,
                          strokeCap: StrokeCap.round,
                          backgroundColor: Colors.transparent,
                          valueColor: const AlwaysStoppedAnimation(Color(0xFF8B7355)),
                        ),
                      ),
                      // Percentage text
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '$percentage%',
                            style: const TextStyle(
                              fontSize: 42,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF4A3F35),
                              letterSpacing: -1,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 40),
              // Status text
              if (isMultiStep) ...[
                const Text(
                  'Creating your look',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF4A3F35),
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8B7355).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Step ${widget.state.currentStep} of ${widget.state.totalSteps} • ${_getCategoryDisplayName(widget.state.currentCategory)}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF8B7355),
                    ),
                  ),
                ),
              ] else ...[
                const Text(
                  'Generating',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF4A3F35),
                    letterSpacing: -0.5,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Text(
                widget.state.statusMessage.replaceAll('top: ', '').replaceAll('bottom: ', '').replaceAll('dress: ', ''),
                style: TextStyle(
                  fontSize: 15,
                  color: const Color(0xFF4A3F35).withOpacity(0.6),
                ),
                textAlign: TextAlign.center,
              ),
              const Spacer(flex: 2),
              // Tip at bottom
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.auto_awesome,
                      color: Color(0xFFF59E0B),
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        isMultiStep
                            ? 'AI is styling ${widget.state.totalSteps} items for your perfect look'
                            : 'AI is working its magic on your outfit',
                        style: TextStyle(
                          fontSize: 13,
                          color: const Color(0xFF4A3F35).withOpacity(0.7),
                        ),
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
}

class _ResultView extends StatefulWidget {
  final TryonSuccessState state;

  const _ResultView({required this.state});

  @override
  State<_ResultView> createState() => _ResultViewState();
}

class _ResultViewState extends State<_ResultView> {
  bool _isSavingToPhotos = false;
  bool _isSavingToApp = false;
  bool _savedToPhotos = false;
  bool _savedToApp = false;

  Future<void> _saveToPhotos() async {
    setState(() => _isSavingToPhotos = true);

    try {
      // Request permission to add photos
      var status = await Permission.photosAddOnly.status;

      if (status.isDenied) {
        status = await Permission.photosAddOnly.request();
      }

      if (status.isPermanentlyDenied) {
        if (mounted) {
          final shouldOpenSettings = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Permission Required'),
              content: const Text('Photo library access is required to save images. Please enable it in Settings.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Open Settings'),
                ),
              ],
            ),
          );
          if (shouldOpenSettings == true) {
            await openAppSettings();
          }
        }
        setState(() => _isSavingToPhotos = false);
        return;
      }

      if (!status.isGranted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Photo library access denied.'),
            ),
          );
        }
        setState(() => _isSavingToPhotos = false);
        return;
      }

      // Download image first
      final dio = Dio();
      final tempDir = await getTemporaryDirectory();
      final filePath = '${tempDir.path}/outfit_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await dio.download(widget.state.result.resultImageUrl, filePath);

      // Save to gallery
      final result = await ImageGallerySaver.saveFile(filePath);

      if (mounted) {
        if (result['isSuccess'] == true) {
          setState(() {
            _savedToPhotos = true;
            _isSavingToPhotos = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Saved to Photos!'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          setState(() => _isSavingToPhotos = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to save to Photos'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSavingToPhotos = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _saveToApp() async {
    setState(() => _isSavingToApp = true);

    try {
      final service = await SavedOutfitsService.getInstance();
      await service.saveOutfitFromUrl(
        widget.state.result.resultImageUrl,
        description: 'Outfit with ${widget.state.itemsProcessed} items',
      );

      if (mounted) {
        setState(() {
          _savedToApp = true;
          _isSavingToApp = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Saved to My Outfits!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSavingToApp = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header with home button
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
          child: Row(
            children: [
              // Home button
              IconButton(
                onPressed: () {
                  Navigator.of(context).popUntil((route) => route.isFirst);
                },
                icon: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.home_outlined,
                    size: 24,
                    color: Color(0xFF4A3F35),
                  ),
                ),
              ),
              const Spacer(),
              // Title badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.auto_awesome,
                      size: 18,
                      color: Color(0xFFF59E0B),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Your New Look',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: const Color(0xFF4A3F35),
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              const SizedBox(width: 48), // Balance the home button
            ],
          ),
        ),

        // Result image with white border
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: ThemeConstants.spacingMedium,
            ),
            child: Center(
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: CachedNetworkImage(
                    imageUrl: widget.state.result.resultImageUrl,
                    fit: BoxFit.contain,
                    placeholder: (_, __) => Container(
                      color: const Color(0xFFF5F5F5),
                      child: const Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFF8B7355),
                        ),
                      ),
                    ),
                    errorWidget: (_, __, ___) => Container(
                      color: const Color(0xFFF5F5F5),
                      child: const Center(
                        child: Icon(Icons.broken_image_outlined, size: 48, color: Colors.grey),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),

        // Action buttons - two columns
        Padding(
          padding: const EdgeInsets.only(
            left: ThemeConstants.spacingLarge,
            right: ThemeConstants.spacingLarge,
            bottom: ThemeConstants.spacingLarge,
            top: ThemeConstants.spacingSmall,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(left: 4, bottom: 10),
                child: Text(
                  'Save to',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF4A3F35),
                  ),
                ),
              ),
              Row(
                children: [
                  // Left column - Save options
                  Expanded(
                    child: Column(
                      children: [
                        SizedBox(
                          height: 48,
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _isSavingToPhotos || _savedToPhotos ? null : _saveToPhotos,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF8B7355),
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: const Color(0xFF8B7355).withOpacity(0.5),
                              disabledForegroundColor: Colors.white70,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            icon: _isSavingToPhotos
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : Icon(_savedToPhotos ? Icons.check : Icons.photo_library_outlined, size: 20),
                            label: Text(_savedToPhotos ? 'Saved' : 'Photos'),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 48,
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _isSavingToApp || _savedToApp ? null : _saveToApp,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF8B7355),
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: const Color(0xFF8B7355).withOpacity(0.5),
                              disabledForegroundColor: Colors.white70,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            icon: _isSavingToApp
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : Icon(_savedToApp ? Icons.check : Icons.checkroom_outlined, size: 20),
                            label: Text(_savedToApp ? 'Saved' : 'Wardrobe'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: ThemeConstants.spacingMedium),
                  // Right column - Actions
                  Expanded(
                    child: Column(
                      children: [
                        SizedBox(
                          height: 48,
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () {
                              context.read<TryonBloc>().add(
                                UseResultAsBaseEvent(widget.state.result.resultImageUrl),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: const Color(0xFF4A3F35),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: const BorderSide(color: Color(0xFFD4C4B5)),
                              ),
                            ),
                            icon: const Icon(Icons.add, size: 20),
                            label: const Text('Add Article'),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 48,
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () {
                              context.read<TryonBloc>().add(const ResetTryonEvent());
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF4A3F35),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            icon: const Icon(Icons.refresh, size: 20),
                            label: const Text('Start Over'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// Custom painter for fitting room ambient background
class _FittingRoomPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFD4C4B5).withOpacity(0.3)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    // Draw subtle vertical lines (like fitting room curtain/panels)
    const spacing = 80.0;
    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        paint,
      );
    }

    // Draw subtle horizontal accent lines
    final accentPaint = Paint()
      ..color = const Color(0xFFB5A090).withOpacity(0.15)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    // Top accent line
    canvas.drawLine(
      Offset(0, size.height * 0.1),
      Offset(size.width, size.height * 0.1),
      accentPaint,
    );

    // Mirror frame effect - subtle rounded rectangle
    final mirrorPaint = Paint()
      ..color = const Color(0xFFCDC1B4).withOpacity(0.2)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    final mirrorRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(size.width / 2, size.height * 0.5),
        width: size.width * 0.85,
        height: size.height * 0.6,
      ),
      const Radius.circular(20),
    );
    canvas.drawRRect(mirrorRect, mirrorPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// Wardrobe Browser Sheet for selecting items from wardrobe
class _WardrobeBrowserSheet extends StatefulWidget {
  final void Function(String path, String category) onArticleSelected;

  const _WardrobeBrowserSheet({
    required this.onArticleSelected,
  });

  @override
  State<_WardrobeBrowserSheet> createState() => _WardrobeBrowserSheetState();
}

class _WardrobeBrowserSheetState extends State<_WardrobeBrowserSheet> {
  String _selectedCategory = 'tops';
  Map<String, List<SavedArticle>> _articlesByCategory = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAllArticles();
  }

  Future<void> _loadAllArticles() async {
    final service = await SavedOutfitsService.getInstance();
    final tops = await service.getSavedArticles(category: 'tops');
    final bottoms = await service.getSavedArticles(category: 'bottoms');
    final dresses = await service.getSavedArticles(category: 'dresses');

    if (mounted) {
      setState(() {
        _articlesByCategory = {
          'tops': tops,
          'bottoms': bottoms,
          'dresses': dresses,
        };
        _isLoading = false;
      });
    }
  }

  String _getCategoryApiName(String category) {
    switch (category) {
      case 'tops':
        return 'tops';
      case 'bottoms':
        return 'bottoms';
      case 'dresses':
        return 'one-pieces';
      default:
        return 'tops';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Handle bar
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 8),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFD4C4B5),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Title
          Padding(
            padding: const EdgeInsets.all(ThemeConstants.spacingMedium),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8B7355).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.checkroom, color: Color(0xFF6B5B4F)),
                ),
                const SizedBox(width: 12),
                Text(
                  'My Wardrobe',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: const Color(0xFF4A3F35),
                      ),
                ),
              ],
            ),
          ),
          // Category tabs
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: ThemeConstants.spacingMedium),
            child: Row(
              children: [
                _CategoryTab(
                  label: 'Tops',
                  isSelected: _selectedCategory == 'tops',
                  onTap: () => setState(() => _selectedCategory = 'tops'),
                ),
                const SizedBox(width: 8),
                _CategoryTab(
                  label: 'Bottoms',
                  isSelected: _selectedCategory == 'bottoms',
                  onTap: () => setState(() => _selectedCategory = 'bottoms'),
                ),
                const SizedBox(width: 8),
                _CategoryTab(
                  label: 'Dresses',
                  isSelected: _selectedCategory == 'dresses',
                  onTap: () => setState(() => _selectedCategory = 'dresses'),
                ),
              ],
            ),
          ),
          const SizedBox(height: ThemeConstants.spacingMedium),
          // Articles grid
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _buildArticlesGrid(),
          ),
        ],
      ),
    );
  }

  Widget _buildArticlesGrid() {
    final articles = _articlesByCategory[_selectedCategory] ?? [];

    if (articles.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.checkroom_outlined,
              size: 48,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 12),
            Text(
              'No items yet',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(ThemeConstants.spacingMedium),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 0.75,
      ),
      itemCount: articles.length,
      itemBuilder: (context, index) {
        final article = articles[index];
        return GestureDetector(
          onTap: () {
            widget.onArticleSelected(
              article.imagePath,
              _getCategoryApiName(_selectedCategory),
            );
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(
              File(article.imagePath),
              fit: BoxFit.cover,
            ),
          ),
        );
      },
    );
  }
}

class _CategoryTab extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _CategoryTab({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF8B7355) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? const Color(0xFF8B7355) : const Color(0xFFD4C4B5),
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : const Color(0xFF6B5B4F),
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
