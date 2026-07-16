//data_service.dart

import '../models/chat.dart';
import '../models/chat_category.dart';
import '../models/message.dart';
import '../models/user_memory.dart';
import '../models/user_profile.dart';

/// A failure worth showing the user. [message] is already user-facing.
class DataFailure implements Exception {
  final String message;

  const DataFailure(this.message);

  @override
  String toString() => message;
}

/// One chat that matched a search, and why it matched.
///
/// [excerpt] is the bit of the conversation the query was found in, or null when
/// the title alone matched. It exists so a result list can show its working: a
/// row that says only "Lending Ravi money" leaves the user guessing which of the
/// six words they typed put it there, and whether the match is the one they
/// meant.
class ChatSearchHit {
  final Chat chat;
  final String? excerpt;

  const ChatSearchHit({required this.chat, this.excerpt});
}

/// A window of [text] around the first occurrence of [term], for a result row.
///
/// Lives here rather than in either implementation because both must produce the
/// same thing — the two backends share one contract, and a search result that
/// read differently on device than against Supabase would be a difference the
/// tests could not see, since they only ever run against one of them.
///
/// Returns null when [term] is not in [text], which is how a caller tells a
/// title-only match from a content match.
String? excerptAround(String text, String term, {int before = 32, int after = 96}) {
  final haystack = text.trim();
  final at = haystack.toLowerCase().indexOf(term.trim().toLowerCase());
  if (at == -1) return null;

  final start = (at - before).clamp(0, haystack.length);
  final end = (at + term.trim().length + after).clamp(0, haystack.length);
  final window = haystack.substring(start, end).replaceAll(RegExp(r'\s+'), ' ');

  // Ellipses only where something was actually cut, so a short message reads as
  // the whole thing it is rather than as a fragment.
  return '${start > 0 ? '...' : ''}$window${end < haystack.length ? '...' : ''}';
}

/// Reads and writes for every table the app owns.
///
/// Implementations must not leak backend types (no Supabase `PostgrestException`
/// escaping into callers) — throw [DataFailure] instead.
abstract class DataService {
  // --- profiles ------------------------------------------------------------

  Future<UserProfile?> fetchProfile(String userId);

  /// Returns the profile, creating an empty one if it is somehow absent.
  /// Supabase provisions it via trigger at sign-up; this makes the app correct
  /// even if that trigger has not been applied yet.
  Future<UserProfile> ensureProfile(String userId);

  Future<UserProfile> saveProfile(UserProfile profile);

  // --- chats ---------------------------------------------------------------

  /// Newest activity first.
  Future<List<Chat>> fetchChats(String userId);

  Future<Chat?> fetchChat(String chatId);

  Future<Chat> createChat({
    required String userId,
    required ChatCategory category,
    String? title,
  });

  Future<Chat> saveChat(Chat chat);

  /// Puts a finished chat back into the conversation.
  ///
  /// Two writes that have to happen together, which is why this is its own
  /// method rather than a [saveChat] with a different status:
  ///
  ///  * `status` back to `awaiting_follow_up`, so the chat is live again; and
  ///  * **`memory_merged_at` back to null**, which is the load-bearing half.
  ///    Completing a chat folds it into the user's long-term memory *once* —
  ///    `memory_merged_at` is the flag that makes that idempotent. Reopening a
  ///    chat and saying something new to it would otherwise never reach memory
  ///    at all: the merge would be skipped as already done, silently, forever.
  ///    Clearing it is safe because the merge is a whole-memory rewrite that
  ///    updates rather than appends, so re-running it over a longer version of
  ///    the same conversation is exactly what should happen.
  ///
  /// `memory_merged_at` is deliberately not on the [Chat] model: nothing in the
  /// app reads it, and the only write it will ever need is this one.
  Future<Chat> reopenChat(String chatId);

  /// Cascades to the chat's messages.
  Future<void> deleteChat(String chatId);

  /// Chats matching [query], best match first, newest first within that.
  ///
  /// Case-insensitive substring match against the chat's title *and* against
  /// what was actually said in it — every message type, both what was asked and
  /// what was answered. A user looking for the conversation about their brother
  /// will not remember what we called it.
  ///
  /// Title matches rank above content matches: a query in the title is a query
  /// about what the chat *was*, which is the stronger claim.
  ///
  /// An empty [query] returns every chat, exactly as [fetchChats] would.
  Future<List<ChatSearchHit>> searchChats(String userId, String query);

  // --- messages ------------------------------------------------------------

  /// In [Message.seq] order.
  Future<List<Message>> fetchMessages(String chatId);

  /// Appends at the next sequence number and bumps the parent chat's
  /// `updated_at`, keeping the chat list ordered by real activity.
  Future<Message> addMessage({
    required String chatId,
    required MessageType type,
    String? questionText,
    String? answerText,
    Map<String, dynamic> metadata = const {},
  });

  Future<Message> saveMessage(Message message);

  /// Removes one turn.
  ///
  /// Exists for a narrow case: the relationship intake words its later questions
  /// around the person the first one established, so going back and changing
  /// "My girlfriend" to "My parents" leaves rows below it answering questions
  /// that were never asked of this chat. Those rows are wrong, not merely stale
  /// — the model reads the transcript as fact — so the flow deletes them rather
  /// than leaving them to be reasoned over. See [IntakeFlowScreen].
  Future<void> deleteMessage(String messageId);

  // --- memory --------------------------------------------------------------

  /// Omit [category] for the cross-topic row.
  Future<UserMemory?> fetchMemory(String userId, {ChatCategory? category});

  /// The global row plus every category row.
  Future<List<UserMemory>> fetchAllMemory(String userId);

  Future<UserMemory> saveMemory({
    required String userId,
    ChatCategory? category,
    required String summary,
    List<dynamic> facts = const [],
  });
}
