import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:thoughtloom/models/chat.dart';
import 'package:thoughtloom/models/chat_category.dart';
import 'package:thoughtloom/models/message.dart';
import 'package:thoughtloom/models/user_profile.dart';
import 'package:thoughtloom/screens/adaptive_flow_screen.dart';
import 'package:thoughtloom/screens/continued_chat_screen.dart';
import 'package:thoughtloom/screens/recommendation_screen.dart';
import 'package:thoughtloom/services/ai_service.dart';
import 'package:thoughtloom/services/backend.dart';
import 'package:thoughtloom/theme/app_theme.dart';

import 'fake_ai.dart';

/// The generated half of the flow, driven against a fake [AiService].
///
/// The model itself is the FastAPI service's problem and is tested there. What
/// is tested here is the client's half of the contract: that an answer goes
/// back with the id it belongs to, that a failure offers a retry instead of
/// losing the conversation, that "done" moves on, and that leaving completes
/// the chat.
void main() {
  late FakeAi ai;
  late Chat chat;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Backend.init();
    ai = FakeAi();
    // usingSupabase: the AI flow refuses up front without it, since the API
    // reads its context from Supabase and authorises by a Supabase token.
    Backend.overrideWith(ai: ai, usingSupabase: true);
  });

  var accounts = 0;

  /// A signed-in user with an empty chat. The email is unique per call because
  /// a test that pumps a screen twice would otherwise trip the duplicate-email
  /// check on the second.
  Future<Chat> makeChat() async {
    final user = await Backend.auth.signUp(
      email: 'ada${accounts++}@example.com',
      password: 'hunter2',
      displayName: 'Ada',
    );
    await Backend.data.ensureProfile(user.user.id);
    return Backend.data.createChat(
      userId: user.user.id,
      category: ChatCategory.education,
    );
  }

  Future<void> pumpAdaptive(WidgetTester tester) async {
    chat = await makeChat();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.theme,
        home: AdaptiveFlowScreen(
          chat: chat,
          profile: UserProfile.empty(chat.userId),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pumpRecommendation(WidgetTester tester) async {
    chat = await makeChat();
    // Torn down first: pumping another MaterialApp over one already on screen
    // updates the element tree in place and preserves State, so initState —
    // and the fetch it kicks off — would never run a second time.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.theme, home: RecommendationScreen(chat: chat)),
    );
    await tester.pumpAndSettle();
  }

  group('adaptive questions', () {
    testWidgets('the generated question and its options are shown',
        (tester) async {
      ai = FakeAi(turns: const [
        AdaptiveTurn(
          done: false,
          round: 1,
          messageId: 'm1',
          question: 'What is actually stopping you?',
          options: ['The money', 'My family', 'I lost interest'],
        ),
      ]);
      Backend.overrideWith(ai: ai, usingSupabase: true);

      await pumpAdaptive(tester);

      expect(find.text('What is actually stopping you?'), findsOneWidget);
      expect(find.text('The money'), findsOneWidget);
      expect(find.text('I lost interest'), findsOneWidget);
    });

    testWidgets('a free-text escape hatch is always offered', (tester) async {
      // Whatever the model generated. Its options are guesses, and being unable
      // to say "none of those" would make them a cage.
      ai = FakeAi(turns: const [
        AdaptiveTurn(
          done: false,
          round: 1,
          messageId: 'm1',
          question: 'Why?',
          options: ['A', 'B'],
        ),
      ]);
      Backend.overrideWith(ai: ai, usingSupabase: true);

      await pumpAdaptive(tester);

      expect(find.text('Something else — let me explain'), findsOneWidget);
      // Not open until asked for.
      expect(find.byType(TextFormField), findsNothing);

      await tester.tap(find.text('Something else — let me explain'));
      await tester.pumpAndSettle();
      expect(find.byType(TextFormField), findsOneWidget);
    });

    testWidgets('the answer goes back against the id it belongs to',
        (tester) async {
      ai = FakeAi(turns: const [
        AdaptiveTurn(
          done: false,
          round: 1,
          messageId: 'm1',
          question: 'Why?',
          options: ['The money', 'My family'],
        ),
        AdaptiveTurn(done: true, round: 1),
      ]);
      Backend.overrideWith(ai: ai, usingSupabase: true);

      await pumpAdaptive(tester);
      await tester.tap(find.text('The money'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      // The pairing is what lets the API fill in the right row.
      expect(ai.answersSent, [
        {'id': 'm1', 'text': 'The money'}
      ]);
    });

    testWidgets('free text is sent instead of an option when chosen',
        (tester) async {
      ai = FakeAi(turns: const [
        AdaptiveTurn(
          done: false,
          round: 1,
          messageId: 'm1',
          question: 'Why?',
          options: ['The money'],
        ),
        AdaptiveTurn(done: true, round: 1),
      ]);
      Backend.overrideWith(ai: ai, usingSupabase: true);

      await pumpAdaptive(tester);

      // Pick an option first, then change to free text — the option must not
      // survive as the answer.
      await tester.tap(find.text('The money'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Something else — let me explain'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField),
        'My brother is ill and I am needed at home.',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(ai.answersSent.single['text'],
          'My brother is ill and I am needed at home.');
    });

    testWidgets('Continue is disabled until the question is answered',
        (tester) async {
      ai = FakeAi(turns: const [
        AdaptiveTurn(
          done: false,
          round: 1,
          messageId: 'm1',
          question: 'Why?',
          options: ['A', 'B'],
        ),
      ]);
      Backend.overrideWith(ai: ai, usingSupabase: true);

      await pumpAdaptive(tester);

      ElevatedButton button() => tester.widget<ElevatedButton>(
            find.ancestor(
              of: find.text('Continue'),
              matching: find.byType(ElevatedButton),
            ),
          );
      expect(button().onPressed, isNull);

      await tester.tap(find.text('A'));
      await tester.pumpAndSettle();
      expect(button().onPressed, isNotNull);
    });

    testWidgets('done moves on to the recommendation', (tester) async {
      ai = FakeAi(turns: const [AdaptiveTurn(done: true, round: 4)]);
      Backend.overrideWith(ai: ai, usingSupabase: true);

      await pumpAdaptive(tester);

      expect(find.byType(RecommendationScreen), findsOneWidget);
      expect(find.byType(AdaptiveFlowScreen), findsNothing);
    });

    testWidgets('a failure offers a retry and promises nothing is lost',
        (tester) async {
      ai = FakeAi(turns: const [
        AdaptiveTurn(
          done: false,
          round: 1,
          messageId: 'm1',
          question: 'Why?',
          options: ['A', 'B'],
        ),
      ]);
      ai.failures.add(const AiFailure('That took too long.'));
      Backend.overrideWith(ai: ai, usingSupabase: true);

      await pumpAdaptive(tester);

      expect(find.text('That took too long.'), findsOneWidget);
      expect(find.text('Nothing you have said is lost.'), findsOneWidget);

      // Retrying gets the question that the failed call never delivered.
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Why?'), findsOneWidget);
    });

    testWidgets('a retry re-sends the answer that failed', (tester) async {
      ai = FakeAi(turns: const [
        AdaptiveTurn(
          done: false,
          round: 1,
          messageId: 'm1',
          question: 'Why?',
          options: ['The money'],
        ),
        AdaptiveTurn(done: true, round: 2),
      ]);
      Backend.overrideWith(ai: ai, usingSupabase: true);

      await pumpAdaptive(tester);
      await tester.tap(find.text('The money'));
      await tester.pumpAndSettle();

      // The submit fails.
      ai.failures.add(const AiFailure('Server had a moment.'));
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.text('Server had a moment.'), findsOneWidget);

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      // Sent twice with the same pairing — the API is idempotent about this, so
      // resending beats making the user re-answer.
      expect(ai.answersSent, [
        {'id': 'm1', 'text': 'The money'},
        {'id': 'm1', 'text': 'The money'},
      ]);
    });

    testWidgets('a fatal failure offers no retry', (tester) async {
      // Being signed out will not fix itself, and a retry button would loop.
      ai.failures.add(
        const AiFailure('Please sign in again.', retryable: false),
      );
      Backend.overrideWith(ai: ai, usingSupabase: true);

      await pumpAdaptive(tester);

      expect(find.text('Please sign in again.'), findsOneWidget);
      expect(find.text('Try again'), findsNothing);
      expect(find.text('Back to start'), findsOneWidget);
    });

    testWidgets('without Supabase it says so instead of failing to connect',
        (tester) async {
      Backend.overrideWith(usingSupabase: false);

      await pumpAdaptive(tester);

      expect(find.textContaining('Supabase'), findsOneWidget);
      expect(find.text('Try again'), findsNothing);
    });
  });

  group('recommendation', () {
    testWidgets('the answer, its steps and its confidence are shown',
        (tester) async {
      await pumpRecommendation(tester);

      expect(
        find.text('Finish the degree, but stop pretending it is the point.'),
        findsOneWidget,
      );
      expect(find.text('Talk to your head of department'), findsOneWidget);
      expect(find.text('Fairly sure.'), findsOneWidget);
    });

    testWidgets('sources are shown only when it actually looked something up',
        (tester) async {
      await pumpRecommendation(tester);
      expect(find.text('What I looked up'), findsNothing);

      ai.recommendation_ = const Recommendation(
        text: 'Go.',
        sources: [Source(title: 'Fees 2026', url: 'https://example.edu')],
      );
      Backend.overrideWith(ai: ai, usingSupabase: true);
      await pumpRecommendation(tester);

      expect(find.text('What I looked up'), findsOneWidget);
      expect(find.text('· Fees 2026'), findsOneWidget);
    });

    testWidgets('a failure offers a retry', (tester) async {
      ai.failures.add(const AiFailure('The server was asleep.'));

      await pumpRecommendation(tester);

      expect(find.text('The server was asleep.'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Finish the degree, but stop pretending it is the point.'),
          findsOneWidget);
    });

    testWidgets('leaving completes the chat', (tester) async {
      await pumpRecommendation(tester);

      // The API left it awaiting_follow_up; only the user leaving ends it.
      expect(
        (await Backend.data.fetchChat(chat.id))!.status,
        ChatStatus.inProgress,
      );

      await tester.tap(find.text("That's enough for now"));
      await tester.pumpAndSettle();

      expect(
        (await Backend.data.fetchChat(chat.id))!.status,
        ChatStatus.completed,
      );
    });

    testWidgets('keep chatting opens the conversation', (tester) async {
      await pumpRecommendation(tester);

      await tester.tap(find.text('Keep chatting'));
      await tester.pumpAndSettle();

      expect(find.byType(ContinuedChatScreen), findsOneWidget);
    });
  });

  group('continued chat', () {
    Future<void> pumpChat(WidgetTester tester) async {
      chat = await makeChat();
      // The recommendation is already in the chat's history, as it would be:
      // the API wrote it before this screen ever opens.
      await Backend.data.addMessage(
        chatId: chat.id,
        type: MessageType.intake,
        questionText: 'Scripted question',
        answerText: 'Scripted answer',
      );
      await Backend.data.addMessage(
        chatId: chat.id,
        type: MessageType.recommendation,
        answerText: 'Finish the degree.',
      );
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.theme, home: ContinuedChatScreen(chat: chat)),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('it opens on the recommendation, not a blank window',
        (tester) async {
      await pumpChat(tester);

      expect(find.text('Finish the degree.'), findsOneWidget);
      // The scripted Q&A is scaffolding they already walked through; replaying
      // it here would bury the answer.
      expect(find.text('Scripted question'), findsNothing);
      expect(find.text('Scripted answer'), findsNothing);
    });

    testWidgets('sending shows the message immediately and then the reply',
        (tester) async {
      await pumpChat(tester);

      await tester.enterText(find.byType(TextField), 'But I cannot afford it.');
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.arrow_upward));
      await tester.pumpAndSettle();

      expect(find.text('But I cannot afford it.'), findsOneWidget);
      expect(find.text('Then do not do it.'), findsOneWidget);
      expect(ai.followUpCalls, 1);
    });

    testWidgets('a failed send can be retried without retyping', (tester) async {
      await pumpChat(tester);
      ai.failures.add(const AiFailure('Server had a moment.'));

      await tester.enterText(find.byType(TextField), 'But I cannot afford it.');
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.arrow_upward));
      await tester.pumpAndSettle();

      expect(find.text('Server had a moment.'), findsOneWidget);
      // Still on screen — the user should not have to remember what they said.
      expect(find.text('But I cannot afford it.'), findsOneWidget);

      await tester.tap(find.text('Try sending again'));
      await tester.pumpAndSettle();

      expect(find.text('Then do not do it.'), findsOneWidget);
    });

    testWidgets('leaving completes the chat', (tester) async {
      await pumpChat(tester);

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      expect(
        (await Backend.data.fetchChat(chat.id))!.status,
        ChatStatus.completed,
      );
    });
  });
}
