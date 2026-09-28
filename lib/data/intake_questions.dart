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
/// Every later question can depend on an earlier answer in the same chat. The
/// relationship set is worded about the person the first question named; the
/// other three hide options that only make sense for some first answers (no
/// "I might not get in" for someone deciding whether to take a break from a
/// course they are already on). The flow rebuilds the list after each answer —
/// see [IntakeFlowScreen], which is also what deletes the rows for a tail that
/// changed underneath.
///
/// ### Typed answers
///
/// Every choice question also offers "Something else — let me explain" (the
/// screen adds it, not this file). A typed answer matches none of the options
/// below, so every branch here treats an unrecognised answer as "could be
/// anything" and falls back to the broadest set rather than a narrow wrong one.
/// The typed text itself is stored on the message row and is what the adaptive
/// flow's model reads.
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
      ChatCategory.education => _education(profile, answers),
      ChatCategory.financial => _financial(profile, answers),
      ChatCategory.relationship => _relationship(profile, answers),
      ChatCategory.other => _other(answers),
    };

// ---------------------------------------------------------------------------
// Who a relationship chat is about
// ---------------------------------------------------------------------------

/// What the person is to the user. Decides which questions are worth asking,
/// and in which tense: an ex is past tense and a want is not-yet, and neither
/// can "not give me time" or be broken up with.
enum Tie { partner, ex, want, family, children, friend, work, unknown }

/// The person a relationship chat is about, and how to talk about them.
///
/// Pronouns come from the option the user *tapped*, never from an inference.
/// "My girlfriend" is she, "My husband" is he, "My partner" is they —
/// whoever is asking.
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

  final Tie tie;

  const PersonRef({
    required this.noun,
    required this.subject,
    required this.object,
    required this.possessive,
    required this.singularVerb,
    required this.tie,
  });

  /// Currently together — including someone they are seeing.
  bool get isPartner => tie == Tie.partner;
  bool get isEx => tie == Tie.ex;
  bool get isWant => tie == Tie.want;

  /// Still in the user's life. Not an ex, not someone they only want to be
  /// with — neither has an ongoing relationship to fight in.
  bool get hasOngoing => !isEx && !isWant;

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
  String verb(String stem) => singularVerb ? '${stem}s' : stem;

  static PersonRef _she(String noun, Tie tie) => PersonRef(
      noun: noun,
      subject: 'she',
      object: 'her',
      possessive: 'her',
      singularVerb: true,
      tie: tie);

  static PersonRef _he(String noun, Tie tie) => PersonRef(
      noun: noun,
      subject: 'he',
      object: 'him',
      possessive: 'his',
      singularVerb: true,
      tie: tie);

  static PersonRef _they(String noun, Tie tie) => PersonRef(
      noun: noun,
      subject: 'they',
      object: 'them',
      possessive: 'their',
      singularVerb: false,
      tie: tie);

  /// Someone typed in, or nobody chosen yet.
  static final unknown = _they('them', Tie.unknown);
}

/// The `rel_who` answer as a [PersonRef]. Anything that is not exactly one of
/// the options — a typed "Something else" answer, or nothing yet — is
/// [PersonRef.unknown], which gets the broad option set.
///
/// Matches the option strings built by [_aboutWhomOptions]; the test suite
/// walks every one of those through here, so rewording an option without
/// touching this fails loudly rather than silently degrading to "them".
PersonRef personFrom(String? answer) => switch (answer) {
      'My girlfriend' => PersonRef._she('your girlfriend', Tie.partner),
      'My wife' => PersonRef._she('your wife', Tie.partner),
      'My boyfriend' => PersonRef._he('your boyfriend', Tie.partner),
      'My husband' => PersonRef._he('your husband', Tie.partner),
      'My partner' => PersonRef._they('your partner', Tie.partner),
      'Someone I am seeing' => PersonRef._they('them', Tie.partner),
      'My ex-girlfriend' => PersonRef._she('your ex-girlfriend', Tie.ex),
      'My ex-wife' => PersonRef._she('your ex-wife', Tie.ex),
      'My ex-boyfriend' => PersonRef._he('your ex-boyfriend', Tie.ex),
      'My ex-husband' => PersonRef._he('your ex-husband', Tie.ex),
      'My ex-partner' => PersonRef._they('your ex-partner', Tie.ex),
      'Someone I want to be with' => PersonRef._they('them', Tie.want),
      'My parents or family' => PersonRef._they('your family', Tie.family),
      'My children' => PersonRef._they('your children', Tie.children),
      'A close friend' => PersonRef._they('your friend', Tie.friend),
      'Someone at work' => PersonRef._they('them', Tie.work),
      _ => PersonRef.unknown,
    };

/// Whether the profile says married specifically, rather than merely committed.
bool _isMarried(UserProfile profile) =>
    onboardingAnswer(profile, 'relationship_status') == 'Married';

/// The romantic options, chosen by relationship status and *ordered* by the
/// asker's gender.
///
/// Status decides the set — someone dating is offered girlfriend / boyfriend /
/// partner, someone married wife / husband / partner, someone divorced the
/// ex-spouse terms before the ex-dating ones. Gender only decides which of the
/// three leads: every one of them is on the same screen, one tap away, so
/// nobody is told what their relationship is.
List<String> _romanticOptions(UserProfile profile) {
  List<String> lead(String hers, String his, String neutral) =>
      switch (genderOf(profile)) {
        Gender.man => [hers, his, neutral],
        Gender.woman => [his, hers, neutral],
        Gender.nonBinary || Gender.unspecified => [neutral, hers, his],
      };

  final dating = lead('My girlfriend', 'My boyfriend', 'My partner');
  final married = lead('My wife', 'My husband', 'My partner');
  final exDating = lead('My ex-girlfriend', 'My ex-boyfriend', 'My ex-partner');
  final exMarried = lead('My ex-wife', 'My ex-husband', 'My ex-partner');
  const seeing = 'Someone I am seeing';
  const want = 'Someone I want to be with';

  // Status decides the order and the likeliest set, never what is fully off
  // the table: a single person still has exes, and "It is complicated" or a
  // declined question gets everything rather than a guess.
  final options = switch (partnerStatusOf(profile)) {
    PartnerStatus.committed when _isMarried(profile) => [...married, ...exDating],
    PartnerStatus.committed => [...dating, ...exDating],
    PartnerStatus.dating => [...dating, seeing, ...exDating],
    PartnerStatus.ended => [...exMarried, ...exDating, seeing, want],
    PartnerStatus.none => [seeing, want, ...exDating],
    PartnerStatus.unclear || PartnerStatus.unknown => [
        ...dating,
        ...married,
        ...exDating,
        ...exMarried,
        seeing,
        want,
      ],
  };
  // "My partner" and "My ex-partner" sit in two of the lists at once.
  return options.toSet().toList();
}

List<String> _aboutWhomOptions(UserProfile profile) => [
      ..._romanticOptions(profile),
      'My parents or family',
      if (!isMinor(profile)) 'My children',
      'A close friend',
      'Someone at work',
    ];

// ---------------------------------------------------------------------------
// Relationship
//
// The category the app is judged on. Most people do not open an app to work out
// what their cousin meant; they open it at 1am because of one person, and the
// questions have to be willing to say so.
// ---------------------------------------------------------------------------

/// Q3 answers that are a question about the situation rather than a step the
/// user might take. "What is stopping you?" has no answer after these.
const _reflectiveDecisions = {
  'Whether I am being unreasonable',
  'Whether to give it more time',
};

List<String> _whatsWrong(PersonRef p) {
  if (p.tie == Tie.partner) {
    return [
      '${p.subjectCap} ${p.doesnt} give me time',
      'I do not feel valued',
      'We fight about the same thing every time',
      '${p.subjectCap} ${p.has} been pulling away',
      'I do not trust ${p.object} anymore',
      '${p.possessiveCap} family or friends are in the middle of it',
      'One of us wants something the other does not',
      // The option that implicates the person asking. A list where every
      // answer is something done *to* them has already taken a side.
      'Honestly, I am the one who has checked out',
    ];
  }
  if (p.tie == Tie.ex) {
    return [
      'I want ${p.object} back',
      'I cannot move on',
      '${p.subjectCap} ${p.isAre} with someone new',
      'We still talk sometimes',
      'I do not know why it ended',
      'One of us wants something the other does not',
      'Honestly, I am the one who ended it',
    ];
  }
  if (p.tie == Tie.want) {
    return [
      '${p.subjectCap} ${p.doesnt} know how I feel',
      '${p.subjectCap} ${p.isAre} with someone else',
      'I do not know if it is mutual',
      '${p.possessiveCap} family or friends are in the middle of it',
      'One of us wants something the other does not',
      'Honestly, I am not sure what I want',
    ];
  }
  final children = p.tie == Tie.children;
  return [
    '${p.subjectCap} ${p.doesnt} listen to me',
    // A parent, a manager — not a friend, and not usually one's own children.
    if (const {Tie.family, Tie.work, Tie.unknown}.contains(p.tie))
      '${p.subjectCap} ${p.verb("decide")} things for me',
    if (children) "${p.subjectCap} ${p.doesnt} want to spend time with me",
    'Money is tangled up in it',
    'I am expected to be someone I am not',
    if (children) 'I am worried about the choices ${p.subject} ${p.verb("make")}',
    'We fight about the same thing every time',
    'Something was said that has not been taken back',
    '${p.subjectCap} ${p.doesnt} know the thing I am not saying',
    'Honestly, I am the one in the wrong here',
  ];
}

List<String> _decisions(PersonRef p) {
  if (p.tie == Tie.partner) {
    return const [
      'Whether to end it',
      'Whether to say the thing I have not said',
      'Whether to give it more time',
      'Whether to commit further',
      'Whether to forgive something',
      'Whether I am being unreasonable',
    ];
  }
  if (p.tie == Tie.ex) {
    return const [
      'Whether to reach out',
      'Whether to try to get back together',
      'Whether to cut contact',
      'Whether to move on',
      'Whether to say the thing I have not said',
      'Whether to forgive something',
      'Whether I am being unreasonable',
    ];
  }
  if (p.tie == Tie.want) {
    return const [
      'Whether to make a move',
      'Whether to say the thing I have not said',
      'Whether to give it more time',
      'Whether to give up',
      'Whether I am being unreasonable',
    ];
  }
  return [
    'Whether to say the thing I have not said',
    'Whether to step back from ${p.object}',
    'Whether to set a boundary',
    'Whether to forgive something',
    'Whether to go along with what ${p.subject} ${p.verb("want")}',
    'Whether I am being unreasonable',
  ];
}

List<IntakeQuestion> _relationship(
  UserProfile profile,
  Map<String, String?> answers,
) {
  final who = personFrom(answers['rel_who']);
  final decision = answers['rel_decision'];

  final noIdea = '${who.subjectCap} ${who.has} no idea';
  const hinted = 'I have hinted, that is all';
  const once = 'We talked once and nothing changed';
  const fight = 'It turns into a fight every time';
  final saysFine =
      '${who.subjectCap} ${who.verb("say")} it is fine and it is not';

  return [
    IntakeQuestion(
      id: 'rel_who',
      text: 'Who is this about?',
      // Single: one relationship per chat, because every question after this
      // is worded about that one person. A situation with two people in it — a
      // partner *and* their family — goes through "Something else", and the
      // adaptive questions pick it up from what was written.
      helper: 'Pick the one this is mainly about. If it is more than one '
          'person, use "Something else".',
      options: _aboutWhomOptions(profile),
    ),

    // Multi-select because it is never one thing, and the options are specific
    // enough to sting — in the right tense for who this is.
    IntakeQuestion(
      id: 'rel_whats_wrong',
      text: 'What is actually going on with ${who.noun}?',
      helper: who.isPartner
          ? 'Pick everything that is true. Most of this is never one thing.'
          : 'Pick everything that is true.',
      kind: IntakeAnswerKind.multiChoice,
      options: _whatsWrong(who),
    ),

    IntakeQuestion(
      id: 'rel_decision',
      text: 'What are you trying to decide?',
      // Single: one decision at a time, and whether "What is stopping you?"
      // follows depends on which.
      helper: 'Pick the main one.',
      options: _decisions(who),
    ),

    // "Going on" is wrong for something that is over, and "as long as I have
    // known them" is wrong for someone's own parents.
    switch (who.tie) {
      Tie.ex => const IntakeQuestion(
          id: 'rel_duration',
          text: 'How long ago did it end?',
          options: [
            'Days ago',
            'Weeks ago',
            'Months ago',
            'Years ago',
            'It never properly ended',
          ],
        ),
      Tie.want => IntakeQuestion(
          id: 'rel_duration',
          text: 'How long have you felt this way?',
          options: [
            'Days',
            'Weeks',
            'Months',
            'Years',
            'As long as I have known ${who.object}',
          ],
        ),
      _ => IntakeQuestion(
          id: 'rel_duration',
          text: 'How long has this been going on?',
          options: [
            'Days',
            'Weeks',
            'Months',
            'Years',
            who.tie == Tie.family || who.tie == Tie.children
                ? 'For as long as I can remember'
                : 'As long as I have known ${who.object}',
          ],
        ),
    },

    IntakeQuestion(
      id: 'rel_spoken',
      text: 'Have you told ${who.object}?',
      // Multi, with a single answer inside it. How far it got — no idea,
      // hinted, once, many times — is one answer. How it goes — a fight, "it is
      // fine" — can be several, and "we do not talk anymore" can sit alongside
      // any of them.
      helper: 'Pick everything that is true.',
      kind: IntakeAnswerKind.multiChoice,
      options: [
        noIdea,
        hinted,
        once,
        // Only for someone still in the user's life: an ex or someone they are
        // not with has no ongoing conversation to keep failing.
        if (who.hasOngoing) ...[
          'We have talked many times and nothing changes',
          fight,
          saysFine,
        ],
        if (who.tie == Tie.ex) 'We do not talk anymore',
      ],
      exclusiveGroups: [
        [noIdea, hinted, once, 'We have talked many times and nothing changes'],
        // "Every time" and "it is fine" both need a conversation to have
        // happened, and "every time" needs more than one.
        [noIdea, fight],
        [noIdea, saysFine],
        [hinted, fight],
        [once, fight],
      ],
    ),

    // Only after a step the user might take. After "Whether I am being
    // unreasonable" there is nothing to be stopped from.
    if (!_reflectiveDecisions.contains(decision))
      IntakeQuestion(
        id: 'rel_fear',
        text: 'What is stopping you?',
        helper: 'All of it, if that is the honest answer.',
        kind: IntakeAnswerKind.multiChoice,
        options: [
          if (who.tie == Tie.partner) 'I do not want to be alone',
          if (who.hasOngoing) 'I would hurt ${who.object}',
          // An ex is already lost, and already walked away from.
          if (!who.isEx) 'I would lose ${who.object}',
          if (who.tie == Tie.ex) ...[
            'I might get hurt again',
            'It would mean admitting it is really over',
          ],
          if (who.tie == Tie.want) ...[
            '${who.subjectCap} might say no',
            'It could ruin what we have now',
          ],
          // Redundant when the family is who this is about.
          if (who.tie != Tie.family)
            'My family would have something to say about it',
          'I would look like the bad one',
          if (!who.isEx)
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
// leaving is on the table). Never re-asks either. Later questions read the
// decision: nobody deciding whether to take a break is "worried they won't get
// in", or asked whether it means moving.
// ---------------------------------------------------------------------------

/// Decisions about a course the user is already on, or learning outside one —
/// no move, no application.
const _eduStayingPut = {
  'Whether to stay on it',
  'Whether to take a break from it',
  'What to specialise in',
  'Whether to add something alongside it',
  'Whether to keep learning on my own',
};

/// Decisions with no admission at the end of them.
const _eduNoApplication = {
  'Whether to stay on it',
  'Whether to take a break from it',
  'What to specialise in',
  'Whether to keep learning on my own',
  'Whether to take a year out first',
};

/// Stepping out for a while — where the cost is falling behind, not "the time
/// it would take".
const _eduPause = {
  'Whether to take a break from it',
  'Whether to take a year out first',
};

List<IntakeQuestion> _education(
  UserProfile profile,
  Map<String, String?> answers,
) {
  final stage = educationStageOf(profile);
  final place = profile.location?.trim();
  final decision = answers['edu_decision'];
  final struggling = decision == 'Whether to stay on it' ||
      decision == 'Whether to take a break from it';

  return [
    // The same question, asked in the terms the user's stage makes real. A
    // school student is not weighing "whether to retrain"; a graduate is not
    // weighing "which entrance exams".
    switch (stage) {
      EducationStage.preDegree => const IntakeQuestion(
          id: 'edu_decision',
          text: 'What are you trying to work out?',
          helper: 'Pick the main one — we already know where you are.',
          options: [
            'What to study next',
            'Where to study it',
            'Whether to study further at all',
            'Which entrance exams to aim for',
            'Whether to take a year out first',
          ],
        ),
      EducationStage.midDegree => const IntakeQuestion(
          id: 'edu_decision',
          text: 'What are you trying to work out about your course?',
          helper: 'Pick the main one.',
          options: [
            'Whether to stay on it',
            'What to specialise in',
            'What to do once it finishes',
            'Whether to add something alongside it',
            'Whether to take a break from it',
          ],
        ),
      EducationStage.graduated => const IntakeQuestion(
          id: 'edu_decision',
          text: 'What are you trying to work out?',
          helper: 'Pick the main one.',
          options: [
            'Whether to study further',
            'Which programme or institution',
            'Whether to retrain in a different field',
            'Whether the cost and time are worth it',
            'Whether to go abroad for it',
          ],
        ),
      EducationStage.vocational ||
      EducationStage.selfTaught ||
      EducationStage.unknown =>
        const IntakeQuestion(
          id: 'edu_decision',
          text: 'What are you trying to work out?',
          helper: 'Pick the main one.',
          options: [
            'Whether a formal qualification would help',
            'Which programme or course to take',
            'Whether to retrain in a different field',
            'Whether the cost and time are worth it',
            'Whether to keep learning on my own',
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

    // Dropped for a decision that cannot involve moving. Uses the location from
    // onboarding rather than asking where they live.
    if (!_eduStayingPut.contains(decision))
      if (place != null)
        IntakeQuestion(
          id: 'edu_geography',
          text: 'Would this mean staying in $place, or leaving?',
          // Multi: the options on the table are often in different places.
          helper: 'Pick every place that is in the running.',
          kind: IntakeAnswerKind.multiChoice,
          options: [
            'Staying in $place',
            'Elsewhere in the same country',
            'Abroad',
            'I am open to anywhere',
            'Not sure yet',
          ],
          soloOptions: const ['I am open to anywhere', 'Not sure yet'],
        )
      else
        const IntakeQuestion(
          id: 'edu_geography',
          text: 'Would this mean moving?',
          helper: 'Pick every place that is in the running.',
          kind: IntakeAnswerKind.multiChoice,
          options: [
            'No, I would stay where I am',
            'Elsewhere in the same country',
            'Abroad',
            'I am open to anywhere',
            'Not sure yet',
          ],
          soloOptions: ['I am open to anywhere', 'Not sure yet'],
        ),

    // Multi-select: money and family and self-doubt are the usual answer, all
    // three at once, and making someone rank them threw two of them away.
    IntakeQuestion(
      id: 'edu_obstacle',
      text: 'What is actually in the way?',
      helper: 'Everything that applies.',
      kind: IntakeAnswerKind.multiChoice,
      options: [
        'The money',
        'My family expects something else',
        if (struggling) 'I am struggling with the course itself',
        if (struggling || decision == 'Whether to take a year out first')
          'I am burnt out',
        'I do not know what I would even enjoy',
        if (!_eduNoApplication.contains(decision)) 'I might not get in',
        'I am not sure it leads anywhere',
        _eduPause.contains(decision)
            ? 'I would fall behind'
            : 'The time it would take',
        'I have already started down another path',
        'Honestly, I am just scared of picking wrong',
      ],
    ),

    IntakeQuestion(
      id: 'edu_stage',
      text: 'Where are you with it?',
      options: [
        'Only just started thinking about it',
        // A "whether to" is already down to two; there is nothing to narrow.
        decision != null && decision.startsWith('Whether')
            ? 'Thought it through, still torn'
            : 'Narrowed it to a couple of options',
        'Leaning one way, but second-guessing',
        'Decided, and now doubting it',
      ],
    ),
  ];
}

// ---------------------------------------------------------------------------
// Financial
//
// Reads: living_situation, relationship_status, financial_context, age_range —
// together they decide whether the "who else does this affect" question is
// worth a screen and who is on it. Never asks for income: onboarding took a
// coarse read, and scale is asked relative to the user rather than in currency.
// Later questions read the decision: money going out and money coming back
// have different people and different fears attached.
// ---------------------------------------------------------------------------

const _finLoan = 'Taking on a loan or debt';
const _finSaving = 'Saving or investing';
const _finPurchase = 'A big purchase';
const _finEarning = 'Earning more — a raise, a switch, a side income';
const _finStretch = 'Making what I have stretch';
const _finGiving = 'Money I would be giving someone else';
const _finOwed = 'Money someone owes me';

const _finDecisions = [
  _finLoan,
  _finSaving,
  _finPurchase,
  _finEarning,
  _finStretch,
  _finGiving,
  _finOwed,
];

List<IntakeQuestion> _financial(
  UserProfile profile,
  Map<String, String?> answers,
) {
  final decision = answers['fin_decision'];
  // Nothing picked yet, or typed: could be anything, so nothing is hidden.
  final unknown = !_finDecisions.contains(decision);
  final involvesSomeone = decision == _finGiving || decision == _finOwed;

  return [
    const IntakeQuestion(
      id: 'fin_decision',
      text: 'What is the money decision about?',
      // Single, like every "what is the decision" question: a loan *for* a big
      // purchase is both, and the one that is actually hard is the one to pick.
      helper: 'Pick the main one.',
      options: _finDecisions,
    ),

    // Relative, not absolute. A number would be more precise and far less likely
    // to be given honestly — and "three months of what I live on" is the part
    // that actually grounds advice. Earning more and stretching are not a sum
    // being spent, so they are asked the question that fits them.
    switch (decision) {
      _finEarning => const IntakeQuestion(
          id: 'fin_scale',
          text: 'How much of a difference would it make?',
          helper: 'Measured against what you live on. No numbers needed.',
          options: [
            'A little breathing room',
            'A noticeable difference each month',
            'Enough to change how I live',
            'It is more about stability than the amount',
          ],
        ),
      _finStretch => const IntakeQuestion(
          id: 'fin_scale',
          text: 'Roughly how short are you?',
          helper: 'Measured against what you live on. No numbers needed.',
          options: [
            'A little — a few days of what I live on',
            'About a month',
            'Several months',
            'A year or more',
            'Not short, it just never feels like enough',
          ],
        ),
      _ => const IntakeQuestion(
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
    },

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
        // Worded as a kind of no-deadline, so it rules the others out the way
        // a single-select answer has to. "Within days, and it has been hanging
        // over me" was true and could not be said.
        'No set deadline, but it has been hanging over me',
      ],
    ),

    // Dropped for someone who lives alone, has no partner, and supports nobody
    // — unless the money is going to or coming from someone, who is then the
    // obvious answer.
    if (!decidesAlone(profile) || involvesSomeone)
      IntakeQuestion(
        id: 'fin_stakeholders',
        text: 'Who else does this land on?',
        helper: 'Everyone it touches.',
        kind: IntakeAnswerKind.multiChoice,
        options: [
          if (decision == _finGiving) 'The person I would give it to',
          if (decision == _finOwed) 'The person who owes it',
          ..._stakeholderOptions(profile),
        ],
        soloOptions: const ['Nobody but me'],
      ),

    IntakeQuestion(
      id: 'fin_blocker',
      text: 'What is making it hard to call?',
      helper: 'Everything that applies.',
      kind: IntakeAnswerKind.multiChoice,
      options: [
        'I do not know what my options are',
        if (unknown || decision == _finEarning)
          'I do not know what I could realistically ask for',
        if (decision != _finOwed)
          'I do not trust myself to get the numbers right',
        'The risk if it goes wrong',
        'Someone else is pushing me one way',
        // Each only where there is a person on the other end of the money.
        if (unknown || decision == _finGiving)
          'Saying no would cost me the relationship',
        if (unknown || decision == _finOwed)
          'Asking for it back could cost me the relationship',
        'I keep putting it off',
        'I already know the answer and do not like it',
      ],
    ),
  ];
}

/// Most-likely answer first, so the common case is the shortest reach. No
/// partner for someone single, the ex for someone separated, and no children
/// for someone under 18.
List<String> _stakeholderOptions(UserProfile profile) {
  final partner = switch (partnerStatusOf(profile)) {
    PartnerStatus.none => null,
    PartnerStatus.ended => 'My ex-partner',
    _ => 'My partner',
  };
  final children = isMinor(profile) ? null : 'My children';

  final ordered = switch (householdOf(profile)) {
    HouseholdShape.withFamily => [
        'My parents or family',
        partner,
        children,
        'Nobody but me',
      ],
    HouseholdShape.withPartner => [
        partner,
        children,
        'My parents or family',
        'Nobody but me',
      ],
    HouseholdShape.withFlatmates ||
    HouseholdShape.institutional ||
    HouseholdShape.alone ||
    HouseholdShape.unknown =>
      [
        'Nobody but me',
        partner,
        'My parents or family',
        children,
      ],
  };
  return [...ordered.whereType<String>(), 'Someone else'];
}

// ---------------------------------------------------------------------------
// Other
//
// The catch-all, so it leans on an open question early rather than guessing at a
// taxonomy. The three named categories are excluded from its option list —
// anyone who wanted those had a card for them on the dashboard — and anything
// else is the "Something else" box the screen adds to every choice question.
// ---------------------------------------------------------------------------

List<IntakeQuestion> _other(Map<String, String?> answers) {
  final shape = answers['oth_shape'];

  return [
    const IntakeQuestion(
      id: 'oth_area',
      text: 'What is this about?',
      helper: 'Pick all that apply. Education, money, and relationships have '
          'their own places — this is for everything else.',
      // Multi: "moving cities for a job" is work and where to live at once.
      kind: IntakeAnswerKind.multiChoice,
      options: [
        'Work or career',
        'Health',
        'Where to live',
        'A habit I want to change',
        'Something creative',
        'How I spend my time',
      ],
    ),

    const IntakeQuestion(
      id: 'oth_what',
      text: 'In your own words, what is the decision?',
      helper: 'A sentence is plenty — there is room to go deeper in a moment.',
      kind: IntakeAnswerKind.text,
      hint: 'e.g. whether to move cities for a job',
      icon: Icons.help_outline,
      maxLines: 3,
    ),

    const IntakeQuestion(
      id: 'oth_shape',
      text: 'What kind of decision is it?',
      helper: 'Pick the closest one.',
      options: [
        'Whether to start something',
        'Whether to stop something',
        'Choosing between options',
        'Whether to tell someone something',
        'How to handle something I cannot leave',
      ],
    ),

    const IntakeQuestion(
      id: 'oth_urgency',
      text: 'How soon do you have to decide?',
      options: [
        'Within days',
        'Within a month',
        'Within a few months',
        'There is no real deadline',
        // Worded as a kind of no-deadline, so it rules the others out the way
        // a single-select answer has to. "Within days, and it has been hanging
        // over me" was true and could not be said.
        'No set deadline, but it has been hanging over me',
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
        if (shape == 'Whether to tell someone something')
          'I do not know how they would react',
        'The money',
        // Starting something new does not mean the old thing was a mistake.
        if (shape != 'Whether to start something')
          'It would mean admitting I was wrong before',
        if (shape == 'How to handle something I cannot leave')
          'I feel stuck with no real way out',
        'I do not trust my own judgement on this',
        'I keep putting it off',
        'I already know the answer and do not like it',
      ],
    ),
  ];
}
