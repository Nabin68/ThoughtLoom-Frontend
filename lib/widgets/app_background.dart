//app_background.dart

import 'package:flutter/material.dart';

/// The full-bleed background every screen sits on, matching the existing
/// Stack + Positioned.fill + SafeArea arrangement.
class AppBackground extends StatelessWidget {
  final Widget child;

  const AppBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset('assets/background.png', fit: BoxFit.cover),
          ),
          SafeArea(child: child),
        ],
      ),
    );
  }
}
