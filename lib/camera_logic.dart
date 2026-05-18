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
import 'services/tutorial_service.dart';

/// Main camera workflow page for the STALA capture flow.
///
/// Refactor goals:
/// - support detection states: strong / weak / fail
/// - support second-pass crop validation before proceeding
/// - allow guarded override for fail state via long press
class CameraLogicPage extends StatefulWidget {
  const CameraLogicPage({super.key});

  @override
  State<CameraLogicPage> createState() => _CameraLogicPageState();
}

enum SheetValidationState { strong, weak, fail }

class DocumentCorner {
  final double x;
  final double y;

  const DocumentCorner({required this.x, required this.y});

  factory DocumentCorner.fromMap(Map<dynamic, dynamic> map) {
    return DocumentCorner(
      x: (map['x'] as num).toDouble(),
      y: (map['y'] as num).toDouble(),
    );
  }

  Map<String, double> toMap() {
    return {'x': x, 'y': y};
  }

  DocumentCorner copyWith({double? x, double? y}) {
    return DocumentCorner(x: x ?? this.x, y: y ?? this.y);
  }
}

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

class DocumentDetectionResult {
  final bool hasDocument;
  final double confidence;
  final DocumentBounds? bounds;
  final String? reason;
  final SheetValidationState validationState;
  final bool needsManualAdjustment;

  const DocumentDetectionResult({
    required this.hasDocument,
    required this.confidence,
    this.bounds,
    this.reason,
    required this.validationState,
    required this.needsManualAdjustment,
  });

  factory DocumentDetectionResult.success({
    required DocumentBounds bounds,
    required double confidence,
    required SheetValidationState validationState,
    required bool needsManualAdjustment,
    String? reason,
  }) {
    return DocumentDetectionResult(
      hasDocument: true,
      confidence: confidence,
      bounds: bounds,
      reason: reason,
      validationState: validationState,
      needsManualAdjustment: needsManualAdjustment,
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
      bounds: null,
      validationState: SheetValidationState.fail,
      needsManualAdjustment: true,
    );
  }
}

class CropValidationResult {
  final SheetValidationState validationState;
  final double confidence;
  final String? reason;

  const CropValidationResult({
    required this.validationState,
    required this.confidence,
    this.reason,
  });
}

class _CameraLogicPageState extends State<CameraLogicPage> {
  static const MethodChannel _visionPipelineChannel = MethodChannel(
    'stala/python_bridge',
  );

  final ImagePicker _imagePicker = ImagePicker();

  CameraController? _cameraController;
  List<CameraDescription> _availableCameras = const [];

  bool _isInitializingCamera = true;
  bool _isCapturingImage = false;
  String? _cameraUnavailableMessage;

  bool _isHdEnabled = true;
  FlashMode _selectedFlashMode = FlashMode.off;

  Timer? _cropValidationDebounce;
  final GlobalKey _cropFrameTourKey = GlobalKey();
  final GlobalKey _cropHandleTourKey = GlobalKey();
  final GlobalKey _cropWarningTourKey = GlobalKey();
  final GlobalKey _cropResetTourKey = GlobalKey();
  final GlobalKey _cropContinueTourKey = GlobalKey();
  final GlobalKey _cropHelpTourKey = GlobalKey();

  List<GlobalKey> get _cropTourKeys => [
    _cropFrameTourKey,
    _cropHandleTourKey,
    _cropResetTourKey,
    _cropContinueTourKey,
    _cropHelpTourKey,
  ];

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    final oldController = _cameraController;

    try {
      if (mounted) {
        setState(() {
          _isInitializingCamera = true;
          _cameraController = null;
          _cameraUnavailableMessage = null;
        });
      }

      await oldController?.dispose();

      final hasCameraPermission = await _ensureCameraPermission();
      if (!hasCameraPermission) {
        if (!mounted) return;

        setState(() {
          _cameraController = null;
          _isInitializingCamera = false;
          _cameraUnavailableMessage =
              'Camera permission is required to capture music sheets.';
        });
        return;
      }

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
      } catch (_) {}

      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _cameraController = controller;
        _isInitializingCamera = false;
        _cameraUnavailableMessage = null;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _cameraController = null;
        _isInitializingCamera = false;
        _cameraUnavailableMessage = 'Failed to initialize camera: $error';
      });

      _showSnackBar('Failed to initialize camera: $error');
    }
  }

  Future<bool> _ensureCameraPermission() async {
    var status = await Permission.camera.status;

    if (status.isGranted || status.isLimited) return true;

    if (status.isPermanentlyDenied || status.isRestricted) return false;

    status = await Permission.camera.request();
    return status.isGranted || status.isLimited;
  }

  Future<void> _openCameraPermissionSettings() async {
    await openAppSettings();
    if (!mounted) return;
    await _initializeCamera();
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
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
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
                          const Icon(Icons.hd_rounded, color: AppColors.accent),
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

  Future<bool> _ensureGalleryPermission() async {
    PermissionStatus status = await Permission.photos.status;

    if (status.isGranted || status.isLimited) return true;

    status = await Permission.photos.request();

    if (status.isGranted || status.isLimited) return true;

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

  SheetValidationState _parseValidationState(String? raw) {
    switch (raw) {
      case 'strong':
        return SheetValidationState.strong;
      case 'weak':
        return SheetValidationState.weak;
      default:
        return SheetValidationState.fail;
    }
  }

  Future<DocumentDetectionResult> _detectDocumentBounds(
    String imagePath,
  ) async {
    try {
      final result = await _visionPipelineChannel.invokeMethod(
        'detectDocumentBounds',
        {'imagePath': imagePath},
      );

      if (result is Map) {
        final confidence = (result['confidence'] as num?)?.toDouble() ?? 0.0;
        final reason = result['reason']?.toString();
        final validationState = _parseValidationState(
          result['validationState']?.toString(),
        );
        final needsManualAdjustment =
            result['needsManualAdjustment'] == true ||
            validationState != SheetValidationState.strong;

        if (result['bounds'] is Map) {
          return DocumentDetectionResult.success(
            bounds: DocumentBounds.fromMap(result['bounds']),
            confidence: confidence,
            validationState: validationState,
            needsManualAdjustment: needsManualAdjustment,
            reason: reason,
          );
        }

        return DocumentDetectionResult.failure(
          confidence: confidence,
          reason:
              reason ??
              'Document bounds could not be detected confidently. Kindly adjust the box.',
        );
      }
    } catch (_) {}

    return DocumentDetectionResult.failure(
      reason: 'Document detection is unavailable. Kindly adjust the box.',
    );
  }

  Future<CropValidationResult> _validateSelectedCrop({
    required String imagePath,
    required DocumentBounds bounds,
  }) async {
    try {
      final result = await _visionPipelineChannel.invokeMethod(
        'validateSelectedCrop',
        {'imagePath': imagePath, 'bounds': bounds.toMap()},
      );

      if (result is Map) {
        return CropValidationResult(
          validationState: _parseValidationState(
            result['validationState']?.toString(),
          ),
          confidence: (result['confidence'] as num?)?.toDouble() ?? 0.0,
          reason: result['reason']?.toString(),
        );
      }
    } catch (_) {}

    return const CropValidationResult(
      validationState: SheetValidationState.fail,
      confidence: 0.0,
      reason:
          'The selected crop does not yet appear to be a reliable music-sheet region.',
    );
  }

  Future<bool> _showWeakValidationDialog(String message) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: AppColors.background,
          title: Text(
            'Music sheet needs review',
            style: AppTextStyles.sectionTitle.copyWith(fontSize: 18),
          ),
          content: Text(
            message,
            style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Adjust'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Proceed'),
            ),
          ],
        );
      },
    );

    return result == true;
  }

  Future<bool> _showFailValidationDialog(String message) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: AppColors.background,
          title: Text(
            'Music sheet not confidently detected',
            style: AppTextStyles.sectionTitle.copyWith(fontSize: 18),
          ),
          content: Text(
            message,
            style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Adjust'),
            ),
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                _showSnackBar('Press and hold to proceed.');
              },
              onLongPress: () => Navigator.pop(dialogContext, true),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.warning),
                ),
                child: Text(
                  'Hold to Proceed',
                  style: AppTextStyles.button.copyWith(
                    color: AppColors.warning,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    return result == true;
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

      if (cross.abs() < 0.002) return false;
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

      if (hasPositive && hasNegative) return false;
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

  Future<String> _cropDocumentImage({
    required String imagePath,
    required DocumentBounds bounds,
  }) async {
    try {
      final result = await _visionPipelineChannel.invokeMethod(
        'cropDocumentImage',
        {'imagePath': imagePath, 'bounds': bounds.toMap()},
      );

      if (result is String && result.isNotEmpty) return result;

      throw Exception('Crop returned an empty path.');
    } on PlatformException catch (e) {
      throw Exception(e.message ?? e.code);
    }
  }

  Future<void> _proceedToCropAndOpen({
    required BuildContext sheetContext,
    required String imagePath,
    required DocumentBounds bounds,
  }) async {
    final croppedImagePath = await _cropDocumentImage(
      imagePath: imagePath,
      bounds: bounds,
    );

    if (!mounted) return;

    Navigator.pop(sheetContext);
    await _openProcessingPage(
      sourceImagePath: imagePath,
      croppedImagePath: croppedImagePath,
    );
  }

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
              (bounds.topLeft.x + dx).clamp(0.0, bounds.topRight.x - minGap),
            ),
            y: clamp01(
              (bounds.topLeft.y + dy).clamp(0.0, bounds.bottomLeft.y - minGap),
            ),
          ),
        );
        break;
      case 'topRight':
        candidate = bounds.copyWith(
          topRight: bounds.topRight.copyWith(
            x: clamp01(
              (bounds.topRight.x + dx).clamp(bounds.topLeft.x + minGap, 1.0),
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
              (bounds.bottomLeft.y + dy).clamp(bounds.topLeft.y + minGap, 1.0),
            ),
          ),
        );
        break;
      default:
        return bounds;
    }

    if (!_isConvexQuadrilateral(candidate)) return bounds;

    final area = _polygonArea([
      Offset(candidate.topLeft.x, candidate.topLeft.y),
      Offset(candidate.topRight.x, candidate.topRight.y),
      Offset(candidate.bottomRight.x, candidate.bottomRight.y),
      Offset(candidate.bottomLeft.x, candidate.bottomLeft.y),
    ]).abs();

    if (area < 0.02) return bounds;

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

    if (edgeLength < 1e-3) return bounds;

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

    if (!_isConvexQuadrilateral(candidate)) return bounds;

    final area = _polygonArea([
      Offset(candidate.topLeft.x, candidate.topLeft.y),
      Offset(candidate.topRight.x, candidate.topRight.y),
      Offset(candidate.bottomRight.x, candidate.bottomRight.y),
      Offset(candidate.bottomLeft.x, candidate.bottomLeft.y),
    ]).abs();

    if (area < 0.02) return bounds;

    return candidate;
  }

  Future<void> _openProcessingPage({
    required String sourceImagePath,
    required String croppedImagePath,
  }) async {
    final oldController = _cameraController;

    if (mounted) {
      setState(() {
        _cameraController = null;
        _isInitializingCamera = true;
      });
    }

    try {
      await oldController?.dispose();
    } catch (_) {}

    if (!mounted) return;

    final shouldReturnHome = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ProcessingPage(
          sourceImagePath: sourceImagePath,
          croppedImagePath: croppedImagePath,
        ),
      ),
    );

    if (!mounted) return;

    if (shouldReturnHome == true) {
      Navigator.pop(context, true);
      return;
    }

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
    final fitted = applyBoxFit(BoxFit.contain, imageSize, previewSize);

    final renderSize = fitted.destination;
    final dx = (previewSize.width - renderSize.width) / 2.0;
    final dy = (previewSize.height - renderSize.height) / 2.0;

    return Rect.fromLTWH(dx, dy, renderSize.width, renderSize.height);
  }

  Future<void> _showImagePreviewSheet({
    required String imagePath,
    required String sourceLabel,
  }) async {
    final detectionResult = await _detectDocumentBounds(imagePath);

    final initialBounds =
        detectionResult.bounds ?? DocumentBounds.defaultInset();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        var cropTourQueued = false;
        DocumentBounds currentBounds = initialBounds;
        bool isProcessing = false;
        bool hasDetectedDocument = detectionResult.bounds != null;
        bool hasManualCandidate = detectionResult.bounds == null;
        String? detectionMessage = detectionResult.reason;
        SheetValidationState detectionState = detectionResult.validationState;
        bool needsManualAdjustment = detectionResult.needsManualAdjustment;
        String? adjustmentMessage;
        bool adjustmentBlocked = false;

        return StatefulBuilder(
          builder: (context, setModalState) {
            if (!cropTourQueued) {
              cropTourQueued = true;
              TutorialService.autoStartTour(
                context,
                pageKey: TutorialService.cropPageKey,
                keys: _cropTourKeys,
                page: TutorialPage.cropPage,
              );
            }

            void triggerPostAdjustValidation() {
              if (!adjustmentBlocked) {
                _scheduleCropValidation(
                  imagePath: imagePath,
                  bounds: currentBounds,
                  setModalState: setModalState,
                  onValidated: (message, state) {
                    detectionMessage = message;
                    hasManualCandidate = true;
                    needsManualAdjustment =
                        state != SheetValidationState.strong;
                    detectionState = state;
                  },
                );
              }
            }

            final bool shapeIsValid = _isValidBounds(currentBounds);

            final bool canContinue =
                (hasDetectedDocument || hasManualCandidate) &&
                shapeIsValid &&
                !adjustmentBlocked;

            final String? cropValidationMessage = !shapeIsValid
                ? 'Crop is not allowed. Please fix the document bounds or tap Reset.'
                : (adjustmentBlocked
                      ? (adjustmentMessage ??
                            'Adjustment not allowed. Keep the crop as a quadrilateral.')
                      : (needsManualAdjustment ? detectionMessage : null));

            return FractionallySizedBox(
              heightFactor: 0.83,
              child: Container(
                decoration: const BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 10),
                    Container(
                      width: 46,
                      height: 5,
                      decoration: BoxDecoration(
                        color: AppColors.textMuted,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    const SizedBox(height: 16),
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
                          const SizedBox(width: 8),
                          TutorialService.showcase(
                            key: _cropHelpTourKey,
                            title: 'Need Crop Help?',
                            description:
                                'Tap this if you want to read the crop tips again or replay this tour.',
                            targetShapeBorder: const CircleBorder(),
                            child: IconButton(
                              tooltip: 'Crop help',
                              onPressed: () {
                                TutorialService.showHowToUse(
                                  context,
                                  page: TutorialPage.cropPage,
                                  onStartTour: () => TutorialService
                                      .showCropGuide(context, _cropTourKeys),
                                );
                              },
                              icon: const Icon(
                                Icons.help_outline_rounded,
                                color: AppColors.accent,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
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
                                        imageRect.left +
                                            (point.x * imageRect.width),
                                        imageRect.top +
                                            (point.y * imageRect.height),
                                      );
                                    }

                                    final topLeftPoint = mapPoint(
                                      currentBounds.topLeft,
                                    );
                                    final topRightPoint = mapPoint(
                                      currentBounds.topRight,
                                    );
                                    final bottomRightPoint = mapPoint(
                                      currentBounds.bottomRight,
                                    );
                                    final bottomLeftPoint = mapPoint(
                                      currentBounds.bottomLeft,
                                    );

                                    return TutorialService.showcase(
                                      key: _cropFrameTourKey,
                                      title: 'Line Up the Sheet',
                                      description:
                                          'Keep the full sheet music page inside this area before you continue.',
                                      child: Stack(
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
                                          TutorialService.showcase(
                                            key: _cropHandleTourKey,
                                            title: 'Adjust the Corners',
                                            description:
                                                'Drag these handles until the frame follows the edges of the page.',
                                            targetShapeBorder:
                                                const CircleBorder(),
                                            child: _DraggableCornerHandle(
                                              point: currentBounds.topLeft,
                                              imageRect: imageRect,
                                              handleColor: Colors.greenAccent,
                                              onDragUpdate: (details) {
                                                setModalState(() {
                                                  final previous =
                                                      currentBounds;
                                                  final updated =
                                                      _updateDraggedCorner(
                                                        bounds: currentBounds,
                                                        cornerKey: 'topLeft',
                                                        details: details,
                                                        imageRect: imageRect,
                                                      );

                                                  final wasBlocked = _sameBounds(
                                                    updated,
                                                    previous,
                                                  );

                                                  currentBounds = updated;
                                                  hasManualCandidate = true;
                                                  adjustmentBlocked =
                                                      wasBlocked;
                                                  adjustmentMessage = wasBlocked
                                                      ? 'Adjustment not allowed. Keep the crop as a quadrilateral.'
                                                      : null;
                                                });
                                              },

                                              onDragEnd:
                                                  triggerPostAdjustValidation,
                                            ),
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

                                              final wasBlocked = _sameBounds(
                                                updated,
                                                previous,
                                              );

                                              currentBounds = updated;
                                              hasManualCandidate = true;
                                              adjustmentBlocked = wasBlocked;
                                              adjustmentMessage = wasBlocked
                                                  ? 'Adjustment not allowed. Keep the crop as a quadrilateral.'
                                                  : null;
                                            });
                                          },

                                          onDragEnd:
                                              triggerPostAdjustValidation,
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

                                              final wasBlocked = _sameBounds(
                                                updated,
                                                previous,
                                              );

                                              currentBounds = updated;
                                              hasManualCandidate = true;
                                              adjustmentBlocked = wasBlocked;
                                              adjustmentMessage = wasBlocked
                                                  ? 'Adjustment not allowed. Keep the crop as a quadrilateral.'
                                                  : null;
                                            });
                                          },

                                          onDragEnd:
                                              triggerPostAdjustValidation,
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

                                              final wasBlocked = _sameBounds(
                                                updated,
                                                previous,
                                              );

                                              currentBounds = updated;
                                              hasManualCandidate = true;
                                              adjustmentBlocked = wasBlocked;
                                              adjustmentMessage = wasBlocked
                                                  ? 'Adjustment not allowed. Keep the crop as a quadrilateral.'
                                                  : null;
                                            });
                                          },

                                          onDragEnd:
                                              triggerPostAdjustValidation,
                                        ),
                                        _EdgeHandle(
                                          start: topLeftPoint,
                                          end: topRightPoint,
                                          highlight:
                                              cropValidationMessage != null,
                                          onDragUpdate: (details) {
                                            setModalState(() {
                                              final previous = currentBounds;
                                              final updated = _updateEdge(
                                                bounds: currentBounds,
                                                edge: 'top',
                                                details: details,
                                                imageRect: imageRect,
                                              );

                                              final wasBlocked = _sameBounds(
                                                updated,
                                                previous,
                                              );

                                              currentBounds = updated;
                                              hasManualCandidate = true;
                                              adjustmentBlocked = wasBlocked;
                                              adjustmentMessage = wasBlocked
                                                  ? 'Adjustment not allowed. Keep the crop as a quadrilateral.'
                                                  : null;
                                            });
                                          },

                                          onDragEnd:
                                              triggerPostAdjustValidation,
                                        ),
                                        _EdgeHandle(
                                          start: bottomLeftPoint,
                                          end: bottomRightPoint,
                                          highlight:
                                              cropValidationMessage != null,
                                          onDragUpdate: (details) {
                                            setModalState(() {
                                              final previous = currentBounds;
                                              final updated = _updateEdge(
                                                bounds: currentBounds,
                                                edge: 'bottom',
                                                details: details,
                                                imageRect: imageRect,
                                              );

                                              final wasBlocked = _sameBounds(
                                                updated,
                                                previous,
                                              );

                                              currentBounds = updated;
                                              hasManualCandidate = true;
                                              adjustmentBlocked = wasBlocked;
                                              adjustmentMessage = wasBlocked
                                                  ? 'Adjustment not allowed. Keep the crop as a quadrilateral.'
                                                  : null;
                                            });
                                          },

                                          onDragEnd:
                                              triggerPostAdjustValidation,
                                        ),
                                        _EdgeHandle(
                                          start: topLeftPoint,
                                          end: bottomLeftPoint,
                                          highlight:
                                              cropValidationMessage != null,
                                          onDragUpdate: (details) {
                                            setModalState(() {
                                              final previous = currentBounds;
                                              final updated = _updateEdge(
                                                bounds: currentBounds,
                                                edge: 'left',
                                                details: details,
                                                imageRect: imageRect,
                                              );

                                              final wasBlocked = _sameBounds(
                                                updated,
                                                previous,
                                              );

                                              currentBounds = updated;
                                              hasManualCandidate = true;
                                              adjustmentBlocked = wasBlocked;
                                              adjustmentMessage = wasBlocked
                                                  ? 'Adjustment not allowed. Keep the crop as a quadrilateral.'
                                                  : null;
                                            });
                                          },

                                          onDragEnd:
                                              triggerPostAdjustValidation,
                                        ),
                                        _EdgeHandle(
                                          start: topRightPoint,
                                          end: bottomRightPoint,
                                          highlight:
                                              cropValidationMessage != null,
                                          onDragUpdate: (details) {
                                            setModalState(() {
                                              final previous = currentBounds;
                                              final updated = _updateEdge(
                                                bounds: currentBounds,
                                                edge: 'right',
                                                details: details,
                                                imageRect: imageRect,
                                              );

                                              final wasBlocked = _sameBounds(
                                                updated,
                                                previous,
                                              );

                                              currentBounds = updated;
                                              hasManualCandidate = true;
                                              adjustmentBlocked = wasBlocked;
                                              adjustmentMessage = wasBlocked
                                                  ? 'Adjustment not allowed. Keep the crop as a quadrilateral.'
                                                  : null;
                                            });
                                          },

                                          onDragEnd:
                                              triggerPostAdjustValidation,
                                        ),
                                        if (cropValidationMessage != null)
                                          Positioned(
                                            left: 14,
                                            right: 14,
                                            bottom: 14,
                                            child: TutorialService.showcase(
                                              key: _cropWarningTourKey,
                                              title: 'Crop Status',
                                              description:
                                                  'If STALA sees a possible crop problem, it will tell you here.',
                                              child: _FloatingValidationMessage(
                                                message: cropValidationMessage,
                                                state: detectionState,
                                              ),
                                            ),
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
                                      ),
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
                                child: TutorialService.showcase(
                                  key: _cropResetTourKey,
                                  title: 'Reset Crop',
                                  description:
                                      'Tap Reset to return the crop frame to its starting position.',
                                  child: _PreviewFooterAction(
                                    icon: Icons.restart_alt_rounded,
                                    label: 'Reset',
                                    color: AppColors.warning,
                                    onTap: () {
                                      _cropValidationDebounce?.cancel();
                                      setModalState(() {
                                        currentBounds = initialBounds;
                                        hasDetectedDocument =
                                            detectionResult.bounds != null;
                                        hasManualCandidate =
                                            detectionResult.bounds == null;
                                        detectionMessage =
                                            detectionResult.reason;
                                        detectionState =
                                            detectionResult.validationState;
                                        needsManualAdjustment = detectionResult
                                            .needsManualAdjustment;
                                        adjustmentBlocked = false;
                                        adjustmentMessage = null;
                                      });

                                      _showSnackBar('Crop reset.');
                                    },
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TutorialService.showcase(
                                  key: _cropContinueTourKey,
                                  title: 'Continue',
                                  description:
                                      'Tap Continue when the sheet is lined up and ready to read.',
                                  child: _PreviewFooterAction(
                                    icon: Icons.check_circle_rounded,
                                    label: 'Continue',
                                    color: canContinue
                                        ? AppColors.accent
                                        : AppColors.textMuted,
                                    isEnabled: canContinue,
                                    onTap: () async {
                                      if (!_isValidBounds(currentBounds)) {
                                        _showSnackBar(
                                          'Crop is not allowed. Please fix the document bounds or tap Reset.',
                                        );
                                        return;
                                      }

                                      setModalState(() {
                                        isProcessing = true;
                                      });

                                      final cropValidation =
                                          await _validateSelectedCrop(
                                            imagePath: imagePath,
                                            bounds: currentBounds,
                                          );

                                      if (!mounted) return;

                                      setModalState(() {
                                        isProcessing = false;
                                      });

                                      if (cropValidation.validationState ==
                                          SheetValidationState.strong) {
                                        await _proceedToCropAndOpen(
                                          sheetContext: sheetContext,
                                          imagePath: imagePath,
                                          bounds: currentBounds,
                                        );
                                        return;
                                      }

                                      if (cropValidation.validationState ==
                                          SheetValidationState.weak) {
                                        final proceed =
                                            await _showWeakValidationDialog(
                                              cropValidation.reason ??
                                                  'The selected crop may not be a reliable music-sheet region. Adjust the box or proceed?',
                                            );

                                        if (proceed) {
                                          await _proceedToCropAndOpen(
                                            sheetContext: sheetContext,
                                            imagePath: imagePath,
                                            bounds: currentBounds,
                                          );
                                        }
                                        return;
                                      }

                                      final proceed =
                                          await _showFailValidationDialog(
                                            cropValidation.reason ??
                                                'The selected crop does not appear to be a reliable music-sheet region. Please adjust the box, or press and hold to continue anyway.',
                                          );

                                      if (proceed) {
                                        await _proceedToCropAndOpen(
                                          sheetContext: sheetContext,
                                          imagePath: imagePath,
                                          bounds: currentBounds,
                                        );
                                      }
                                    },
                                  ),
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

  void _showSnackBar(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.backgroundSecondary,
        content: Text(message, style: AppTextStyles.body),
      ),
    );
  }

  @override
  void dispose() {
    _cropValidationDebounce?.cancel();
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
                child: CircularProgressIndicator(color: AppColors.accent),
              )
            : controller == null || !controller.value.isInitialized
            ? _CameraUnavailableView(
                message: _cameraUnavailableMessage,
                onRetry: _initializeCamera,
                onOpenSettings: _openCameraPermissionSettings,
              )
            : Stack(
                children: [
                  Positioned.fill(child: CameraPreview(controller)),
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
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(painter: _CameraGridPainter()),
                    ),
                  ),
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
                        _ShutterButton(onTap: _captureImage),
                        const SizedBox(width: 52, height: 52),
                      ],
                    ),
                  ),
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

  void _scheduleCropValidation({
    required String imagePath,
    required DocumentBounds bounds,
    required void Function(void Function()) setModalState,
    required void Function(String? message, SheetValidationState state)
    onValidated,
  }) {
    _cropValidationDebounce?.cancel();

    _cropValidationDebounce = Timer(
      const Duration(milliseconds: 300),
      () async {
        final result = await _validateSelectedCrop(
          imagePath: imagePath,
          bounds: bounds,
        );

        if (!mounted) return;

        setModalState(() {
          onValidated(result.reason, result.validationState);
        });
      },
    );
  }
}

class _CameraUnavailableView extends StatelessWidget {
  final String? message;
  final VoidCallback onRetry;
  final VoidCallback onOpenSettings;

  const _CameraUnavailableView({
    this.message,
    required this.onRetry,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.no_photography_outlined,
              color: AppColors.textSecondary,
              size: 42,
            ),
            const SizedBox(height: 14),
            Text(
              'Camera unavailable',
              textAlign: TextAlign.center,
              style: AppTextStyles.sectionTitle.copyWith(fontSize: 18),
            ),
            const SizedBox(height: 8),
            Text(
              message ?? 'Unable to start the camera.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySecondary,
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  onPressed: onRetry,
                  child: Text('Retry', style: AppTextStyles.button),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: AppColors.textPrimary,
                  ),
                  onPressed: onOpenSettings,
                  child: Text('Settings', style: AppTextStyles.button),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TopCircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _TopCircleButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0x220B162B),
        border: Border.all(color: AppColors.border),
      ),
      child: IconButton(
        onPressed: onTap,
        icon: Icon(icon, size: 20, color: AppColors.textSecondary),
      ),
    );
  }
}

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
        child: Icon(icon, color: AppColors.textPrimary, size: 24),
      ),
    );
  }
}

class _ShutterButton extends StatelessWidget {
  final VoidCallback onTap;

  const _ShutterButton({required this.onTap});

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
          border: Border.all(color: AppColors.textSecondary, width: 4),
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
              border: Border.all(color: const Color(0xFFDADADA), width: 2),
            ),
          ),
        ),
      ),
    );
  }
}

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
    final effectiveColor = isEnabled
        ? color
        : AppColors.textMuted.withOpacity(0.75);

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
            border: Border.all(color: effectiveBorderColor),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: effectiveColor, size: 20),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.button.copyWith(color: effectiveColor),
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
                color: isSelected ? AppColors.accent : AppColors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DraggableCornerHandle extends StatelessWidget {
  final DocumentCorner point;
  final Rect imageRect;
  final Color handleColor;
  final ValueChanged<DragUpdateDetails> onDragUpdate;
  final VoidCallback? onDragEnd;

  const _DraggableCornerHandle({
    required this.point,
    required this.imageRect,
    required this.handleColor,
    required this.onDragUpdate,
    this.onDragEnd,
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
        onPanEnd: (_) => onDragEnd?.call(),
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
              border: Border.all(color: handleColor, width: 3),
            ),
          ),
        ),
      ),
    );
  }
}

class _EdgeHandle extends StatelessWidget {
  final Offset start;
  final Offset end;
  final bool highlight;
  final ValueChanged<DragUpdateDetails> onDragUpdate;
  final VoidCallback? onDragEnd;

  const _EdgeHandle({
    required this.start,
    required this.end,
    required this.onDragUpdate,
    this.highlight = false,
    this.onDragEnd,
  });

  @override
  Widget build(BuildContext context) {
    final edgeColor = highlight
        ? Colors.white.withOpacity(0.96)
        : Colors.white.withOpacity(0.86);

    final outlineColor = Colors.black.withOpacity(0.65);

    final mid = Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2);

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
        onPanEnd: (_) => onDragEnd?.call(),
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
                border: Border.all(color: outlineColor, width: 1.8),
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

class _DocumentBoundsPainter extends CustomPainter {
  final DocumentBounds bounds;
  final Rect imageRect;

  const _DocumentBoundsPainter({required this.bounds, required this.imageRect});

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
    final bottomRight = mapPoint(
      Offset(bounds.bottomRight.x, bounds.bottomRight.y),
    );
    final bottomLeft = mapPoint(
      Offset(bounds.bottomLeft.x, bounds.bottomLeft.y),
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
    return oldDelegate.bounds != bounds || oldDelegate.imageRect != imageRect;
  }
}

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

class _FloatingValidationMessage extends StatelessWidget {
  final String message;
  final SheetValidationState state;

  const _FloatingValidationMessage({
    required this.message,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    final Color accentColor;

    switch (state) {
      case SheetValidationState.strong:
        accentColor = AppColors.success;
        break;
      case SheetValidationState.weak:
        accentColor = AppColors.warning;
        break;
      case SheetValidationState.fail:
        accentColor = AppColors.accentSoft;
        break;
    }

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: 1,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.background.withOpacity(0.90),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: accentColor),
          boxShadow: const [
            BoxShadow(
              color: Color(0x66000000),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.warning_amber_rounded, color: accentColor, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: AppTextStyles.bodySecondary.copyWith(
                  fontSize: 12.5,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
