import 'package:flutter/material.dart';

class RestartWidget extends StatefulWidget {
  final Widget child;

  const RestartWidget({
    super.key,
    required this.child,
  });

  static void restartApp(BuildContext context) {
    context.findAncestorStateOfType<_RestartWidgetState>()?.restartApp();
  }

  @override
  State<RestartWidget> createState() => _RestartWidgetState();
}

class _RestartWidgetState extends State<RestartWidget> {
  Key _restartKey = UniqueKey();

  void restartApp() {
    setState(() {
      _restartKey = UniqueKey();
    });
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: _restartKey,
      child: widget.child,
    );
  }
}