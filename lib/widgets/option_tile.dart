//option_tile.dart

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A selectable option row in the app's cream-card style.
///
/// Lifted verbatim from the single-select rows in [MCQFlowScreen] and
/// [ReasonScreen] — same pill radius, same sage fill when selected, same
/// shadow pair — so onboarding is visually indistinguishable from the flows
/// that already exist. Named here so the three of them cannot drift apart.
class OptionTile extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const OptionTile({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: EdgeInsets.only(bottom: screenHeight * 0.015),
        padding: EdgeInsets.symmetric(
          horizontal: screenWidth * 0.05,
          vertical: screenHeight * 0.02,
        ),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.selected
              : AppTheme.cardBg.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(AppTheme.pillRadius),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              offset: const Offset(0, 4),
              blurRadius: 12,
            ),
            BoxShadow(
              color: Colors.white.withValues(alpha: selected ? 0.1 : 0.4),
              offset: const Offset(0, -1),
              blurRadius: 2,
            ),
          ],
        ),
        child: Center(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: screenWidth * 0.042,
              color: selected ? Colors.white : AppTheme.textOnCard,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
            ),
          ),
        ),
      ),
    );
  }
}
