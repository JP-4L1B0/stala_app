import 'package:flutter/material.dart';
import 'package:showcaseview/showcaseview.dart';
import 'pages/splash_page.dart';
import 'app_restart_widget.dart';

void main() {
  runApp(
    const RestartWidget(
      child: STALAApp(),
    ),
  );
}

class STALAApp extends StatelessWidget {
  const STALAApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'STALA',
      home: const SplashPage(),
      builder: (context, child) {
        return ShowCaseWidget(
          builder: (_) => child ?? const SizedBox.shrink(),
          enableAutoScroll: true,
        );
      },
    );
  }
}
