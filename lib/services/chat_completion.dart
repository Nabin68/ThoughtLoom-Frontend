//chat_completion.dart

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/chat.dart';
import 'backend.dart';

/// Ends a chat, from wherever the user chose to leave it.
///
/// Two things have to happen, and they are deliberately not the same kind of
/// thing:
///
///  * **The status write** is direct Flutter → Supabase. It is a flag on a row
///    the user owns, RLS covers it, and it is what the history screen reads a
///    second later.
///  * **The naming and the memory merge** are the API's, because they are model
///    calls that need the service-role key. They are *not awaited*: the user has
///    pressed Back, and the request only has to reach the server — everything
///    after that happens there, in a background task, whether or not this app is
///    still running a second from now.
///
/// Never throws. The user asked to leave; refusing because a status write failed
/// would be absurd, and every failure here is recoverable. A chat left at
/// `awaiting_follow_up` renders honestly in history, and one that reaches
/// `completed` without a title gets asked about again the next time it is
/// opened.
Future<void> completeChat(Chat chat) async {
  // Fired before the status write, so the request is on the wire while that
  // round trip happens rather than after it. Nothing downstream needs its
  // result — the server owns the rest.
  if (Backend.usingSupabase) {
    unawaited(
      Backend.ai.completeChat(chatId: chat.id).catchError((Object e) {
        // Worth a line in the log and nothing more: the title and the memory
        // are both best-effort, and the user is already gone. The API re-offers
        // both the next time this chat is opened.
        debugPrint('ThoughtLoom: could not close chat ${chat.id} — $e');
      }),
    );
  }

  // Skipped when it is already true, because this write is not free: it trips
  // the touch_updated_at trigger, and updated_at is what orders history. A chat
  // finished in March, reopened today only to backfill a title that never
  // landed, would jump to the top of the list reading "Just now".
  if (chat.status == ChatStatus.completed) return;

  try {
    await Backend.data.saveChat(chat.copyWith(status: ChatStatus.completed));
  } catch (e) {
    // The API sets this too, from its own side, which is the backstop for
    // exactly this case.
    debugPrint('ThoughtLoom: could not mark chat ${chat.id} completed — $e');
  }
}
