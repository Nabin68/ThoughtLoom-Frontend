//local_data_service.dart

import '../../models/chat.dart';
import '../../models/chat_category.dart';
import '../../models/message.dart';
import '../../models/user_memory.dart';
import '../../models/user_profile.dart';
import '../data_service.dart';
import 'local_store.dart';

/// On-device stand-in for the Supabase tables, used when no credentials are
/// configured. Mirrors [SupabaseDataService]'s behaviour — same ordering, same
/// sequence numbering, same nullable-category memory split — so swapping
/// backends does not change what the app does.
///
/// Row Level Security has no analogue here. The user-scoped reads filter by id
/// in Dart, but the ones addressed by chat or message id trust their caller
/// where Supabase would return nothing for another user's row. On a dev-only,
/// single-device backend that gap is not worth the signature churn to close.
class LocalDataService extends DataService {
  final LocalStore _store;

  LocalDataService(this._store);

  List<Map<String, dynamic>> _rows(String key) => _store
      .readTable(key)
      .values
      .map((row) => Map<String, dynamic>.from(row as Map))
      .toList();

  // --- profiles ------------------------------------------------------------

  @override
  Future<UserProfile?> fetchProfile(String userId) async {
    final row = _store.readTable(LocalStore.profilesKey)[userId];
    return row == null
        ? null
        : UserProfile.fromJson(Map<String, dynamic>.from(row as Map));
  }

  @override
  Future<UserProfile> ensureProfile(String userId) async {
    final existing = await fetchProfile(userId);
    if (existing != null) return existing;

    // Stands in for the handle_new_user trigger: a fresh account gets a profile
    // carrying the name captured at sign-up, plus a global memory row.
    final profile = UserProfile.empty(userId).copyWith(
      displayName: _displayNameFromAccount(userId),
    );
    await _writeProfile(profile);
    await _ensureGlobalMemory(userId);
    return profile;
  }

  /// Reads the name back out of the account record.
  ///
  /// Mirrors the trigger, which reads it from `auth.users.raw_user_meta_data` —
  /// [LocalAuthService] keeps it in the same place relative to the account, so
  /// a registered name survives on both backends rather than only on Supabase.
  String? _displayNameFromAccount(String userId) {
    for (final entry in _store.readTable(LocalStore.usersKey).values) {
      final record = Map<String, dynamic>.from(entry as Map);
      if (record['id'] != userId) continue;
      final name = (record['display_name'] as String?)?.trim();
      return (name == null || name.isEmpty) ? null : name;
    }
    return null;
  }

  Future<void> _writeProfile(UserProfile profile) async {
    final rows = _store.readTable(LocalStore.profilesKey);
    rows[profile.id] = {
      ...profile.toJson(),
      'created_at': profile.createdAt.toIso8601String(),
      'updated_at': profile.updatedAt.toIso8601String(),
    };
    await _store.writeTable(LocalStore.profilesKey, rows);
  }

  Future<void> _ensureGlobalMemory(String userId) async {
    final existing = await fetchMemory(userId);
    if (existing != null) return;
    await saveMemory(userId: userId, summary: '');
  }

  @override
  Future<UserProfile> saveProfile(UserProfile profile) async {
    final updated = profile.copyWith();
    await _writeProfile(updated);
    return updated;
  }

  // --- chats ---------------------------------------------------------------

  @override
  Future<List<Chat>> fetchChats(String userId) async {
    final chats = _rows(LocalStore.chatsKey)
        .where((row) => row['user_id'] == userId)
        .map(Chat.fromJson)
        .toList();
    // Falls back to creation order when two chats share an updated_at, which a
    // coarse clock makes likely for chats started moments apart. Without the
    // tie-break the list would shuffle between reads.
    chats.sort((a, b) {
      final byActivity = b.updatedAt.compareTo(a.updatedAt);
      return byActivity != 0 ? byActivity : b.createdAt.compareTo(a.createdAt);
    });
    return chats;
  }

  @override
  Future<Chat?> fetchChat(String chatId) async {
    final row = _store.readTable(LocalStore.chatsKey)[chatId];
    return row == null
        ? null
        : Chat.fromJson(Map<String, dynamic>.from(row as Map));
  }

  @override
  Future<Chat> createChat({
    required String userId,
    required ChatCategory category,
    String? title,
  }) async {
    final now = DateTime.now().toUtc();
    final chat = Chat(
      id: newUuidV4(),
      userId: userId,
      category: category,
      title: title,
      createdAt: now,
      updatedAt: now,
    );
    await _writeChat(chat);
    return chat;
  }

  Future<void> _writeChat(Chat chat) async {
    final rows = _store.readTable(LocalStore.chatsKey);
    rows[chat.id] = {
      ...chat.toJson(),
      'created_at': chat.createdAt.toIso8601String(),
      'updated_at': chat.updatedAt.toIso8601String(),
    };
    await _store.writeTable(LocalStore.chatsKey, rows);
  }

  @override
  Future<Chat> saveChat(Chat chat) async {
    final existing = await fetchChat(chat.id);
    if (existing == null) throw const DataFailure('That chat no longer exists.');
    final updated = chat.copyWith();
    await _writeChat(updated);
    return updated;
  }

  @override
  Future<void> deleteChat(String chatId) async {
    final chats = _store.readTable(LocalStore.chatsKey)..remove(chatId);
    await _store.writeTable(LocalStore.chatsKey, chats);

    // Stands in for the ON DELETE CASCADE on messages.chat_id.
    final messages = _store.readTable(LocalStore.messagesKey)
      ..removeWhere((_, row) => (row as Map)['chat_id'] == chatId);
    await _store.writeTable(LocalStore.messagesKey, messages);
  }

  /// Mirrors [SupabaseDataService.searchChats]: title matches first, then chats
  /// whose `answer_text` contains the term, each newest-first, deduplicated.
  ///
  /// The Supabase side does this in two indexed queries; here it is two passes
  /// over what is already in memory, which at one device's worth of chats is
  /// the same thing.
  @override
  Future<List<ChatSearchHit>> searchChats(String userId, String query) async {
    final term = query.trim();
    final chats = await fetchChats(userId);
    if (term.isEmpty) {
      return chats.map((c) => ChatSearchHit(chat: c)).toList();
    }

    final lowered = term.toLowerCase();
    final hits = <String, ChatSearchHit>{};

    for (final chat in chats) {
      if ((chat.title ?? '').toLowerCase().contains(lowered)) {
        hits[chat.id] = ChatSearchHit(chat: chat);
      }
    }
    for (final chat in chats) {
      if (hits.containsKey(chat.id)) continue;
      for (final message in await fetchMessages(chat.id)) {
        final excerpt = excerptAround(message.answerText ?? '', term);
        if (excerpt != null) {
          hits[chat.id] = ChatSearchHit(chat: chat, excerpt: excerpt);
          break;
        }
      }
    }
    return hits.values.toList();
  }

  // --- messages ------------------------------------------------------------

  @override
  Future<List<Message>> fetchMessages(String chatId) async {
    final messages = _rows(LocalStore.messagesKey)
        .where((row) => row['chat_id'] == chatId)
        .map(Message.fromJson)
        .toList();
    messages.sort((a, b) => a.seq.compareTo(b.seq));
    return messages;
  }

  @override
  Future<Message> addMessage({
    required String chatId,
    required MessageType type,
    String? questionText,
    String? answerText,
    Map<String, dynamic> metadata = const {},
  }) async {
    final existing = await fetchMessages(chatId);
    final nextSeq = existing.isEmpty ? 1 : existing.last.seq + 1;

    final message = Message(
      id: newUuidV4(),
      chatId: chatId,
      seq: nextSeq,
      type: type,
      questionText: questionText,
      answerText: answerText,
      metadata: metadata,
      createdAt: DateTime.now().toUtc(),
    );
    await _writeMessage(message);

    // Mirrors the updated_at bump the Supabase path relies on for ordering.
    final chat = await fetchChat(chatId);
    if (chat != null) await _writeChat(chat.copyWith());

    return message;
  }

  Future<void> _writeMessage(Message message) async {
    final rows = _store.readTable(LocalStore.messagesKey);
    rows[message.id] = {
      ...message.toJson(),
      'created_at': message.createdAt.toIso8601String(),
    };
    await _store.writeTable(LocalStore.messagesKey, rows);
  }

  @override
  Future<Message> saveMessage(Message message) async {
    // Checked rather than blind-written: the Supabase path updates by id and
    // fails when nothing matches, so writing a deleted message back into
    // existence here would make the backends disagree.
    if (!_store.readTable(LocalStore.messagesKey).containsKey(message.id)) {
      throw const DataFailure('That message no longer exists.');
    }
    await _writeMessage(message);
    return message;
  }

  // --- memory --------------------------------------------------------------

  @override
  Future<UserMemory?> fetchMemory(String userId, {ChatCategory? category}) async {
    final wanted = category?.wireValue;
    for (final row in _rows(LocalStore.memoryKey)) {
      if (row['user_id'] == userId && row['category'] == wanted) {
        return UserMemory.fromJson(row);
      }
    }
    return null;
  }

  @override
  Future<List<UserMemory>> fetchAllMemory(String userId) async =>
      _rows(LocalStore.memoryKey)
          .where((row) => row['user_id'] == userId)
          .map(UserMemory.fromJson)
          .toList();

  @override
  Future<UserMemory> saveMemory({
    required String userId,
    ChatCategory? category,
    required String summary,
    List<dynamic> facts = const [],
  }) async {
    final existing = await fetchMemory(userId, category: category);
    final now = DateTime.now().toUtc();

    final memory = UserMemory(
      id: existing?.id ?? newUuidV4(),
      userId: userId,
      category: category,
      summary: summary,
      facts: facts,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );

    final rows = _store.readTable(LocalStore.memoryKey);
    rows[memory.id] = {
      ...memory.toJson(),
      'created_at': memory.createdAt.toIso8601String(),
      'updated_at': memory.updatedAt.toIso8601String(),
    };
    await _store.writeTable(LocalStore.memoryKey, rows);

    return memory;
  }
}
