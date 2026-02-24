import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

class ManualBlurEditor extends StatefulWidget {
  final String imagePath;

  const ManualBlurEditor({
    super.key,
    required this.imagePath,
  });

  static Future<String?> show(BuildContext context, String imagePath) {
    return Navigator.of(context).push<String>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => ManualBlurEditor(imagePath: imagePath),
      ),
    );
  }

  @override
  State<ManualBlurEditor> createState() => _ManualBlurEditorState();
}

class _ManualBlurEditorState extends State<ManualBlurEditor> {
  final List<BlurRegion> _blurRegions = [];
  final GlobalKey _imageKey = GlobalKey();
  Size? _imageSize;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    // Add a default blur region in the upper area
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _addDefaultBlurRegion();
    });
  }

  void _addDefaultBlurRegion() {
    final renderBox = _imageKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox != null) {
      _imageSize = renderBox.size;
      setState(() {
        _blurRegions.add(BlurRegion(
          center: Offset(_imageSize!.width / 2, _imageSize!.height * 0.25),
          radiusX: _imageSize!.width * 0.12,
          radiusY: _imageSize!.width * 0.16,
        ));
      });
    }
  }

  void _onTapDown(TapDownDetails details) {
    final renderBox = _imageKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final localPosition = renderBox.globalToLocal(details.globalPosition);
    _imageSize = renderBox.size;

    setState(() {
      _blurRegions.add(BlurRegion(
        center: localPosition,
        radiusX: _imageSize!.width * 0.12,
        radiusY: _imageSize!.width * 0.16,
      ));
    });
  }

  void _removeRegion(int index) {
    setState(() {
      _blurRegions.removeAt(index);
    });
  }

  Future<void> _applyBlurAndSave() async {
    if (_blurRegions.isEmpty || _imageSize == null) {
      Navigator.of(context).pop(widget.imagePath);
      return;
    }

    setState(() => _isProcessing = true);

    try {
      // Load original image
      final bytes = await File(widget.imagePath).readAsBytes();
      final originalImage = img.decodeImage(bytes);

      if (originalImage == null) {
        Navigator.of(context).pop(widget.imagePath);
        return;
      }

      // Calculate scale between display size and actual image size
      final scaleX = originalImage.width / _imageSize!.width;
      final scaleY = originalImage.height / _imageSize!.height;

      // Apply oval blur to each region
      for (final region in _blurRegions) {
        // Scale coordinates to actual image size
        final centerX = (region.center.dx * scaleX).toInt();
        final centerY = (region.center.dy * scaleY).toInt();
        final radiusX = (region.radiusX * scaleX).toInt();
        final radiusY = (region.radiusY * scaleY).toInt();

        // Calculate bounding box for the blur region
        final left = (centerX - radiusX).clamp(0, originalImage.width - 1);
        final top = (centerY - radiusY).clamp(0, originalImage.height - 1);
        final right = (centerX + radiusX).clamp(0, originalImage.width);
        final bottom = (centerY + radiusY).clamp(0, originalImage.height);
        final width = right - left;
        final height = bottom - top;

        if (width <= 0 || height <= 0) continue;

        // Extract region
        final regionImage = img.copyCrop(
          originalImage,
          x: left,
          y: top,
          width: width,
          height: height,
        );

        // Apply blur
        final blurredRegion = img.gaussianBlur(regionImage, radius: 13);

        // Apply oval mask - only copy pixels within the ellipse
        final regionCenterX = centerX - left;
        final regionCenterY = centerY - top;

        for (int y = 0; y < height; y++) {
          for (int x = 0; x < width; x++) {
            // Calculate normalized distance from center (ellipse equation)
            final dx = (x - regionCenterX) / radiusX;
            final dy = (y - regionCenterY) / radiusY;
            final distance = (dx * dx + dy * dy);

            // Only apply blur within the ellipse (distance <= 1)
            if (distance <= 1.0) {
              final blurredPixel = blurredRegion.getPixel(x, y);
              originalImage.setPixel(left + x, top + y, blurredPixel);
            }
          }
        }
      }

      // Save blurred image
      final tempDir = await getTemporaryDirectory();
      final outputPath = '${tempDir.path}/manual_blur_${const Uuid().v4()}.jpg';
      final outputFile = File(outputPath);
      await outputFile.writeAsBytes(img.encodeJpg(originalImage, quality: 90));

      if (mounted) {
        Navigator.of(context).pop(outputPath);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error applying blur: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Blur Face'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(null),
        ),
        actions: [
          TextButton(
            onPressed: _isProcessing ? null : _applyBlurAndSave,
            child: _isProcessing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text(
                    'Done',
                    style: TextStyle(
                      color: Color(0xFFF59E0B),
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Instructions
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.black,
            child: const Text(
              'Tap to add blur circles. Drag to move. Pinch to resize.',
              style: TextStyle(color: Colors.white70, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ),
          // Image with blur regions
          Expanded(
            child: Center(
              child: GestureDetector(
                onTapDown: _onTapDown,
                child: Stack(
                  children: [
                    Image.file(
                      File(widget.imagePath),
                      key: _imageKey,
                      fit: BoxFit.contain,
                    ),
                    // Blur region overlays
                    ..._blurRegions.asMap().entries.map((entry) {
                      final index = entry.key;
                      final region = entry.value;
                      return _BlurRegionWidget(
                        region: region,
                        onChanged: (newRegion) {
                          setState(() {
                            _blurRegions[index] = newRegion;
                          });
                        },
                        onDelete: () => _removeRegion(index),
                      );
                    }),
                  ],
                ),
              ),
            ),
          ),
          // Bottom controls
          Container(
            padding: const EdgeInsets.all(20),
            color: Colors.black,
            child: SafeArea(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _ControlButton(
                    icon: Icons.add_circle_outline,
                    label: 'Add Blur',
                    onTap: () {
                      if (_imageSize != null) {
                        setState(() {
                          _blurRegions.add(BlurRegion(
                            center: Offset(
                              _imageSize!.width / 2,
                              _imageSize!.height / 3,
                            ),
                            radiusX: _imageSize!.width * 0.12,
                            radiusY: _imageSize!.width * 0.16,
                          ));
                        });
                      }
                    },
                  ),
                  _ControlButton(
                    icon: Icons.delete_outline,
                    label: 'Clear All',
                    onTap: () {
                      setState(() {
                        _blurRegions.clear();
                      });
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class BlurRegion {
  final Offset center;
  final double radiusX;
  final double radiusY;

  BlurRegion({required this.center, required this.radiusX, required this.radiusY});

  BlurRegion copyWith({Offset? center, double? radiusX, double? radiusY}) {
    return BlurRegion(
      center: center ?? this.center,
      radiusX: radiusX ?? this.radiusX,
      radiusY: radiusY ?? this.radiusY,
    );
  }
}

class _BlurRegionWidget extends StatefulWidget {
  final BlurRegion region;
  final ValueChanged<BlurRegion> onChanged;
  final VoidCallback onDelete;

  const _BlurRegionWidget({
    required this.region,
    required this.onChanged,
    required this.onDelete,
  });

  @override
  State<_BlurRegionWidget> createState() => _BlurRegionWidgetState();
}

class _BlurRegionWidgetState extends State<_BlurRegionWidget> {
  Offset? _startFocalPoint;
  late Offset _startCenter;
  late double _startRadiusX;
  late double _startRadiusY;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: widget.region.center.dx - widget.region.radiusX,
      top: widget.region.center.dy - widget.region.radiusY,
      child: GestureDetector(
        onScaleStart: (details) {
          _startFocalPoint = details.focalPoint;
          _startCenter = widget.region.center;
          _startRadiusX = widget.region.radiusX;
          _startRadiusY = widget.region.radiusY;
        },
        onScaleUpdate: (details) {
          // Handle both drag (scale=1) and pinch (scale!=1)
          final delta = details.focalPoint - _startFocalPoint!;

          widget.onChanged(widget.region.copyWith(
            center: Offset(
              _startCenter.dx + delta.dx,
              _startCenter.dy + delta.dy,
            ),
            radiusX: (_startRadiusX * details.scale).clamp(20.0, 200.0),
            radiusY: (_startRadiusY * details.scale).clamp(25.0, 250.0),
          ));
        },
        onDoubleTap: widget.onDelete,
        child: Container(
          width: widget.region.radiusX * 2,
          height: widget.region.radiusY * 2,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.all(
              Radius.elliptical(widget.region.radiusX, widget.region.radiusY),
            ),
            color: Colors.black.withOpacity(0.5),
            border: Border.all(
              color: const Color(0xFFF59E0B),
              width: 3,
            ),
          ),
          child: const Center(
            child: Icon(
              Icons.blur_on,
              color: Colors.white,
              size: 24,
            ),
          ),
        ),
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ControlButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
