//error_banner.dart

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// An inline failure notice.
///
/// Deliberately not a SnackBar: an auth error has to stay on screen next to the
/// fields the user needs to correct, rather than timing out after four seconds.
///
/// The clay red is the app's only non-sage accent, kept muted so it reads as
/// part of the same palette. It lives in [AppTheme] now — the delete
/// confirmation needs the same red.
class ErrorBanner extends StatelessWidget {
  final String message;
  final IconData icon;

  static const Color _accent = AppTheme.danger;
  static const Color _text = AppTheme.dangerText;

  const ErrorBanner({
    super.key,
    required this.message,
    this.icon = Icons.error_outline,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: screenWidth * 0.05,
        vertical: screenWidth * 0.035,
      ),
      decoration: BoxDecoration(
        color: _accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppTheme.pillRadius),
        border: Border.all(color: _accent.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, size: screenWidth * 0.045, color: _accent),
          SizedBox(width: screenWidth * 0.03),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: screenWidth * 0.035,
                color: _text,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The same shape in the app's sage, for outcomes that are not failures — a
/// sign-up that succeeded but needs an email confirmed, for instance.
class InfoBanner extends StatelessWidget {
  final String message;
  final IconData icon;

  const InfoBanner({
    super.key,
    required this.message,
    this.icon = Icons.mark_email_unread_outlined,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: screenWidth * 0.05,
        vertical: screenWidth * 0.035,
      ),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppTheme.pillRadius),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(icon, size: screenWidth * 0.045, color: AppTheme.primary),
          SizedBox(width: screenWidth * 0.03),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: screenWidth * 0.035,
                color: AppTheme.textOnCard,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
