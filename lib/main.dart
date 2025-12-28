import 'package:flutter/material.dart';
import 'screens/landing_screen.dart';

void main() {
  runApp(const ThoughtLoomApp());
}

class ThoughtLoomApp extends StatelessWidget {
  const ThoughtLoomApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: LandingScreen(),
    );
  }
}