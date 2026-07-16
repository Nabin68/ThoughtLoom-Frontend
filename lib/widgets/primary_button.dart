//primary_button.dart

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The app's sage CTA, lifted verbatim from the existing screens so auth looks
/// like the rest of the product.
///
/// [onPressed] of null disables it; [busy] swaps the label for a spinner while
/// keeping the button's size, so the layout does not jump mid-request.
class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final IconData? icon;
  final double widthFactor;

  const PrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.busy = false,
    this.icon,
    this.widthFactor = 0.65,
  });

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    final enabled = onPressed != null && !busy;

    return Container(
      width: screenWidth * widthFactor,
      height: screenHeight * 0.065,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.pillRadius),
        boxShadow: enabled
            ? [
                BoxShadow(
                  color: AppTheme.primary.withValues(alpha: 0.3),
                  offset: const Offset(0, 8),
                  blurRadius: 20,
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  offset: const Offset(0, 4),
                  blurRadius: 8,
                ),
              ]
            : const [],
      ),
      child: ElevatedButton(
        onPressed: enabled ? onPressed : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppTheme.primary.withValues(alpha: 0.5),
          disabledForegroundColor: Colors.white.withValues(alpha: 0.8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.pillRadius),
          ),
          elevation: 0,
          shadowColor: Colors.transparent,
          padding: EdgeInsets.zero,
        ),
        child: busy
            ? SizedBox(
                width: screenWidth * 0.05,
                height: screenWidth * 0.05,
                child: const CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : Padding(
                padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.04),
                // Flexible + ellipsis rather than a bare Row: the label is
                // sized off screen width, so a long one on a wide viewport
                // would otherwise overflow the pill. Same treatment the option
                // rows use.
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: screenWidth * 0.042,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                    if (icon != null) ...[
                      SizedBox(width: screenWidth * 0.02),
                      Icon(icon, size: screenWidth * 0.05),
                    ],
                  ],
                ),
              ),
      ),
    );
  }
}
