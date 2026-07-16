//history_screen.dart

import 'dart:async';

import 'package:flutter/material.dart';

import '../models/chat.dart';
import '../services/backend.dart';
import '../services/data_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_background.dart';
import '../widgets/app_button.dart';
import '../widgets/app_card.dart';
import '../widgets/app_header.dart';
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
/// ### What a tap does
///
/// It follows `status`, because status is already the record of how far a chat
/// got — but the rule has changed. It used to be:
///
///   awaiting_follow_up -> resume;  anything else -> read-only
///
/// which made `completed` — the status of every chat anyone ever finished
/// properly — a dead end. The advice landed, the user left, and the conversation
/// could never be picked up again. That is backwards: a finished chat is the one
/// most likely to be worth returning to, because life moved and the advice can
/// now be tested against it.
///
/// The rule is now "did this chat ever produce advice?":
///
///  * `awaiting_follow_up` or `completed` — there is a recommendation in it.
///    Tapping carries on the conversation; [ContinuedChatScreen] reopens a
///    completed one properly, and links to the full transcript.
///  * `in_progress` — abandoned before any advice. There is nothing to continue,
///    so it opens read-only and honestly shows the little it holds.
///
/// Resuming an unfinished *intake* is still not offered. The scripted questions
/// branch on a profile that may have changed since — and now on earlier answers
/// too — so "carry on from question three" means rebuilding a list that no
/// longer matches what was asked.
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
        builder: (_) => chat.status == ChatStatus.inProgress
            ? ChatTranscriptScreen(chat: chat)
            : ContinuedChatScreen(chat: chat),
      ),
    );
    // Reloaded on return because both destinations can change what this list
    // shows: leaving a resumed chat completes it and may retitle it, and opening
    // an untitled one asks for its title back.
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
      // Dropped from the list in place rather than by reloading: the row is gone
      // from the database, and a spinner over the whole list to prove it would be
      // a worse answer than it simply not being there.
      setState(() => _hits?.removeWhere((h) => h.chat.id == chat.id));
    } on DataFailure catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppBackground(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppHeader(
            title: 'Your chats',
            subtitle: 'Everything you have thought through',
            onBack: () => Navigator.pop(context),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              AppTheme.s5,
              AppTheme.s2,
              AppTheme.s5,
              AppTheme.s3,
            ),
            child: _SearchField(
              controller: _search,
              onChanged: _onQueryChanged,
              onClear: () {
                _search.clear();
                _onQueryChanged();
              },
            ),
          ),
          if (_error != null) ...[
            Padding(
              padding: EdgeInsets.symmetric(horizontal: AppTheme.s5),
              child: ErrorBanner(message: _error!),
            ),
            SizedBox(height: AppTheme.s3),
          ],
          Expanded(child: _buildList()),
        ],
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
      padding: EdgeInsets.fromLTRB(
        AppTheme.s5,
        0,
        AppTheme.s5,
        AppTheme.s8,
      ),
      itemCount: hits.length,
      itemBuilder: (context, i) => _ChatRow(
        hit: hits[i],
        onTap: () => _open(hits[i].chat),
        onDelete: () => _confirmDelete(hits[i].chat),
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
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.pillRadius),
        boxShadow: AppTheme.shadowSoft,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.cardBg,
          borderRadius: BorderRadius.circular(AppTheme.pillRadius),
          border: Border.all(color: AppTheme.border),
        ),
        child: Row(
          children: [
            SizedBox(width: AppTheme.s4),
            Icon(Icons.search_rounded, size: 19, color: AppTheme.textFaint),
            SizedBox(width: AppTheme.s2),
            Expanded(
              child: TextField(
                controller: controller,
                onChanged: (_) => onChanged(),
                textInputAction: TextInputAction.search,
                style: AppTheme.body(context),
                decoration: InputDecoration(
                  // Says what it searches. "Search" alone would leave the user
                  // guessing whether it matches only the names, which are ours
                  // rather than theirs.
                  hintText: 'Search what you said, or a title',
                  hintStyle:
                      AppTheme.body(context).copyWith(color: AppTheme.textFaint),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: AppTheme.s4),
                ),
              ),
            ),
            if (controller.text.isNotEmpty)
              HeaderIconButton(
                icon: Icons.close_rounded,
                tooltip: 'Clear',
                onPressed: onClear,
              )
            else
              SizedBox(width: AppTheme.s4),
          ],
        ),
      ),
    );
  }
}

class _NoChatsYet extends StatelessWidget {
  const _NoChatsYet();

  @override
  Widget build(BuildContext context) {
    // Scrollable, like the other full-height messages in the app: a short or
    // landscape viewport can leave the column taller than the space it was given.
    return Center(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            AppTheme.s6,
            0,
            AppTheme.s6,
            AppTheme.s10 * 2,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.forum_outlined,
                size: 44,
                color: AppTheme.textFaint.withValues(alpha: 0.5),
              ),
              SizedBox(height: AppTheme.s4),
              Text('Nothing here yet', style: AppTheme.title(context)),
              SizedBox(height: AppTheme.s2),
              Text(
                'Anything you think through will show up here.',
                textAlign: TextAlign.center,
                style: AppTheme.secondary(context),
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
    return Center(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppTheme.s6,
          0,
          AppTheme.s6,
          AppTheme.s10 * 2,
        ),
        child: Text(
          'Nothing matches "$query".',
          textAlign: TextAlign.center,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: AppTheme.secondary(context),
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
    return AlertDialog(
      backgroundColor: AppTheme.cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.rLg),
      ),
      title: Text('Delete this chat?', style: AppTheme.heading(context)),
      content: Text(
        // Says what actually goes, because it is more than the row they are
        // looking at and none of it comes back.
        '"${chat.title ?? chat.category.label}" and everything said in it. '
        'This cannot be undone.',
        style: AppTheme.secondary(context),
      ),
      actionsPadding: EdgeInsets.fromLTRB(
        AppTheme.s4,
        0,
        AppTheme.s4,
        AppTheme.s4,
      ),
      actions: [
        AppButton.quiet(
          label: 'Keep it',
          onPressed: () => Navigator.pop(context, false),
        ),
        SizedBox(width: AppTheme.s2),
        AppButton.danger(
          label: 'Delete',
          expand: false,
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
    );
  }
}

class _ChatRow extends StatelessWidget {
  final ChatSearchHit hit;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _ChatRow({
    required this.hit,
    required this.onTap,
    required this.onDelete,
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
    final unfinished = chat.status == ChatStatus.inProgress;
    final excerpt = hit.excerpt;

    return Padding(
      padding: EdgeInsets.only(bottom: AppTheme.s3),
      child: AppCard(
        onTap: onTap,
        // Long-press still works and is what most people will find first, but it
        // is no longer the *only* way: an action nobody can see is an action that
        // does not exist, and these rows accumulate — the dashboard opens a chat
        // on the category tap, so every mis-tap is a row to clear.
        onLongPress: onDelete,
        padding: EdgeInsets.fromLTRB(
          AppTheme.s4,
          AppTheme.s4,
          AppTheme.s2,
          AppTheme.s4,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    // An untitled chat falls back to its category: either the
                    // titler has not run yet, or the chat never got far enough to
                    // have a topic. Both read honestly as "Education".
                    chat.title ?? chat.category.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.label(context).copyWith(
                      fontSize: 15.5 * AppTheme.scaleOf(context),
                      height: 1.3,
                    ),
                  ),
                  SizedBox(height: AppTheme.s2),
                  Row(
                    children: [
                      AppChip(label: chat.category.label),
                      SizedBox(width: AppTheme.s2),
                      if (unfinished) ...[
                        const AppChip(
                          label: 'Unfinished',
                          color: AppTheme.accentDeep,
                        ),
                        SizedBox(width: AppTheme.s2),
                      ],
                      Flexible(
                        child: Text(
                          _when,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.meta(context),
                        ),
                      ),
                    ],
                  ),
                  // Only on a content match. Showing the row's own first line
                  // when the title matched would be noise dressed as evidence.
                  if (excerpt != null) ...[
                    SizedBox(height: AppTheme.s2),
                    Text(
                      excerpt,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.meta(context).copyWith(
                        fontStyle: FontStyle.italic,
                        color: AppTheme.textLight,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            SizedBox(width: AppTheme.s1),
            HeaderIconButton(
              icon: Icons.delete_outline_rounded,
              tooltip: 'Delete this chat',
              color: AppTheme.textFaint,
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}
