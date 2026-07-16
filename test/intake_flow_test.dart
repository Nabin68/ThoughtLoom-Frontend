import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:thoughtloom/data/intake_questions.dart';
import 'package:thoughtloom/data/onboarding_questions.dart';
import 'package:thoughtloom/main.dart';
import 'package:thoughtloom/models/chat.dart';
import 'package:thoughtloom/models/chat_category.dart';
import 'package:thoughtloom/models/intake_question.dart';
import 'package:thoughtloom/models/message.dart';
import 'package:thoughtloom/models/user_profile.dart';
import 'package:thoughtloom/screens/adaptive_flow_screen.dart';
import 'package:thoughtloom/screens/dashboard_screen.dart';
import 'package:thoughtloom/screens/describe_problem_screen.dart';
import 'package:thoughtloom/screens/history_screen.dart';
import 'package:thoughtloom/screens/intake_flow_screen.dart';
import 'package:thoughtloom/services/backend.dart';

/// Covers the dashboard and the per-category scripted opening: that picking a
/// category opens a real chat row, that every question and answer lands in
/// `messages` in order, and that the flow arrives at the Prompt 4 seam with all
/// of it persisted and queryable.
///
/// Runs on the on-device backend — no --dart-define credentials under test —
/// but only through [DataService], whose contract both implementations share.
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Backend.init();
  });

  // Default 800x600 viewport, matching the other suites: 'Inter' is not
  // bundled, so text measures wider under test than on a device.
  Future<void> pumpApp(WidgetTester tester) =>
      tester.pumpWidget(const ThoughtLoomApp());

  /// Registers, then writes a finished profile straight to the backend so the
  /// gate lands on the dashboard rather than making every test walk onboarding.
  Future<String> signInWithProfile(
    WidgetTester tester, {
    Map<String, dynamic> answers = const {},
    String? location,
  }) async {
    final result = await Backend.auth.signUp(
      email: 'ada@example.com',
      password: 'hunter2',
      displayName: 'Ada',
    );
    final userId = result.user.id;

    final profile = await Backend.data.ensureProfile(userId);
    await Backend.data.saveProfile(
      profile.copyWith(
        location: location,
        onboardingAnswers: {
          for (final q in onboardingQuestions) q.id: null,
          ...answers,
        },
        onboardingCompleted: true,
      ),
    );

    await pumpApp(tester);
    await tester.pumpAndSettle();
    return userId;
  }

  Future<void> tapCategory(WidgetTester tester, ChatCategory category) async {
    // ensureVisible first: the fourth card sits below the fold on the test
    // viewport, and tap on an off-screen target fails rather than scrolling.
    final card = find.text(category.label);
    await tester.ensureVisible(card);
    await tester.pumpAndSettle();
    await tester.tap(card);
    await tester.pumpAndSettle();
  }

  /// Taps a radio option.
  ///
  /// ensureVisible is not optional here. On the test viewport the option list
  /// runs under the fixed bottom button, and tap() only *warns* when its offset
  /// misses — it still dispatches, so the press lands on whatever is really
  /// there (the Next button) and the test silently does the wrong thing.
  Future<void> choose(WidgetTester tester, String option) async {
    final target = find.text(option);
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  /// Answers whatever question is on screen and advances. The last question's
  /// button reads Continue rather than Next.
  Future<void> answerCurrent(
    WidgetTester tester,
    IntakeQuestion q, {
    bool isLast = false,
  }) async {
    if (q.kind == IntakeAnswerKind.text) {
      await tester.enterText(find.byType(TextField).first, 'my answer');
      await tester.pumpAndSettle();
    } else {
      await choose(tester, q.options.first);
    }
    await tester.tap(find.text(isLast ? 'Continue' : 'Next'));
    await tester.pumpAndSettle();
  }

  /// Walks the whole scripted opening for [category] and returns its chat.
  Future<Chat> completeIntake(
    WidgetTester tester,
    String userId,
    ChatCategory category,
  ) async {
    await tapCategory(tester, category);
    final profile = (await Backend.data.fetchProfile(userId))!;
    final questions = questionsFor(category, profile);

    for (var i = 0; i < questions.length; i++) {
      await answerCurrent(tester, questions[i],
          isLast: i == questions.length - 1);
    }
    return (await Backend.data.fetchChats(userId)).single;
  }

  group('dashboard', () {
    testWidgets('shows all four categories and a way into history',
        (tester) async {
      await signInWithProfile(tester);

      expect(find.byType(DashboardScreen), findsOneWidget);
      for (final category in ChatCategory.values) {
        expect(find.text(category.label), findsOneWidget);
      }
      expect(find.text('Past'), findsOneWidget);
      expect(find.text('Hello, Ada'), findsOneWidget);
    });

    testWidgets('picking a category opens an in-progress chat row for it',
        (tester) async {
      final userId = await signInWithProfile(tester);

      await tapCategory(tester, ChatCategory.financial);

      final chats = await Backend.data.fetchChats(userId);
      expect(chats, hasLength(1));
      expect(chats.single.category, ChatCategory.financial);
      expect(chats.single.status, ChatStatus.inProgress);
      expect(chats.single.userId, userId);
      expect(find.byType(IntakeFlowScreen), findsOneWidget);
    });

    testWidgets('the history button opens history', (tester) async {
      await signInWithProfile(tester);

      await tester.tap(find.text('Past'));
      await tester.pumpAndSettle();

      expect(find.byType(HistoryScreen), findsOneWidget);
      expect(find.text('Nothing here yet'), findsOneWidget);
    });

    testWidgets('a started chat shows up in history as unfinished',
        (tester) async {
      await signInWithProfile(tester);
      await tapCategory(tester, ChatCategory.education);

      // Back out of the flow without answering anything. Abandoning must not
      // lose the chat — it is the user's, and Prompt 6 resumes it.
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.byType(DashboardScreen), findsOneWidget);

      await tester.tap(find.text('Past'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Unfinished'), findsOneWidget);
    });

    testWidgets('stepping back and changing an answer rewrites its row, '
        'rather than adding a second', (tester) async {
      final userId = await signInWithProfile(tester);
      await tapCategory(tester, ChatCategory.other);

      final chat = (await Backend.data.fetchChats(userId)).single;
      final profile = (await Backend.data.fetchProfile(userId))!;
      final questions = questionsFor(ChatCategory.other, profile);
      final first = questions.first;

      await answerCurrent(tester, first);
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      // The earlier answer is still selected, not lost.
      expect(find.text(first.text), findsOneWidget);

      // Change it and go forward again.
      await choose(tester, first.options[1]);
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      final messages = await Backend.data.fetchMessages(chat.id);
      expect(messages, hasLength(1));
      expect(messages.single.answerText, first.options[1]);
      expect(messages.single.seq, 1);
    });
  });

  group('intake persistence', () {
    testWidgets('every question and answer lands in messages, in order',
        (tester) async {
      final userId = await signInWithProfile(tester);
      await tapCategory(tester, ChatCategory.other);

      final chat = (await Backend.data.fetchChats(userId)).single;
      final profile = (await Backend.data.fetchProfile(userId))!;
      final questions = questionsFor(ChatCategory.other, profile);

      for (var i = 0; i < questions.length; i++) {
        expect(find.text(questions[i].text), findsOneWidget, reason: questions[i].id);
        await answerCurrent(tester, questions[i],
            isLast: i == questions.length - 1);
      }

      final messages = await Backend.data.fetchMessages(chat.id);
      expect(messages, hasLength(questions.length));

      for (var i = 0; i < questions.length; i++) {
        final message = messages[i];
        expect(message.type, MessageType.intake, reason: questions[i].id);
        // seq is 1-based and gapless, which is what makes "in order" mean
        // anything to the prompt that reads this back.
        expect(message.seq, i + 1);
        expect(message.questionText, questions[i].text);
        expect(message.answerText, isNotNull);
        expect(message.metadata['question_id'], questions[i].id);
      }
    });

    testWidgets('a choice question records the options it offered',
        (tester) async {
      final userId = await signInWithProfile(tester);
      await tapCategory(tester, ChatCategory.other);

      final chat = (await Backend.data.fetchChats(userId)).single;
      final profile = (await Backend.data.fetchProfile(userId))!;
      final first = questionsFor(ChatCategory.other, profile).first;

      await answerCurrent(tester, first);

      final message = (await Backend.data.fetchMessages(chat.id)).first;
      expect(message.answerText, first.options.first);
      // The option list travels with the answer, so a later reword of the
      // question set cannot make an old transcript unreadable.
      expect(message.metadata['options'], first.options);
    });

    testWidgets('Next is disabled until the question is answered',
        (tester) async {
      await signInWithProfile(tester);
      await tapCategory(tester, ChatCategory.education);

      final button = tester.widget<ElevatedButton>(
        find.ancestor(
          of: find.text('Next'),
          matching: find.byType(ElevatedButton),
        ),
      );
      expect(button.onPressed, isNull);
    });
  });

  group('describe your problem', () {
    testWidgets('the scripted questions end on the describe screen',
        (tester) async {
      final userId = await signInWithProfile(tester);
      await completeIntake(tester, userId, ChatCategory.relationship);

      expect(find.byType(DescribeProblemScreen), findsOneWidget);
      expect(find.text('So — what is going on?'), findsOneWidget);
    });

    testWidgets('the description is saved as a free-text message',
        (tester) async {
      final userId = await signInWithProfile(tester);
      final chat = await completeIntake(tester, userId, ChatCategory.education);

      await tester.enterText(
        find.byType(TextField).first,
        'I cannot tell if I am running towards something or away from it.',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      final messages = await Backend.data.fetchMessages(chat.id);
      final free = messages.last;
      expect(free.type, MessageType.freeText);
      expect(
        free.answerText,
        'I cannot tell if I am running towards something or away from it.',
      );
      // Typed, because dictation is unavailable under test — there is no
      // recogniser behind the platform channel.
      expect(free.metadata['input_method'], 'typed');
      // It comes last, after every intake row.
      expect(free.seq, messages.length);
    });

    testWidgets('the mic is hidden when dictation is unavailable',
        (tester) async {
      final userId = await signInWithProfile(tester);
      await completeIntake(tester, userId, ChatCategory.other);

      // PluginSpeechService.initialize() swallows the MissingPluginException
      // and reports false, so the button is never offered rather than offered
      // and broken.
      expect(find.text('Or say it out loud'), findsNothing);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('Continue is disabled until something is written',
        (tester) async {
      final userId = await signInWithProfile(tester);
      await completeIntake(tester, userId, ChatCategory.other);

      ElevatedButton button() => tester.widget<ElevatedButton>(
            find.ancestor(
              of: find.text('Continue'),
              matching: find.byType(ElevatedButton),
            ),
          );
      expect(button().onPressed, isNull);

      await tester.enterText(find.byType(TextField).first, '   ');
      await tester.pumpAndSettle();
      expect(button().onPressed, isNull);

      await tester.enterText(find.byType(TextField).first, 'here is the thing');
      await tester.pumpAndSettle();
      expect(button().onPressed, isNotNull);
    });

    testWidgets('the scripted flow hands off to the adaptive one with '
        'everything persisted', (tester) async {
      final userId = await signInWithProfile(tester);
      final chat = await completeIntake(tester, userId, ChatCategory.financial);

      await tester.enterText(find.byType(TextField).first, 'the whole story');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.byType(AdaptiveFlowScreen), findsOneWidget);

      // What the adaptive endpoint reads to build its first question. If this
      // holds, the handoff holds.
      final messages = await Backend.data.fetchMessages(chat.id);
      final profile = (await Backend.data.fetchProfile(userId))!;
      expect(messages.where((m) => m.type == MessageType.intake), isNotEmpty);
      expect(messages.where((m) => m.type == MessageType.freeText), hasLength(1));
      expect(messages.map((m) => m.seq), List.generate(messages.length, (i) => i + 1));
      expect(profile.onboardingCompleted, isTrue);
    });
  });

  group('questions read the profile instead of re-asking', () {
    UserProfile profileWith(Map<String, dynamic> answers, {String? location}) =>
        UserProfile.empty('u').copyWith(
          location: location,
          onboardingAnswers: answers,
        );

    test('no category re-asks anything onboarding already captured', () {
      // The guarantee this whole design exists for. If an intake question ever
      // duplicates an onboarding question's text, this fails.
      final onboardingText =
          onboardingQuestions.map((q) => q.text.toLowerCase()).toSet();
      final profile = profileWith(const {});

      for (final category in ChatCategory.values) {
        for (final q in questionsFor(category, profile)) {
          expect(
            onboardingText.contains(q.text.toLowerCase()),
            isFalse,
            reason: '${category.label}/${q.id} re-asks an onboarding question',
          );
        }
      }
    });

    test('education is worded for where the user actually is', () {
      final student = profileWith(const {
        'education_level': 'Partway through an undergraduate degree',
      });
      final graduate = profileWith(const {
        'education_level': 'Postgraduate degree finished',
      });

      String decisionText(UserProfile p) => questionsFor(ChatCategory.education, p)
          .firstWhere((q) => q.id == 'edu_decision')
          .text;

      expect(decisionText(student), contains('course'));
      expect(decisionText(graduate), isNot(contains('course')));

      // A graduate is not offered "which entrance exams"; a mid-degree student
      // is not offered "whether to retrain".
      List<String> options(UserProfile p) =>
          questionsFor(ChatCategory.education, p)
              .firstWhere((q) => q.id == 'edu_decision')
              .options;
      expect(options(student), contains('Whether to stay on it'));
      expect(options(graduate), contains('Whether to study further'));
    });

    test('education uses the location from onboarding rather than asking it',
        () {
      final located = profileWith(const {}, location: 'Pune, India');
      final geography = questionsFor(ChatCategory.education, located)
          .firstWhere((q) => q.id == 'edu_geography');

      expect(geography.text, contains('Pune, India'));
      expect(geography.options, contains('Staying in Pune, India'));

      // And degrades to a neutral wording when the profile has no location.
      final unlocated = questionsFor(ChatCategory.education, profileWith(const {}))
          .firstWhere((q) => q.id == 'edu_geography');
      expect(unlocated.text, 'Would this mean moving?');
    });

    test('financial skips the stakeholder question for someone deciding alone',
        () {
      final alone = profileWith(const {
        'living_situation': 'On my own',
        'relationship_status': 'Single',
        'financial_context': 'I support myself',
      });
      final withFamily = profileWith(const {
        'living_situation': 'With my parents or family',
        'relationship_status': 'Single',
        'financial_context': 'Partly supported by family',
      });

      bool asksStakeholders(UserProfile p) => questionsFor(ChatCategory.financial, p)
          .any((q) => q.id == 'fin_stakeholders');

      expect(asksStakeholders(alone), isFalse);
      expect(asksStakeholders(withFamily), isTrue);

      // And the options lead with the household the profile describes.
      final options = questionsFor(ChatCategory.financial, withFamily)
          .firstWhere((q) => q.id == 'fin_stakeholders')
          .options;
      expect(options.first, 'My parents or family');
    });

    test('relationship wording follows the status, and never re-asks it', () {
      List<String> whoOptions(String? status) => questionsFor(
            ChatCategory.relationship,
            profileWith({if (status != null) 'relationship_status': status}),
          ).firstWhere((q) => q.id == 'rel_who').options;

      expect(whoOptions('Married').first, 'My partner');
      expect(whoOptions('Seeing someone').first, 'Someone I am seeing');
      expect(whoOptions('Separated or divorced').first, 'My ex');

      // Declined in onboarding: neutral wording, and no second attempt at
      // asking what they chose not to say.
      expect(whoOptions(null).first, 'My partner, or someone I am seeing');
      final questions = questionsFor(
        ChatCategory.relationship,
        profileWith(const {}),
      );
      expect(
        questions.any((q) => q.text.toLowerCase().contains('are you in a relationship')),
        isFalse,
      );
    });
  });

  group('question sets', () {
    final profile = UserProfile.empty('u');

    test('every category is a handful of questions, never a form', () {
      for (final category in ChatCategory.values) {
        final count = questionsFor(category, profile).length;
        expect(count, inInclusiveRange(3, 6), reason: category.label);
      }
    });

    test('ids are unique within a category', () {
      for (final category in ChatCategory.values) {
        final questions = questionsFor(category, profile);
        final ids = questions.map((q) => q.id).toSet();
        expect(ids.length, questions.length, reason: category.label);
      }
    });

    test('every choice question offers options', () {
      for (final category in ChatCategory.values) {
        for (final q in questionsFor(category, profile)) {
          if (q.kind == IntakeAnswerKind.choice) {
            expect(q.options, isNotEmpty, reason: '${category.label}/${q.id}');
          }
        }
      }
    });

    test('every category offers a way out of its fixed options', () {
      // A scripted MCQ that cannot express the user's actual situation is a
      // trap. Every category needs either an open text question or an escape
      // hatch option.
      for (final category in ChatCategory.values) {
        final questions = questionsFor(category, profile);
        final hasText =
            questions.any((q) => q.kind == IntakeAnswerKind.text);
        final hasEscape = questions.any((q) => q.options.any(
              (o) => o.toLowerCase().startsWith('something else'),
            ));
        expect(hasText || hasEscape, isTrue, reason: category.label);
      }
    });
  });
}
