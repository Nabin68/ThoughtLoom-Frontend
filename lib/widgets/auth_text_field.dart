//auth_text_field.dart

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A single-line field in the app's cream card style, with the pill radius the
/// option rows and buttons already use.
class AuthTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final IconData icon;
  final bool obscureText;
  final TextInputType keyboardType;
  final TextInputAction textInputAction;
  final String? Function(String?)? validator;
  final VoidCallback? onToggleObscure;
  final ValueChanged<String>? onFieldSubmitted;
  final ValueChanged<String>? onChanged;
  final bool enabled;

  /// Above 1 the field grows into a paragraph box, keeping the card styling.
  /// Onboarding's free-text questions use it; auth's fields are all single-line.
  final int maxLines;

  const AuthTextField({
    super.key,
    required this.controller,
    required this.hintText,
    required this.icon,
    this.obscureText = false,
    this.keyboardType = TextInputType.text,
    this.textInputAction = TextInputAction.next,
    this.validator,
    this.onToggleObscure,
    this.onFieldSubmitted,
    this.onChanged,
    this.enabled = true,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardBg.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(AppTheme.pillRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            offset: const Offset(0, 4),
            blurRadius: 12,
          ),
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.4),
            offset: const Offset(0, -1),
            blurRadius: 2,
          ),
        ],
      ),
      child: TextFormField(
        controller: controller,
        obscureText: obscureText,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        validator: validator,
        enabled: enabled,
        onFieldSubmitted: onFieldSubmitted,
        onChanged: onChanged,
        maxLines: obscureText ? 1 : maxLines,
        // Keeps the leading icon beside the first line rather than floating in
        // the middle of a grown paragraph box.
        textAlignVertical:
            maxLines > 1 ? TextAlignVertical.top : TextAlignVertical.center,
        style: TextStyle(
          fontSize: screenWidth * 0.042,
          color: AppTheme.textOnCard,
        ),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: TextStyle(
            fontSize: screenWidth * 0.04,
            color: AppTheme.textLight.withValues(alpha: 0.5),
          ),
          prefixIcon: Icon(
            icon,
            size: screenWidth * 0.055,
            color: AppTheme.textOnCard,
          ),
          suffixIcon: onToggleObscure == null
              ? null
              : IconButton(
                  onPressed: onToggleObscure,
                  icon: Icon(
                    obscureText
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: screenWidth * 0.05,
                    color: AppTheme.textLight,
                  ),
                ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppTheme.pillRadius),
            borderSide: BorderSide.none,
          ),
          // The validator message sits outside the pill; without this the error
          // text would stretch the card itself.
          errorStyle: TextStyle(fontSize: screenWidth * 0.032, height: 1.2),
          contentPadding: EdgeInsets.symmetric(
            horizontal: screenWidth * 0.05,
            vertical: screenWidth * 0.045,
          ),
        ),
      ),
    );
  }
}
