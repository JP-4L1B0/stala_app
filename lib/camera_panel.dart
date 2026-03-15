import 'package:flutter/material.dart';
import 'camera_logic.dart';

/// Panel 02 camera page.
///
/// This page replaces the former Panel 02 placeholder.
/// Its responsibility is intentionally small:
/// - serve as the dedicated navigation target from Panel 01
/// - host the full camera workflow page
///
/// Keeping this wrapper separate makes the project easier to scale later
/// if Panel 02 needs its own routing, guards, or surrounding layout.
class CameraPanelPage extends StatelessWidget {
  const CameraPanelPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const CameraLogicPage();
  }
}