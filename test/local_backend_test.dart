import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:thoughtloom/models/chat.dart';
import 'package:thoughtloom/models/chat_category.dart';
import 'package:thoughtloom/models/message.dart';
import 'package:thoughtloom/services/auth_service.dart';
import 'package:thoughtloom/services/data_service.dart';
import 'package:thoughtloom/services/local/local_auth_service.dart';
import 'package:thoughtloom/services/local/local_data_service.dart';
import 'package:thoughtloom/services/local/local_store.dart';

/// Exercises the on-device implementations of [AuthService] and [DataService].
///
/// These assert the *contract* both backends share — sequence numbering, chat
/// ordering, the nullable-category memory split, cascade-on-delete — so the
/// same expectations can be pointed at Supabase once credentials exist.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocalStore store;
  late LocalAuthService auth;
  late LocalDataService data;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = await LocalStore.open();
    auth = LocalAuthService(store);
    data = LocalDataService(store);
  });

  Future<String> signUpAda() async {
    final result = await auth.signUp(
      email: 'ada@example.com',
      password: 'hunter2',
      displayName: 'Ada',
    );
    return result.user.id;
  }

  group('auth', () {
    test('sign-up signs the user straight in and normalises the email', () async {
      final result = await auth.signUp(
        email: '  Ada@Example.COM ',
        password: 'hunter2',
      );

      expect(result.needsEmailConfirmation, isFalse);
      expect(result.user.email, 'ada@example.com');
      expect(auth.currentUser?.id, result.user.id);
      expect(auth.isSignedIn, isTrue);
    });

    test('a duplicate email is rejected regardless of case', () async {
      await signUpAda();

      expect(
        () => auth.signUp(email: 'ADA@example.com', password: 'other-pass'),
        throwsA(isA<AuthFailure>()),
      );
    });

    test('a too-short password is rejected', () async {
      expect(
        () => auth.signUp(email: 'ada@example.com', password: 'abc'),
        throwsA(isA<AuthFailure>()),
      );
    });

    test('the wrong password does not sign anyone in', () async {
      await signUpAda();
      await auth.signOut();

      expect(
        () => auth.signIn(email: 'ada@example.com', password: 'wrong'),
        throwsA(isA<AuthFailure>()),
      );
      expect(auth.currentUser, isNull);
    });

    test('an unknown email fails the same way as a wrong password', () async {
      // Identical messages, so the screen cannot be used to enumerate accounts.
      await signUpAda();
      await auth.signOut();

      Future<String> failureFor(String email, String password) async {
        try {
          await auth.signIn(email: email, password: password);
          fail('Expected sign-in to fail for $email');
        } on AuthFailure catch (e) {
          return e.message;
        }
      }

      expect(
        await failureFor('nobody@example.com', 'hunter2'),
        await failureFor('ada@example.com', 'wrong'),
      );
    });

    test('sign-out clears the session and notifies listeners', () async {
      await signUpAda();
      expectLater(auth.authStateChanges, emits(isNull));

      await auth.signOut();
      expect(auth.currentUser, isNull);
    });

    test('a session is restored on the next launch', () async {
      final userId = await signUpAda();

      // A fresh service over the same storage stands in for an app restart.
      final restored = LocalAuthService(await LocalStore.open());
      expect(restored.currentUser?.id, userId);
    });
  });

  group('profiles', () {
    test('ensureProfile provisions an empty profile and global memory', () async {
      final userId = await signUpAda();

      final profile = await data.ensureProfile(userId);
      expect(profile.id, userId);
      expect(profile.onboardingCompleted, isFalse);
      expect(profile.onboardingAnswers, isEmpty);

      // Mirrors what the handle_new_user trigger does on Supabase.
      final memory = await data.fetchMemory(userId);
      expect(memory, isNotNull);
      expect(memory!.isGlobal, isTrue);
    });

    test('the name given at sign-up reaches the profile', () async {
      // Supabase carries this across via raw_user_meta_data and the
      // handle_new_user trigger; the on-device path has to match or the two
      // backends greet the user differently.
      final userId = await signUpAda();

      expect((await data.ensureProfile(userId)).displayName, 'Ada');
    });

    test('registering without a name leaves it unset rather than blank', () async {
      final result = await auth.signUp(
        email: 'bob@example.com',
        password: 'hunter2',
        displayName: '   ',
      );

      expect((await data.ensureProfile(result.user.id)).displayName, isNull);
    });

    test('ensureProfile is idempotent', () async {
      final userId = await signUpAda();

      final first = await data.ensureProfile(userId);
      await data.saveProfile(first.copyWith(displayName: 'Ada L'));
      final second = await data.ensureProfile(userId);

      expect(second.displayName, 'Ada L');
      expect(second.id, first.id);
    });

    test('onboarding answers round-trip', () async {
      final userId = await signUpAda();
      final profile = await data.ensureProfile(userId);

      await data.saveProfile(profile.copyWith(
        onboardingAnswers: {'age_range': '25-34', 'goals': ['clarity']},
        onboardingCompleted: true,
      ));

      final reloaded = await data.fetchProfile(userId);
      expect(reloaded!.onboardingCompleted, isTrue);
      expect(reloaded.onboardingAnswers['age_range'], '25-34');
      expect(reloaded.onboardingAnswers['goals'], ['clarity']);
    });
  });

  group('chats and messages', () {
    test('turns are numbered from 1 and read back in order', () async {
      final userId = await signUpAda();
      final chat = await data.createChat(
        userId: userId,
        category: ChatCategory.education,
      );

      await data.addMessage(
        chatId: chat.id,
        type: MessageType.intake,
        questionText: 'What are you currently doing?',
        answerText: 'Studying',
      );
      await data.addMessage(
        chatId: chat.id,
        type: MessageType.freeText,
        answerText: 'I cannot decide on a masters.',
      );
      await data.addMessage(
        chatId: chat.id,
        type: MessageType.recommendation,
        answerText: 'Here is what I would do.',
      );

      final messages = await data.fetchMessages(chat.id);
      expect(messages.map((m) => m.seq), [1, 2, 3]);
      expect(messages.first.type, MessageType.intake);
      expect(messages.last.type, MessageType.recommendation);
    });

    test('metadata round-trips so citations survive', () async {
      final userId = await signUpAda();
      final chat = await data.createChat(
        userId: userId,
        category: ChatCategory.financial,
      );

      await data.addMessage(
        chatId: chat.id,
        type: MessageType.recommendation,
        answerText: 'Rates are falling.',
        metadata: {
          'sources': ['https://example.com/rates'],
          'model': 'command-r-plus-08-2024',
        },
      );

      final message = (await data.fetchMessages(chat.id)).single;
      expect(message.metadata['sources'], ['https://example.com/rates']);
      expect(message.metadata['model'], 'command-r-plus-08-2024');
    });

    test('a new message reorders the chat list by activity', () async {
      final userId = await signUpAda();

      final older = await data.createChat(
        userId: userId,
        category: ChatCategory.education,
      );
      // Ordering by wall-clock needs the wall clock to actually move. Windows
      // resolves DateTime.now() coarsely enough that two back-to-back writes
      // otherwise land on the same timestamp and the order is a coin toss.
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final newer = await data.createChat(
        userId: userId,
        category: ChatCategory.other,
      );

      expect((await data.fetchChats(userId)).first.id, newer.id);

      await Future<void>.delayed(const Duration(milliseconds: 5));
      await data.addMessage(
        chatId: older.id,
        type: MessageType.freeText,
        answerText: 'One more thing.',
      );

      expect((await data.fetchChats(userId)).first.id, older.id);
    });

    test('chats are scoped to their owner', () async {
      final ada = await signUpAda();
      await data.createChat(userId: ada, category: ChatCategory.education);

      final bob = (await auth.signUp(email: 'bob@example.com', password: 'hunter2')).user;

      expect(await data.fetchChats(bob.id), isEmpty);
      expect(await data.fetchChats(ada), hasLength(1));
    });

    test('deleting a chat takes its messages with it', () async {
      final userId = await signUpAda();
      final chat = await data.createChat(
        userId: userId,
        category: ChatCategory.relationship,
      );
      await data.addMessage(
        chatId: chat.id,
        type: MessageType.freeText,
        answerText: 'Something private.',
      );

      await data.deleteChat(chat.id);

      expect(await data.fetchChat(chat.id), isNull);
      expect(await data.fetchMessages(chat.id), isEmpty);
    });

    test('saving a deleted message fails instead of resurrecting it', () async {
      // Supabase updates by id and matches no rows; the on-device path must not
      // quietly write the row back into existence.
      final userId = await signUpAda();
      final chat = await data.createChat(
        userId: userId,
        category: ChatCategory.other,
      );
      final message = await data.addMessage(
        chatId: chat.id,
        type: MessageType.freeText,
        answerText: 'Something private.',
      );

      await data.deleteChat(chat.id);

      expect(
        () => data.saveMessage(message.copyWith(answerText: 'edited')),
        throwsA(isA<DataFailure>()),
      );
      expect(await data.fetchMessages(chat.id), isEmpty);
    });

    test('search matches titles case-insensitively and skips untitled chats',
        () async {
      final userId = await signUpAda();
      final titled = await data.createChat(
        userId: userId,
        category: ChatCategory.education,
      );
      await data.saveChat(titled.copyWith(title: 'Choosing a Masters Program'));
      await data.createChat(userId: userId, category: ChatCategory.other);

      expect(await data.searchChats(userId, 'masters'), hasLength(1));
      expect(await data.searchChats(userId, 'MASTERS'), hasLength(1));
      expect(await data.searchChats(userId, 'plumbing'), isEmpty);

      // An empty query is a cleared search box, not a request for nothing.
      expect(await data.searchChats(userId, '   '), hasLength(2));
    });

    test('status survives a round-trip', () async {
      final userId = await signUpAda();
      final chat = await data.createChat(
        userId: userId,
        category: ChatCategory.education,
      );
      expect(chat.status, ChatStatus.inProgress);

      await data.saveChat(chat.copyWith(status: ChatStatus.completed));
      expect((await data.fetchChat(chat.id))!.status, ChatStatus.completed);
    });
  });

  group('memory', () {
    test('global and per-category memory are separate rows', () async {
      final userId = await signUpAda();

      await data.saveMemory(userId: userId, summary: 'Based in Pune.');
      await data.saveMemory(
        userId: userId,
        category: ChatCategory.financial,
        summary: 'Saving for a house.',
      );

      expect((await data.fetchMemory(userId))!.summary, 'Based in Pune.');
      expect(
        (await data.fetchMemory(userId, category: ChatCategory.financial))!.summary,
        'Saving for a house.',
      );
      // A category with nothing learned yet must not fall back to the global row.
      expect(
        await data.fetchMemory(userId, category: ChatCategory.relationship),
        isNull,
      );
    });

    test('saving twice updates in place rather than duplicating', () async {
      final userId = await signUpAda();

      final first = await data.saveMemory(userId: userId, summary: 'Draft.');
      final second = await data.saveMemory(
        userId: userId,
        summary: 'Revised.',
        facts: const ['two kids'],
      );

      expect(second.id, first.id);
      expect(await data.fetchAllMemory(userId), hasLength(1));
      expect((await data.fetchMemory(userId))!.facts, ['two kids']);
    });

    test('fetchAllMemory returns the global row plus every category', () async {
      final userId = await signUpAda();

      await data.saveMemory(userId: userId, summary: 'Global.');
      await data.saveMemory(
        userId: userId,
        category: ChatCategory.education,
        summary: 'Education.',
      );
      await data.saveMemory(
        userId: userId,
        category: ChatCategory.financial,
        summary: 'Financial.',
      );

      final all = await data.fetchAllMemory(userId);
      expect(all, hasLength(3));
      expect(all.where((m) => m.isGlobal), hasLength(1));
    });
  });
}
