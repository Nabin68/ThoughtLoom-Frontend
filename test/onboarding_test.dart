import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:thoughtloom/data/onboarding_questions.dart';
import 'package:thoughtloom/main.dart';
import 'package:thoughtloom/models/onboarding_question.dart';
import 'package:thoughtloom/models/user_profile.dart';
import 'package:thoughtloom/screens/dashboard_screen.dart';
import 'package:thoughtloom/screens/onboarding_screen.dart';
import 'package:thoughtloom/services/backend.dart';

/// Covers the one-time basic profile: that answers land in the database as the
/// user goes rather than at the end, that an interrupted run resumes, and that
/// a finished profile is never asked again.
///
/// Runs on the on-device backend — no --dart-define credentials under test — but
/// only through [DataService], whose contract both implementations share.
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Backend.init();
  });

  // Left on the default 800x600 viewport, matching widget_test.dart: 'Inter' is
  // not bundled, so text measures far wider under test than on a device and a
  // realistic phone size reports overflows no user can hit.
  Future<void> pumpApp(WidgetTester tester) =>
      tester.pumpWidget(const ThoughtLoomApp());

  /// A cold launch. Tearing the tree down first matters: pumping another
  /// ThoughtLoomApp over the old one updates the element tree in place and
  /// preserves State, so AuthGate would never re-read the profile.
  Future<void> restartApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await Backend.init();
    await pumpApp(tester);
    await tester.pumpAndSettle();
  }

  /// Registers a fresh account, which lands on the first onboarding question.
  Future<String> register(WidgetTester tester) async {
    await pumpApp(tester);
    await tester.pumpAndSettle(const Duration(seconds: 1));
    await tester.tap(find.text('Start Thinking Clearly'));
    await tester.pumpAndSettle();

    // Fields in order: name, email, password, confirm.
    await tester.enterText(find.byType(TextFormField).at(0), 'Ada');
    await tester.enterText(find.byType(TextFormField).at(1), 'ada@example.com');
    await tester.enterText(find.byType(TextFormField).at(2), 'hunter2');
    await tester.enterText(find.byType(TextFormField).at(3), 'hunter2');

    final button = find.text('Create Account');
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();

    return Backend.auth.currentUser!.id;
  }

  Future<void> tapContinue(WidgetTester tester) async {
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
  }

  Future<void> choose(WidgetTester tester, String option) async {
    final target = find.text(option);
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Future<void> typeAnswer(WidgetTester tester, String value) async {
    await tester.enterText(find.byType(TextFormField), value);
    await tester.pumpAndSettle();
  }

  testWidgets('A new registration is asked the basic profile', (tester) async {
    await register(tester);

    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(find.text(onboardingQuestions.first.text), findsOneWidget);
    expect(find.text('Step 1 of ${onboardingQuestions.length}'), findsOneWidget);
  });

  testWidgets('Each answer is saved as the user goes, not at the end',
      (tester) async {
    final userId = await register(tester);

    await typeAnswer(tester, 'Pune, India');
    await tapContinue(tester);

    // In the database already, one question in — the whole point of writing
    // incrementally is that a connection dropped here costs nothing.
    final profile = (await Backend.data.fetchProfile(userId))!;
    expect(profile.onboardingAnswers['location'], 'Pune, India');
    expect(profile.onboardingCompleted, isFalse);
  });

  testWidgets('A promoted answer is mirrored into its own column',
      (tester) async {
    final userId = await register(tester);

    await typeAnswer(tester, 'Pune, India');
    await tapContinue(tester);
    await choose(tester, '22–25');
    await tapContinue(tester);

    // location and age_range are columns as well as blob keys; later queries
    // filter on the columns.
    final profile = (await Backend.data.fetchProfile(userId))!;
    expect(profile.location, 'Pune, India');
    expect(profile.ageRange, '22–25');
    expect(profile.onboardingAnswers['age_range'], '22–25');
  });

  testWidgets('Continue is disabled until the question is answered',
      (tester) async {
    await register(tester);

    ElevatedButton button() => tester.widget<ElevatedButton>(
          find.ancestor(
            of: find.text('Continue'),
            matching: find.byType(ElevatedButton),
          ),
        );

    expect(button().onPressed, isNull);

    // Whitespace is not an answer.
    await typeAnswer(tester, '   ');
    expect(button().onPressed, isNull);

    await typeAnswer(tester, 'Pune, India');
    expect(button().onPressed, isNotNull);
  });

  testWidgets('An interrupted run resumes at the first unanswered question',
      (tester) async {
    final userId = await register(tester);

    await typeAnswer(tester, 'Pune, India');
    await tapContinue(tester);
    await choose(tester, '22–25');
    await tapContinue(tester);

    // The app dies here, on question three.
    await restartApp(tester);

    expect(find.text(onboardingQuestions[2].text), findsOneWidget);
    expect(find.text('Step 3 of ${onboardingQuestions.length}'), findsOneWidget);
    // Not back at the start, and not asking for what it already knows.
    expect(find.text(onboardingQuestions.first.text), findsNothing);
    expect((await Backend.data.fetchProfile(userId))!.location, 'Pune, India');
  });

  testWidgets('Stepping back shows the answer already given', (tester) async {
    await register(tester);

    await typeAnswer(tester, 'Pune, India');
    await tapContinue(tester);
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    expect(find.text(onboardingQuestions.first.text), findsOneWidget);
    expect(find.text('Pune, India'), findsOneWidget);
  });

  testWidgets('Skipping an optional question records the skip and moves past it',
      (tester) async {
    final userId = await register(tester);

    final optional = onboardingQuestions.firstWhere((q) => q.optional);
    final upto = onboardingQuestions.indexOf(optional);

    // Walk to it honestly, so resume is exercised against real answers.
    for (var i = 0; i < upto; i++) {
      final q = onboardingQuestions[i];
      if (q.kind == OnboardingAnswerKind.text) {
        await typeAnswer(tester, 'something');
      } else {
        await choose(tester, q.options.first);
      }
      await tapContinue(tester);
    }

    expect(find.text(optional.text), findsOneWidget);
    await tester.tap(find.text('Skip this one'));
    await tester.pumpAndSettle();

    // Stored as an explicit null rather than left absent — that is what stops
    // resume sending the user back to a question they declined.
    final answers = (await Backend.data.fetchProfile(userId))!.onboardingAnswers;
    expect(answers.containsKey(optional.id), isTrue);
    expect(answers[optional.id], isNull);
    expect(firstUnansweredIndex(answers), greaterThan(upto));

    await restartApp(tester);
    expect(find.text(optional.text), findsNothing);
  });

  testWidgets('Finishing the last question lands on the dashboard',
      (tester) async {
    final userId = await register(tester);

    for (final q in onboardingQuestions) {
      if (q.kind == OnboardingAnswerKind.text) {
        await typeAnswer(tester, 'Pune, India');
      } else {
        await choose(tester, q.options.first);
      }
      await tester.tap(find.text(q == onboardingQuestions.last ? 'Finish' : 'Continue'));
      await tester.pumpAndSettle();
    }

    expect(find.byType(DashboardScreen), findsOneWidget);
    expect(find.byType(OnboardingScreen), findsNothing);
    expect((await Backend.data.fetchProfile(userId))!.onboardingCompleted, isTrue);
  });

  testWidgets('A finished profile is never asked again', (tester) async {
    final userId = await register(tester);

    // Signing in again with everything already answered must go straight
    // through, which is the whole "asked once, never again" promise.
    final profile = await Backend.data.ensureProfile(userId);
    await Backend.data.saveProfile(
      profile.copyWith(
        onboardingAnswers: {
          for (final q in onboardingQuestions) q.id: 'whatever',
        },
        onboardingCompleted: true,
      ),
    );

    await restartApp(tester);

    expect(find.byType(DashboardScreen), findsOneWidget);
    expect(find.byType(OnboardingScreen), findsNothing);
    expect(find.text('Hello, Ada'), findsOneWidget);
  });

  group('firstUnansweredIndex', () {
    test('an empty profile starts at the beginning', () {
      expect(firstUnansweredIndex(const {}), 0);
    });

    test('a fully answered profile reports past the end', () {
      final answers = <String, dynamic>{
        for (final q in onboardingQuestions) q.id: 'x',
      };
      expect(firstUnansweredIndex(answers), onboardingQuestions.length);
    });

    test('a skipped question counts as answered', () {
      // Presence, not truthiness. A null here means "asked and declined"; a
      // missing key means "never asked".
      final answers = <String, dynamic>{onboardingQuestions.first.id: null};
      expect(firstUnansweredIndex(answers), 1);
    });

    test('a gap resumes at the gap, not after the last answer', () {
      final answers = <String, dynamic>{
        onboardingQuestions[0].id: 'x',
        onboardingQuestions[2].id: 'x',
      };
      expect(firstUnansweredIndex(answers), 1);
    });
  });

  group('question set', () {
    test('ids are unique', () {
      // Two questions sharing an id would silently overwrite each other's
      // answer and break resume.
      final ids = onboardingQuestions.map((q) => q.id).toSet();
      expect(ids.length, onboardingQuestions.length);
    });

    test('every choice question offers options', () {
      for (final q in onboardingQuestions) {
        if (q.kind == OnboardingAnswerKind.choice) {
          expect(q.options, isNotEmpty, reason: '${q.id} has no options');
        }
      }
    });

    test('each promoted column is claimed by exactly one question', () {
      for (final column in ProfileColumn.values) {
        final claimants =
            onboardingQuestions.where((q) => q.column == column).toList();
        expect(claimants.length, 1, reason: '$column');
      }
    });
  });

  group('profile classifiers stay in step with the options', () {
    // The per-category intake branches on these reads instead of re-asking
    // what onboarding knows. They match answer strings literally, so an option
    // reworded without updating the classifier would quietly stop matching and
    // the branch would switch itself off — with nothing failing to say so.
    //
    // These are that alarm: every real option must classify to something. Only
    // an absent answer is allowed to be `unknown`.

    UserProfile answering(String id, String? answer) => UserProfile.empty('u')
        .copyWith(onboardingAnswers: {if (answer != null) id: answer});

    List<String> optionsOf(String id) =>
        onboardingQuestions.firstWhere((q) => q.id == id).options;

    test('every education_level option maps to a stage', () {
      for (final option in optionsOf('education_level')) {
        expect(
          educationStageOf(answering('education_level', option)),
          isNot(EducationStage.unknown),
          reason: '"$option" no longer maps to a stage',
        );
      }
      expect(
        educationStageOf(answering('education_level', null)),
        EducationStage.unknown,
      );
    });

    test('every relationship_status option maps to a partner status', () {
      for (final option in optionsOf('relationship_status')) {
        expect(
          partnerStatusOf(answering('relationship_status', option)),
          isNot(PartnerStatus.unknown),
          reason: '"$option" no longer maps to a partner status',
        );
      }
      // Optional in onboarding, so declining it is the ordinary case rather
      // than an error — and it must read as unknown, not as "single".
      expect(
        partnerStatusOf(answering('relationship_status', null)),
        PartnerStatus.unknown,
      );
    });

    test('every living_situation option maps to a household', () {
      for (final option in optionsOf('living_situation')) {
        expect(
          householdOf(answering('living_situation', option)),
          isNot(HouseholdShape.unknown),
          reason: '"$option" no longer maps to a household',
        );
      }
    });

    test('the string supportsOthers matches is a real financial_context option',
        () {
      expect(optionsOf('financial_context'), contains('I support myself and others'));
      expect(
        supportsOthers(answering('financial_context', 'I support myself and others')),
        isTrue,
      );
      expect(
        supportsOthers(answering('financial_context', 'I support myself')),
        isFalse,
      );
    });

    test('decidesAlone needs every condition, not just one', () {
      UserProfile profile({
        required String living,
        required String relationship,
        required String money,
      }) =>
          UserProfile.empty('u').copyWith(onboardingAnswers: {
            'living_situation': living,
            'relationship_status': relationship,
            'financial_context': money,
          });

      expect(
        decidesAlone(profile(
          living: 'On my own',
          relationship: 'Single',
          money: 'I support myself',
        )),
        isTrue,
      );
      // Any one of them being false is enough that someone else is in the room.
      expect(
        decidesAlone(profile(
          living: 'With my parents or family',
          relationship: 'Single',
          money: 'I support myself',
        )),
        isFalse,
      );
      expect(
        decidesAlone(profile(
          living: 'On my own',
          relationship: 'Married',
          money: 'I support myself',
        )),
        isFalse,
      );
      expect(
        decidesAlone(profile(
          living: 'On my own',
          relationship: 'Single',
          money: 'I support myself and others',
        )),
        isFalse,
      );
      // A profile that skipped the optional questions is not assumed alone.
      expect(decidesAlone(UserProfile.empty('u')), isFalse);
    });
  });
}
