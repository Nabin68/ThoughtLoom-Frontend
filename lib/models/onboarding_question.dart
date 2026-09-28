//onboarding_question.dart

import 'package:flutter/material.dart';

import 'intake_question.dart';

/// How a question is answered.
///
/// Radio is the default; [multiChoice] is for the questions where more than one
/// option can be true of someone at once and nothing downstream needs just one
/// (see the rule in `docs/BUILD_LOG.md`, Prompt 14). [text] is only for
/// questions whose honest answer space is unbounded, where a fixed option list
/// would force the user to pick a lie.
enum OnboardingAnswerKind { choice, multiChoice, text }

/// A `user_profiles` column an answer is mirrored into.
///
/// Every answer lives in `onboarding_answers` regardless. These three columns
/// exist because later queries filter and personalise on them, and a jsonb
/// lookup is a poor thing to build that on.
enum ProfileColumn { ageRange, occupation, location }

/// One screen of the one-time basic profile.
class OnboardingQuestion {
  /// Key in `user_profiles.onboarding_answers`. Never reuse or repurpose one:
  /// resume and skip-on-login both key off it, and a returning user's stored
  /// answers are matched by it.
  final String id;

  /// The headline. Written as a person would ask it out loud.
  final String text;

  /// The line under the headline — why we ask, or how to read the options.
  final String? helper;

  final OnboardingAnswerKind kind;

  /// Options, in display order. Empty for [OnboardingAnswerKind.text].
  final List<String> options;

  /// On a multi-select, opt-outs that clear every other option — see
  /// `IntakeQuestion.soloOptions`.
  final List<String> soloOptions;

  /// When true the user can move on without answering, and the skip is recorded
  /// as an explicit null so resume does not stop here again.
  final bool optional;

  /// Placeholder and leading icon for [OnboardingAnswerKind.text].
  final String? hint;
  final IconData? icon;
  final int maxLines;

  /// Non-null when the answer is also written to a promoted column.
  final ProfileColumn? column;

  const OnboardingQuestion({
    required this.id,
    required this.text,
    this.helper,
    this.kind = OnboardingAnswerKind.choice,
    this.options = const [],
    this.soloOptions = const [],
    this.optional = false,
    this.hint,
    this.icon,
    this.maxLines = 1,
    this.column,
  });

  bool get isMulti => kind == OnboardingAnswerKind.multiChoice;

  /// The options stored in [answer], in option order. A multi-select answer is
  /// joined with `selectionSeparator`, the same as an intake answer.
  Set<String> picked(Object? answer) => answer is String
      ? answer.split(selectionSeparator).where(options.contains).toSet()
      : {};

  /// [picked] as the string that is stored — in option order, so the same
  /// ticks always make the same answer.
  String join(Set<String> picked) =>
      joinSelections(options.where(picked.contains));

  Set<String> toggle(Set<String> picked, String option) =>
      toggleChoice(picked, option, multi: isMulti, solo: soloOptions);
}
