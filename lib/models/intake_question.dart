//intake_question.dart

import 'package:flutter/material.dart';

/// How an intake question is answered.
///
/// [multiChoice] exists because most of these questions were always multi-select
/// questions being asked as single-select ones. "Why does it feel like this?" is
/// not a question with one true answer — someone is tired *and* not listened to
/// *and* frightened of what happens if they say so, all at once. Forcing one tap
/// made the user pick the least wrong option and threw the rest away, and the
/// model then advised on the fragment that survived.
enum IntakeAnswerKind { choice, multiChoice, text }

/// One screen of a category's scripted opening.
///
/// Deliberately dumb: no profile predicates, no conditional fields. Which
/// questions get asked, and how they are worded for a given person, is decided
/// in `data/intake_questions.dart` when the list is built — see [questionsFor].
/// Keeping the branching in plain Dart there beats inventing a predicate DSL
/// here that would only ever have one caller.
class IntakeQuestion {
  /// Stable key, written to `messages.metadata.question_id`. It is how the API
  /// and the history screen find a specific answer without string-matching the
  /// question text, so it must not be reused or repurposed.
  final String id;

  /// What the user reads. Already interpolated with any profile facts — and, for
  /// the questions that follow one, with the person the chat turned out to be
  /// about — by the time it gets here. Stored verbatim on the message row, so a
  /// saved transcript never depends on being able to rebuild this list.
  final String text;

  final String? helper;
  final IntakeAnswerKind kind;

  /// Options in display order. Empty for [IntakeAnswerKind.text].
  final List<String> options;

  /// A skip is recorded as an explicit null answer, so the turn still gets a row
  /// and the transcript shows the question was asked and declined.
  final bool optional;

  final String? hint;
  final IconData? icon;
  final int maxLines;

  /// On a multi-select, opt-outs that mean "none of the others": "Nobody but
  /// me", "Not sure yet". Ticking one clears the rest, and ticking anything else
  /// clears it. This is the only way a square ever unticks another square —
  /// options that are merely incompatible peers mean the list is two questions,
  /// and it gets split instead (see `rel_spoken`).
  final List<String> soloOptions;

  const IntakeQuestion({
    required this.id,
    required this.text,
    this.helper,
    this.kind = IntakeAnswerKind.choice,
    this.options = const [],
    this.optional = false,
    this.hint,
    this.icon,
    this.maxLines = 1,
    this.soloOptions = const [],
  });

  bool get isChoice =>
      kind == IntakeAnswerKind.choice || kind == IntakeAnswerKind.multiChoice;

  bool get isMulti => kind == IntakeAnswerKind.multiChoice;

  /// What is ticked after tapping [option], given [picked] before. The one place
  /// the rules above are applied, so the screen and the tests cannot disagree.
  Set<String> toggle(Set<String> picked, String option) =>
      toggleChoice(picked, option, multi: isMulti, solo: soloOptions);
}

/// Tapping [option] on a list where [picked] is ticked.
///
/// Single-select: the tap replaces whatever was there — a circle is one answer.
/// Multi-select: the tap flips that option alone, except that an opt-out in
/// [solo] clears everything else and anything else clears it. Shared by the
/// intake, onboarding, and profile screens so a circle and a square behave the
/// same wherever they are drawn.
Set<String> toggleChoice(
  Set<String> picked,
  String option, {
  required bool multi,
  List<String> solo = const [],
}) {
  if (!multi) return {option};
  if (picked.contains(option)) return {...picked}..remove(option);
  if (solo.contains(option)) return {option};
  return {...picked.where((p) => !solo.contains(p)), option};
}

/// How a multi-select answer is written to `answer_text`.
///
/// The column is one string, and making it a list would mean a migration plus a
/// second shape for every reader — the API's transcript builder, the search
/// excerpt, the history row — to handle. A separator costs none of that, and
/// `answer_text` stays the thing every reader already treats it as: what the
/// user said, in the order they said it.
///
/// The chosen options also ride along in `metadata.selected` for anything that
/// wants them apart, so the join is a rendering of the answer rather than the
/// only record of it.
const String selectionSeparator = '; ';

String joinSelections(Iterable<String> selections) =>
    selections.join(selectionSeparator);
