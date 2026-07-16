//app_button.dart

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// What a button is *for*, which is what decides how it looks.
///
/// The app previously had exactly one button — the sage pill — and everything
/// else was a bare [TextButton]: sign out, "Skip this one", "That's enough for
/// now", "Back to start". A bare TextButton on a busy cream background is a
/// coloured word. It has no edge, no fill, and no press target you can see, so
/// it does not read as a control at all — which is exactly the complaint that
/// "the sign out button doesn't seem like a button".
///
/// Three levels, and the level says how much the app wants you to press it:
enum AppButtonKind {
  /// The one thing this screen is for. At most one per screen.
  primary,

  /// A real alternative, offered without competing — a visible pill, but cream
  /// and outlined rather than filled.
  secondary,

  /// A way out that should be findable rather than inviting. Still a pill with
  /// a real border and a real hit target; still obviously pressable.
  quiet,

  /// Destructive. Clay red, and never the primary on its screen.
  danger,
}

/// The app's button.
///
/// Sized to a real 48pt minimum touch target — several of the old text buttons
/// were under 30pt tall, which is below every platform's guidance and is why
/// they felt like they were ignoring taps.
class AppButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final AppButtonKind kind;
  final bool busy;
  final IconData? icon;

  /// Fill the available width. The default for [AppButtonKind.primary], because
  /// a screen's main action should not be hunting for its own edges.
  final bool expand;

  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.kind = AppButtonKind.primary,
    this.busy = false,
    this.icon,
    this.expand = true,
  });

  /// Convenience for the common trio, so call sites read as prose.
  const AppButton.secondary({
    super.key,
    required this.label,
    this.onPressed,
    this.busy = false,
    this.icon,
    this.expand = true,
  }) : kind = AppButtonKind.secondary;

  const AppButton.quiet({
    super.key,
    required this.label,
    this.onPressed,
    this.busy = false,
    this.icon,
    this.expand = false,
  }) : kind = AppButtonKind.quiet;

  const AppButton.danger({
    super.key,
    required this.label,
    this.onPressed,
    this.busy = false,
    this.icon,
    this.expand = true,
  }) : kind = AppButtonKind.danger;

  bool get _enabled => onPressed != null && !busy;

  Color get _fill => switch (kind) {
        AppButtonKind.primary => AppTheme.primary,
        AppButtonKind.danger => AppTheme.danger,
        AppButtonKind.secondary => AppTheme.cardBg,
        AppButtonKind.quiet => Colors.transparent,
      };

  Color get _ink => switch (kind) {
        AppButtonKind.primary || AppButtonKind.danger => Colors.white,
        AppButtonKind.secondary => AppTheme.textOnCard,
        AppButtonKind.quiet => AppTheme.textLight,
      };

  Color? get _edge => switch (kind) {
        AppButtonKind.primary || AppButtonKind.danger => null,
        AppButtonKind.secondary => AppTheme.borderStrong,
        AppButtonKind.quiet => AppTheme.border,
      };

  @override
  Widget build(BuildContext context) {
    final scale = AppTheme.scaleOf(context);
    final height = 50.0 * scale;
    final edge = _edge;

    final content = busy
        ? SizedBox(
            width: 18 * scale,
            height: 18 * scale,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              valueColor: AlwaysStoppedAnimation<Color>(_ink),
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.label(context).copyWith(
                    color: _ink,
                    fontWeight: kind == AppButtonKind.quiet
                        ? FontWeight.w600
                        : FontWeight.w700,
                  ),
                ),
              ),
              if (icon != null) ...[
                SizedBox(width: AppTheme.s2),
                Icon(icon, size: 18 * scale, color: _ink),
              ],
            ],
          );

    return Opacity(
      // One dimming rule for every kind, rather than four disabled palettes.
      opacity: _enabled ? 1 : 0.45,
      child: Container(
        width: expand ? double.infinity : null,
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppTheme.pillRadius),
          // The glow is the primary button's alone: it is what makes one control
          // on the screen look lit from underneath, and giving it to the others
          // would flatten the hierarchy it exists to create.
          boxShadow: _enabled && kind == AppButtonKind.primary
              ? AppTheme.shadowPrimary
              : _enabled && kind == AppButtonKind.secondary
                  ? AppTheme.shadowSoft
                  : null,
        ),
        child: Material(
          color: _fill,
          borderRadius: BorderRadius.circular(AppTheme.pillRadius),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: _enabled ? onPressed : null,
            // A press that is *felt* — the old text buttons gave no feedback at
            // all, which reads as an unresponsive app rather than a quiet one.
            splashColor: _ink.withValues(alpha: 0.12),
            highlightColor: _ink.withValues(alpha: 0.06),
            child: Container(
              alignment: Alignment.center,
              padding: EdgeInsets.symmetric(horizontal: AppTheme.s5),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppTheme.pillRadius),
                border: edge == null ? null : Border.all(color: edge, width: 1.5),
              ),
              child: content,
            ),
          ),
        ),
      ),
    );
  }
}
