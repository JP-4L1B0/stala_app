import 'dart:async';
import 'package:flutter/material.dart';
import '../panel01.dart';

/// SplashPage
///
/// Initial animated splash before entering Panel01 dashboard.
class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  @override
  void initState() {
    super.initState();

    Timer(const Duration(seconds: 3), () {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => const MainPanel01Page(),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Center(
        child: Image.asset(
          'assets/images/stala_logo_animated.gif',
          width: 220,
        ),
      ),
    );
  }
}