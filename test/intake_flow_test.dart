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
import 'package:thoughtloom/widgets/option_tile.dart';

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

      // Change it and go forward again. oth_area is multi-select, so the old
      // tick comes off first.
      await choose(tester, first.options.first);
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

    testWidgets(
        'a choice question with nothing that fits offers a way to say so',
        (tester) async {
      final userId = await signInWithProfile(tester);
      await tapCategory(tester, ChatCategory.relationship);

      // rel_who has no hardcoded escape at all — the exact gap this exists
      // to close. Whatever the options, "Something else" is always there too.
      expect(find.text('Who is this about?'), findsOneWidget);
      await choose(tester, 'Something else — let me explain');
      await tester.enterText(
        find.byType(TextField).first,
        'My cousin, sort of raised me',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      final chat = (await Backend.data.fetchChats(userId)).single;
      final messages = await Backend.data.fetchMessages(chat.id);
      expect(messages.single.answerText, 'My cousin, sort of raised me');
      // Not tagged as a choice answer: it is prose, not a tap, and must not
      // be split on "; " or read back later as several ticked options.
      expect(messages.single.metadata.containsKey('selected'), isFalse);
      expect(messages.single.metadata.containsKey('options'), isFalse);

      // And the flow carries on from it, into the broad option set rather than
      // a narrow guess about who "my cousin" is.
      expect(find.text('What is actually going on with them?'), findsOneWidget);

      // Stepping back restores the free text, rather than showing the
      // question as unanswered because nothing matched a fixed option.
      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pumpAndSettle();
      expect(find.text('My cousin, sort of raised me'), findsOneWidget);
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
      // Divorced means an ex-spouse first — the bug where a divorced man was
      // only ever offered "My ex-girlfriend".
      expect(whoOptions(status: 'Separated or divorced', gender: 'Man').first,
          'My ex-wife');
      expect(whoOptions(status: 'Separated or divorced').first, 'My ex-partner');

      // Every term is offered whatever the asker's gender; gender only orders.
      final married = whoOptions(status: 'Married', gender: 'Man');
      expect(married, containsAll(['My wife', 'My husband', 'My partner']));
      final divorced = whoOptions(status: 'Separated or divorced', gender: 'Man');
      expect(
          divorced,
          containsAll([
            'My ex-wife',
            'My ex-husband',
            'My ex-girlfriend',
            'My ex-boyfriend',
            'My ex-partner',
          ]));
      final dating = whoOptions(status: 'Seeing someone', gender: 'Woman');
      expect(dating,
          containsAll(['My boyfriend', 'My girlfriend', 'My partner']));

      // Children are a real option now — except for someone under 18.
      expect(whoOptions(), contains('My children'));
      expect(
        questionsFor(ChatCategory.relationship,
                profileWith(const {'age_range': 'Under 18'}))
            .first
            .options,
        isNot(contains('My children')),
      );

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

    group('every later relationship option fits who Q1 named', () {
      final profile = profileWith(const {});
      List<IntakeQuestion> about(String who, [String? decision]) =>
          questionsFor(ChatCategory.relationship, profile, {
            'rel_who': who,
            if (decision != null) 'rel_decision': decision,
          });
      List<String> opts(List<IntakeQuestion> qs, String id) =>
          qs.firstWhere((q) => q.id == id).options;

      test('every rel_who option is understood by personFrom', () {
        // Reword an option without teaching personFrom and this fails, rather
        // than the flow quietly calling a girlfriend "them".
        final all = questionsFor(ChatCategory.relationship, profile)
            .first
            .options;
        for (final option in all) {
          expect(personFrom(option).tie, isNot(Tie.unknown), reason: option);
        }
      });

      test('an ex is asked about in the past tense', () {
        final ex = about('My ex-girlfriend');
        final wrong = opts(ex, 'rel_whats_wrong');
        expect(wrong, containsAll(['I want her back', 'I cannot move on',
            'She is with someone new', 'We still talk sometimes',
            'I do not know why it ended']));
        expect(wrong, isNot(contains("She doesn't give me time")));
        expect(wrong, isNot(contains('She has been pulling away')));
        expect(wrong, isNot(contains('Honestly, I am the one who has checked out')));

        final decide = opts(ex, 'rel_decision');
        expect(decide, containsAll(['Whether to reach out',
            'Whether to try to get back together', 'Whether to cut contact',
            'Whether to move on']));
        expect(decide, isNot(contains('Whether to end it')));
        expect(decide, isNot(contains('Whether to commit further')));

        expect(ex.firstWhere((q) => q.id == 'rel_duration').text,
            'How long ago did it end?');

        final spoken = opts(ex, 'rel_spoken');
        expect(spoken, contains('We do not talk anymore'));
        expect(spoken, isNot(contains('It turns into a fight every time')));
        expect(spoken, isNot(contains('She says it is fine and it is not')));
        expect(spoken,
            isNot(contains('We have talked many times and nothing changes')));

        final fear = opts(ex, 'rel_fear');
        expect(fear, isNot(contains('I do not want to be alone')));
        expect(fear, isNot(contains('I would lose her')));
        expect(fear,
            isNot(contains('I have already put too much into this to walk away')));
      });

      test('an ex-husband is he, an ex-partner is they', () {
        expect(about('My ex-husband').firstWhere((q) => q.id == 'rel_spoken').text,
            'Have you told him?');
        expect(opts(about('My ex-partner'), 'rel_whats_wrong'),
            contains('They are with someone new'));
        expect(opts(about('My wife'), 'rel_whats_wrong'),
            contains("She doesn't give me time"));
      });

      test('someone they want to be with is not a relationship to end', () {
        final want = about('Someone I want to be with');
        final wrong = opts(want, 'rel_whats_wrong');
        expect(wrong, containsAll(["They don't know how I feel",
            'They are with someone else', 'I do not know if it is mutual']));
        expect(wrong, isNot(contains("They don't give me time")));
        expect(wrong, isNot(contains('They have been pulling away')));

        final decide = opts(want, 'rel_decision');
        expect(decide, containsAll(['Whether to make a move', 'Whether to give up']));
        expect(decide, isNot(contains('Whether to end it')));
        expect(decide, isNot(contains('Whether to commit further')));

        expect(opts(want, 'rel_spoken'),
            isNot(contains('It turns into a fight every time')));
        expect(opts(want, 'rel_fear'), isNot(contains('I do not want to be alone')));
      });

      test('"what is stopping you" only follows a step, not a reflection', () {
        bool asksFear(String decision) => about('My girlfriend', decision)
            .any((q) => q.id == 'rel_fear');
        expect(asksFear('Whether I am being unreasonable'), isFalse);
        expect(asksFear('Whether to give it more time'), isFalse);
        expect(asksFear('Whether to end it'), isTrue);
        // A typed decision could be either, so the question stays.
        expect(asksFear('whether to propose on her birthday'), isTrue);
      });

      test('Q4 names the person the way the rest of the flow does', () {
        expect(opts(about('My girlfriend'), 'rel_duration'),
            contains('As long as I have known her'));
        expect(opts(about('My boyfriend'), 'rel_duration'),
            contains('As long as I have known him'));
        expect(opts(about('My parents or family'), 'rel_duration'),
            contains('For as long as I can remember'));
        expect(opts(about('My parents or family'), 'rel_fear'),
            isNot(contains('My family would have something to say about it')));
      });

      test('more than one person is said in words, and the flow carries on',
          () {
        // Q1 is single-select; "my girlfriend and her parents" goes through
        // "Something else". What follows is the broad, neutral set — worded
        // about "them", never guessing which of the two a line is about.
        final typed = about('My girlfriend and her parents');
        expect(typed.firstWhere((q) => q.id == 'rel_whats_wrong').text,
            'What is actually going on with them?');
        expect(opts(typed, 'rel_whats_wrong'),
            contains("They don't listen to me"));
        expect(typed.firstWhere((q) => q.id == 'rel_spoken').text,
            'Have you told them?');
        expect(typed.map((q) => q.id),
            containsAll(['rel_decision', 'rel_duration', 'rel_fear']));
      });

      test('a typed answer falls back to the broad set, not a wrong one', () {
        final typed = about('My cousin, sort of raised me');
        expect(typed.firstWhere((q) => q.id == 'rel_whats_wrong').text,
            'What is actually going on with them?');
        expect(opts(typed, 'rel_whats_wrong'), contains("They don't listen to me"));
      });
    });

    test('education hides options its decision rules out', () {
      final p = profileWith(const {
        'education_level': 'Partway through an undergraduate degree',
      }, location: 'Pune, India');
      List<IntakeQuestion> after(String decision) =>
          questionsFor(ChatCategory.education, p, {'edu_decision': decision});
      List<String> obstacles(String d) =>
          after(d).firstWhere((q) => q.id == 'edu_obstacle').options;

      expect(obstacles('Whether to take a break from it'),
          isNot(contains('I might not get in')));
      expect(obstacles('Whether to take a break from it'),
          contains('I would fall behind'));
      expect(obstacles('Whether to stay on it'),
          contains('I am struggling with the course itself'));
      expect(obstacles('What to do once it finishes'),
          contains('I might not get in'));
      expect(after('Whether to stay on it').any((q) => q.id == 'edu_geography'),
          isFalse);
      expect(after('What to do once it finishes')
          .any((q) => q.id == 'edu_geography'), isTrue);
      expect(after('Whether to stay on it').last.options,
          contains('Thought it through, still torn'));
    });

    test('financial options follow the decision and the profile', () {
      List<IntakeQuestion> after(String decision, [Map<String, dynamic>? a]) =>
          questionsFor(ChatCategory.financial, profileWith(a ?? const {}),
              {'fin_decision': decision});
      List<String> blockers(String d) =>
          after(d).firstWhere((q) => q.id == 'fin_blocker').options;

      const cost = 'Saying no would cost me the relationship';
      expect(blockers('Money I would be giving someone else'), contains(cost));
      for (final d in [
        'Saving or investing',
        'Earning more — a raise, a switch, a side income',
        'Money someone owes me',
        'Making what I have stretch',
      ]) {
        expect(blockers(d), isNot(contains(cost)), reason: d);
      }
      expect(blockers('Money someone owes me'),
          contains('Asking for it back could cost me the relationship'));

      expect(after('Making what I have stretch')
          .firstWhere((q) => q.id == 'fin_scale').text,
          'Roughly how short are you?');

      // No partner for someone single, no children for someone under 18.
      final stakeholders = after('A big purchase', const {
        'living_situation': 'With my parents or family',
        'relationship_status': 'Single',
        'age_range': 'Under 18',
      }).firstWhere((q) => q.id == 'fin_stakeholders').options;
      expect(stakeholders, isNot(contains('My partner')));
      expect(stakeholders, isNot(contains('My children')));

      // Someone deciding alone is still asked when the money goes to someone.
      final alone = after('Money I would be giving someone else', const {
        'living_situation': 'On my own',
        'relationship_status': 'Single',
        'financial_context': 'I support myself',
      });
      expect(alone.firstWhere((q) => q.id == 'fin_stakeholders').options.first,
          'The person I would give it to');
    });

    test('other hides "admitting I was wrong" for starting something new', () {
      List<String> blockers(String shape) =>
          questionsFor(ChatCategory.other, profileWith(const {}),
                  {'oth_shape': shape})
              .last
              .options;
      const wrong = 'It would mean admitting I was wrong before';
      expect(blockers('Whether to start something'), isNot(contains(wrong)));
      expect(blockers('Whether to stop something'), contains(wrong));
      expect(blockers('Whether to tell someone something'),
          contains('I do not know how they would react'));
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

      // And these take several for the same reason; the durations, deadlines,
      // and the one decision a chat is about stay single.
      const alsoMulti = {
        ChatCategory.relationship: ['rel_spoken', 'rel_fear'],
        ChatCategory.education: ['edu_geography'],
        ChatCategory.other: ['oth_area'],
      };
      const single = {
        ChatCategory.relationship: ['rel_who', 'rel_decision', 'rel_duration'],
        ChatCategory.education: ['edu_decision', 'edu_stage'],
        ChatCategory.financial: ['fin_decision', 'fin_scale', 'fin_urgency'],
        ChatCategory.other: ['oth_shape', 'oth_urgency'],
      };
      alsoMulti.forEach((category, ids) {
        for (final q in questionsFor(category, profileWith(const {}))
            .where((q) => ids.contains(q.id))) {
          expect(q.isMulti, isTrue, reason: q.id);
        }
      });
      single.forEach((category, ids) {
        for (final q in questionsFor(category, profileWith(const {}))
            .where((q) => ids.contains(q.id))) {
          expect(q.kind, IntakeAnswerKind.choice, reason: q.id);
        }
      });

      multi.forEach((category, id) {
        final question = questionsFor(category, profileWith(const {}))
            .firstWhere((q) => q.id == id);
        expect(question.isMulti, isTrue, reason: '$id should take several');
        expect(question.kind, IntakeAnswerKind.multiChoice);
      });
    });
  });

  group('which options can be ticked together', () {
    UserProfile profileWith(Map<String, dynamic> answers, {String? location}) =>
        UserProfile.empty('u').copyWith(
          location: location,
          onboardingAnswers: answers,
        );
    IntakeQuestion q(ChatCategory c, String id,
            {Map<String, dynamic> profile = const {},
            Map<String, String?> answers = const {},
            String? location}) =>
        questionsFor(c, profileWith(profile, location: location), answers)
            .firstWhere((q) => q.id == id);

    /// Taps [taps] in order, as a user would, and returns what is ticked.
    Set<String> tap(IntakeQuestion question, List<String> taps) {
      var picked = <String>{};
      for (final t in taps) {
        expect(question.options, contains(t), reason: t);
        picked = question.toggle(picked, t);
      }
      return picked;
    }

    test('who it is about is one person, picked like the decision', () {
      // Every term on offer: a profile that declined the status question.
      final who = q(ChatCategory.relationship, 'rel_who');
      expect(who.kind, IntakeAnswerKind.choice);
      expect(who.exclusiveGroups, isEmpty);
      expect(tap(who, ['Someone I am seeing', 'Someone I want to be with',
          'My ex-boyfriend', 'My parents or family', 'My children']),
          {'My children'}, reason: 'each tap replaces the last');
      // Every option is still there.
      expect(who.options, containsAll([
        'My girlfriend', 'My boyfriend', 'My wife', 'My husband', 'My partner',
        'My ex-girlfriend', 'My ex-boyfriend', 'My ex-wife', 'My ex-husband',
        'My ex-partner', 'Someone I am seeing', 'Someone I want to be with',
        'My parents or family', 'My children', 'A close friend',
        'Someone at work',
      ]));
    });

    test('the decision stays one decision', () {
      final decide = q(ChatCategory.relationship, 'rel_decision',
          answers: {'rel_who': 'My girlfriend'});
      expect(decide.kind, IntakeAnswerKind.choice);
      expect(tap(decide, ['Whether to end it', 'Whether to commit further']),
          {'Whether to commit further'});
    });

    test('how far a conversation got is one answer inside a multi-select', () {
      final spoken = q(ChatCategory.relationship, 'rel_spoken',
          answers: {'rel_who': 'My girlfriend'});
      expect(
          tap(spoken, [
            'We talked once and nothing changed',
            'We have talked many times and nothing changes',
          ]),
          {'We have talked many times and nothing changes'});
      expect(
          tap(spoken, [
            'We have talked many times and nothing changes',
            'It turns into a fight every time',
            'She says it is fine and it is not',
          ]),
          hasLength(3));
      expect(
          tap(spoken, ['It turns into a fight every time', 'She has no idea']),
          {'She has no idea'});

      final ex = q(ChatCategory.relationship, 'rel_spoken',
          answers: {'rel_who': 'My ex-wife'});
      expect(tap(ex, ['She has no idea', 'We do not talk anymore']),
          hasLength(2), reason: 'never told her, and no longer in touch');
    });

    test('"anywhere" and "not sure" rule out specific places', () {
      final geo = q(ChatCategory.education, 'edu_geography',
          location: 'Pune, India');
      expect(tap(geo, ['Staying in Pune, India', 'Abroad']), hasLength(2));
      expect(tap(geo, ['Staying in Pune, India', 'I am open to anywhere']),
          {'I am open to anywhere'});
      expect(tap(geo, ['Not sure yet', 'Abroad']), {'Abroad'});
    });

    test('"nobody but me" rules out everyone else', () {
      final who = q(ChatCategory.financial, 'fin_stakeholders',
          profile: const {'living_situation': 'With my parents or family'});
      expect(tap(who, ['My parents or family', 'Nobody but me']),
          {'Nobody but me'});
      expect(tap(who, ['Nobody but me', 'Someone else']), {'Someone else'});
    });

    test('every question is single or multi for a reason', () {
      // Re-derived by asking of each: can more than one of these be true of
      // me at once? One answer where the options are points on one scale, or
      // the one decision later questions depend on.
      const expected = {
        ChatCategory.relationship: {
          'rel_who': false,
          'rel_whats_wrong': true,
          'rel_decision': false,
          'rel_duration': false,
          'rel_spoken': true,
          'rel_fear': true,
        },
        ChatCategory.education: {
          'edu_decision': false,
          'edu_geography': true,
          'edu_obstacle': true,
          'edu_stage': false,
        },
        ChatCategory.financial: {
          'fin_decision': false,
          'fin_scale': false,
          'fin_urgency': false,
          'fin_stakeholders': true,
          'fin_blocker': true,
        },
        ChatCategory.other: {
          'oth_area': true,
          'oth_shape': false,
          'oth_urgency': false,
          'oth_blocker': true,
        },
      };
      expected.forEach((category, ids) {
        final qs = questionsFor(category, profileWith(const {}));
        ids.forEach((id, multi) {
          expect(qs.firstWhere((q) => q.id == id).isMulti, multi, reason: id);
        });
      });
    });

    testWidgets('on screen, picking a second person replaces the first',
        (tester) async {
      final userId = await signInWithProfile(tester);
      await tapCategory(tester, ChatCategory.relationship);

      await choose(tester, 'My ex-girlfriend');
      await choose(tester, 'My parents or family');
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      final chat = (await Backend.data.fetchChats(userId)).single;
      final row = (await Backend.data.fetchMessages(chat.id)).single;
      expect(row.answerText, 'My parents or family');
      expect(row.metadata['multi'], isFalse);
    });

    // Circle for one answer, square for several — on every tile of every
    // scripted question, "Something else" included, so no list mixes the two.
    for (final category in ChatCategory.values) {
      testWidgets('${category.label}: every tile has its question\'s shape',
          (tester) async {
        final userId = await signInWithProfile(tester);
        await tapCategory(tester, category);
        final profile = (await Backend.data.fetchProfile(userId))!;

        final answers = <String, String?>{};
        var questions = questionsFor(category, profile, answers);
        for (var i = 0; i < questions.length; i++) {
          final question = questions[i];
          final want = question.isMulti ? ChoiceMode.multi : ChoiceMode.single;
          final tiles = tester.widgetList<OptionTile>(find.byType(OptionTile));
          if (question.isChoice) {
            expect(tiles, hasLength(question.options.length + 1),
                reason: '${question.id}: its options and "Something else"');
          }
          for (final tile in tiles) {
            expect(tile.mode, want, reason: '${question.id} / ${tile.label}');
          }
          answers[question.id] = await answerCurrent(tester, question,
              isLast: i == questions.length - 1);
          questions = questionsFor(category, profile, answers);
        }
      });
    }
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

    test('no category hardcodes its own "something else" any more', () {
      // IntakeFlowScreen now renders a real "Something else — let me explain"
      // tile, with a text box behind it, on every choice question — see the
      // "a choice question with nothing that fits" test below. A category
      // still hardcoding the words itself would put two of that tile on the
      // same screen, one live and one a dead end; see AdaptiveFlowScreen's
      // _clean_options for the same rule on the model's side.
      for (final category in ChatCategory.values) {
        for (final q in questionsFor(category, profile)) {
          expect(
            q.options.any((o) => o.toLowerCase().startsWith('something else')),
            isFalse,
            reason: '${category.label}/${q.id}',
          );
        }
      }
    });
  });
}
