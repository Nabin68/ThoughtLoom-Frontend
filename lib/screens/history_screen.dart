//history_screen.dart

import 'dart:async';

import 'package:flutter/material.dart';

import '../models/chat.dart';
import '../services/backend.dart';
import '../services/data_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_background.dart';
import '../widgets/error_banner.dart';
import 'chat_transcript_screen.dart';
import 'continued_chat_screen.dart';

/// Everything the user has thought through, newest first, and a way to find one.
///
/// ### The read is direct
///
/// Straight to Supabase under RLS — no FastAPI. The policies already scope every
/// row to its owner, so routing a list of the user's own chats through a service
/// holding a key that bypasses those policies would be adding an authorisation
/// problem in order to solve nothing. Search is the same two ILIKE queries, for
/// the same reason. See [DataService.searchChats].
///
/// ### What a tap does depends on where the chat got to
///
/// Prompt 3 left this open. The answer follows from `status`, because status is
/// already the record of how far a chat got:
///
///  * `awaiting_follow_up` — the advice landed and they closed the app on it.
///    They are mid-conversation. Tapping resumes it.
///  * anything else — a record to read back. Completed chats are the point;
///    an unfinished one opens too, and honestly shows the little it holds.
///
/// Resuming an *unfinished* intake is deliberately not offered. The scripted
/// questions branch on a profile that may have changed since, so "carry on from
/// question three" would mean rebuilding a list that no longer matches what was
/// asked — a wrong-data bug in exchange for saving four taps on a chat the user
/// walked away from.
///
/// [userId] is passed in rather than read from `SessionScope`: this is a pushed
/// route, and `SessionScope` lives inside `AuthGate`, which is the *home* route.
/// Pushed routes stack beside it, not underneath, so `SessionScope.of` throws
/// here.
class HistoryScreen extends StatefulWidget {
  final String userId;

  const HistoryScreen({super.key, required this.userId});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _search = TextEditingController();

  List<ChatSearchHit>? _hits;
  String? _error;
  Timer? _debounce;

  /// Which query the in-flight load is for, so a slow response for "bro" cannot
  /// land after a fast one for "brother" and put the wrong list on screen.
  String _wanted = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final query = _search.text;
    _wanted = query;
    try {
      final hits = await Backend.data.searchChats(widget.userId, query);
      if (!mounted || _wanted != query) return;
      setState(() {
        _hits = hits;
        _error = null;
      });
    } on DataFailure catch (e) {
      if (!mounted || _wanted != query) return;
      setState(() => _error = e.message);
    }
  }

  /// Search runs as they type, but not on every keystroke: each one is two
  /// queries, and a seven-letter word would fire fourteen to show the answer to
  /// the last one.
  void _onQueryChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _load);
    setState(() {}); // The clear button appears with the first character.
  }

  Future<void> _open(Chat chat) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => chat.status == ChatStatus.awaitingFollowUp
            ? ContinuedChatScreen(chat: chat)
            : ChatTranscriptScreen(chat: chat),
      ),
    );
    // Reloaded on return because both destinations can change what this list
    // shows: leaving a resumed chat completes it, and opening an untitled one
    // asks for its title back.
    if (mounted) _load();
  }

  Future<void> _confirmDelete(Chat chat) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _DeleteDialog(chat: chat),
    );
    if (confirmed != true || !mounted) return;

    try {
      await Backend.data.deleteChat(chat.id);
      if (!mounted) return;
      // Dropped from the list in place rather than by reloading: the row is
      // gone from the database, and a spinner over the whole list to prove it
      // would be a worse answer than it simply not being there.
      setState(() => _hits?.removeWhere((h) => h.chat.id == chat.id));
    } on DataFailure catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;

    return AppBackground(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.06),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: screenHeight * 0.02),
            Row(
              children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: EdgeInsets.only(right: screenWidth * 0.03),
                    child: Icon(
                      Icons.arrow_back,
                      size: screenWidth * 0.055,
                      color: AppTheme.textLight,
                    ),
                  ),
                ),
                Text(
                  'Your chats',
                  style: TextStyle(
                    fontSize: screenWidth * 0.038,
                    color: AppTheme.textLight,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            SizedBox(height: screenHeight * 0.02),
            _SearchField(
              controller: _search,
              onChanged: _onQueryChanged,
              onClear: () {
                _search.clear();
                _onQueryChanged();
              },
            ),
            SizedBox(height: screenHeight * 0.02),
            if (_error != null) ...[
              ErrorBanner(message: _error!),
              SizedBox(height: screenHeight * 0.015),
            ],
            Expanded(child: _buildList()),
          ],
        ),
      ),
    );
  }

  Widget _buildList() {
    final hits = _hits;
    if (hits == null) {
      return const Center(
        child: CircularProgressIndicator(
          strokeWidth: 3,
          valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primary),
        ),
      );
    }

    if (hits.isEmpty) {
      return _search.text.trim().isEmpty
          ? const _NoChatsYet()
          : _NoMatches(query: _search.text.trim());
    }

    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      itemCount: hits.length,
      itemBuilder: (context, i) => _ChatRow(
        hit: hits[i],
        onTap: () => _open(hits[i].chat),
        onLongPress: () => _confirmDelete(hits[i].chat),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onChanged;
  final VoidCallback onClear;

  const _SearchField({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardBg.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(AppTheme.pillRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            offset: const Offset(0, 4),
            blurRadius: 12,
          ),
        ],
      ),
      child: Row(
        children: [
          SizedBox(width: screenWidth * 0.045),
          Icon(
            Icons.search,
            size: screenWidth * 0.05,
            color: AppTheme.textLight,
          ),
          SizedBox(width: screenWidth * 0.025),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: (_) => onChanged(),
              textInputAction: TextInputAction.search,
              style: TextStyle(
                fontSize: screenWidth * 0.04,
                color: AppTheme.textOnCard,
              ),
              decoration: InputDecoration(
                // Says what it searches. "Search" alone would leave the user
                // guessing whether it matches only the names, which are ours
                // rather than theirs.
                hintText: 'Search what you said, or a title',
                hintStyle: TextStyle(
                  fontSize: screenWidth * 0.038,
                  color: AppTheme.textLight.withValues(alpha: 0.5),
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  vertical: screenWidth * 0.04,
                ),
              ),
            ),
          ),
          if (controller.text.isNotEmpty)
            GestureDetector(
              onTap: onClear,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.04),
                child: Icon(
                  Icons.close,
                  size: screenWidth * 0.045,
                  color: AppTheme.textLight,
                ),
              ),
            )
          else
            SizedBox(width: screenWidth * 0.045),
        ],
      ),
    );
  }
}

class _NoChatsYet extends StatelessWidget {
  const _NoChatsYet();

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    // Scrollable, like the other full-height messages in the app: everything
    // here is sized off screen *width*, so a short or landscape viewport can
    // leave the column taller than the space it was given.
    return Center(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Padding(
          padding: EdgeInsets.only(bottom: screenWidth * 0.2),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.forum_outlined,
                size: screenWidth * 0.12,
                color: AppTheme.textLight.withValues(alpha: 0.4),
              ),
              SizedBox(height: screenWidth * 0.04),
              Text(
                'Nothing here yet',
                style: TextStyle(
                  fontSize: screenWidth * 0.05,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textDark,
                  letterSpacing: -0.3,
                ),
              ),
              SizedBox(height: screenWidth * 0.02),
              Text(
                'Anything you think through will show up here.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: screenWidth * 0.038,
                  color: AppTheme.textLight,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoMatches extends StatelessWidget {
  final String query;

  const _NoMatches({required this.query});

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Center(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          screenWidth * 0.06,
          0,
          screenWidth * 0.06,
          screenWidth * 0.2,
        ),
        child: Text(
          'Nothing matches "$query".',
          textAlign: TextAlign.center,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: screenWidth * 0.042,
            color: AppTheme.textLight,
            height: 1.4,
          ),
        ),
      ),
    );
  }
}

class _DeleteDialog extends StatelessWidget {
  final Chat chat;

  const _DeleteDialog({required this.chat});

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return AlertDialog(
      backgroundColor: AppTheme.cardBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text(
        'Delete this chat?',
        style: TextStyle(
          fontSize: screenWidth * 0.05,
          fontWeight: FontWeight.w700,
          color: AppTheme.textOnCard,
          letterSpacing: -0.3,
        ),
      ),
      content: Text(
        // Says what actually goes, because it is more than the row they are
        // looking at and none of it comes back.
        '"${chat.title ?? chat.category.label}" and everything said in it. '
        'This cannot be undone.',
        style: TextStyle(
          fontSize: screenWidth * 0.038,
          color: AppTheme.textLight,
          height: 1.4,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(
            'Keep it',
            style: TextStyle(
              fontSize: screenWidth * 0.038,
              color: AppTheme.textLight,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(
            'Delete',
            style: TextStyle(
              fontSize: screenWidth * 0.038,
              color: AppTheme.dangerText,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _ChatRow extends StatelessWidget {
  final ChatSearchHit hit;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _ChatRow({
    required this.hit,
    required this.onTap,
    required this.onLongPress,
  });

  Chat get chat => hit.chat;

  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  /// Recent chats get a relative date, older ones a real one.
  ///
  /// "3 days ago" is what someone wants for this week and useless for last year;
  /// "14 March" is the reverse. The switch is at a week, which is roughly where
  /// people stop counting days.
  String get _when {
    final at = chat.updatedAt.toLocal();
    final now = DateTime.now();
    final age = now.difference(at);

    if (age.inMinutes < 1) return 'Just now';
    if (age.inHours < 1) return '${age.inMinutes}m ago';
    if (age.inDays < 1) return '${age.inHours}h ago';
    if (age.inDays == 1) return 'Yesterday';
    if (age.inDays < 7) return '${age.inDays} days ago';

    final month = _months[at.month - 1];
    return at.year == now.year
        ? '${at.day} $month'
        : '${at.day} $month ${at.year}';
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final unfinished = chat.status == ChatStatus.inProgress;
    final excerpt = hit.excerpt;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: EdgeInsets.only(bottom: screenWidth * 0.03),
        padding: EdgeInsets.symmetric(
          horizontal: screenWidth * 0.05,
          vertical: screenWidth * 0.04,
        ),
        decoration: BoxDecoration(
          color: AppTheme.cardBg.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(AppTheme.pillRadius),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              offset: const Offset(0, 4),
              blurRadius: 12,
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    // An untitled chat falls back to its category: either the
                    // titler has not run yet, or the chat never got far enough
                    // to have a topic. Both read honestly as "Education".
                    chat.title ?? chat.category.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: screenWidth * 0.042,
                      color: AppTheme.textOnCard,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.2,
                      height: 1.3,
                    ),
                  ),
                  SizedBox(height: screenWidth * 0.015),
                  Row(
                    children: [
                      _CategoryChip(chat: chat),
                      SizedBox(width: screenWidth * 0.02),
                      Expanded(
                        child: Text(
                          unfinished ? '$_when · Unfinished' : _when,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: screenWidth * 0.032,
                            color: AppTheme.textLight,
                          ),
                        ),
                      ),
                    ],
                  ),
                  // Only on a content match. Showing the row's own first line
                  // when the title matched would be noise dressed as evidence.
                  if (excerpt != null) ...[
                    SizedBox(height: screenWidth * 0.025),
                    Text(
                      excerpt,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: screenWidth * 0.033,
                        color: AppTheme.textLight,
                        height: 1.4,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            SizedBox(width: screenWidth * 0.02),
            Icon(
              Icons.arrow_forward,
              size: screenWidth * 0.04,
              color: AppTheme.textLight.withValues(alpha: 0.6),
            ),
          ],
        ),
      ),
    );
  }
}

/// The category, as a quiet chip rather than a word in the subtitle — it is a
/// fixed label from a set of four, and reads faster as a shape than as prose.
class _CategoryChip extends StatelessWidget {
  final Chat chat;

  const _CategoryChip({required this.chat});

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: screenWidth * 0.02,
        vertical: screenWidth * 0.005,
      ),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        chat.category.label,
        style: TextStyle(
          fontSize: screenWidth * 0.028,
          color: AppTheme.textOnCard,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
