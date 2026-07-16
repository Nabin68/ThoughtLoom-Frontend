//supabase_data_service.dart

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../models/chat.dart';
import '../../models/chat_category.dart';
import '../../models/message.dart';
import '../../models/user_memory.dart';
import '../../models/user_profile.dart';
import '../data_service.dart';

class SupabaseDataService extends DataService {
  final sb.SupabaseClient _client;

  SupabaseDataService(this._client);

  /// Every public method funnels through this so no Postgrest type escapes into
  /// the UI and no call site has to remember to catch.
  Future<T> _guard<T>(Future<T> Function() action, String whatFailed) async {
    try {
      return await action();
    } on sb.PostgrestException catch (e) {
      throw DataFailure('Could not $whatFailed. ${e.message}');
    } on DataFailure {
      rethrow;
    } catch (e) {
      // The user-facing guess is a network problem, which is what this almost
      // always is. Log the real one: a decoding error would otherwise spend a
      // debugging session disguised as bad connectivity.
      debugPrint('ThoughtLoom: failed to $whatFailed — $e');
      throw DataFailure('Could not $whatFailed. Please check your connection.');
    }
  }

  // --- profiles ------------------------------------------------------------

  @override
  Future<UserProfile?> fetchProfile(String userId) => _guard(() async {
        final row = await _client
            .from('user_profiles')
            .select()
            .eq('id', userId)
            .maybeSingle();
        return row == null ? null : UserProfile.fromJson(row);
      }, 'load your profile');

  @override
  Future<UserProfile> ensureProfile(String userId) => _guard(() async {
        final existing = await fetchProfile(userId);
        if (existing != null) return existing;

        // Reaching here means handle_new_user did not run — an account created
        // before the trigger was applied, or a database without it. Stand in for
        // the whole trigger, not just its first half, so the two backends agree
        // on what a provisioned account looks like.
        //
        // Losing a race against the real trigger is harmless: the insert is
        // ignored and the select below returns the trigger's row.
        await _client
            .from('user_profiles')
            .upsert({'id': userId}, ignoreDuplicates: true);

        // Not an upsert: user_memory's primary key is a synthetic uuid, so
        // ignore-duplicates would arbitrate on a key that never collides and
        // insert a second global row — which the partial unique index would then
        // reject. saveMemory reads first, which is what this needs.
        if (await fetchMemory(userId) == null) {
          await saveMemory(userId: userId, summary: '');
        }

        final row = await _client
            .from('user_profiles')
            .select()
            .eq('id', userId)
            .maybeSingle();
        if (row == null) {
          throw const DataFailure('Could not set up your profile.');
        }
        return UserProfile.fromJson(row);
      }, 'set up your profile');

  @override
  Future<UserProfile> saveProfile(UserProfile profile) => _guard(() async {
        final row = await _client
            .from('user_profiles')
            .upsert(profile.toJson())
            .select()
            .single();
        return UserProfile.fromJson(row);
      }, 'save your profile');

  // --- chats ---------------------------------------------------------------

  @override
  Future<List<Chat>> fetchChats(String userId) => _guard(() async {
        final rows = await _client
            .from('chats')
            .select()
            .eq('user_id', userId)
            .order('updated_at', ascending: false)
            // Tie-break, so chats sharing an updated_at do not shuffle between
            // reads. Postgres has no stable sort to fall back on.
            .order('created_at', ascending: false);
        return rows.map(Chat.fromJson).toList();
      }, 'load your chats');

  @override
  Future<Chat?> fetchChat(String chatId) => _guard(() async {
        final row =
            await _client.from('chats').select().eq('id', chatId).maybeSingle();
        return row == null ? null : Chat.fromJson(row);
      }, 'load that chat');

  @override
  Future<Chat> createChat({
    required String userId,
    required ChatCategory category,
    String? title,
  }) =>
      _guard(() async {
        final row = await _client
            .from('chats')
            .insert({
              'user_id': userId,
              'category': category.wireValue,
              'title': title,
            })
            .select()
            .single();
        return Chat.fromJson(row);
      }, 'start a new chat');

  @override
  Future<Chat> saveChat(Chat chat) => _guard(() async {
        final row = await _client
            .from('chats')
            .update({
              'title': chat.title,
              'status': chat.status.wireValue,
              'category': chat.category.wireValue,
            })
            .eq('id', chat.id)
            .select()
            .single();
        return Chat.fromJson(row);
      }, 'save that chat');

  @override
  Future<Chat> reopenChat(String chatId) => _guard(() async {
        final row = await _client
            .from('chats')
            .update({
              'status': ChatStatus.awaitingFollowUp.wireValue,
              // The whole point — see DataService.reopenChat. Without this the
              // merge stays skipped and everything said from here on is
              // forgotten.
              'memory_merged_at': null,
            })
            .eq('id', chatId)
            .select()
            .single();
        return Chat.fromJson(row);
      }, 'reopen that chat');

  @override
  Future<void> deleteChat(String chatId) => _guard(
        () => _client.from('chats').delete().eq('id', chatId),
        'delete that chat',
      );

  /// Two queries — titles, then what was said — merged in Dart.
  ///
  /// Not one query: PostgREST cannot OR a top-level column against an embedded
  /// one, and the alternative (a hand-built `or=(...)` string carrying a
  /// user-typed value through two layers of quoting) is a parsing bug waiting
  /// to happen for no gain. Two round trips on a debounced, user-initiated
  /// search is not a cost worth that.
  ///
  /// Content matching is against `answer_text` only. That is where the content
  /// of *every* message type lives: what they chose in the intake, what they
  /// wrote, what we advised, and every turn since. `question_text` is our words
  /// — and the scripted intake questions are identical for everyone in a
  /// category, so including them would mean a search for "money" returned every
  /// financial chat ever started, on the strength of a question we asked.
  @override
  Future<List<ChatSearchHit>> searchChats(String userId, String query) =>
      _guard(() async {
        final term = query.trim();
        if (term.isEmpty) {
          final all = await fetchChats(userId);
          return all.map((c) => ChatSearchHit(chat: c)).toList();
        }

        // Escape SQL's wildcards so a literal % or _ in the query does not
        // widen the search.
        //
        // PostgREST also maps * onto % inside the value before it reaches SQL,
        // and that one cannot be escaped through ilike — `\*` arrives as `\%`
        // and matches a literal percent instead. So a * in a query still acts
        // as a wildcard here while LocalDataService takes it literally. Reach
        // for imatch if that divergence ever matters.
        final escaped = term.replaceAll('%', r'\%').replaceAll('_', r'\_');

        final titleRows = await _client
            .from('chats')
            .select()
            .eq('user_id', userId)
            .ilike('title', '%$escaped%')
            .order('updated_at', ascending: false)
            .order('created_at', ascending: false);

        // `messages!inner` turns the embedded filter into a join filter: chats
        // with no matching message drop out, and the ones that survive carry
        // only their matching messages — which is exactly the excerpt.
        final contentRows = await _client
            .from('chats')
            .select('*, messages!inner(answer_text)')
            .eq('user_id', userId)
            .ilike('messages.answer_text', '%$escaped%')
            .order('updated_at', ascending: false)
            .order('created_at', ascending: false);

        final hits = <String, ChatSearchHit>{};
        // Titles first: a query matching the title is a claim about what the
        // chat *was*, which beats it having been mentioned once in passing.
        // Insertion order carries the ranking, and a chat already in from its
        // title is not downgraded by also matching on content.
        for (final row in titleRows) {
          final chat = Chat.fromJson(row);
          hits[chat.id] = ChatSearchHit(chat: chat);
        }
        for (final row in contentRows) {
          final chat = Chat.fromJson(row);
          if (hits.containsKey(chat.id)) continue;
          hits[chat.id] = ChatSearchHit(
            chat: chat,
            excerpt: _firstExcerpt(row['messages'], term),
          );
        }
        return hits.values.toList();
      }, 'search your chats');

  /// The first matching message's text, windowed around the query.
  ///
  /// Postgres matched these rows, so one of them contains the term — but the
  /// ILIKE that found it and the Dart search here are two different engines, and
  /// an escaped wildcard is exactly where they could disagree. A null excerpt
  /// renders as a plain result rather than an error, so a disagreement costs the
  /// snippet and nothing else.
  String? _firstExcerpt(dynamic messages, String term) {
    if (messages is! List) return null;
    for (final message in messages) {
      if (message is! Map) continue;
      final text = message['answer_text'] as String?;
      if (text == null) continue;
      final excerpt = excerptAround(text, term);
      if (excerpt != null) return excerpt;
    }
    return null;
  }

  // --- messages ------------------------------------------------------------

  @override
  Future<List<Message>> fetchMessages(String chatId) => _guard(() async {
        final rows = await _client
            .from('messages')
            .select()
            .eq('chat_id', chatId)
            .order('seq', ascending: true);
        return rows.map(Message.fromJson).toList();
      }, 'load this conversation');

  @override
  Future<Message> addMessage({
    required String chatId,
    required MessageType type,
    String? questionText,
    String? answerText,
    Map<String, dynamic> metadata = const {},
  }) =>
      _guard(() async {
        final last = await _client
            .from('messages')
            .select('seq')
            .eq('chat_id', chatId)
            .order('seq', ascending: false)
            .limit(1)
            .maybeSingle();
        final nextSeq = ((last?['seq'] as int?) ?? 0) + 1;

        final row = await _client
            .from('messages')
            .insert({
              'chat_id': chatId,
              'seq': nextSeq,
              'type': type.wireValue,
              'question_text': questionText,
              'answer_text': answerText,
              'metadata': metadata,
            })
            .select()
            .single();

        // Keeps the chat list ordered by real activity. The touch_updated_at
        // trigger overwrites this with server time; the value sent only has to
        // make it a real update.
        await _client
            .from('chats')
            .update({'updated_at': DateTime.now().toUtc().toIso8601String()})
            .eq('id', chatId);

        return Message.fromJson(row);
      }, 'save that message');

  @override
  Future<Message> saveMessage(Message message) => _guard(() async {
        final row = await _client
            .from('messages')
            .update({
              'question_text': message.questionText,
              'answer_text': message.answerText,
              'metadata': message.metadata,
            })
            .eq('id', message.id)
            .select()
            .single();
        return Message.fromJson(row);
      }, 'save that message');

  @override
  Future<void> deleteMessage(String messageId) => _guard(
        () => _client.from('messages').delete().eq('id', messageId),
        'remove that answer',
      );

  // --- memory --------------------------------------------------------------

  @override
  Future<UserMemory?> fetchMemory(String userId, {ChatCategory? category}) =>
      _guard(() async {
        final row = await _categoryFilter(
          _client.from('user_memory').select().eq('user_id', userId),
          category,
        ).maybeSingle();
        return row == null ? null : UserMemory.fromJson(row);
      }, 'load what we remember about you');

  @override
  Future<List<UserMemory>> fetchAllMemory(String userId) => _guard(() async {
        final rows =
            await _client.from('user_memory').select().eq('user_id', userId);
        return rows.map(UserMemory.fromJson).toList();
      }, 'load what we remember about you');

  @override
  Future<UserMemory> saveMemory({
    required String userId,
    ChatCategory? category,
    required String summary,
    List<dynamic> facts = const [],
  }) =>
      _guard(() async {
        // Not an upsert: uniqueness here comes from two *partial* indexes, and
        // PostgREST's on_conflict cannot express their WHERE predicate. Read,
        // then update or insert.
        final existing = await fetchMemory(userId, category: category);

        if (existing != null) {
          final row = await _client
              .from('user_memory')
              .update({'summary': summary, 'facts': facts})
              .eq('id', existing.id)
              .select()
              .single();
          return UserMemory.fromJson(row);
        }

        final row = await _client
            .from('user_memory')
            .insert({
              'user_id': userId,
              'category': category?.wireValue,
              'summary': summary,
              'facts': facts,
            })
            .select()
            .single();
        return UserMemory.fromJson(row);
      }, 'save what we remember about you');

  /// `category = null` and `category IS NULL` are different queries in SQL;
  /// PostgREST needs `is` for the global row and `eq` for a scoped one.
  sb.PostgrestFilterBuilder<T> _categoryFilter<T>(
    sb.PostgrestFilterBuilder<T> query,
    ChatCategory? category,
  ) =>
      category == null
          ? query.isFilter('category', null)
          : query.eq('category', category.wireValue);
}
