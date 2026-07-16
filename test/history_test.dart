import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:thoughtloom/models/chat.dart';
import 'package:thoughtloom/models/chat_category.dart';
import 'package:thoughtloom/models/message.dart';
import 'package:thoughtloom/screens/chat_transcript_screen.dart';
import 'package:thoughtloom/screens/continued_chat_screen.dart';
import 'package:thoughtloom/screens/history_screen.dart';
import 'package:thoughtloom/services/ai_service.dart';
import 'package:thoughtloom/services/backend.dart';
import 'package:thoughtloom/services/chat_completion.dart';
import 'package:thoughtloom/services/data_service.dart';
import 'package:thoughtloom/theme/app_theme.dart';

import 'fake_ai.dart';

/// History, search, and what closing a chat sets in motion.
///
/// Runs on the on-device backend, but only through [DataService] — whose
/// contract both implementations share, and which is where the search behaviour
/// under test lives. What cannot be covered here is whether PostgREST's
/// embedded `messages!inner` filter returns what [SupabaseDataService] believes
/// it does; that needs a real project.
void main() {
  late FakeAi ai;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Backend.init();
    ai = FakeAi();
    Backend.overrideWith(ai: ai, usingSupabase: true);
  });

  var accounts = 0;

  Future<String> signIn() async {
    final result = await Backend.auth.signUp(
      email: 'ada${accounts++}@example.com',
      password: 'hunter2',
      displayName: 'Ada',
    );
    await Backend.data.ensureProfile(result.user.id);
    return result.user.id;
  }

  /// A chat with something in it, at a given point in its life.
  Future<Chat> makeChat(
    String userId, {
    ChatCategory category = ChatCategory.financial,
    String? title,
    ChatStatus status = ChatStatus.completed,
    String said = 'I keep lending my brother money and he never pays it back.',
  }) async {
    var chat = await Backend.data.createChat(userId: userId, category: category);
    await Backend.data.addMessage(
      chatId: chat.id,
      type: MessageType.freeText,
      answerText: said,
    );
    chat = await Backend.data.saveChat(chat.copyWith(title: title, status: status));
    return chat;
  }

  Future<void> pumpHistory(WidgetTester tester, String userId) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.theme, home: HistoryScreen(userId: userId)),
    );
    await tester.pumpAndSettle();
  }

  /// Types into the search box and waits out the debounce.
  Future<void> search(WidgetTester tester, String query) async {
    await tester.enterText(find.byType(TextField), query);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
  }

  group('the list', () {
    testWidgets('a brand-new user sees an honest empty state', (tester) async {
      final userId = await signIn();

      await pumpHistory(tester, userId);

      expect(find.text('Nothing here yet'), findsOneWidget);
    });

    testWidgets('past chats show their title, category and date',
        (tester) async {
      final userId = await signIn();
      await makeChat(userId, title: 'Lending Ravi money — March 2026');

      await pumpHistory(tester, userId);

      expect(find.text('Lending Ravi money — March 2026'), findsOneWidget);
      expect(find.text('Financial'), findsOneWidget);
      expect(find.text('Just now'), findsOneWidget);
    });

    testWidgets('an untitled chat falls back to its category', (tester) async {
      // Either the titler has not run yet or the chat never got far enough to
      // have a topic. Both read honestly as "Financial".
      final userId = await signIn();
      await makeChat(userId, title: null);

      await pumpHistory(tester, userId);

      expect(find.text('Financial'), findsWidgets);
    });

    testWidgets('an unfinished chat says so', (tester) async {
      final userId = await signIn();
      await makeChat(userId, title: null, status: ChatStatus.inProgress);

      await pumpHistory(tester, userId);

      expect(find.textContaining('Unfinished'), findsOneWidget);
    });

    testWidgets('newest first', (tester) async {
      final userId = await signIn();
      await makeChat(userId, title: 'The old one');
      await makeChat(userId, title: 'The new one');

      await pumpHistory(tester, userId);

      final titles = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .where((d) => d == 'The old one' || d == 'The new one')
          .toList();
      expect(titles, ['The new one', 'The old one']);
    });

    testWidgets('another user\'s chats are not listed', (tester) async {
      final stranger = await signIn();
      await makeChat(stranger, title: 'Not yours');
      final userId = await signIn();

      await pumpHistory(tester, userId);

      expect(find.text('Not yours'), findsNothing);
      expect(find.text('Nothing here yet'), findsOneWidget);
    });
  });

  group('search', () {
    testWidgets('finds a chat by its title', (tester) async {
      final userId = await signIn();
      await makeChat(userId, title: 'Lending Ravi money — March 2026');
      await makeChat(userId, title: 'Which masters to apply for');

      await pumpHistory(tester, userId);
      await search(tester, 'Ravi');

      expect(find.text('Lending Ravi money — March 2026'), findsOneWidget);
      expect(find.text('Which masters to apply for'), findsNothing);
    });

    testWidgets('finds a chat by what was said in it', (tester) async {
      // The point of searching content at all: the user did not write the
      // title, we did, and they will not remember it.
      final userId = await signIn();
      await makeChat(
        userId,
        title: 'A conversation about nothing in particular',
        said: 'My brother keeps borrowing and never pays me back.',
      );

      await pumpHistory(tester, userId);
      await search(tester, 'borrowing');

      expect(find.text('A conversation about nothing in particular'),
          findsOneWidget);
    });

    testWidgets('a content match shows the line it matched', (tester) async {
      final userId = await signIn();
      await makeChat(
        userId,
        title: 'A conversation about nothing in particular',
        said: 'My brother keeps borrowing and never pays me back.',
      );

      await pumpHistory(tester, userId);
      await search(tester, 'borrowing');

      // Otherwise the user is left guessing which of the six words they typed
      // put this row here, and whether it is the match they meant.
      //
      // Matched on the whole line rather than with textContaining: the search
      // field holds the query too, so `textContaining('borrowing')` would pass
      // on the box the user just typed into.
      expect(
        find.text('My brother keeps borrowing and never pays me back.'),
        findsOneWidget,
      );
    });

    testWidgets('a title match shows no excerpt', (tester) async {
      final userId = await signIn();
      await makeChat(userId, title: 'Lending Ravi money', said: 'Something else.');

      await pumpHistory(tester, userId);
      await search(tester, 'Ravi');

      expect(find.text('Something else.'), findsNothing);
    });

    testWidgets('every message type is searchable, including the advice',
        (tester) async {
      final userId = await signIn();
      final chat = await makeChat(userId, title: 'Untitled thing');
      await Backend.data.addMessage(
        chatId: chat.id,
        type: MessageType.recommendation,
        answerText: 'Stop lending him money. Tell him in person.',
      );
      await Backend.data.addMessage(
        chatId: chat.id,
        type: MessageType.assistantReply,
        answerText: 'Because a loan he cannot repay is a gift with resentment.',
      );

      await pumpHistory(tester, userId);
      await search(tester, 'resentment');

      expect(find.text('Untitled thing'), findsOneWidget);
    });

    testWidgets('a title match outranks a content match', (tester) async {
      final userId = await signIn();
      await makeChat(userId, title: 'Mentioned in passing', said: 'About Ravi.');
      await makeChat(userId, title: 'All about Ravi', said: 'Something else.');

      await pumpHistory(tester, userId);
      await search(tester, 'Ravi');

      final titles = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .where((d) => d == 'All about Ravi' || d == 'Mentioned in passing')
          .toList();
      // A query in the title is a claim about what the chat *was*, which beats
      // it having come up once.
      expect(titles, ['All about Ravi', 'Mentioned in passing']);
    });

    testWidgets('a chat matching on both title and content appears once',
        (tester) async {
      // Two queries are merged to build this list, and this chat is in both
      // result sets.
      final userId = await signIn();
      await makeChat(userId, title: 'All about Ravi', said: 'Ravi again.');

      await pumpHistory(tester, userId);
      await search(tester, 'Ravi');

      expect(find.text('All about Ravi'), findsOneWidget);
    });

    testWidgets('no matches says so rather than looking empty', (tester) async {
      final userId = await signIn();
      await makeChat(userId, title: 'Lending Ravi money');

      await pumpHistory(tester, userId);
      await search(tester, 'astrophysics');

      expect(find.textContaining('Nothing matches'), findsOneWidget);
      expect(find.text('Nothing here yet'), findsNothing);
    });

    testWidgets('clearing the search brings everything back', (tester) async {
      final userId = await signIn();
      await makeChat(userId, title: 'Lending Ravi money');
      await makeChat(userId, title: 'Which masters to apply for');

      await pumpHistory(tester, userId);
      await search(tester, 'Ravi');
      expect(find.text('Which masters to apply for'), findsNothing);

      await search(tester, '');

      expect(find.text('Which masters to apply for'), findsOneWidget);
      expect(find.text('Lending Ravi money'), findsOneWidget);
    });

    testWidgets('search is case-insensitive', (tester) async {
      final userId = await signIn();
      await makeChat(userId, title: 'Lending Ravi money');

      await pumpHistory(tester, userId);
      await search(tester, 'RAVI');

      expect(find.text('Lending Ravi money'), findsOneWidget);
    });
  });

  group('opening a chat', () {
    testWidgets('a finished chat opens as a transcript', (tester) async {
      final userId = await signIn();
      await makeChat(userId, title: 'Lending Ravi money');

      await pumpHistory(tester, userId);
      await tester.tap(find.text('Lending Ravi money'));
      await tester.pumpAndSettle();

      expect(find.byType(ChatTranscriptScreen), findsOneWidget);
    });

    testWidgets('a chat left on the advice resumes the conversation',
        (tester) async {
      // They closed the app on the answer. They are mid-conversation, not
      // reading a record.
      final userId = await signIn();
      await makeChat(
        userId,
        title: 'Lending Ravi money',
        status: ChatStatus.awaitingFollowUp,
      );

      await pumpHistory(tester, userId);
      await tester.tap(find.text('Lending Ravi money'));
      await tester.pumpAndSettle();

      expect(find.byType(ContinuedChatScreen), findsOneWidget);
    });

    testWidgets('a completed chat with no title asks for one again',
        (tester) async {
      // Titling runs after the user leaves, and the request that starts it can
      // simply not arrive. Without this, that chat is untitled forever.
      final userId = await signIn();
      await makeChat(userId, title: null);

      await pumpHistory(tester, userId);
      await tester.tap(find.text('Financial').first);
      await tester.pumpAndSettle();

      expect(ai.completed, hasLength(1));
    });

    testWidgets('a chat that already has a title does not', (tester) async {
      final userId = await signIn();
      await makeChat(userId, title: 'Lending Ravi money');

      await pumpHistory(tester, userId);
      await tester.tap(find.text('Lending Ravi money'));
      await tester.pumpAndSettle();

      expect(ai.completed, isEmpty);
    });

    testWidgets('an unfinished chat is not completed behind the user\'s back',
        (tester) async {
      // It is not finished. Asking the API to close it would end a chat the
      // user may yet come back to.
      final userId = await signIn();
      await makeChat(userId, title: null, status: ChatStatus.inProgress);

      await pumpHistory(tester, userId);
      await tester.tap(find.text('Financial').first);
      await tester.pumpAndSettle();

      expect(ai.completed, isEmpty);
    });
  });

  group('deleting', () {
    testWidgets('a long press asks before deleting anything', (tester) async {
      final userId = await signIn();
      await makeChat(userId, title: 'Lending Ravi money');

      await pumpHistory(tester, userId);
      await tester.longPress(find.text('Lending Ravi money'));
      await tester.pumpAndSettle();

      expect(find.text('Delete this chat?'), findsOneWidget);

      await tester.tap(find.text('Keep it'));
      await tester.pumpAndSettle();

      expect(find.text('Lending Ravi money'), findsOneWidget);
      expect(await Backend.data.fetchChats(userId), hasLength(1));
    });

    testWidgets('confirming deletes the chat and its messages', (tester) async {
      final userId = await signIn();
      final chat = await makeChat(userId, title: 'Lending Ravi money');

      await pumpHistory(tester, userId);
      await tester.longPress(find.text('Lending Ravi money'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Lending Ravi money'), findsNothing);
      expect(await Backend.data.fetchChats(userId), isEmpty);
      // Cascades, as the schema's ON DELETE CASCADE does.
      expect(await Backend.data.fetchMessages(chat.id), isEmpty);
    });
  });

  group('completeChat', () {
    testWidgets('marks the chat completed and asks the API to close it',
        (tester) async {
      final userId = await signIn();
      final chat = await makeChat(userId, status: ChatStatus.awaitingFollowUp);

      await completeChat(chat);
      await tester.pumpAndSettle();

      expect((await Backend.data.fetchChat(chat.id))!.status,
          ChatStatus.completed);
      expect(ai.completed, [chat.id]);
    });

    testWidgets('a chat already completed is not written again', (tester) async {
      // The status write trips the touch_updated_at trigger, and updated_at is
      // what orders history and what recall treats as "most recent". Reopening
      // a chat from March to backfill its title must not move it to the top of
      // the list dated "Just now".
      final userId = await signIn();
      final chat = await makeChat(userId, status: ChatStatus.completed);
      final before = (await Backend.data.fetchChat(chat.id))!.updatedAt;

      await completeChat(chat);
      await tester.pumpAndSettle();

      expect((await Backend.data.fetchChat(chat.id))!.updatedAt, before);
      // The API is still asked — the title is the whole reason we are here.
      expect(ai.completed, [chat.id]);
    });

    testWidgets('an API failure still completes the chat', (tester) async {
      // The two are independent on purpose: the title and the memory are
      // best-effort, and the chat is over either way.
      final userId = await signIn();
      final chat = await makeChat(userId, status: ChatStatus.awaitingFollowUp);
      ai.failures.add(const AiFailure('the server is asleep'));

      await completeChat(chat);
      await tester.pumpAndSettle();

      expect((await Backend.data.fetchChat(chat.id))!.status,
          ChatStatus.completed);
    });

    testWidgets('it never throws', (tester) async {
      // The user asked to leave. Refusing because a write failed would trap
      // them on a screen they are done with.
      final userId = await signIn();
      final chat = await makeChat(userId);
      await Backend.data.deleteChat(chat.id);
      ai.failures.add(const AiFailure('and the API is down too'));

      await expectLater(completeChat(chat), completes);
    });
  });

  group('at a phone viewport', () {
    /// 360×780, which is the small end of what this app will actually run on.
    ///
    /// An overflow throws in a test, so these pass by not exploding. They are
    /// conservative: 'Inter' is not bundled, so `flutter test` falls back to a
    /// box-glyph font and text measures *wider* here than on a device. Fitting
    /// under test therefore implies fitting on the phone, not the reverse.
    void phone(WidgetTester tester) {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
    }

    testWidgets('the empty state fits', (tester) async {
      phone(tester);
      final userId = await signIn();

      await pumpHistory(tester, userId);

      expect(find.text('Nothing here yet'), findsOneWidget);
    });

    testWidgets('a long title and a long excerpt fit', (tester) async {
      phone(tester);
      final userId = await signIn();
      await makeChat(
        userId,
        title: 'Whether to drop out of the BTech and do design instead — '
            'March 2026',
        said: 'I have been going back and forth on this for months and I still '
            'have not told my father, who paid for the first two years of it '
            'and asks me about my results every single Sunday.',
      );

      await pumpHistory(tester, userId);
      await search(tester, 'father');

      expect(find.byType(HistoryScreen), findsOneWidget);
    });

    testWidgets('a full transcript fits', (tester) async {
      phone(tester);
      final userId = await signIn();
      final chat = await makeChat(userId, title: 'Lending Ravi money');
      await Backend.data.addMessage(
        chatId: chat.id,
        type: MessageType.intake,
        questionText: 'How urgent is this?',
        answerText: 'Within a month',
      );
      await Backend.data.addMessage(
        chatId: chat.id,
        type: MessageType.recommendation,
        answerText: 'Stop lending him money. Tell him in person, this week, '
            'and say it once rather than negotiating it.',
        metadata: {
          'next_steps': ['Say it on Sunday', 'Do not offer a smaller amount'],
        },
      );
      await Backend.data.addMessage(
        chatId: chat.id,
        type: MessageType.assistantReply,
        answerText: 'Because a loan he cannot repay is a gift with resentment '
            'attached, and you both know it.',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.theme, home: ChatTranscriptScreen(chat: chat)),
      );
      await tester.pumpAndSettle();

      // The whole arc, not just the advice — this is the "what did I say?" view.
      expect(find.text('How urgent is this?'), findsOneWidget);
      expect(find.text('Within a month'), findsOneWidget);
      expect(find.text('What I said'), findsOneWidget);
      expect(find.text('Say it on Sunday'), findsOneWidget);
      expect(find.textContaining('gift with resentment'), findsOneWidget);
    });

    testWidgets('an abandoned chat says so rather than rendering blank',
        (tester) async {
      phone(tester);
      final userId = await signIn();
      // The dashboard opens a chat row on the category tap, so a mis-tap is a
      // real row with nothing in it.
      final chat = await Backend.data.createChat(
        userId: userId,
        category: ChatCategory.other,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.theme, home: ChatTranscriptScreen(chat: chat)),
      );
      await tester.pumpAndSettle();

      expect(find.text('This one never got started.'), findsOneWidget);
    });
  });

  group('excerptAround', () {
    test('windows around the match, cutting at both ends', () {
      final excerpt = excerptAround(
        'I have been thinking about this for months and months and my brother '
        'still owes me money from last year, and from the year before that, '
        'and I have never once mentioned it to him or to anyone else at all.',
        'brother',
      );

      expect(excerpt, contains('brother'));
      expect(excerpt, startsWith('...'));
      expect(excerpt, endsWith('...'));
      // Short enough for two lines of a list row.
      expect(excerpt!.length, lessThan(150));
    });

    test('a short message is shown whole, with no ellipses', () {
      // It is not a fragment, so it must not look like one.
      expect(excerptAround('My brother owes me money.', 'brother'),
          'My brother owes me money.');
    });

    test('no match is null, which is how a title-only hit is told apart', () {
      expect(excerptAround('My brother owes me money.', 'astrophysics'), isNull);
    });

    test('it is case-insensitive, as the ILIKE that found the row was', () {
      expect(excerptAround('My Brother owes me money.', 'brother'), isNotNull);
    });

    test('newlines are collapsed so a row stays a row', () {
      expect(
        excerptAround('My brother\n\n  owes me money.', 'brother'),
        'My brother owes me money.',
      );
    });
  });
}
