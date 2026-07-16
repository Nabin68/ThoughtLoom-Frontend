//onboarding_questions.dart

import 'package:flutter/material.dart';

import '../models/onboarding_question.dart';
import '../models/user_profile.dart';

/// The one-time basic profile: topic-agnostic facts that hold true no matter
/// which category a user later opens a chat in.
///
/// The bar for being in this list is that the answer is *durable* and *grounds
/// advice across all four categories*. "Where do you live" belongs — it changes
/// what a course, a salary, or a family conversation actually means. "What are
/// you deciding right now" does not: it belongs to a chat, is asked per
/// category, and is stale next week.
///
/// Wording is deliberately plain and non-clinical. This runs immediately after
/// registration, before the user has any reason to trust the app, and it reads
/// as an interrogation if the questions sound like a form.
///
/// Names are not asked: registration already captured one, and the sign-up
/// trigger has written it to `user_profiles.display_name` before this screen
/// ever renders.
///
/// Order matters. Easy and factual first (where, how old), identity and plans
/// in the middle, money and relationships last — by then the user has invested
/// eight screens and is likelier to answer the two that feel invasive, both of
/// which are optional anyway.
const List<OnboardingQuestion> onboardingQuestions = [
  // Free text, not a country list: "Pune, India" and "rural Kerala" and
  // "Berlin, but moving home in June" are all answers a picker would destroy,
  // and location is the single highest-leverage fact for grounding.
  OnboardingQuestion(
    id: 'location',
    text: 'Where are you based?',
    helper: 'City and country is plenty. It shapes what advice is realistic.',
    kind: OnboardingAnswerKind.text,
    hint: 'e.g. Pune, India',
    icon: Icons.place_outlined,
    column: ProfileColumn.location,
  ),

  // Ranges rather than a number: the point is life stage, and a range is both
  // less intrusive to give and less likely to be a lie.
  OnboardingQuestion(
    id: 'age_range',
    text: 'How old are you?',
    helper: 'A range is fine — it helps pitch advice at the right stage.',
    options: [
      'Under 18',
      '18–21',
      '22–25',
      '26–30',
      '31–40',
      '41–55',
      'Over 55',
    ],
    column: ProfileColumn.ageRange,
  ),

  OnboardingQuestion(
    id: 'education_level',
    text: 'How far have you got in your education?',
    helper: 'Wherever you are now — there is no right answer here.',
    options: [
      'Still in school',
      'Finished school',
      'Partway through an undergraduate degree',
      'Undergraduate degree finished',
      'Partway through a postgraduate degree',
      'Postgraduate degree finished',
      'Diploma or vocational training',
      'Mostly self-taught',
    ],
  ),

  OnboardingQuestion(
    id: 'field_of_study',
    text: 'What did you study, or what are you studying?',
    helper: 'Pick the closest one.',
    options: [
      'Engineering or technology',
      'Medicine or healthcare',
      'Business or commerce',
      'Science or research',
      'Arts or humanities',
      'Law',
      'Design or creative fields',
      'Education or social work',
      'Something else',
      'Not studied formally',
    ],
  ),

  // Mirrored to `occupation`. Phrased as "doing" rather than "job title"
  // because the honest answer for much of this audience is not a job.
  OnboardingQuestion(
    id: 'current_status',
    text: 'What are you doing at the moment?',
    helper: 'Whatever takes up most of your week.',
    options: [
      'Studying full-time',
      'Working a full-time job',
      'Working part-time or freelancing',
      'Running my own thing',
      'Preparing for exams or applications',
      'Looking for work',
      'Between things right now',
      'Taking a break or caring for family',
    ],
    column: ProfileColumn.occupation,
  ),

  OnboardingQuestion(
    id: 'next_plan',
    text: 'What are you hoping to do next?',
    helper: 'Your best guess. This is not a commitment.',
    options: [
      'Keep studying',
      'Find my first job',
      'Change career or field',
      'Go for higher studies',
      'Start something of my own',
      'Grow where I already am',
      'Not sure yet — that is partly why I am here',
    ],
  ),

  // Separates "someday" from "by March", which changes the shape of every
  // recommendation far more than the goal itself does.
  OnboardingQuestion(
    id: 'time_horizon',
    text: 'When would you like that to happen?',
    helper: 'Rough is fine.',
    options: [
      'Within 3 months',
      'In 3 to 6 months',
      'In 6 to 12 months',
      'In 1 to 2 years',
      'No fixed timeline',
    ],
  ),

  // Who a decision has to be cleared with, and who absorbs its cost. Grounds
  // the relationship category directly and quietly constrains the other three.
  OnboardingQuestion(
    id: 'living_situation',
    text: 'Who do you live with?',
    helper: 'Big decisions rarely affect only the person making them.',
    options: [
      'With my parents or family',
      'On my own',
      'With a partner or spouse',
      'With flatmates',
      'In a hostel or dorm',
    ],
  ),

  // Optional and late: the two questions below are the ones a stranger has the
  // least right to ask, so they are asked last and can be skipped outright.
  OnboardingQuestion(
    id: 'financial_context',
    text: 'How would you describe your money situation?',
    helper: 'Only so advice does not assume a budget you do not have.',
    options: [
      'Fully supported by family',
      'Partly supported by family',
      'I support myself',
      'I support myself and others',
    ],
    optional: true,
  ),

  OnboardingQuestion(
    id: 'relationship_status',
    text: 'Are you in a relationship?',
    options: [
      'Single',
      'Seeing someone',
      'In a long-term relationship',
      'Married',
      'Separated or divorced',
      'It is complicated',
    ],
    optional: true,
  ),

  // Not a fact about the user's life but about how to talk to them, and it
  // changes the form of every answer the app will ever give.
  OnboardingQuestion(
    id: 'decision_style',
    text: 'When a decision is hard, what usually helps you most?',
    options: [
      'Talking it through with someone',
      'Seeing the numbers and comparisons',
      'A clear step-by-step plan',
      'Hearing from someone who has done it',
      'Quiet time to think it over',
    ],
  ),

  // The catch-all. Everything above is a box; this is where the thing that
  // does not fit in one goes — a visa, an illness, a family business waiting.
  OnboardingQuestion(
    id: 'anything_else',
    text: 'Anything else worth knowing about your situation?',
    helper: 'Skip this if nothing comes to mind.',
    kind: OnboardingAnswerKind.text,
    hint: 'e.g. I am on a student visa and it expires next year',
    icon: Icons.edit_note_outlined,
    maxLines: 4,
    optional: true,
  ),
];

/// Where onboarding should resume.
///
/// Returns the index of the first question with no recorded answer, or
/// `onboardingQuestions.length` when every one has been answered.
///
/// Presence is what counts, not truthiness: a skipped optional question is
/// stored as an explicit null, so it is *answered* and resume moves past it.
/// That is why this reads [Map.containsKey] rather than testing the value.
int firstUnansweredIndex(Map<String, dynamic> answers) {
  for (var i = 0; i < onboardingQuestions.length; i++) {
    if (!answers.containsKey(onboardingQuestions[i].id)) return i;
  }
  return onboardingQuestions.length;
}

/// The stored answer for [id], or null if it was skipped or never asked.
String? onboardingAnswer(UserProfile profile, String id) {
  final value = profile.onboardingAnswers[id];
  return value is String && value.isNotEmpty ? value : null;
}

// ---------------------------------------------------------------------------
// Coarse reads of a finished profile
//
// The per-category intake branches on these instead of re-asking what
// onboarding already knows. They live here, next to the option strings they
// match, so rewording an option and updating the branch that depends on it are
// one edit rather than two files apart.
//
// The literals below are asserted against the real option lists by
// `onboarding_test.dart` — reword an option without touching these and the
// suite fails, rather than the branch silently switching itself off.
// ---------------------------------------------------------------------------

/// How far through formal education someone is.
enum EducationStage {
  /// School-age or school-finished, no higher qualification started.
  preDegree,

  /// Currently partway through a degree.
  midDegree,

  /// Holds a degree.
  graduated,
  vocational,
  selfTaught,

  /// Never answered — a profile from before the question existed.
  unknown,
}

EducationStage educationStageOf(UserProfile profile) =>
    switch (onboardingAnswer(profile, 'education_level')) {
      'Still in school' => EducationStage.preDegree,
      'Finished school' => EducationStage.preDegree,
      'Partway through an undergraduate degree' => EducationStage.midDegree,
      'Partway through a postgraduate degree' => EducationStage.midDegree,
      'Undergraduate degree finished' => EducationStage.graduated,
      'Postgraduate degree finished' => EducationStage.graduated,
      'Diploma or vocational training' => EducationStage.vocational,
      'Mostly self-taught' => EducationStage.selfTaught,
      _ => EducationStage.unknown,
    };

/// Whether there is a partner in the picture.
///
/// [unknown] is the common case, not an error: `relationship_status` is
/// optional in onboarding. A user who declined it is *not* re-asked in the
/// relationship intake — they get neutral wording instead. Declining once
/// should mean declined.
enum PartnerStatus { none, dating, committed, ended, unclear, unknown }

PartnerStatus partnerStatusOf(UserProfile profile) =>
    switch (onboardingAnswer(profile, 'relationship_status')) {
      'Single' => PartnerStatus.none,
      'Seeing someone' => PartnerStatus.dating,
      'In a long-term relationship' => PartnerStatus.committed,
      'Married' => PartnerStatus.committed,
      'Separated or divorced' => PartnerStatus.ended,
      'It is complicated' => PartnerStatus.unclear,
      _ => PartnerStatus.unknown,
    };

/// Who the user shares a roof with.
enum HouseholdShape { alone, withFamily, withPartner, withFlatmates, institutional, unknown }

HouseholdShape householdOf(UserProfile profile) =>
    switch (onboardingAnswer(profile, 'living_situation')) {
      'With my parents or family' => HouseholdShape.withFamily,
      'On my own' => HouseholdShape.alone,
      'With a partner or spouse' => HouseholdShape.withPartner,
      'With flatmates' => HouseholdShape.withFlatmates,
      'In a hostel or dorm' => HouseholdShape.institutional,
      _ => HouseholdShape.unknown,
    };

/// Whether someone else's money depends on this user's.
bool supportsOthers(UserProfile profile) =>
    onboardingAnswer(profile, 'financial_context') ==
    'I support myself and others';

/// True when a money decision plausibly lands on this user alone — nobody in
/// the household, no partner, nobody depending on their income. The financial
/// intake skips its "who else does this affect" question for these users
/// rather than asking a question the profile already answers.
bool decidesAlone(UserProfile profile) =>
    householdOf(profile) == HouseholdShape.alone &&
    partnerStatusOf(profile) == PartnerStatus.none &&
    !supportsOthers(profile);
