import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import 'core/theme/app_colors.dart';
import 'core/theme/app_text_styles.dart';
import 'processing_page.dart';

/// Main camera workflow page for the STALA capture flow.
///
/// Responsibilities:
/// - initialize and display the back camera
/// - capture an image or select one from gallery
/// - show a crop preview sheet
/// - allow manual crop corner adjustment
/// - auto-detect and crop document bounds through the native bridge
/// - forward the final cropped image to the processing page
class CameraLogicPage extends StatefulWidget {
  const CameraLogicPage({super.key});

  @override
  State<CameraLogicPage> createState() => _CameraLogicPageState();
}

/// A single normalized crop corner.
///
/// Values are stored from 0.0 to 1.0 relative to the image space
/// so they are easy to pass across UI and native processing layers.
class DocumentCorner {
  final double x;
  final double y;

  const DocumentCorner({
    required this.x,
    required this.y,
  });

  factory DocumentCorner.fromMap(Map<dynamic, dynamic> map) {
    return DocumentCorner(
      x: (map['x'] as num).toDouble(),
      y: (map['y'] as num).toDouble(),
    );
  }

  Map<String, double> toMap() {
    return {
      'x': x,
      'y': y,
    };
  }

  DocumentCorner copyWith({
    double? x,
    double? y,
  }) {
    return DocumentCorner(
      x: x ?? this.x,
      y: y ?? this.y,
    );
  }
}

/// Holds the four document crop corners.
///
/// Expected order:
/// - topLeft
/// - topRight
/// - bottomRight
/// - bottomLeft
///
/// This structure is shared between the UI crop overlay and the
/// native/Python crop pipeline.
class DocumentBounds {
  final DocumentCorner topLeft;
  final DocumentCorner topRight;
  final DocumentCorner bottomRight;
  final DocumentCorner bottomLeft;

  const DocumentBounds({
    required this.topLeft,
    required this.topRight,
    required this.bottomRight,
    required this.bottomLeft,
  });

  factory DocumentBounds.fromMap(Map<dynamic, dynamic> map) {
    return DocumentBounds(
      topLeft: DocumentCorner.fromMap(map['topLeft']),
      topRight: DocumentCorner.fromMap(map['topRight']),
      bottomRight: DocumentCorner.fromMap(map['bottomRight']),
      bottomLeft: DocumentCorner.fromMap(map['bottomLeft']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'topLeft': topLeft.toMap(),
      'topRight': topRight.toMap(),
      'bottomRight': bottomRight.toMap(),
      'bottomLeft': bottomLeft.toMap(),
    };
  }

  /// Fallback crop rectangle used when automatic detection is not available.
  factory DocumentBounds.defaultInset() {
    return const DocumentBounds(
      topLeft: DocumentCorner(x: 0.08, y: 0.12),
      topRight: DocumentCorner(x: 0.92, y: 0.12),
      bottomRight: DocumentCorner(x: 0.92, y: 0.90),
      bottomLeft: DocumentCorner(x: 0.08, y: 0.90),
    );
  }

  DocumentBounds copyWith({
    DocumentCorner? topLeft,
    DocumentCorner? topRight,
    DocumentCorner? bottomRight,
    DocumentCorner? bottomLeft,
  }) {
    return DocumentBounds(
      topLeft: topLeft ?? this.topLeft,
      topRight: topRight ?? this.topRight,
      bottomRight: bottomRight ?? this.bottomRight,
      bottomLeft: bottomLeft ?? this.bottomLeft,
    );
  }
}

class _CameraLogicPageState extends State<CameraLogicPage> {
  /// Bridge used for native Android / Chaquopy / Python document operations.
  ///
  /// Current intended methods:
  /// - detectDocumentBounds
  /// - cropDocumentImage
  static const MethodChannel _pythonChannel =
  MethodChannel('stala/python_bridge');

  final ImagePicker _imagePicker = ImagePicker();

  CameraController? _cameraController;
  List<CameraDescription> _availableCameras = const [];

  bool _isInitializingCamera = true;
  bool _isCapturingImage = false;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  /// Initializes the best available back camera and prepares the preview.
  ///
  /// Auto focus and auto exposure are enabled after setup to keep the
  /// capture experience simple and mostly automatic.
  Future<void> _initializeCamera() async {
    try {
      _availableCameras = await availableCameras();

      if (_availableCameras.isEmpty) {
        throw Exception('No available camera was found on this device.');
      }

      final backCamera = _availableCameras.firstWhere(
            (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => _availableCameras.first,
      );

      final controller = CameraController(
        backCamera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await controller.initialize();
      await controller.setFocusMode(FocusMode.auto);
      await controller.setExposureMode(ExposureMode.auto);

      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _cameraController = controller;
        _isInitializingCamera = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _isInitializingCamera = false;
      });

      _showSnackBar('Failed to initialize camera: $error');
    }
  }

  /// Requests access to photos before opening gallery.
  ///
  /// Limited access is also accepted because it is sufficient
  /// for user-selected images on modern Android/iOS flows.
  Future<bool> _ensureGalleryPermission() async {
    PermissionStatus status = await Permission.photos.status;

    if (status.isGranted || status.isLimited) {
      return true;
    }

    status = await Permission.photos.request();

    if (status.isGranted || status.isLimited) {
      return true;
    }

    if (status.isPermanentlyDenied) {
      _showSnackBar(
        'Gallery permission is permanently denied. Please enable it in app settings.',
      );
      await openAppSettings();
      return false;
    }

    _showSnackBar('Gallery permission was not granted.');
    return false;
  }

  /// Captures a photo using the active camera preview and opens the crop sheet.
  Future<void> _captureImage() async {
    final controller = _cameraController;

    if (controller == null ||
        !controller.value.isInitialized ||
        _isCapturingImage) {
      return;
    }

    try {
      setState(() {
        _isCapturingImage = true;
      });

      final capturedFile = await controller.takePicture();

      if (!mounted) return;

      await _showImagePreviewSheet(
        imagePath: capturedFile.path,
        sourceLabel: 'Captured Photo',
      );
    } catch (error) {
      _showSnackBar('Failed to capture image: $error');
    } finally {
      if (!mounted) return;

      setState(() {
        _isCapturingImage = false;
      });
    }
  }

  /// Opens the gallery picker and sends the selected image
  /// into the same preview-and-crop flow as camera capture.
  Future<void> _pickImageFromGallery() async {
    try {
      final hasPermission = await _ensureGalleryPermission();
      if (!hasPermission) return;

      final pickedFile = await _imagePicker.pickImage(
        source: ImageSource.gallery,
      );

      if (pickedFile == null || !mounted) return;

      await _showImagePreviewSheet(
        imagePath: pickedFile.path,
        sourceLabel: 'From Gallery',
      );
    } catch (error) {
      _showSnackBar('Failed to open gallery: $error');
    }
  }

  /// Asks the native layer to detect document bounds on the selected image.
  ///
  /// Unlike the old version, this does not silently pretend success.
  /// If no document is detected, the UI can stop auto-crop cleanly.
  Future<DocumentDetectionResult> _detectDocumentBounds(String imagePath) async {
    try {
      final result = await _pythonChannel.invokeMethod(
        'detectDocumentBounds',
        {'imagePath': imagePath},
      );

      if (result is Map) {
        final hasDocument = result['hasDocument'] == true;
        final confidence = (result['confidence'] as num?)?.toDouble() ?? 0.0;
        final reason = result['reason']?.toString();

        if (hasDocument && result['bounds'] is Map) {
          return DocumentDetectionResult.success(
            bounds: DocumentBounds.fromMap(result['bounds']),
            confidence: confidence,
          );
        }

        return DocumentDetectionResult.failure(
          confidence: confidence,
          reason: reason ?? 'No visible document detected.',
        );
      }
    } catch (_) {
      // Keep failure quiet here; the UI will handle the message.
    }

    return DocumentDetectionResult.failure(
      reason: 'Automatic crop is unavailable.',
    );
  }

  /// Re-runs boundary detection and returns fresh crop points.
  Future<DocumentBounds> _resetDocumentBounds(String imagePath) async {
    return _detectDocumentBounds(imagePath);
  }

  bool _isValidBounds(DocumentBounds bounds) {
    double widthTop = (bounds.topRight.x - bounds.topLeft.x).abs();
    double widthBottom = (bounds.bottomRight.x - bounds.bottomLeft.x).abs();
    double heightLeft = (bounds.bottomLeft.y - bounds.topLeft.y).abs();
    double heightRight = (bounds.bottomRight.y - bounds.topRight.y).abs();

    const minSize = 0.08;

    return widthTop >= minSize &&
        widthBottom >= minSize &&
        heightLeft >= minSize &&
        heightRight >= minSize;
  }

  /// Sends the current crop bounds to the native layer and requests
  /// a real cropped image file.
  ///
  /// If cropping is unavailable, the original image path is returned
  /// so downstream navigation still works.
  Future<String> _cropDocumentImage({
    required String imagePath,
    required DocumentBounds bounds,
  }) async {
    try {
      final result = await _pythonChannel.invokeMethod(
        'cropDocumentImage',
        {
          'imagePath': imagePath,
          'bounds': bounds.toMap(),
        },
      );

      if (result is String && result.isNotEmpty) {
        return result;
      }
    } catch (_) {
      //
    }

    return imagePath;
  }

  /// Updates one dragged crop corner while preventing the shape
  /// from crossing over itself.
  ///
  /// A minimum gap is preserved so the resulting quadrilateral stays valid.
  DocumentBounds _updateDraggedCorner({
    required DocumentBounds bounds,
    required String cornerKey,
    required DragUpdateDetails details,
    required Size previewSize,
  }) {
    const double minGap = 0.06;

    final double dx = details.delta.dx / previewSize.width;
    final double dy = details.delta.dy / previewSize.height;

    switch (cornerKey) {
      case 'topLeft':
        return bounds.copyWith(
          topLeft: bounds.topLeft.copyWith(
            x: (bounds.topLeft.x + dx).clamp(0.0, bounds.topRight.x - minGap),
            y: (bounds.topLeft.y + dy).clamp(0.0, bounds.bottomLeft.y - minGap),
          ),
        );

      case 'topRight':
        return bounds.copyWith(
          topRight: bounds.topRight.copyWith(
            x: (bounds.topRight.x + dx).clamp(bounds.topLeft.x + minGap, 1.0),
            y: (bounds.topRight.y + dy)
                .clamp(0.0, bounds.bottomRight.y - minGap),
          ),
        );

      case 'bottomRight':
        return bounds.copyWith(
          bottomRight: bounds.bottomRight.copyWith(
            x: (bounds.bottomRight.x + dx)
                .clamp(bounds.bottomLeft.x + minGap, 1.0),
            y: (bounds.bottomRight.y + dy)
                .clamp(bounds.topRight.y + minGap, 1.0),
          ),
        );

      case 'bottomLeft':
        return bounds.copyWith(
          bottomLeft: bounds.bottomLeft.copyWith(
            x: (bounds.bottomLeft.x + dx)
                .clamp(0.0, bounds.bottomRight.x - minGap),
            y: (bounds.bottomLeft.y + dy)
                .clamp(bounds.topLeft.y + minGap, 1.0),
          ),
        );

      default:
        return bounds;
    }
  }

  /// Navigates to the processing page using the finalized image path.
  Future<void> _openProcessingPage(String imagePath) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProcessingPage(imagePath: imagePath),
      ),
    );
  }

  /// Shows the image preview bottom sheet.
  ///
  /// Available actions:
  /// - Retry: discard preview and return to capture page
  /// - Auto Crop: re-detect document bounds
  /// - Continue: crop image and proceed to processing page
  Future<void> _showImagePreviewSheet({
    required String imagePath,
    required String sourceLabel,
  }) async {
    final detectionResult = await _detectDocumentBounds(imagePath);
    final initialBounds =
    detectionResult.hasDocument && detectionResult.bounds != null
        ? detectionResult.bounds!
        : DocumentBounds.defaultInset();

    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        DocumentBounds currentBounds = initialBounds;
        bool isProcessing = false;

        return StatefulBuilder(
          builder: (context, setModalState) {
            return FractionallySizedBox(
              heightFactor: 0.83,
              child: Container(
                decoration: const BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(28),
                  ),
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 10),

                    /// Small top handle to indicate draggable bottom sheet.
                    Container(
                      width: 46,
                      height: 5,
                      decoration: BoxDecoration(
                        color: AppColors.textMuted,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),

                    const SizedBox(height: 16),

                    /// Sheet header.
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Image Preview',
                              style: AppTextStyles.sectionTitle.copyWith(
                                fontSize: 20,
                              ),
                            ),
                          ),
                          Text(
                            sourceLabel,
                            style: AppTextStyles.bodySecondary.copyWith(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    /// Main preview area with crop overlay and draggable handles.
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(22),
                          child: Container(
                            color: AppColors.surface,
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                final previewSize = Size(
                                  constraints.maxWidth,
                                  constraints.maxHeight,
                                );

                                return Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    Image.file(
                                      File(imagePath),
                                      fit: BoxFit.contain,
                                    ),
                                    IgnorePointer(
                                      child: CustomPaint(
                                        painter: _DocumentBoundsPainter(
                                          bounds: currentBounds,
                                        ),
                                      ),
                                    ),
                                    _DraggableCornerHandle(
                                      point: currentBounds.topLeft,
                                      previewSize: previewSize,
                                      onDragUpdate: (details) {
                                        setModalState(() {
                                          currentBounds = _updateDraggedCorner(
                                            bounds: currentBounds,
                                            cornerKey: 'topLeft',
                                            details: details,
                                            previewSize: previewSize,
                                          );
                                        });
                                      },
                                    ),
                                    _DraggableCornerHandle(
                                      point: currentBounds.topRight,
                                      previewSize: previewSize,
                                      onDragUpdate: (details) {
                                        setModalState(() {
                                          currentBounds = _updateDraggedCorner(
                                            bounds: currentBounds,
                                            cornerKey: 'topRight',
                                            details: details,
                                            previewSize: previewSize,
                                          );
                                        });
                                      },
                                    ),
                                    _DraggableCornerHandle(
                                      point: currentBounds.bottomRight,
                                      previewSize: previewSize,
                                      onDragUpdate: (details) {
                                        setModalState(() {
                                          currentBounds = _updateDraggedCorner(
                                            bounds: currentBounds,
                                            cornerKey: 'bottomRight',
                                            details: details,
                                            previewSize: previewSize,
                                          );
                                        });
                                      },
                                    ),
                                    _DraggableCornerHandle(
                                      point: currentBounds.bottomLeft,
                                      previewSize: previewSize,
                                      onDragUpdate: (details) {
                                        setModalState(() {
                                          currentBounds = _updateDraggedCorner(
                                            bounds: currentBounds,
                                            cornerKey: 'bottomLeft',
                                            details: details,
                                            previewSize: previewSize,
                                          );
                                        });
                                      },
                                    ),

                                    /// Processing blocker used while auto-cropping
                                    /// or generating the cropped output.
                                    if (isProcessing)
                                      Container(
                                        color: const Color(0x66000000),
                                        child: const Center(
                                          child: CircularProgressIndicator(
                                            color: AppColors.accent,
                                          ),
                                        ),
                                      ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    /// Footer actions for preview flow.
                    Container(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
                      decoration: const BoxDecoration(
                        color: AppColors.backgroundSecondary,
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(22),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: _PreviewFooterAction(
                              icon: Icons.refresh_rounded,
                              label: 'Retry',
                              color: AppColors.textSecondary,
                              onTap: () {
                                Navigator.pop(sheetContext);
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _PreviewFooterAction(
                              icon: Icons.crop_free_rounded,
                              label: 'Auto Crop',
                              color: AppColors.warning,
                              onTap: () async {
                                setModalState(() {
                                  isProcessing = true;
                                });

                                final detection = await _detectDocumentBounds(imagePath);

                                if (!mounted) return;

                                setModalState(() {
                                  isProcessing = false;
                                });

                                if (detection.hasDocument && detection.bounds != null) {
                                  setModalState(() {
                                    currentBounds = detection.bounds!;
                                  });

                                  _showSnackBar('Document detected.');
                                  return;
                                }

                                _showSnackBar(
                                  detection.reason ?? 'No visible document detected. Adjust manually or retake the image.',
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _PreviewFooterAction(
                              icon: Icons.check_circle_rounded,
                              label: 'Continue',
                              color: AppColors.accent,
                              isPrimary: true,
                              onTap: () async {
                                setModalState(() {
                                  isProcessing = true;
                                });

                                final croppedImagePath = await _cropDocumentImage(
                                  imagePath: imagePath,
                                  bounds: currentBounds,
                                );

                                if (!_isValidBounds(currentBounds)) {
                                  setModalState(() {
                                    isProcessing = false;
                                  });
                                  _showSnackBar('Crop area is too small or invalid.');
                                  return;
                                }

                                Navigator.pop(sheetContext);
                                await _openProcessingPage(croppedImagePath);
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }


  /// Shows a short message for camera and gallery flow feedback.
  void _showSnackBar(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.backgroundSecondary,
        content: Text(
          message,
          style: AppTextStyles.body,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _cameraController;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: _isInitializingCamera
            ? const Center(
          child: CircularProgressIndicator(
            color: AppColors.accent,
          ),
        )
            : controller == null || !controller.value.isInitialized
            ? const _CameraUnavailableView()
            : Stack(
          children: [
            /// Live camera feed.
            Positioned.fill(
              child: CameraPreview(controller),
            ),

            /// Soft dark overlay to improve contrast of controls.
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0xAA05101D),
                        Colors.transparent,
                        Color(0x8805111D),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            /// Rule-of-thirds grid for capture framing.
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _CameraGridPainter(),
                ),
              ),
            ),

            /// Top navigation and settings actions.
            Positioned(
              top: 14,
              left: 20,
              right: 20,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _TopCircleButton(
                    icon: Icons.arrow_back_ios_new_rounded,
                    onTap: () => Navigator.pop(context),
                  ),
                  _TopCircleButton(
                    icon: Icons.settings_outlined,
                    onTap: () {
                      _showSnackBar(
                        'Settings button is reserved for future camera options.',
                      );
                    },
                  ),
                ],
              ),
            ),

            /// Bottom capture controls.
            Positioned(
              left: 22,
              right: 22,
              bottom: 30,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _BottomSquareButton(
                    icon: Icons.photo_library_outlined,
                    backgroundColor: AppColors.accentSoft,
                    onTap: _pickImageFromGallery,
                  ),
                  _ShutterButton(
                    onTap: _captureImage,
                  ),
                  const SizedBox(width: 52, height: 52),
                ],
              ),
            ),

            /// Fullscreen blocker while taking a picture.
            if (_isCapturingImage)
              Positioned.fill(
                child: Container(
                  color: const Color(0x66000000),
                  child: const Center(
                    child: CircularProgressIndicator(
                      color: AppColors.accent,
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

/// Fallback content shown when camera initialization fails.
class _CameraUnavailableView extends StatelessWidget {
  const _CameraUnavailableView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'Camera unavailable',
        style: AppTextStyles.body.copyWith(fontSize: 16),
      ),
    );
  }
}

/// Small circular action button used in the camera top bar.
class _TopCircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _TopCircleButton({
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0x220B162B),
        border: Border.all(
          color: AppColors.border,
        ),
      ),
      child: IconButton(
        onPressed: onTap,
        icon: Icon(
          icon,
          size: 20,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

/// Square gallery shortcut button shown at the bottom left.
class _BottomSquareButton extends StatelessWidget {
  final IconData icon;
  final Color backgroundColor;
  final VoidCallback onTap;

  const _BottomSquareButton({
    required this.icon,
    required this.backgroundColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(
          icon,
          color: AppColors.textPrimary,
          size: 24,
        ),
      ),
    );
  }
}

/// Main circular shutter button used for camera capture.
class _ShutterButton extends StatelessWidget {
  final VoidCallback onTap;

  const _ShutterButton({
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 82,
        height: 82,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.textPrimary,
          border: Border.all(
            color: AppColors.textSecondary,
            width: 4,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Center(
          child: Container(
            width: 66,
            height: 66,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFFDADADA),
                width: 2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Footer button used in the preview sheet.
///
/// `isPrimary` is used to visually emphasize the final continue action.
class _PreviewFooterAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool isPrimary;

  const _PreviewFooterAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.isPrimary = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Ink(
          height: 56,
          decoration: BoxDecoration(
            color: isPrimary ? AppColors.card : AppColors.background,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isPrimary
                  ? const Color(0x33FF8F69)
                  : AppColors.border,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: color,
                size: 20,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.button.copyWith(
                    color: color,
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

/// Interactive crop handle anchored to one normalized corner point.
class _DraggableCornerHandle extends StatelessWidget {
  final DocumentCorner point;
  final Size previewSize;
  final ValueChanged<DragUpdateDetails> onDragUpdate;

  const _DraggableCornerHandle({
    required this.point,
    required this.previewSize,
    required this.onDragUpdate,
  });

  @override
  Widget build(BuildContext context) {
    final left = (point.x * previewSize.width) - 20;
    final top = (point.y * previewSize.height) - 20;

    return Positioned(
      left: left,
      top: top,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onPanUpdate: onDragUpdate,
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.textPrimary,
              border: Border.all(
                color: AppColors.success,
                width: 3,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Draws the crop quadrilateral and its corner markers over the preview image.
class _DocumentBoundsPainter extends CustomPainter {
  final DocumentBounds bounds;

  const _DocumentBoundsPainter({
    required this.bounds,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final topLeft =
    Offset(bounds.topLeft.x * size.width, bounds.topLeft.y * size.height);
    final topRight =
    Offset(bounds.topRight.x * size.width, bounds.topRight.y * size.height);
    final bottomRight = Offset(
      bounds.bottomRight.x * size.width,
      bounds.bottomRight.y * size.height,
    );
    final bottomLeft = Offset(
      bounds.bottomLeft.x * size.width,
      bounds.bottomLeft.y * size.height,
    );

    final borderPaint = Paint()
      ..color = AppColors.success
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    final handleFillPaint = Paint()
      ..color = AppColors.textPrimary
      ..style = PaintingStyle.fill;

    final handleStrokePaint = Paint()
      ..color = AppColors.success
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final borderPath = Path()
      ..moveTo(topLeft.dx, topLeft.dy)
      ..lineTo(topRight.dx, topRight.dy)
      ..lineTo(bottomRight.dx, bottomRight.dy)
      ..lineTo(bottomLeft.dx, bottomLeft.dy)
      ..close();

    canvas.drawPath(borderPath, borderPaint);

    for (final point in [topLeft, topRight, bottomRight, bottomLeft]) {
      canvas.drawCircle(point, 8, handleFillPaint);
      canvas.drawCircle(point, 10, handleStrokePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _DocumentBoundsPainter oldDelegate) {
    return oldDelegate.bounds != bounds;
  }
}

/// Paints a basic rule-of-thirds grid on the live camera preview.
class _CameraGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.textSecondary.withOpacity(0.20)
      ..strokeWidth = 0.8;

    final col1 = size.width / 3;
    final col2 = col1 * 2;
    final row1 = size.height / 3;
    final row2 = row1 * 2;

    canvas.drawLine(Offset(col1, 0), Offset(col1, size.height), paint);
    canvas.drawLine(Offset(col2, 0), Offset(col2, size.height), paint);
    canvas.drawLine(Offset(0, row1), Offset(size.width, row1), paint);
    canvas.drawLine(Offset(0, row2), Offset(size.width, row2), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Result returned by document auto-detection.
///
/// This tells the UI whether a document was found and, if so,
/// what bounds should be used for the crop overlay.
class DocumentDetectionResult {
  final bool hasDocument;
  final double confidence;
  final DocumentBounds? bounds;
  final String? reason;

  const DocumentDetectionResult({
    required this.hasDocument,
    required this.confidence,
    this.bounds,
    this.reason,
  });

  factory DocumentDetectionResult.success({
    required DocumentBounds bounds,
    double confidence = 1.0,
  }) {
    return DocumentDetectionResult(
      hasDocument: true,
      confidence: confidence,
      bounds: bounds,
    );
  }

  factory DocumentDetectionResult.failure({
    double confidence = 0.0,
    String? reason,
  }) {
    return DocumentDetectionResult(
      hasDocument: false,
      confidence: confidence,
      reason: reason,
    );
  }
}