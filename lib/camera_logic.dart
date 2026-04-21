import 'dart:async';
import 'dart:io';
import 'dart:math';

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

  bool _isHdEnabled = true;
  FlashMode _selectedFlashMode = FlashMode.off;

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
    final oldController = _cameraController;

    try {
      if (mounted) {
        setState(() {
          _isInitializingCamera = true;
          _cameraController = null;
        });
      }

      await oldController?.dispose();

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
        _isHdEnabled ? ResolutionPreset.high : ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await controller.initialize();
      await controller.setFocusMode(FocusMode.auto);
      await controller.setExposureMode(ExposureMode.auto);

      try {
        await controller.setFlashMode(_selectedFlashMode);
      } catch (_) {
        //
      }

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
        _cameraController = null;
        _isInitializingCamera = false;
      });

      _showSnackBar('Failed to initialize camera: $error');
    }
  }

  Future<void> _setFlashMode(FlashMode mode) async {
    final controller = _cameraController;

    if (controller == null || !controller.value.isInitialized) return;

    try {
      await controller.setFlashMode(mode);

      if (!mounted) return;

      setState(() {
        _selectedFlashMode = mode;
      });
    } catch (error) {
      _showSnackBar('Failed to change flash mode: $error');
    }
  }

  Future<void> _toggleHd(bool enabled) async {
    if (_isHdEnabled == enabled) return;

    setState(() {
      _isHdEnabled = enabled;
    });

    await _initializeCamera();
  }

  String _flashModeLabel(FlashMode mode) {
    switch (mode) {
      case FlashMode.off:
        return 'OFF';
      case FlashMode.auto:
        return 'AUTO';
      case FlashMode.always:
        return 'ON';
      case FlashMode.torch:
        return 'TORCH';
    }
  }

  Future<void> _showCameraSettingsSheet() async {
    await showModalBottomSheet(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              decoration: const BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 46,
                        height: 5,
                        decoration: BoxDecoration(
                          color: AppColors.textMuted,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Camera Settings',
                      style: AppTextStyles.sectionTitle.copyWith(fontSize: 20),
                    ),
                    const SizedBox(height: 18),

                    /// HD Toggle
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.backgroundSecondary,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.hd_rounded,
                            color: AppColors.accent,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'HD Capture',
                                  style: AppTextStyles.cardTitle.copyWith(
                                    fontSize: 15,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _isHdEnabled
                                      ? 'High resolution is enabled.'
                                      : 'Medium resolution is enabled.',
                                  style: AppTextStyles.bodySecondary.copyWith(
                                    fontSize: 12.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: _isHdEnabled,
                            onChanged: (value) async {
                              Navigator.pop(sheetContext);
                              await _toggleHd(value);
                            },
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 14),

                    /// Flash Mode
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.backgroundSecondary,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Flash Mode',
                            style: AppTextStyles.cardTitle.copyWith(
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Current: ${_flashModeLabel(_selectedFlashMode)}',
                            style: AppTextStyles.bodySecondary.copyWith(
                              fontSize: 12.5,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: _FlashModeButton(
                                  label: 'OFF',
                                  isSelected:
                                  _selectedFlashMode == FlashMode.off,
                                  onTap: () async {
                                    Navigator.pop(sheetContext);
                                    await _setFlashMode(FlashMode.off);
                                  },
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _FlashModeButton(
                                  label: 'AUTO',
                                  isSelected:
                                  _selectedFlashMode == FlashMode.auto,
                                  onTap: () async {
                                    Navigator.pop(sheetContext);
                                    await _setFlashMode(FlashMode.auto);
                                  },
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _FlashModeButton(
                                  label: 'ON',
                                  isSelected:
                                  _selectedFlashMode == FlashMode.always,
                                  onTap: () async {
                                    Navigator.pop(sheetContext);
                                    await _setFlashMode(FlashMode.always);
                                  },
                                ),
                              ),
                            ],
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
    } catch (_) {}

    return DocumentDetectionResult.failure(
      reason: 'Automatic crop is unavailable.',
    );
  }

  bool _isValidBounds(DocumentBounds bounds) {
    const minSize = 0.08;
    const minArea = 0.04;

    final tl = Offset(bounds.topLeft.x, bounds.topLeft.y);
    final tr = Offset(bounds.topRight.x, bounds.topRight.y);
    final br = Offset(bounds.bottomRight.x, bounds.bottomRight.y);
    final bl = Offset(bounds.bottomLeft.x, bounds.bottomLeft.y);

    double distance(Offset a, Offset b) => (a - b).distance;

    final widthTop = distance(tl, tr);
    final widthBottom = distance(bl, br);
    final heightLeft = distance(tl, bl);
    final heightRight = distance(tr, br);

    if (widthTop < minSize ||
        widthBottom < minSize ||
        heightLeft < minSize ||
        heightRight < minSize) {
      return false;
    }

    final area = _polygonArea([tl, tr, br, bl]).abs();
    if (area < minArea) {
      return false;
    }

    return _isConvexQuadrilateral(bounds);
  }

  bool _isConvexQuadrilateral(DocumentBounds bounds) {
    final points = <Offset>[
      Offset(bounds.topLeft.x, bounds.topLeft.y),
      Offset(bounds.topRight.x, bounds.topRight.y),
      Offset(bounds.bottomRight.x, bounds.bottomRight.y),
      Offset(bounds.bottomLeft.x, bounds.bottomLeft.y),
    ];

    for (int i = 0; i < points.length; i++) {
      final a = points[i];
      final b = points[(i + 1) % points.length];
      final c = points[(i + 2) % points.length];
      final cross = _cross(a, b, c);

      if (cross.abs() < 0.002) {
        return false;
      }
    }

    bool hasPositive = false;
    bool hasNegative = false;

    for (int i = 0; i < points.length; i++) {
      final a = points[i];
      final b = points[(i + 1) % points.length];
      final c = points[(i + 2) % points.length];
      final cross = _cross(a, b, c);

      if (cross > 0) hasPositive = true;
      if (cross < 0) hasNegative = true;

      if (hasPositive && hasNegative) {
        return false;
      }
    }

    return true;
  }

  double _cross(Offset a, Offset b, Offset c) {
    final ab = b - a;
    final bc = c - b;
    return (ab.dx * bc.dy) - (ab.dy * bc.dx);
  }

  double _polygonArea(List<Offset> points) {
    double sum = 0.0;

    for (int i = 0; i < points.length; i++) {
      final current = points[i];
      final next = points[(i + 1) % points.length];
      sum += (current.dx * next.dy) - (next.dx * current.dy);
    }

    return 0.5 * sum;
  }

  bool _sameBounds(DocumentBounds a, DocumentBounds b) {
    return a.topLeft.x == b.topLeft.x &&
        a.topLeft.y == b.topLeft.y &&
        a.topRight.x == b.topRight.x &&
        a.topRight.y == b.topRight.y &&
        a.bottomRight.x == b.bottomRight.x &&
        a.bottomRight.y == b.bottomRight.y &&
        a.bottomLeft.x == b.bottomLeft.x &&
        a.bottomLeft.y == b.bottomLeft.y;
  }

  /// Sends the current crop bounds to the native layer and requests
  /// a real cropped image file.
  ///
  /// This now throws on crop failure so the preview flow can stop
  /// instead of silently forwarding the original image.
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

      throw Exception('Crop returned an empty path.');
    } on PlatformException catch (e) {
      throw Exception(e.message ?? e.code);
    }
  }

  /// Updates one dragged crop corner while keeping the crop
  /// as a usable quadrilateral.
  ///
  /// Invalid updates are rejected and the previous bounds are kept.
  DocumentBounds _updateDraggedCorner({
    required DocumentBounds bounds,
    required String cornerKey,
    required DragUpdateDetails details,
    required Rect imageRect,
  }) {
    const double minGap = 0.03;

    final dx = details.delta.dx / imageRect.width;
    final dy = details.delta.dy / imageRect.height;

    double clamp01(double value) => value.clamp(0.0, 1.0);

    DocumentBounds candidate;

    switch (cornerKey) {
      case 'topLeft':
        candidate = bounds.copyWith(
          topLeft: bounds.topLeft.copyWith(
            x: clamp01(
              (bounds.topLeft.x + dx).clamp(
                0.0,
                bounds.topRight.x - minGap,
              ),
            ),
            y: clamp01(
              (bounds.topLeft.y + dy).clamp(
                0.0,
                bounds.bottomLeft.y - minGap,
              ),
            ),
          ),
        );
        break;

      case 'topRight':
        candidate = bounds.copyWith(
          topRight: bounds.topRight.copyWith(
            x: clamp01(
              (bounds.topRight.x + dx).clamp(
                bounds.topLeft.x + minGap,
                1.0,
              ),
            ),
            y: clamp01(
              (bounds.topRight.y + dy).clamp(
                0.0,
                bounds.bottomRight.y - minGap,
              ),
            ),
          ),
        );
        break;

      case 'bottomRight':
        candidate = bounds.copyWith(
          bottomRight: bounds.bottomRight.copyWith(
            x: clamp01(
              (bounds.bottomRight.x + dx).clamp(
                bounds.bottomLeft.x + minGap,
                1.0,
              ),
            ),
            y: clamp01(
              (bounds.bottomRight.y + dy).clamp(
                bounds.topRight.y + minGap,
                1.0,
              ),
            ),
          ),
        );
        break;

      case 'bottomLeft':
        candidate = bounds.copyWith(
          bottomLeft: bounds.bottomLeft.copyWith(
            x: clamp01(
              (bounds.bottomLeft.x + dx).clamp(
                0.0,
                bounds.bottomRight.x - minGap,
              ),
            ),
            y: clamp01(
              (bounds.bottomLeft.y + dy).clamp(
                bounds.topLeft.y + minGap,
                1.0,
              ),
            ),
          ),
        );
        break;

      default:
        return bounds;
    }

    if (!_isConvexQuadrilateral(candidate)) {
      return bounds;
    }

    final area = _polygonArea([
      Offset(candidate.topLeft.x, candidate.topLeft.y),
      Offset(candidate.topRight.x, candidate.topRight.y),
      Offset(candidate.bottomRight.x, candidate.bottomRight.y),
      Offset(candidate.bottomLeft.x, candidate.bottomLeft.y),
    ]).abs();

    if (area < 0.02) {
      return bounds;
    }

    return candidate;
  }

  DocumentBounds _updateEdge({
    required DocumentBounds bounds,
    required String edge,
    required DragUpdateDetails details,
    required Rect imageRect,
  }) {
    double clamp01(double value) => value.clamp(0.0, 1.0);

    DocumentCorner startCorner;
    DocumentCorner endCorner;

    switch (edge) {
      case 'top':
        startCorner = bounds.topLeft;
        endCorner = bounds.topRight;
        break;
      case 'right':
        startCorner = bounds.topRight;
        endCorner = bounds.bottomRight;
        break;
      case 'bottom':
        startCorner = bounds.bottomLeft;
        endCorner = bounds.bottomRight;
        break;
      case 'left':
        startCorner = bounds.topLeft;
        endCorner = bounds.bottomLeft;
        break;
      default:
        return bounds;
    }

    final startPx = Offset(
      imageRect.left + (startCorner.x * imageRect.width),
      imageRect.top + (startCorner.y * imageRect.height),
    );

    final endPx = Offset(
      imageRect.left + (endCorner.x * imageRect.width),
      imageRect.top + (endCorner.y * imageRect.height),
    );

    final edgeVector = endPx - startPx;
    final edgeLength = edgeVector.distance;

    if (edgeLength < 1e-3) {
      return bounds;
    }

    // Unit normal pointing perpendicular to the edge.
    // This is the direction the edge should move when dragged.
    final normal = Offset(
      -edgeVector.dy / edgeLength,
      edgeVector.dx / edgeLength,
    );

    final drag = details.delta;
    final projected = (drag.dx * normal.dx) + (drag.dy * normal.dy);

    final moveDxNorm = (normal.dx * projected) / imageRect.width;
    final moveDyNorm = (normal.dy * projected) / imageRect.height;

    DocumentBounds candidate;

    switch (edge) {
      case 'top':
        candidate = bounds.copyWith(
          topLeft: bounds.topLeft.copyWith(
            x: clamp01(bounds.topLeft.x + moveDxNorm),
            y: clamp01(bounds.topLeft.y + moveDyNorm),
          ),
          topRight: bounds.topRight.copyWith(
            x: clamp01(bounds.topRight.x + moveDxNorm),
            y: clamp01(bounds.topRight.y + moveDyNorm),
          ),
        );
        break;

      case 'right':
        candidate = bounds.copyWith(
          topRight: bounds.topRight.copyWith(
            x: clamp01(bounds.topRight.x + moveDxNorm),
            y: clamp01(bounds.topRight.y + moveDyNorm),
          ),
          bottomRight: bounds.bottomRight.copyWith(
            x: clamp01(bounds.bottomRight.x + moveDxNorm),
            y: clamp01(bounds.bottomRight.y + moveDyNorm),
          ),
        );
        break;

      case 'bottom':
        candidate = bounds.copyWith(
          bottomLeft: bounds.bottomLeft.copyWith(
            x: clamp01(bounds.bottomLeft.x + moveDxNorm),
            y: clamp01(bounds.bottomLeft.y + moveDyNorm),
          ),
          bottomRight: bounds.bottomRight.copyWith(
            x: clamp01(bounds.bottomRight.x + moveDxNorm),
            y: clamp01(bounds.bottomRight.y + moveDyNorm),
          ),
        );
        break;

      case 'left':
        candidate = bounds.copyWith(
          topLeft: bounds.topLeft.copyWith(
            x: clamp01(bounds.topLeft.x + moveDxNorm),
            y: clamp01(bounds.topLeft.y + moveDyNorm),
          ),
          bottomLeft: bounds.bottomLeft.copyWith(
            x: clamp01(bounds.bottomLeft.x + moveDxNorm),
            y: clamp01(bounds.bottomLeft.y + moveDyNorm),
          ),
        );
        break;

      default:
        return bounds;
    }

    if (!_isConvexQuadrilateral(candidate)) {
      return bounds;
    }

    final area = _polygonArea([
      Offset(candidate.topLeft.x, candidate.topLeft.y),
      Offset(candidate.topRight.x, candidate.topRight.y),
      Offset(candidate.bottomRight.x, candidate.bottomRight.y),
      Offset(candidate.bottomLeft.x, candidate.bottomLeft.y),
    ]).abs();

    if (area < 0.02) {
      return bounds;
    }

    return candidate;
  }

  /// Navigates to the processing page using the finalized image path.
  Future<void> _openProcessingPage(String imagePath) async {
    final oldController = _cameraController;

    if (mounted) {
      setState(() {
        _cameraController = null;
        _isInitializingCamera = true;
      });
    }

    try {
      await oldController?.dispose();
    } catch (_) {
      //
    }

    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProcessingPage(imagePath: imagePath),
      ),
    );

    if (!mounted) return;

    await _initializeCamera();
  }

  Future<ImageInfo> _loadImageInfo(File file) async {
    final imageProvider = FileImage(file);
    final completer = Completer<ImageInfo>();
    final stream = imageProvider.resolve(const ImageConfiguration());

    late final ImageStreamListener listener;
    listener = ImageStreamListener(
          (info, _) {
        completer.complete(info);
        stream.removeListener(listener);
      },
      onError: (error, stackTrace) {
        completer.completeError(error, stackTrace);
        stream.removeListener(listener);
      },
    );

    stream.addListener(listener);
    return completer.future;
  }

  Rect _computeContainImageRect({
    required Size imageSize,
    required Size previewSize,
  }) {
    final fitted = applyBoxFit(
      BoxFit.contain,
      imageSize,
      previewSize,
    );

    final renderSize = fitted.destination;
    final dx = (previewSize.width - renderSize.width) / 2.0;
    final dy = (previewSize.height - renderSize.height) / 2.0;

    return Rect.fromLTWH(
      dx,
      dy,
      renderSize.width,
      renderSize.height,
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

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        DocumentBounds currentBounds = initialBounds;
        bool isProcessing = false;
        bool hasDetectedDocument = detectionResult.hasDocument;
        String? detectionMessage = detectionResult.hasDocument
            ? null
            : (detectionResult.reason ?? 'No visible document detected.');
        String? adjustmentMessage;
        bool adjustmentBlocked = false;

        return StatefulBuilder(
          builder: (context, setModalState) {
            final bool shapeIsValid = _isValidBounds(currentBounds);

            final bool canContinue =
                hasDetectedDocument && shapeIsValid && !adjustmentBlocked;

            final String? cropValidationMessage = !hasDetectedDocument
                ? (detectionMessage ?? 'No visible document detected.')
                : (!shapeIsValid
                ? 'Crop is not allowed. Please fix the document bounds or retry Auto Crop.'
                : (adjustmentBlocked
                ? (adjustmentMessage ??
                'Adjustment not allowed. Keep the crop as a quadrilateral.')
                : null));

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

                    /// Main preview area with:
                    /// - fitted image display
                    /// - crop polygon overlay
                    /// - colored corner handles for precise adjustment
                    /// - subtle edge handles for quick border movement
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

                                return FutureBuilder<ImageInfo>(
                                  future: _loadImageInfo(File(imagePath)),
                                  builder: (context, snapshot) {
                                    if (!snapshot.hasData) {
                                      return const Center(
                                        child: CircularProgressIndicator(
                                          color: AppColors.accent,
                                        ),
                                      );
                                    }

                                    final imageInfo = snapshot.data!;
                                    final imageSize = Size(
                                      imageInfo.image.width.toDouble(),
                                      imageInfo.image.height.toDouble(),
                                    );

                                    final imageRect = _computeContainImageRect(
                                      imageSize: imageSize,
                                      previewSize: previewSize,
                                    );

                                    Offset mapPoint(DocumentCorner point) {
                                      return Offset(
                                        imageRect.left + (point.x * imageRect.width),
                                        imageRect.top + (point.y * imageRect.height),
                                      );
                                    }

                                    final topLeftPoint = mapPoint(currentBounds.topLeft);
                                    final topRightPoint = mapPoint(currentBounds.topRight);
                                    final bottomRightPoint = mapPoint(currentBounds.bottomRight);
                                    final bottomLeftPoint = mapPoint(currentBounds.bottomLeft);

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
                                              imageRect: imageRect,
                                            ),
                                          ),
                                        ),
                                        _DraggableCornerHandle(
                                          point: currentBounds.topLeft,
                                          imageRect: imageRect,
                                          handleColor: Colors.greenAccent,
                                          onDragUpdate: (details) {
                                            setModalState(() {
                                              final previous = currentBounds;

                                              final updated =
                                              _updateDraggedCorner(
                                                bounds: currentBounds,
                                                cornerKey: 'topLeft',
                                                details: details,
                                                imageRect: imageRect,
                                              );

                                              final wasBlocked =
                                              _sameBounds(updated, previous);

                                              currentBounds = updated;
                                              adjustmentBlocked = wasBlocked;
                                              adjustmentMessage = wasBlocked
                                                  ? 'Adjustment not allowed. Keep the crop as a quadrilateral.'
                                                  : null;
                                            });
                                          },
                                        ),
                                        _DraggableCornerHandle(
                                          point: currentBounds.topRight,
                                          imageRect: imageRect,
                                          handleColor: Colors.lightBlueAccent,
                                          onDragUpdate: (details) {
                                            setModalState(() {
                                              final previous = currentBounds;

                                              final updated =
                                              _updateDraggedCorner(
                                                bounds: currentBounds,
                                                cornerKey: 'topRight',
                                                details: details,
                                                imageRect: imageRect,
                                              );

                                              final wasBlocked =
                                              _sameBounds(updated, previous);

                                              currentBounds = updated;
                                              adjustmentBlocked = wasBlocked;
                                              adjustmentMessage = wasBlocked
                                                  ? 'Adjustment not allowed. Keep the crop as a quadrilateral.'
                                                  : null;
                                            });
                                          },
                                        ),
                                        _DraggableCornerHandle(
                                          point: currentBounds.bottomRight,
                                          imageRect: imageRect,
                                          handleColor: Colors.orangeAccent,
                                          onDragUpdate: (details) {
                                            setModalState(() {
                                              final previous = currentBounds;

                                              final updated =
                                              _updateDraggedCorner(
                                                bounds: currentBounds,
                                                cornerKey: 'bottomRight',
                                                details: details,
                                                imageRect: imageRect,
                                              );

                                              final wasBlocked =
                                              _sameBounds(updated, previous);

                                              currentBounds = updated;
                                              adjustmentBlocked = wasBlocked;
                                              adjustmentMessage = wasBlocked
                                                  ? 'Adjustment not allowed. Keep the crop as a quadrilateral.'
                                                  : null;
                                            });
                                          },
                                        ),
                                        _DraggableCornerHandle(
                                          point: currentBounds.bottomLeft,
                                          imageRect: imageRect,
                                          handleColor: Colors.purpleAccent,
                                          onDragUpdate: (details) {
                                            setModalState(() {
                                              final previous = currentBounds;

                                              final updated =
                                              _updateDraggedCorner(
                                                bounds: currentBounds,
                                                cornerKey: 'bottomLeft',
                                                details: details,
                                                imageRect: imageRect,
                                              );

                                              final wasBlocked =
                                              _sameBounds(updated, previous);

                                              currentBounds = updated;
                                              adjustmentBlocked = wasBlocked;
                                              adjustmentMessage = wasBlocked
                                                  ? 'Adjustment not allowed. Keep the crop as a quadrilateral.'
                                                  : null;
                                            });
                                          },
                                        ),
                                        _EdgeHandle(
                                          start: topLeftPoint,
                                          end: topRightPoint,
                                          highlight: cropValidationMessage != null,
                                          onDragUpdate: (details) {
                                            setModalState(() {
                                              final previous = currentBounds;

                                              final updated = _updateEdge(
                                                bounds: currentBounds,
                                                edge: 'top',
                                                details: details,
                                                imageRect: imageRect,
                                              );

                                              final wasBlocked = _sameBounds(updated, previous);

                                              currentBounds = updated;
                                              adjustmentBlocked = wasBlocked;
                                              adjustmentMessage = wasBlocked
                                                  ? 'Adjustment not allowed. Keep the crop as a quadrilateral.'
                                                  : null;
                                            });
                                          },
                                        ),
                                        _EdgeHandle(
                                          start: bottomLeftPoint,
                                          end: bottomRightPoint,
                                          highlight: cropValidationMessage != null,
                                          onDragUpdate: (details) {
                                            setModalState(() {
                                              final previous = currentBounds;

                                              final updated = _updateEdge(
                                                bounds: currentBounds,
                                                edge: 'bottom',
                                                details: details,
                                                imageRect: imageRect,
                                              );

                                              final wasBlocked = _sameBounds(updated, previous);

                                              currentBounds = updated;
                                              adjustmentBlocked = wasBlocked;
                                              adjustmentMessage = wasBlocked
                                                  ? 'Adjustment not allowed. Keep the crop as a quadrilateral.'
                                                  : null;
                                            });
                                          },
                                        ),
                                        _EdgeHandle(
                                          start: topLeftPoint,
                                          end: bottomLeftPoint,
                                          highlight: cropValidationMessage != null,
                                          onDragUpdate: (details) {
                                            setModalState(() {
                                              final previous = currentBounds;

                                              final updated = _updateEdge(
                                                bounds: currentBounds,
                                                edge: 'left',
                                                details: details,
                                                imageRect: imageRect,
                                              );

                                              final wasBlocked = _sameBounds(updated, previous);

                                              currentBounds = updated;
                                              adjustmentBlocked = wasBlocked;
                                              adjustmentMessage = wasBlocked
                                                  ? 'Adjustment not allowed. Keep the crop as a quadrilateral.'
                                                  : null;
                                            });
                                          },
                                        ),
                                        _EdgeHandle(
                                          start: topRightPoint,
                                          end: bottomRightPoint,
                                          highlight: cropValidationMessage != null,
                                          onDragUpdate: (details) {
                                            setModalState(() {
                                              final previous = currentBounds;

                                              final updated = _updateEdge(
                                                bounds: currentBounds,
                                                edge: 'right',
                                                details: details,
                                                imageRect: imageRect,
                                              );

                                              final wasBlocked = _sameBounds(updated, previous);

                                              currentBounds = updated;
                                              adjustmentBlocked = wasBlocked;
                                              adjustmentMessage = wasBlocked
                                                  ? 'Adjustment not allowed. Keep the crop as a quadrilateral.'
                                                  : null;
                                            });
                                          },
                                        ),
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
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (cropValidationMessage != null) ...[
                            Container(
                              width: double.infinity,
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.background,
                                borderRadius: BorderRadius.circular(14),
                                border:
                                Border.all(color: AppColors.accentSoft),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(
                                    Icons.warning_amber_rounded,
                                    color: AppColors.accentSoft,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      cropValidationMessage,
                                      style:
                                      AppTextStyles.bodySecondary.copyWith(
                                        fontSize: 12.5,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          Row(
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

                                    final detection =
                                    await _detectDocumentBounds(imagePath);

                                    if (!mounted) return;

                                    setModalState(() {
                                      isProcessing = false;
                                      hasDetectedDocument =
                                          detection.hasDocument;
                                      detectionMessage = detection.hasDocument
                                          ? null
                                          : (detection.reason ??
                                          'No clear document detected.');

                                      if (detection.hasDocument &&
                                          detection.bounds != null) {
                                        currentBounds = detection.bounds!;
                                        adjustmentBlocked = false;
                                        adjustmentMessage = null;
                                      }
                                    });

                                    if (detection.hasDocument &&
                                        detection.bounds != null) {
                                      _showSnackBar('Auto-crop updated.');
                                      return;
                                    }

                                    _showSnackBar(
                                      detection.reason ??
                                          'No clear document detected. Processing remains blocked.',
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _PreviewFooterAction(
                                  icon: Icons.check_circle_rounded,
                                  label: 'Continue',
                                  color: canContinue
                                      ? AppColors.accent
                                      : AppColors.textMuted,
                                  isEnabled: canContinue,
                                  onTap: () async {
                                    if (!hasDetectedDocument) {
                                      _showSnackBar(
                                        detectionMessage ??
                                            'No visible document detected. Please retry or recapture.',
                                      );
                                      return;
                                    }

                                    if (!_isValidBounds(currentBounds)) {
                                      _showSnackBar(
                                        'Crop is not allowed. Please fix the document bounds or retry Auto Crop.',
                                      );
                                      return;
                                    }

                                    setModalState(() {
                                      isProcessing = true;
                                    });

                                    try {
                                      final croppedImagePath =
                                      await _cropDocumentImage(
                                        imagePath: imagePath,
                                        bounds: currentBounds,
                                      );

                                      if (!mounted) return;

                                      setModalState(() {
                                        adjustmentBlocked = false;
                                        adjustmentMessage = null;
                                      });

                                      Navigator.pop(sheetContext);
                                      await _openProcessingPage(croppedImagePath);
                                    } catch (error) {
                                      if (!mounted) return;

                                      setModalState(() {
                                        isProcessing = false;
                                      });

                                      _showSnackBar('Cropping failed: $error');
                                    }
                                  },
                                ),
                              ),
                            ],
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
                    onTap: _showCameraSettingsSheet,
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
  final bool isEnabled;

  const _PreviewFooterAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.isPrimary = false,
    this.isEnabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor =
    isEnabled ? color : AppColors.textMuted.withOpacity(0.75);

    final effectiveBackground = isPrimary
        ? (isEnabled ? AppColors.card : AppColors.background)
        : AppColors.background;

    final effectiveBorderColor = isPrimary
        ? (isEnabled ? const Color(0x33FF8F69) : AppColors.border)
        : AppColors.border;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: isEnabled ? onTap : null,
        child: Ink(
          height: 56,
          decoration: BoxDecoration(
            color: effectiveBackground,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: effectiveBorderColor,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: effectiveColor,
                size: 20,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.button.copyWith(
                    color: effectiveColor,
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

class _FlashModeButton extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _FlashModeButton({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Ink(
          height: 46,
          decoration: BoxDecoration(
            color: isSelected ? AppColors.card : AppColors.background,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected ? AppColors.accent : AppColors.border,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: AppTextStyles.button.copyWith(
                color: isSelected
                    ? AppColors.accent
                    : AppColors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Interactive crop handle anchored to one normalized corner point.
class _DraggableCornerHandle extends StatelessWidget {
  final DocumentCorner point;
  final Rect imageRect;
  final Color handleColor;
  final ValueChanged<DragUpdateDetails> onDragUpdate;

  const _DraggableCornerHandle({
    required this.point,
    required this.imageRect,
    required this.handleColor,
    required this.onDragUpdate,
  });

  @override
  Widget build(BuildContext context) {
    const double handleRadius = 20;

    return Positioned(
      left: imageRect.left + (point.x * imageRect.width) - handleRadius,
      top: imageRect.top + (point.y * imageRect.height) - handleRadius,
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
                color: handleColor,
                width: 3,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Visible draggable edge handle that stays attached to the current crop edge.
///
/// The handle rotates to match the edge direction and includes a dark outline
/// so it remains visible on bright or white backgrounds.
class _EdgeHandle extends StatelessWidget {
  final Offset start;
  final Offset end;
  final bool highlight;
  final ValueChanged<DragUpdateDetails> onDragUpdate;

  const _EdgeHandle({
    required this.start,
    required this.end,
    required this.onDragUpdate,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final edgeColor = highlight
        ? Colors.white.withOpacity(0.96)
        : Colors.white.withOpacity(0.86);

    final outlineColor = Colors.black.withOpacity(0.65);

    final mid = Offset(
      (start.dx + end.dx) / 2,
      (start.dy + end.dy) / 2,
    );

    final angle = atan2(end.dy - start.dy, end.dx - start.dx);

    const double pillWidth = 58;
    const double pillHeight = 12;
    const double hitPadding = 18;

    return Positioned(
      left: mid.dx - (pillWidth / 2) - hitPadding / 2,
      top: mid.dy - (pillHeight / 2) - hitPadding / 2,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onPanUpdate: onDragUpdate,
        child: Container(
          width: pillWidth + hitPadding,
          height: pillHeight + hitPadding,
          alignment: Alignment.center,
          child: Transform.rotate(
            angle: angle,
            child: Container(
              width: pillWidth,
              height: pillHeight,
              decoration: BoxDecoration(
                color: edgeColor,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: outlineColor,
                  width: 1.8,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.28),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                  BoxShadow(
                    color: edgeColor.withOpacity(0.30),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ],
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
  final Rect imageRect;

  const _DocumentBoundsPainter({
    required this.bounds,
    required this.imageRect,
  });

  @override
  void paint(Canvas canvas, Size size) {
    Offset mapPoint(Offset normalized) {
      return Offset(
        imageRect.left + (normalized.dx * imageRect.width),
        imageRect.top + (normalized.dy * imageRect.height),
      );
    }

    final topLeft = mapPoint(Offset(bounds.topLeft.x, bounds.topLeft.y));
    final topRight = mapPoint(Offset(bounds.topRight.x, bounds.topRight.y));
    final bottomRight =
    mapPoint(Offset(bounds.bottomRight.x, bounds.bottomRight.y));
    final bottomLeft =
    mapPoint(Offset(bounds.bottomLeft.x, bounds.bottomLeft.y));

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
    return oldDelegate.bounds != bounds ||
        oldDelegate.imageRect != imageRect;
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
