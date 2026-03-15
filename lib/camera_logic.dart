import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

/// A full camera workflow page used by Panel 02.
///
/// Responsibilities:
/// - Opens the device back camera
/// - Displays a live camera preview
/// - Uses auto-focus and auto-exposure
/// - Lets the user capture an image
/// - Lets the user pick an image from gallery
/// - Shows a preview bottom sheet after capture or gallery pick
/// - Exposes an image path ready for native / Chaquopy / Python processing
///
/// Notes:
/// - Zoom and camera flip are intentionally removed
/// - Auto focus and auto brightness are handled by the camera plugin modes
/// - The "Accept" action is already bridged to a MethodChannel placeholder
class CameraLogicPage extends StatefulWidget {
  const CameraLogicPage({super.key});

  @override
  State<CameraLogicPage> createState() => _CameraLogicPageState();
}

class _CameraLogicPageState extends State<CameraLogicPage> {
  /// Native bridge prepared for Android-side processing, such as Chaquopy.
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

  /// Loads the available cameras, selects the back camera,
  /// and starts the live preview controller.
  ///
  /// Auto focus and auto exposure are enabled after initialization.
  Future<void> _initializeCamera() async {
    try {
      _availableCameras = await availableCameras();

      if (_availableCameras.isEmpty) {
        throw Exception('No available camera was found on this device.');
      }

      final CameraDescription backCamera = _availableCameras.firstWhere(
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

      /// Set camera behavior to automatic for focus and exposure.
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

  /// Checks and requests gallery/storage-related permission before opening
  /// the image picker.
  ///
  /// Notes:
  /// - On newer Android versions, the system photo picker may allow selecting
  ///   a specific image without broad storage access.
  /// - This explicit check is still kept so the camera page follows the same
  ///   permission-aware behavior as the Settings section.
  Future<bool> _ensureGalleryPermission() async {
    PermissionStatus status = await Permission.photos.status;

    if (status.isGranted) {
      return true;
    }

    status = await Permission.photos.request();

    if (status.isGranted) {
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

  /// Captures a still image from the active camera preview.
  ///
  /// After capture, the preview bottom sheet is shown so the user can:
  /// - retry and discard the image
  /// - accept the image for downstream processing
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

      final XFile capturedFile = await controller.takePicture();

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

  /// Opens the gallery and lets the user select an image instead of capturing one.
  ///
  /// The chosen image is sent to the same preview flow as a captured image.
  Future<void> _pickImageFromGallery() async {
    try {
      final bool hasPermission = await _ensureGalleryPermission();

      if (!hasPermission) return;

      final XFile? pickedFile = await _imagePicker.pickImage(
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

  /// Shows the selected or captured image inside a bottom-sheet preview panel.
  ///
  /// Footer actions:
  /// - Retry: closes the sheet and returns to camera
  /// - Accept: sends the image path to the native bridge
  Future<void> _showImagePreviewSheet({
    required String imagePath,
    required String sourceLabel,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF081222),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          top: false,
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.80,
            child: Column(
              children: [
                const SizedBox(height: 12),

                /// Drag handle for the modal sheet.
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFF566487),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),

                const SizedBox(height: 16),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Image Preview',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'Poppins',
                          ),
                        ),
                      ),
                      Text(
                        sourceLabel,
                        style: const TextStyle(
                          color: Color(0xFFA0AFC4),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          fontFamily: 'Inter',
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                /// Main preview container.
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        width: double.infinity,
                        color: const Color(0xFF05101D),
                        child: Image.file(
                          File(imagePath),
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                /// Footer with retry and accept actions.
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                  decoration: const BoxDecoration(
                    color: Color(0xFF091425),
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _PreviewFooterAction(
                        icon: Icons.refresh_rounded,
                        label: 'Retry',
                        color: const Color(0xFFA0AFC4),
                        onTap: () {
                          Navigator.pop(context);
                        },
                      ),
                      _PreviewFooterAction(
                        icon: Icons.check_circle_rounded,
                        label: 'Accept',
                        color: const Color(0xFFFF8F69),
                        onTap: () async {
                          Navigator.pop(context);
                          await _acceptImage(imagePath);
                        },
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
  }

  /// Sends the accepted image path to Android native code.
  ///
  /// This is already prepared for future Chaquopy integration.
  /// For now, if the native bridge is not yet connected,
  /// the page still behaves safely and reports that readiness.
  Future<void> _acceptImage(String imagePath) async {
    try {
      final result = await _pythonChannel.invokeMethod(
        'processImage',
        {'imagePath': imagePath},
      );

      if (!mounted) return;

      _showSnackBar('Image accepted. Result: $result');
    } on MissingPluginException {
      if (!mounted) return;

      _showSnackBar(
        'Image accepted. Python bridge is not connected yet, '
            'but the page is ready for integration.',
      );
    } catch (error) {
      _showSnackBar('Failed to send image to Python bridge: $error');
    }
  }

  /// Displays a styled message near the bottom of the screen.
  void _showSnackBar(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF091425),
        content: Text(message),
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
      backgroundColor: const Color(0xFF081222),
      body: SafeArea(
        child: _isInitializingCamera
            ? const Center(
          child: CircularProgressIndicator(
            color: Color(0xFFFF8F69),
          ),
        )
            : controller == null || !controller.value.isInitialized
            ? const _CameraUnavailableView()
            : Stack(
          children: [
            /// Live camera preview.
            Positioned.fill(
              child: CameraPreview(controller),
            ),

            /// Soft top-bottom dark overlay to preserve the design style.
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

            /// Grid lines for composition guidance.
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _CameraGridPainter(),
                ),
              ),
            ),

            /// Top controls.
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

            /// Bottom controls:
            /// - Gallery button on the left
            /// - Shutter button at the center
            /// - Empty spacing on the right for symmetry
            Positioned(
              left: 22,
              right: 22,
              bottom: 30,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _BottomSquareButton(
                    icon: Icons.photo_library_outlined,
                    backgroundColor: const Color(0xFFFF7E57),
                    onTap: _pickImageFromGallery,
                  ),
                  _ShutterButton(
                    onTap: _captureImage,
                  ),
                  const SizedBox(width: 52, height: 52),
                ],
              ),
            ),

            /// A loading blocker while an image is being captured.
            if (_isCapturingImage)
              Positioned.fill(
                child: Container(
                  color: const Color(0x55000000),
                  child: const Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFFFF8F69),
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

/// Fallback UI shown when the camera cannot be used.
class _CameraUnavailableView extends StatelessWidget {
  const _CameraUnavailableView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'Camera unavailable',
        style: TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontFamily: 'Inter',
        ),
      ),
    );
  }
}

/// Circular button used in the top overlay controls.
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
        border: Border.all(color: const Color(0xFF22314B)),
      ),
      child: IconButton(
        onPressed: onTap,
        icon: Icon(
          icon,
          size: 20,
          color: const Color(0xFFB4C0D0),
        ),
      ),
    );
  }
}

/// Small square action button used for gallery access.
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
          color: Colors.white,
          size: 24,
        ),
      ),
    );
  }
}

/// Center shutter button used to capture an image.
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
          color: Colors.white,
          border: Border.all(
            color: const Color(0xFFB4C0D0),
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
                color: Color(0xFFDADADA),
                width: 2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Footer action button used inside the preview sheet.
class _PreviewFooterAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _PreviewFooterAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF081222),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF1A2940)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                fontFamily: 'Poppins',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Paints a simple rule-of-thirds camera grid over the preview.
class _CameraGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x33B4C0D0)
      ..strokeWidth = 0.8;

    final double col1 = size.width / 3;
    final double col2 = col1 * 2;
    final double row1 = size.height / 3;
    final double row2 = row1 * 2;

    canvas.drawLine(Offset(col1, 0), Offset(col1, size.height), paint);
    canvas.drawLine(Offset(col2, 0), Offset(col2, size.height), paint);
    canvas.drawLine(Offset(0, row1), Offset(size.width, row1), paint);
    canvas.drawLine(Offset(0, row2), Offset(size.width, row2), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}