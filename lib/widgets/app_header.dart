//app_header.dart

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The bar at the top of a pushed screen: a way back, what this is, and at most
/// one action.
///
/// Every screen used to hand-roll this as a `Row` with a bare `GestureDetector`
/// around an `Icon` — an 18pt tap target with no press feedback, at a slightly
/// different vertical offset on each screen. Naming it makes the back arrow the
/// same size, in the same place, with the same ripple, everywhere.
class AppHeader extends StatelessWidget {
  final String title;

  /// The line under the title — a step counter, a state, a date.
  final String? subtitle;

  /// Null hides the arrow entirely, for a screen with nowhere to go back to.
  final VoidCallback? onBack;

  /// Up to two trailing controls. More than that and it is a screen, not a
  /// header.
  final List<Widget> actions;

  const AppHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.onBack,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final scale = AppTheme.scaleOf(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppTheme.s3,
        AppTheme.s2,
        AppTheme.s4,
        AppTheme.s2,
      ),
      child: Row(
        children: [
          if (onBack != null)
            HeaderIconButton(
              icon: Icons.arrow_back_rounded,
              tooltip: 'Back',
              onPressed: onBack!,
            )
          else
            SizedBox(width: AppTheme.s2),
          SizedBox(width: AppTheme.s1),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15 * scale,
                    color: AppTheme.textDark,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.meta(context),
                  ),
              ],
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

/// A round icon control for a header — 44pt of tap target around an 20pt glyph.
class HeaderIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color? color;

  const HeaderIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final scale = AppTheme.scaleOf(context);

    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            width: 44 * scale,
            height: 44 * scale,
            child: Icon(
              icon,
              size: 20 * scale,
              color: color ?? AppTheme.textOnCard,
            ),
          ),
        ),
      ),
    );
  }
}

/// A pill-shaped header control with a word on it — "Past", "Profile".
///
/// Reads as a destination rather than a glyph someone has to decode, which is
/// what the history entry point needed.
class HeaderPillButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  const HeaderPillButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final scale = AppTheme.scaleOf(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.pillRadius),
        boxShadow: AppTheme.shadowSoft,
      ),
      child: Material(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(AppTheme.pillRadius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: AppTheme.s3,
              vertical: AppTheme.s2 + 1,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTheme.pillRadius),
              border: Border.all(color: AppTheme.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16 * scale, color: AppTheme.textOnCard),
                SizedBox(width: AppTheme.s1 + 2),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13 * scale,
                    color: AppTheme.textOnCard,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
