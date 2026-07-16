//app_card.dart

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A container. Not a control.
///
/// The distinction is the whole point. The app used one cream pill for
/// everything, so a card holding text and a row waiting to be tapped were the
/// same object. A card has no border and a soft, wide shadow — it reads as
/// paper. An [OptionTile] or an [AppButton] has a crisp edge and a press
/// response — it reads as a thing to touch.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;

  /// Set for a card that is genuinely tappable — a chat row in history. It gets
  /// a border and a ripple, because the moment a card can be pressed it owes the
  /// user that signal.
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Lifts the card and tints its edge — the row you are being pointed at.
  final bool highlighted;

  final Color? color;
  final double? radius;

  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
    this.onLongPress,
    this.highlighted = false,
    this.color,
    this.radius,
  });

  @override
  Widget build(BuildContext context) {
    final r = radius ?? AppTheme.rLg;
    final interactive = onTap != null || onLongPress != null;

    final body = Padding(
      padding: padding ?? EdgeInsets.all(AppTheme.s5),
      child: child,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(r),
        boxShadow: highlighted ? AppTheme.shadowLifted : AppTheme.shadowCard,
      ),
      child: Material(
        color: color ?? AppTheme.cardBg,
        borderRadius: BorderRadius.circular(r),
        clipBehavior: Clip.antiAlias,
        child: interactive
            ? InkWell(
                onTap: onTap,
                onLongPress: onLongPress,
                splashColor: AppTheme.primary.withValues(alpha: 0.10),
                child: _bordered(r, body),
              )
            : _bordered(r, body),
      ),
    );
  }

  Widget _bordered(double r, Widget body) => Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(r),
          border: Border.all(
            color: highlighted ? AppTheme.primary : AppTheme.border,
            width: highlighted ? 1.5 : 1,
          ),
        ),
        child: body,
      );
}

/// The all-caps micro-label that names a group of things.
///
/// Cheap structure: it lets a screen say "Where to start" or "What I looked up"
/// without spending a heading on it, which is how a long page stays scannable
/// instead of turning into the wall of prose the recommendation used to be.
class SectionLabel extends StatelessWidget {
  final String text;
  final IconData? icon;

  const SectionLabel(this.text, {super.key, this.icon});

  @override
  Widget build(BuildContext context) {
    final scale = AppTheme.scaleOf(context);

    return Semantics(
      // The label is *drawn* upper-case because that is what makes an overline
      // read as a label rather than as a very small sentence. It must not be
      // *announced* that way: a screen reader hands "WHAT I LOOKED UP" to the
      // synthesiser as an initialism and spells it out letter by letter. So the
      // real sentence is the semantics, and the shouting is only pixels.
      label: text,
      // This is what it is: the heading of a section, which is how a screen
      // reader user navigates a long answer instead of hearing all of it.
      header: true,
      // Without a container of its own the label merges into whatever node is
      // above it, and "Where to start" is announced as part of the first step
      // rather than as the thing introducing them.
      container: true,
      child: ExcludeSemantics(
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 13 * scale, color: AppTheme.textFaint),
              SizedBox(width: AppTheme.s1 + 2),
            ],
            Flexible(
              child: Text(
                text.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.overline(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A small tinted chip — a category, a state, a count.
class AppChip extends StatelessWidget {
  final String label;
  final Color? color;
  final IconData? icon;

  const AppChip({super.key, required this.label, this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    final scale = AppTheme.scaleOf(context);
    final tone = color ?? AppTheme.primary;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: AppTheme.s2,
        vertical: 3 * scale,
      ),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(AppTheme.rSm - 4),
        border: Border.all(color: tone.withValues(alpha: 0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11 * scale, color: tone),
            SizedBox(width: 3 * scale),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 11 * scale,
              color: tone,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }
}
