//option_tile.dart

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// How many answers a question takes, which is what decides the control's shape.
///
/// A circle means "one of these"; a square means "as many as apply". That
/// convention is old enough that people read it without being told — which is
/// the entire reason the mark exists, because the app previously drew neither
/// and left "selected" indistinguishable from "not selected but cream".
enum ChoiceMode { single, multi }

/// A selectable option row.
///
/// ### What changed
///
/// The old row was a centred string in a cream pill, and its only selected state
/// was the pill turning sage. Three things were wrong with that:
///
///  * **No mark.** Nothing said whether a row could be chosen, or how many
///    could be. It looked exactly like the cards, the search field, and the
///    chat rows, which were also cream pills.
///  * **Centred text.** Fine for "Yes" / "No"; a mess for "Whether the cost and
///    time are worth it", which wraps to two ragged centred lines. Options are
///    read down a left edge, not centred like a title.
///  * **No feedback.** A bare GestureDetector gives no ripple, so a tap that
///    registered felt identical to one that missed.
class OptionTile extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final ChoiceMode mode;

  /// A second line under the label, for options that need a word of context.
  final String? helper;

  final bool enabled;

  const OptionTile({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.mode = ChoiceMode.single,
    this.helper,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final scale = AppTheme.scaleOf(context);

    return Semantics(
      inMutuallyExclusiveGroup: mode == ChoiceMode.single,
      checked: selected,
      button: true,
      child: Padding(
        padding: EdgeInsets.only(bottom: AppTheme.s3),
        child: Material(
          color: selected ? AppTheme.primary : AppTheme.cardBg,
          borderRadius: BorderRadius.circular(AppTheme.rMd),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: enabled ? onTap : null,
            splashColor: (selected ? Colors.white : AppTheme.primary)
                .withValues(alpha: 0.12),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              padding: EdgeInsets.symmetric(
                horizontal: AppTheme.s4,
                vertical: AppTheme.s4 * scale,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppTheme.rMd),
                border: Border.all(
                  color: selected ? AppTheme.primary : AppTheme.border,
                  width: 1.5,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _Mark(mode: mode, selected: selected, scale: scale),
                  SizedBox(width: AppTheme.s3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          label,
                          style: AppTheme.label(context).copyWith(
                            color:
                                selected ? Colors.white : AppTheme.textOnCard,
                            height: 1.35,
                          ),
                        ),
                        if (helper != null) ...[
                          SizedBox(height: AppTheme.s1),
                          Text(
                            helper!,
                            style: AppTheme.meta(context).copyWith(
                              color: selected
                                  ? Colors.white.withValues(alpha: 0.82)
                                  : AppTheme.textFaint,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The radio dot or the checkbox tick.
class _Mark extends StatelessWidget {
  final ChoiceMode mode;
  final bool selected;
  final double scale;

  const _Mark({
    required this.mode,
    required this.selected,
    required this.scale,
  });

  @override
  Widget build(BuildContext context) {
    final size = 21.0 * scale;
    final single = mode == ChoiceMode.single;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: selected ? Colors.white : Colors.transparent,
        // A fully-rounded rectangle, never BoxShape.circle.
        //
        // The two marks have to be able to become each other: consecutive
        // questions can be single- then multi-select, and the mark at the same
        // position in the tree is the same element, so AnimatedContainer tweens
        // its decoration. A tween between a circle and a rounded rectangle
        // produces an interpolated decoration carrying *both* a circle shape and
        // a border radius, which is a framework assertion rather than a shape —
        // it crashed the flow outright. Interpolating one radius into another is
        // both legal and the animation we actually wanted.
        borderRadius: BorderRadius.circular(single ? size / 2 : 6),
        border: Border.all(
          color: selected ? Colors.white : AppTheme.borderStrong,
          width: 1.8,
        ),
      ),
      child: selected
          ? Icon(
              single ? Icons.circle : Icons.check_rounded,
              size: (single ? 9 : 14) * scale,
              color: AppTheme.primary,
            )
          : null,
    );
  }
}
