import 'package:flutter/material.dart';
import 'panel01.dart';

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
      home: const StalaApp(),
    );
  }
}