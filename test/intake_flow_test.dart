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
import 'package:thoughtloom/widgets/app_button.dart';

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

  /// Answers whatever question is on screen and advances, returning what it
  /// answered. The last question's button reads Continue rather than Next.
  ///
  /// The answer comes back because the caller needs it: the question list is a
  /// function of the answers so far, so walking the flow means feeding each one
  /// back in to find out what is asked next.
  Future<String> answerCurrent(
    WidgetTester tester,
    IntakeQuestion q, {
    bool isLast = false,
  }) async {
    final String answer;
    if (q.kind == IntakeAnswerKind.text) {
      answer = 'my answer';
      await tester.enterText(find.byType(TextField).first, answer);
      await tester.pumpAndSettle();
    } else {
      // One option, even on a multi-select: a single tick is a valid answer and
      // is the shortest way through a flow this helper only exists to get past.
      answer = q.options.first;
      await choose(tester, answer);
    }
    await tester.tap(find.text(isLast ? 'Continue' : 'Next'));
    await tester.pumpAndSettle();
    return answer;
  }

  /// Walks the whole scripted opening for [category] and returns its chat.
  Future<Chat> completeIntake(
    WidgetTester tester,
    String userId,
    ChatCategory category,
  ) async {
    await tapCategory(tester, category);
    final profile = (await Backend.data.fetchProfile(userId))!;

    // Rebuilt after every answer, exactly as the screen does it. A list computed
    // once up front stops matching what is on screen the moment the
    // relationship set learns who the chat is about — it rewords everything
    // after `rel_who` around that person — and this helper would then tap for an
    // option that is no longer offered.
    final answers = <String, String?>{};
    var questions = questionsFor(category, profile, answers);
    var i = 0;
    while (i < questions.length) {
      final question = questions[i];
      final answer = await answerCurrent(
        tester,
        question,
        isLast: i == questions.length - 1,
      );
      answers[question.id] = answer;
      questions = questionsFor(category, profile, answers);
      i++;
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
      // The way into history is a labelled icon in the header now rather than
      // a "Past" pill competing with the four topics for the eye.
      expect(find.byTooltip('Your past chats'), findsOneWidget);
      expect(find.byTooltip('Profile and sign out'), findsOneWidget);
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

      await tester.tap(find.byTooltip('Your past chats'));
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
      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pumpAndSettle();
      expect(find.byType(DashboardScreen), findsOneWidget);

      await tester.tap(find.byTooltip('Your past chats'));
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
      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
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

    testWidgets('a multi-select question keeps every answer, not the last tap',
        (tester) async {
      final userId = await signInWithProfile(
        tester,
        answers: const {
          'gender': 'Man',
          'relationship_status': 'In a long-term relationship',
        },
      );
      await tapCategory(tester, ChatCategory.relationship);

      // Question one names the person, which is what the rest are worded around.
      await choose(tester, 'My girlfriend');
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      // Question two is the one that was never one thing.
      await choose(tester, 'I do not feel valued');
      await choose(tester, "She doesn't give me time");
      await choose(tester, 'We fight about the same thing every time');

      // Ticking is a toggle, so a mis-tap is undoable rather than final.
      await choose(tester, 'We fight about the same thing every time');

      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      final chat = (await Backend.data.fetchChats(userId)).single;
      final answer = (await Backend.data.fetchMessages(chat.id))
          .firstWhere((m) => m.metadata['question_id'] == 'rel_whats_wrong');

      // Joined in *option* order rather than tap order, so two people who ticked
      // the same things produce the same string — the transcript is read by a
      // model, and "A; C" versus "C; A" being different answers to one question
      // is noise it does not need.
      expect(
        answer.answerText,
        "She doesn't give me time${selectionSeparator}I do not feel valued",
      );
      expect(answer.metadata['multi'], isTrue);
      expect(answer.metadata['selected'], [
        "She doesn't give me time",
        'I do not feel valued',
      ]);
    });

    testWidgets('changing who the chat is about drops the answers about '
        'someone else', (tester) async {
      // The relationship set words everything after the first question around
      // the person it named. Going back and naming a different person does not
      // just re-word what is ahead — it invalidates rows already written, which
      // are answers to questions that were never asked of this chat. The model
      // reads the transcript as a record of what this person said, so a stale
      // row is wrong rather than merely untidy.
      final userId = await signInWithProfile(
        tester,
        answers: const {
          'gender': 'Man',
          'relationship_status': 'In a long-term relationship',
        },
      );
      await tapCategory(tester, ChatCategory.relationship);

      await choose(tester, 'My girlfriend');
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      await choose(tester, "She doesn't give me time");
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      final chat = (await Backend.data.fetchChats(userId)).single;
      expect(
        (await Backend.data.fetchMessages(chat.id)),
        hasLength(2),
        reason: 'rel_who and rel_whats_wrong are both written by now',
      );

      // Back to the first question, and it is about someone else entirely.
      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pumpAndSettle();
      await choose(tester, 'My parents or family');
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      final after = await Backend.data.fetchMessages(chat.id);
      expect(after, hasLength(1), reason: 'the girlfriend answer is gone');
      expect(after.single.metadata['question_id'], 'rel_who');
      expect(after.single.answerText, 'My parents or family');

      // And the question now on screen is about them, not her.
      expect(
        find.text('What is actually going on with your family?'),
        findsOneWidget,
      );
    });

    testWidgets('Next is disabled until the question is answered',
        (tester) async {
      await signInWithProfile(tester);
      await tapCategory(tester, ChatCategory.education);

      final button =
          tester.widget<AppButton>(find.widgetWithText(AppButton, 'Next'));
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

      AppButton button() =>
          tester.widget<AppButton>(find.widgetWithText(AppButton, 'Continue'));
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

    test('who a relationship chat is about is offered in the user\'s own terms',
        () {
      List<String> whoOptions({String? status, String? gender}) => questionsFor(
            ChatCategory.relationship,
            profileWith({
              if (status != null) 'relationship_status': status,
              if (gender != null) 'gender': gender,
            }),
          ).firstWhere((q) => q.id == 'rel_who').options;

      // The entire reason gender is asked. "Who is this about? Someone I am
      // close to" is a question nobody has ever asked themselves.
      expect(
        whoOptions(status: 'In a long-term relationship', gender: 'Man').first,
        'My girlfriend',
      );
      expect(
        whoOptions(status: 'In a long-term relationship', gender: 'Woman').first,
        'My boyfriend',
      );
      expect(whoOptions(status: 'Married', gender: 'Man').first, 'My wife');
      expect(whoOptions(status: 'Married', gender: 'Woman').first, 'My husband');

      // Offered first, never assumed: the alternative is on the same screen and
      // one tap away, so nobody is told what their relationship is.
      expect(
        whoOptions(status: 'In a long-term relationship', gender: 'Man'),
        contains('My boyfriend'),
      );

      // Declined, or a profile written before the question existed. Neutral
      // wording, and no second attempt at asking what they chose not to say.
      expect(
        whoOptions(
          status: 'In a long-term relationship',
          gender: 'Prefer not to say',
        ).first,
        'My partner',
      );
      expect(whoOptions(status: 'In a long-term relationship').first,
          'My partner');
      expect(whoOptions(status: 'Separated or divorced', gender: 'Man').first,
          'My ex-girlfriend');
      expect(whoOptions(status: 'Separated or divorced').first, 'My ex');

      // Neither onboarding question is ever asked again.
      final questions =
          questionsFor(ChatCategory.relationship, profileWith(const {}));
      final texts = questions.map((q) => q.text.toLowerCase());
      expect(texts.any((t) => t.contains('are you in a relationship')), isFalse);
      expect(texts.any((t) => t.contains('how do you describe yourself')),
          isFalse);
    });

    test('the questions after the first are about the person it named', () {
      List<IntakeQuestion> about(String who) => questionsFor(
            ChatCategory.relationship,
            profileWith(const {
              'gender': 'Man',
              'relationship_status': 'In a long-term relationship',
            }),
            {'rel_who': who},
          );

      IntakeQuestion find(List<IntakeQuestion> qs, String id) =>
          qs.firstWhere((q) => q.id == id);

      final her = about('My girlfriend');
      expect(find(her, 'rel_whats_wrong').text,
          'What is actually going on with your girlfriend?');
      expect(find(her, 'rel_whats_wrong').options,
          contains("She doesn't give me time"));
      expect(find(her, 'rel_spoken').text, 'Have you told her?');

      // The pronoun follows the tap, not the gender of the person asking. A man
      // who picked "My boyfriend" is not then asked about "her" — which is the
      // whole reason the first answer, and not an inference, decides this.
      final him = about('My boyfriend');
      expect(find(him, 'rel_spoken').text, 'Have you told him?');
      expect(find(him, 'rel_whats_wrong').options,
          contains("He doesn't give me time"));

      // Singular they takes the plural verb, which is the tell that a string was
      // assembled by a machine when it gets it wrong.
      final family = about('My parents or family');
      expect(find(family, 'rel_spoken').text, 'Have you told them?');
      expect(find(family, 'rel_spoken').options, contains('They have no idea'));
      expect(find(family, 'rel_whats_wrong').options,
          contains("They don't listen to me"));

      // A family chat is not asked the questions that only make sense of a
      // partner.
      expect(find(family, 'rel_fear').options,
          isNot(contains('I do not want to be alone')));
      expect(find(her, 'rel_fear').options,
          contains('I do not want to be alone'));
    });

    test('the honest answer to several of these is more than one thing', () {
      // The complaint this exists for: every one of these was a single-select,
      // so someone who was tired *and* unheard *and* frightened of saying so had
      // to pick one and the app advised on the fragment that survived.
      final multi = <ChatCategory, String>{
        ChatCategory.relationship: 'rel_whats_wrong',
        ChatCategory.education: 'edu_obstacle',
        ChatCategory.financial: 'fin_blocker',
        ChatCategory.other: 'oth_blocker',
      };

      multi.forEach((category, id) {
        final question = questionsFor(category, profileWith(const {}))
            .firstWhere((q) => q.id == id);
        expect(question.isMulti, isTrue, reason: '$id should take several');
        expect(question.kind, IntakeAnswerKind.multiChoice);
      });
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
