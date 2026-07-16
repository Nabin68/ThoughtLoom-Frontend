//intake_question.dart

import 'package:flutter/material.dart';

/// How an intake question is answered. Radio unless the honest answer space is
/// unbounded — same rule the onboarding set follows.
enum IntakeAnswerKind { choice, text }

/// One screen of a category's scripted opening.
///
/// Deliberately dumb: no profile predicates, no conditional fields. Which
/// questions get asked, and how they are worded for a given person, is decided
/// in `data/intake_questions.dart` when the list is built — see
/// [questionsFor]. Keeping the branching in plain Dart there beats inventing a
/// predicate DSL here that would only ever have one caller.
class IntakeQuestion {
  /// Stable key, written to `messages.metadata.question_id`. It is how Prompt 4
  /// and the history screen find a specific answer without string-matching the
  /// question text, so it must not be reused or repurposed.
  final String id;

  /// What the user reads. Already interpolated with any profile facts by the
  /// time it gets here, and stored verbatim on the message row — so a saved
  /// transcript never depends on being able to rebuild this list.
  final String text;

  final String? helper;
  final IntakeAnswerKind kind;

  /// Radio options in display order. Empty for [IntakeAnswerKind.text].
  final List<String> options;

  /// A skip is recorded as an explicit null answer, so the turn still gets a
  /// row and the transcript shows the question was asked and declined.
  final bool optional;

  final String? hint;
  final IconData? icon;
  final int maxLines;

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
  });
}
