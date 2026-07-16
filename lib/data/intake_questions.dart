//intake_questions.dart

import 'package:flutter/material.dart';

import '../models/chat_category.dart';
import '../models/intake_question.dart';
import '../models/user_profile.dart';
import 'onboarding_questions.dart';

/// The scripted opening for a category — four or five questions, built for the
/// person asking.
///
/// ### What belongs here, and what does not
///
/// Onboarding already knows where the user lives, how far they got in
/// education, what they do, who they live with, their money situation, and how
/// they like to be advised. None of that is asked again. It is *used*: to word
/// a question, to fill an option list, or to drop a question that the profile
/// already answers. Everything here is about the decision in front of them,
/// which no profile can know.
///
/// ### Why plain Dart and not a predicate DSL
///
/// The list is built once, from the profile, at the moment a chat starts. That
/// makes branching an ordinary `switch` instead of a `when:` field on every
/// question and an engine to evaluate it. The questions a user is asked are
/// therefore a pure function of (category, profile) — easy to test, and easy
/// to read as prose.
///
/// The answer rows do not depend on this file being able to rebuild the list:
/// each message stores its own `question_text`, so a transcript stays readable
/// even after these questions are reworded.
List<IntakeQuestion> questionsFor(ChatCategory category, UserProfile profile) =>
    switch (category) {
      ChatCategory.education => _education(profile),
      ChatCategory.financial => _financial(profile),
      ChatCategory.relationship => _relationship(profile),
      ChatCategory.other => _other(profile),
    };

// ---------------------------------------------------------------------------
// Education
//
// Reads: education_level (which decision is even plausible), location (whether
// leaving is on the table). Never re-asks either.
// ---------------------------------------------------------------------------

List<IntakeQuestion> _education(UserProfile profile) {
  final stage = educationStageOf(profile);
  final place = profile.location?.trim();

  return [
    // The same question, asked in the terms the user's stage makes real. A
    // school student is not weighing "whether to retrain"; a graduate is not
    // weighing "which entrance exams".
    switch (stage) {
      EducationStage.preDegree => const IntakeQuestion(
          id: 'edu_decision',
          text: 'What are you trying to work out?',
          helper: 'We already know where you are — this is about the choice.',
          options: [
            'What to study next',
            'Where to study it',
            'Whether to study further at all',
            'Which entrance exams to aim for',
            'Whether to take a year out first',
            'Something else',
          ],
        ),
      EducationStage.midDegree => const IntakeQuestion(
          id: 'edu_decision',
          text: 'What are you trying to work out about your course?',
          options: [
            'Whether to stay on it',
            'What to specialise in',
            'What to do once it finishes',
            'Whether to add something alongside it',
            'Whether to take a break from it',
            'Something else',
          ],
        ),
      EducationStage.graduated => const IntakeQuestion(
          id: 'edu_decision',
          text: 'What are you trying to work out?',
          options: [
            'Whether to study further',
            'Which programme or institution',
            'Whether to retrain in a different field',
            'Whether the cost and time are worth it',
            'Whether to go abroad for it',
            'Something else',
          ],
        ),
      EducationStage.vocational ||
      EducationStage.selfTaught ||
      EducationStage.unknown =>
        const IntakeQuestion(
          id: 'edu_decision',
          text: 'What are you trying to work out?',
          options: [
            'Whether a formal qualification would help',
            'Which programme or course to take',
            'Whether to retrain in a different field',
            'Whether the cost and time are worth it',
            'Whether to keep learning on my own',
            'Something else',
          ],
        ),
    },

    // Open text: the real options are course names, institutions, and offers.
    // No fixed list could hold them, and forcing one would throw away the most
    // useful sentence the user could give us.
    const IntakeQuestion(
      id: 'edu_options',
      text: 'Which options are on the table?',
      helper: 'However you think of them. "Nothing yet" is a real answer.',
      kind: IntakeAnswerKind.text,
      hint: 'e.g. an MSc in Delhi vs. the job offer at home',
      icon: Icons.list_alt_outlined,
      maxLines: 3,
    ),

    // Uses the location from onboarding rather than asking where they live.
    // The chosen option records the place by name, so the answer still reads
    // on its own in a transcript.
    if (place != null)
      IntakeQuestion(
        id: 'edu_geography',
        text: 'Would this mean staying in $place, or leaving?',
        options: [
          'Staying in $place',
          'Elsewhere in the same country',
          'Abroad',
          'I am open to anywhere',
          'Not sure yet',
        ],
      )
    else
      const IntakeQuestion(
        id: 'edu_geography',
        text: 'Would this mean moving?',
        options: [
          'No, I would stay where I am',
          'Elsewhere in the same country',
          'Abroad',
          'I am open to anywhere',
          'Not sure yet',
        ],
      ),

    const IntakeQuestion(
      id: 'edu_obstacle',
      text: 'What is the hardest part of it?',
      options: [
        'The money',
        'What my family expects',
        'Not knowing what I would actually enjoy',
        'Whether I would even get in',
        'Whether it leads anywhere',
        'The time it would take',
        'Something else',
      ],
    ),

    const IntakeQuestion(
      id: 'edu_stage',
      text: 'Where are you with it?',
      options: [
        'Only just started thinking about it',
        'Narrowed it to a couple of options',
        'Leaning one way, but second-guessing',
        'Decided, and now doubting it',
      ],
    ),
  ];
}

// ---------------------------------------------------------------------------
// Financial
//
// Reads: living_situation, relationship_status, financial_context — together
// they decide whether the "who else does this affect" question is worth a
// screen. Never asks for income: onboarding took a coarse read, and scale is
// asked relative to the user rather than in currency.
// ---------------------------------------------------------------------------

List<IntakeQuestion> _financial(UserProfile profile) {
  final household = householdOf(profile);

  return [
    const IntakeQuestion(
      id: 'fin_decision',
      text: 'What is the money decision about?',
      options: [
        'Taking on a loan or debt',
        'Saving or investing',
        'A big purchase',
        'Earning more — a raise, a switch, a side income',
        'Making what I have stretch',
        'Money I would be giving someone else',
        'Something else',
      ],
    ),

    // Relative, not absolute. A number would be more precise and far less
    // likely to be given honestly — and "three months of what I live on" is
    // the part that actually grounds advice.
    const IntakeQuestion(
      id: 'fin_scale',
      text: 'Roughly how big is this, for you?',
      helper: 'Measured against what you live on. No numbers needed.',
      options: [
        'Small — a few days of what I live on',
        'Noticeable — about a month',
        'Big — several months',
        'Very big — a year or more',
        'It is not really about a fixed amount',
      ],
    ),

    // Distinct from onboarding's time_horizon, which is about their life plan.
    // This is the deadline on this one decision.
    const IntakeQuestion(
      id: 'fin_urgency',
      text: 'How soon do you have to decide?',
      helper: 'On this specific decision.',
      options: [
        'Within days',
        'Within a month',
        'Within a few months',
        'There is no real deadline',
        'It has been hanging over me for a while',
      ],
    ),

    // Dropped entirely for someone who lives alone, has no partner, and
    // supports nobody — the profile has already answered it.
    if (!decidesAlone(profile))
      IntakeQuestion(
        id: 'fin_stakeholders',
        text: 'Who else does this land on?',
        options: _stakeholderOptions(household),
      ),

    const IntakeQuestion(
      id: 'fin_blocker',
      text: 'What is making it hard to call?',
      options: [
        'I do not know what my options are',
        'I do not trust myself to get the numbers right',
        'The risk if it goes wrong',
        'Someone else is pushing me one way',
        'I keep putting it off',
        'Something else',
      ],
    ),
  ];
}

/// Most-likely answer first, so the common case is the shortest reach.
List<String> _stakeholderOptions(HouseholdShape household) => switch (household) {
      HouseholdShape.withFamily => const [
          'My parents or family',
          'My partner',
          'My children',
          'Just me, really',
          'Someone else',
        ],
      HouseholdShape.withPartner => const [
          'My partner',
          'My children',
          'My parents or family',
          'Just me, really',
          'Someone else',
        ],
      HouseholdShape.withFlatmates ||
      HouseholdShape.institutional ||
      HouseholdShape.alone ||
      HouseholdShape.unknown =>
        const [
          'Just me, really',
          'My partner',
          'My parents or family',
          'My children',
          'Someone else',
        ],
    };

// ---------------------------------------------------------------------------
// Relationship
//
// Reads: relationship_status — which is optional in onboarding, so it is
// frequently unknown. Unknown gets neutral wording; it is never asked again.
// ---------------------------------------------------------------------------

List<IntakeQuestion> _relationship(UserProfile profile) {
  return [
    IntakeQuestion(
      id: 'rel_who',
      text: 'Who is this about?',
      options: _aboutWhomOptions(partnerStatusOf(profile)),
    ),

    const IntakeQuestion(
      id: 'rel_decision',
      text: 'What are you trying to decide?',
      options: [
        'Whether to say something difficult',
        'Whether to step back or end it',
        'Whether to commit further',
        'How to handle a specific conflict',
        'Whether to set a boundary',
        'Whether to forgive something',
        'Something else',
      ],
    ),

    const IntakeQuestion(
      id: 'rel_duration',
      text: 'How long has this been on your mind?',
      options: ['A few days', 'A few weeks', 'Months', 'Years'],
    ),

    const IntakeQuestion(
      id: 'rel_spoken',
      text: 'Have you talked to them about it?',
      options: [
        'Not at all — they do not know',
        'I have hinted at it',
        'We talked about it once',
        'We have talked many times and nothing changes',
        'It turns into an argument every time',
      ],
    ),

    const IntakeQuestion(
      id: 'rel_fear',
      text: 'What is the worst outcome you keep picturing?',
      options: [
        'Hurting them',
        'Losing them',
        'Being judged for it',
        'Regretting it later',
        'Nothing changing at all',
        'Something else',
      ],
    ),
  ];
}

/// Worded so the first option is the person the profile suggests this is most
/// likely about — without ever stating it back at them as a fact.
List<String> _aboutWhomOptions(PartnerStatus partner) => switch (partner) {
      PartnerStatus.committed => const [
          'My partner',
          'My parents or family',
          'My children',
          'A friend',
          'Someone at work',
          'More than one of these',
        ],
      PartnerStatus.dating => const [
          'Someone I am seeing',
          'My parents or family',
          'A friend',
          'Someone at work',
          'More than one of these',
        ],
      PartnerStatus.ended => const [
          'My ex',
          'My parents or family',
          'My children',
          'A friend',
          'Someone new',
          'More than one of these',
        ],
      PartnerStatus.none => const [
          'Someone I am close to',
          'My parents or family',
          'A friend',
          'Someone at work',
          'Someone I would like to be with',
          'More than one of these',
        ],
      // Includes everyone who declined the optional onboarding question. No
      // assumption either way, and no second attempt at asking.
      PartnerStatus.unclear || PartnerStatus.unknown => const [
          'My partner, or someone I am seeing',
          'My parents or family',
          'A friend',
          'Someone at work',
          'More than one of these',
        ],
    };

// ---------------------------------------------------------------------------
// Other
//
// The catch-all, so it leans on an open question early rather than guessing at
// a taxonomy. The three named categories are excluded from its option list —
// anyone who wanted those had a card for them on the dashboard.
// ---------------------------------------------------------------------------

List<IntakeQuestion> _other(UserProfile profile) => const [
      IntakeQuestion(
        id: 'oth_area',
        text: 'What is this about?',
        helper: 'Education, money, and relationships have their own places — '
            'this is for everything else.',
        options: [
          'Work or career',
          'Health',
          'Where to live',
          'A habit I want to change',
          'Something creative',
          'How I spend my time',
          'Something else entirely',
        ],
      ),

      IntakeQuestion(
        id: 'oth_what',
        text: 'In your own words, what is the decision?',
        helper: 'A sentence is plenty — there is room to go deeper in a moment.',
        kind: IntakeAnswerKind.text,
        hint: 'e.g. whether to move cities for a job',
        icon: Icons.help_outline,
        maxLines: 3,
      ),

      IntakeQuestion(
        id: 'oth_shape',
        text: 'What kind of decision is it?',
        options: [
          'Whether to start something',
          'Whether to stop something',
          'Choosing between options',
          'Whether to tell someone something',
          'How to handle something I cannot leave',
        ],
      ),

      IntakeQuestion(
        id: 'oth_urgency',
        text: 'How soon do you have to decide?',
        options: [
          'Within days',
          'Within a month',
          'Within a few months',
          'There is no real deadline',
        ],
      ),

      IntakeQuestion(
        id: 'oth_stage',
        text: 'Where are you with it?',
        options: [
          'Only just started thinking about it',
          'Weighing options',
          'Leaning one way, but second-guessing',
          'Decided, and now doubting it',
        ],
      ),
    ];
