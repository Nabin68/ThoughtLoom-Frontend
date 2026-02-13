import 'package:flutter/material.dart';

class AppTheme {
  static const Color primary = Color(0xFF6F8F9B);
  static const Color textDark = Color(0xFF2E3A3F);
  static const Color textLight = Color(0xFF5F6F78);
  static const Color cardBg = Color(0xFFF5F1E8);

  static ThemeData theme = ThemeData(
    scaffoldBackgroundColor: Colors.transparent,
    fontFamily: 'Inter',
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      foregroundColor: textDark,
    ),
  );
}
