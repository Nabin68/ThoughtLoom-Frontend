//main.dart

import 'package:flutter/material.dart';
import 'screens/landing_screen.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const ThoughtLoomApp());
}

class ThoughtLoomApp extends StatelessWidget {
  const ThoughtLoomApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme,
      home: const LandingScreen(),
    );
  }
}
