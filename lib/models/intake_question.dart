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

  /// On a multi-select, sets of options that cannot be true together — at most
  /// one of each is ever ticked. "My ex-girlfriend" and "My ex-boyfriend" are
  /// two words for the one ex, not two people. An option may sit in several
  /// groups; ticking it unticks anything it shares a group with.
  final List<List<String>> exclusiveGroups;

  /// On a multi-select, options that rule out every other: "Nobody but me",
  /// "Not sure yet". Ticking one clears the rest, and ticking anything else
  /// clears it.
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
    this.exclusiveGroups = const [],
    this.soloOptions = const [],
  });

  bool get isChoice =>
      kind == IntakeAnswerKind.choice || kind == IntakeAnswerKind.multiChoice;

  bool get isMulti => kind == IntakeAnswerKind.multiChoice;

  bool _conflict(String a, String b) =>
      soloOptions.contains(a) ||
      soloOptions.contains(b) ||
      exclusiveGroups.any((g) => g.contains(a) && g.contains(b));

  /// What is ticked after tapping [option], given [picked] before. The one place
  /// the rules above are applied, so the screen and the tests cannot disagree.
  Set<String> toggle(Set<String> picked, String option) {
    if (!isMulti) return {option};
    if (picked.contains(option)) return {...picked}..remove(option);
    return {
      for (final p in picked)
        if (!_conflict(p, option)) p,
      option,
    };
  }
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
