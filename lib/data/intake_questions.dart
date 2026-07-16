//intake_questions.dart

import 'package:flutter/material.dart';

import '../models/chat_category.dart';
import '../models/intake_question.dart';
import '../models/user_profile.dart';
import 'onboarding_questions.dart';

/// The scripted opening for a category — built for the person asking, and for
/// what they have already said in this chat.
///
/// ### What belongs here, and what does not
///
/// Onboarding already knows where the user lives, how far they got in
/// education, what they do, who they live with, their money situation, how they
/// like to be advised, and now how they describe themselves. None of that is
/// asked again. It is *used*: to word a question, to fill an option list, or to
/// drop a question the profile already answers.
///
/// ### Why [answers] exists
///
/// This used to be a pure function of `(category, profile)` — the list was built
/// once when the chat started and never looked at again. That is what produced
/// the flat, evasive relationship intake: the app had to word every question
/// without knowing who the chat was about, so it asked "Who is this about?
/// Someone I am close to" and then "What is the worst outcome you keep
/// picturing?" — questions carefully phrased to be equally applicable to a
/// girlfriend and a line manager, and therefore about nobody.
///
/// Now the first question establishes the person, and the rest are written about
/// *them*: "Does she actually give you time?" rather than "How are things?" The
/// flow rebuilds the list from the answers so far after each one — see
/// [IntakeFlowScreen], which is also what deletes the rows for a tail that
/// changed underneath.
///
/// The answer rows do not depend on this file being able to rebuild the list:
/// each message stores its own `question_text`, so a transcript stays readable
/// even after these questions are reworded.
List<IntakeQuestion> questionsFor(
  ChatCategory category,
  UserProfile profile, [
  Map<String, String?> answers = const {},
]) =>
    switch (category) {
      ChatCategory.education => _education(profile),
      ChatCategory.financial => _financial(profile),
      ChatCategory.relationship => _relationship(profile, answers),
      ChatCategory.other => _other(profile),
    };

// ---------------------------------------------------------------------------
// Who a relationship chat is about
// ---------------------------------------------------------------------------

/// The person a relationship chat is about, and how to talk about them.
///
/// Pronouns come from the option the user *tapped*, never from an inference. A
/// man's partner is offered as "My girlfriend" first because that is who it
/// usually is — but "My boyfriend" and "My partner" are on the same screen, and
/// whichever he picks is what the rest of the flow believes. Guessing from his
/// gender alone would be wrong for some people every single time, and the guess
/// buys nothing that the tap does not.
class PersonRef {
  /// How to name them in a question: "your girlfriend", "your family".
  final String noun;

  /// she / he / they.
  final String subject;

  /// her / him / them.
  final String object;

  /// her / his / their.
  final String possessive;

  /// Whether the verb after [subject] takes the third-person -s. "She does" vs
  /// "They do" — singular *they* takes the plural verb, and getting this wrong
  /// is the tell that a string was assembled by a machine.
  final bool singularVerb;

  /// Romantic, as opposed to family, a friend, or someone at work. Decides which
  /// questions are even worth asking.
  final bool isPartner;

  const PersonRef({
    required this.noun,
    required this.subject,
    required this.object,
    required this.possessive,
    required this.singularVerb,
    required this.isPartner,
  });

  static String _capitalise(String word) =>
      word[0].toUpperCase() + word.substring(1);

  /// [subject] at the start of a sentence — "She", "They".
  String get subjectCap => _capitalise(subject);

  /// [possessive] at the start of a sentence — "Her", "Their".
  String get possessiveCap => _capitalise(possessive);

  /// "doesn't" / "don't", agreeing with [subject].
  String get doesnt => singularVerb ? "doesn't" : "don't";

  /// "is" / "are".
  String get isAre => singularVerb ? 'is' : 'are';

  /// "has" / "have".
  String get has => singularVerb ? 'has' : 'have';

  /// The present tense of [stem] agreeing with [subject]: "wants" / "want".
  /// Singular *they* takes the plural verb, which is the whole reason this is a
  /// method rather than a string concatenation at each call site.
  String verb(String stem) => singularVerb ? '${stem}s' : stem;

  static const _sheHer = PersonRef(
    noun: '',
    subject: 'she',
    object: 'her',
    possessive: 'her',
    singularVerb: true,
    isPartner: true,
  );

  static const _heHim = PersonRef(
    noun: '',
    subject: 'he',
    object: 'him',
    possessive: 'his',
    singularVerb: true,
    isPartner: true,
  );

  static const _they = PersonRef(
    noun: '',
    subject: 'they',
    object: 'them',
    possessive: 'their',
    singularVerb: false,
    isPartner: true,
  );

  PersonRef named(String noun, {bool? isPartner}) => PersonRef(
        noun: noun,
        subject: subject,
        object: object,
        possessive: possessive,
        singularVerb: singularVerb,
        isPartner: isPartner ?? this.isPartner,
      );
}

/// Reads the answer to `rel_who` back into a [PersonRef].
///
/// Matches the option strings built by [_aboutWhomOptions]. They are asserted
/// against each other by `intake_flow_test.dart` — reword an option without
/// touching this and the suite fails, rather than the flow silently falling back
/// to "them" for a girlfriend.
PersonRef personFrom(String? answer) => switch (answer) {
      'My girlfriend' => PersonRef._sheHer.named('your girlfriend'),
      'My wife' => PersonRef._sheHer.named('your wife'),
      'My ex-girlfriend' => PersonRef._sheHer.named('your ex'),
      'My boyfriend' => PersonRef._heHim.named('your boyfriend'),
      'My husband' => PersonRef._heHim.named('your husband'),
      'My ex-boyfriend' => PersonRef._heHim.named('your ex'),
      'My partner' => PersonRef._they.named('your partner'),
      'My ex' => PersonRef._they.named('your ex'),
      'Someone I am seeing' => PersonRef._they.named('them'),
      'Someone I want to be with' => PersonRef._they.named('them'),
      'My parents or family' =>
        PersonRef._they.named('your family', isPartner: false),
      'My children' =>
        PersonRef._they.named('your children', isPartner: false),
      'A close friend' =>
        PersonRef._they.named('your friend', isPartner: false),
      'Someone at work' =>
        PersonRef._they.named('them', isPartner: false),
      // Includes "More than one of these" and an unanswered first question.
      _ => PersonRef._they.named('them', isPartner: false),
    };

/// Whether the profile says married specifically, rather than merely committed.
/// "My wife" and "My girlfriend" are not interchangeable to the person being
/// asked, and [PartnerStatus.committed] covers both.
bool _isMarried(UserProfile profile) =>
    onboardingAnswer(profile, 'relationship_status') == 'Married';

/// The partner option, worded for who is asking.
///
/// The likeliest noun leads — a man in a relationship is asked about his
/// girlfriend, which is the entire point of having asked his gender. The
/// alternatives are on the same screen and one tap away, so nobody is told what
/// their relationship is; they are just offered the common case first.
List<String> _partnerOptions(UserProfile profile) {
  final gender = genderOf(profile);
  final status = partnerStatusOf(profile);
  final married = _isMarried(profile);

  final (theirs, alternative) = switch (gender) {
    Gender.man => ('My girlfriend', 'My boyfriend'),
    Gender.woman => ('My boyfriend', 'My girlfriend'),
    Gender.nonBinary || Gender.unspecified => ('My partner', null),
  };

  final spouse = switch (gender) {
    Gender.man => 'My wife',
    Gender.woman => 'My husband',
    Gender.nonBinary || Gender.unspecified => 'My partner',
  };

  return switch (status) {
    PartnerStatus.committed when married => [spouse],
    PartnerStatus.committed || PartnerStatus.dating => [
        theirs,
        if (alternative != null) alternative,
      ],
    PartnerStatus.ended => [
        switch (gender) {
          Gender.man => 'My ex-girlfriend',
          Gender.woman => 'My ex-boyfriend',
          Gender.nonBinary || Gender.unspecified => 'My ex',
        },
        'Someone I am seeing',
      ],
    PartnerStatus.none => ['Someone I am seeing', 'Someone I want to be with'],
    // Declined the optional onboarding question, or a profile from before it
    // existed. No assumption, and no second attempt at asking — declining once
    // means declined.
    PartnerStatus.unclear || PartnerStatus.unknown => [
        theirs,
        if (alternative != null) alternative,
      ],
  };
}

List<String> _aboutWhomOptions(UserProfile profile) => [
      ..._partnerOptions(profile),
      'My parents or family',
      'A close friend',
      'Someone at work',
      'More than one of these',
    ];

// ---------------------------------------------------------------------------
// Relationship
//
// The category the app is judged on. Most people do not open an app to work out
// what their cousin meant; they open it at 1am because of one person, and the
// questions have to be willing to say so.
// ---------------------------------------------------------------------------

List<IntakeQuestion> _relationship(
  UserProfile profile,
  Map<String, String?> answers,
) {
  final who = personFrom(answers['rel_who']);

  return [
    IntakeQuestion(
      id: 'rel_who',
      text: 'Who is this about?',
      options: _aboutWhomOptions(profile),
    ),

    // The question the old set never asked. It had `rel_decision` ("What are you
    // trying to decide?") as its second screen — asking someone to name their
    // own conclusion before they have said what happened. This asks what is
    // actually going on, it is multi-select because it is never one thing, and
    // the options are specific enough to sting.
    if (who.isPartner)
      IntakeQuestion(
        id: 'rel_whats_wrong',
        text: 'What is actually going on with ${who.noun}?',
        helper: 'Pick everything that is true. Most of this is never one thing.',
        kind: IntakeAnswerKind.multiChoice,
        options: [
          '${who.subjectCap} ${who.doesnt} give me time',
          'I do not feel valued',
          'We fight about the same thing every time',
          '${who.subjectCap} ${who.has} been pulling away',
          'I do not trust ${who.object} anymore',
          '${who.possessiveCap} family or friends are in the middle of it',
          'One of us wants something the other does not',
          // The option that implicates the person asking. A list where every
          // answer is something done *to* them is a list that has already taken
          // a side, and the app would then advise on a story it helped write.
          'Honestly, I am the one who has checked out',
        ],
      )
    else
      IntakeQuestion(
        id: 'rel_whats_wrong',
        text: 'What is actually going on with ${who.noun}?',
        helper: 'Pick everything that is true.',
        kind: IntakeAnswerKind.multiChoice,
        options: [
          '${who.subjectCap} ${who.doesnt} listen to me',
          '${who.subjectCap} ${who.verb("decide")} things for me',
          'Money is tangled up in it',
          'I am expected to be someone I am not',
          'We fight about the same thing every time',
          'Something was said that has not been taken back',
          '${who.subjectCap} ${who.doesnt} know the thing I am not saying',
          'Honestly, I am the one in the wrong here',
        ],
      ),

    IntakeQuestion(
      id: 'rel_decision',
      text: 'What are you trying to decide?',
      options: [
        if (who.isPartner) ...[
          'Whether to end it',
          'Whether to say the thing I have not said',
          'Whether to give it more time',
          'Whether to commit further',
          'Whether to forgive something',
          'Whether I am being unreasonable',
        ] else ...[
          'Whether to say the thing I have not said',
          'Whether to step back from ${who.object}',
          'Whether to set a boundary',
          'Whether to forgive something',
          'Whether to go along with what ${who.subject} ${who.verb("want")}',
          'Whether I am being unreasonable',
        ],
        'Something else',
      ],
    ),

    const IntakeQuestion(
      id: 'rel_duration',
      text: 'How long has this been going on?',
      options: [
        'Days',
        'Weeks',
        'Months',
        'Years',
        'As long as I have known them',
      ],
    ),

    IntakeQuestion(
      id: 'rel_spoken',
      text: 'Have you told ${who.object}?',
      options: [
        '${who.subjectCap} ${who.has} no idea',
        'I have hinted, that is all',
        'We talked once and nothing changed',
        'We have talked many times and nothing changes',
        'It turns into a fight every time',
        '${who.subjectCap} ${who.verb("say")} it is fine and it is not',
      ],
    ),

    // Multi-select and blunt. The old version asked for "the worst outcome you
    // keep picturing" and offered "Hurting them" / "Losing them" — true, and
    // useless, because everyone picks both and the app learned nothing.
    IntakeQuestion(
      id: 'rel_fear',
      text: 'What is stopping you?',
      helper: 'All of it, if that is the honest answer.',
      kind: IntakeAnswerKind.multiChoice,
      options: [
        if (who.isPartner) 'I do not want to be alone',
        'I would hurt ${who.object}',
        'I would lose ${who.object}',
        'My family would have something to say about it',
        'I would look like the bad one',
        'I have already put too much into this to walk away',
        'I might regret it',
        'Nothing would change anyway',
      ],
    ),
  ];
}

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

    // Open text: the real options are course names, institutions, and offers. No
    // fixed list could hold them, and forcing one would throw away the most
    // useful sentence the user could give us.
    const IntakeQuestion(
      id: 'edu_options',
      text: 'Which options are actually on the table?',
      helper: 'However you think of them. "Nothing yet" is a real answer.',
      kind: IntakeAnswerKind.text,
      hint: 'e.g. an MSc in Delhi vs. the job offer at home',
      icon: Icons.list_alt_outlined,
      maxLines: 3,
    ),

    // Uses the location from onboarding rather than asking where they live. The
    // chosen option records the place by name, so the answer still reads on its
    // own in a transcript.
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

    // Multi-select: money and family and self-doubt are the usual answer, all
    // three at once, and making someone rank them threw two of them away.
    const IntakeQuestion(
      id: 'edu_obstacle',
      text: 'What is actually in the way?',
      helper: 'Everything that applies.',
      kind: IntakeAnswerKind.multiChoice,
      options: [
        'The money',
        'My family expects something else',
        'I do not know what I would even enjoy',
        'I might not get in',
        'I am not sure it leads anywhere',
        'The time it would take',
        'I have already started down another path',
        'Honestly, I am just scared of picking wrong',
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
        'Money someone owes me',
        'Something else',
      ],
    ),

    // Relative, not absolute. A number would be more precise and far less likely
    // to be given honestly — and "three months of what I live on" is the part
    // that actually grounds advice.
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

    // Dropped entirely for someone who lives alone, has no partner, and supports
    // nobody — the profile has already answered it.
    if (!decidesAlone(profile))
      IntakeQuestion(
        id: 'fin_stakeholders',
        text: 'Who else does this land on?',
        helper: 'Everyone it touches.',
        kind: IntakeAnswerKind.multiChoice,
        options: _stakeholderOptions(household),
      ),

    const IntakeQuestion(
      id: 'fin_blocker',
      text: 'What is making it hard to call?',
      helper: 'Everything that applies.',
      kind: IntakeAnswerKind.multiChoice,
      options: [
        'I do not know what my options are',
        'I do not trust myself to get the numbers right',
        'The risk if it goes wrong',
        'Someone else is pushing me one way',
        'Saying no would cost me the relationship',
        'I keep putting it off',
        'I already know the answer and do not like it',
      ],
    ),
  ];
}

/// Most-likely answer first, so the common case is the shortest reach.
List<String> _stakeholderOptions(HouseholdShape household) =>
    switch (household) {
      HouseholdShape.withFamily => const [
          'My parents or family',
          'My partner',
          'My children',
          'Nobody but me',
          'Someone else',
        ],
      HouseholdShape.withPartner => const [
          'My partner',
          'My children',
          'My parents or family',
          'Nobody but me',
          'Someone else',
        ],
      HouseholdShape.withFlatmates ||
      HouseholdShape.institutional ||
      HouseholdShape.alone ||
      HouseholdShape.unknown =>
        const [
          'Nobody but me',
          'My partner',
          'My parents or family',
          'My children',
          'Someone else',
        ],
    };

// ---------------------------------------------------------------------------
// Other
//
// The catch-all, so it leans on an open question early rather than guessing at a
// taxonomy. The three named categories are excluded from its option list —
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
        id: 'oth_blocker',
        text: 'What is actually in the way?',
        helper: 'Everything that applies.',
        kind: IntakeAnswerKind.multiChoice,
        options: [
          'I do not know enough yet',
          'Someone else would have to be okay with it',
          'The money',
          'It would mean admitting I was wrong before',
          'I do not trust my own judgement on this',
          'I keep putting it off',
          'I already know the answer and do not like it',
        ],
      ),
    ];
