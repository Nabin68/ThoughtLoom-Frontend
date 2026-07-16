import 'package:flutter/material.dart';

class AppTheme {
  static const Color primary = Color(0xFF6F8F9B);
  static const Color textDark = Color(0xFF2E3A3F);
  static const Color textLight = Color(0xFF5F6F78);
  static const Color cardBg = Color(0xFFF5F1E8);

  /// Already in use across the screens, named here so new code has one source
  /// for them. Values are unchanged.
  static const Color textOnCard = Color(0xFF3D4F56);
  static const Color selected = Color(0xFF9FB6C2);
  static const double pillRadius = 30;

  /// The clay red — the app's only non-sage accent, kept muted so it reads as
  /// part of the same palette. [danger] is the mark, [dangerText] the darker
  /// tone that stays legible on cream.
  ///
  /// Lived privately in `ErrorBanner` until something else needed it: a delete
  /// confirmation has to be the same red as every other warning, and a second
  /// literal is a drift waiting to happen.
  static const Color danger = Color(0xFFC0574E);
  static const Color dangerText = Color(0xFF8F3F38);

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
