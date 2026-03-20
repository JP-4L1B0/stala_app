import 'package:flutter/material.dart';
import 'pages/splash_page.dart';

void main() {
  runApp(const STALAApp());
}

class STALAApp extends StatelessWidget {
  const STALAApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'STALA',
      home: const SplashPage(),
    );
  }
}