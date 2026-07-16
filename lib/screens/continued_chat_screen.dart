//continued_chat_screen.dart

import 'package:flutter/material.dart';

import '../models/chat.dart';
import '../models/message.dart';
import '../services/ai_service.dart';
import '../services/backend.dart';
import '../services/chat_completion.dart';
import '../theme/app_theme.dart';
import '../widgets/app_background.dart';
import '../widgets/app_header.dart';
import '../widgets/dictation.dart';
import '../widgets/error_banner.dart';
import '../widgets/rich_body.dart';
import 'chat_transcript_screen.dart';

/// The conversation after the recommendation — including one picked back up
/// weeks later.
///
/// ### Reopening a finished chat
///
/// History used to send anything that was not `awaiting_follow_up` to a
/// read-only transcript, which meant a *completed* chat — every chat anybody
/// ever finished properly — was a dead end. You could read what you were told
/// and had no way to say "that didn't work" or "something changed". The
/// conversation ended the moment it became useful to keep having.
///
/// Now any chat that got as far as advice opens here, whatever its status, and
/// [_reopenIfNeeded] puts a completed one back into the conversation before the
/// first new message lands. A chat that never reached advice still opens
/// read-only — there is nothing to continue, and the scripted intake cannot be
/// resumed safely (its questions branch on a profile, and now on answers, that
/// may both have changed since).
///
/// ### What is shown
///
/// The recommendation onward: the conversation the user is actually having. The
/// intake is how we got here, not part of it, and replaying twelve scripted
/// questions above the answer would bury it — the transcript screen exists for
/// anyone who wants the whole thing, and the header links to it.
class ContinuedChatScreen extends StatefulWidget {
  final Chat chat;

  const ContinuedChatScreen({super.key, required this.chat});

  @override
  State<ContinuedChatScreen> createState() => _ContinuedChatScreenState();
}

class _ContinuedChatScreenState extends State<ContinuedChatScreen> {
  final _composer = TextEditingController();
  final _scrollController = ScrollController();
  late final _dictation = DictationController(_composer)
    ..addListener(_onDictationChanged);

  final List<_Bubble> _bubbles = [];

  /// Tracked rather than read from the widget: reopening a completed chat
  /// changes its status, and leaving has to write the right one back.
  late Chat _chat = widget.chat;

  bool _loading = true;
  bool _sending = false;
  String? _error;

  /// Kept so a failed send can be retried with one tap instead of retyping.
  String? _failedMessage;

  @override
  void initState() {
    super.initState();
    _dictation.init();
    _backfill();
    _loadHistory();
  }

  /// Asks the API to finish closing this chat, if it never got that far.
  ///
  /// This used to live only in [ChatTranscriptScreen], which was where history
  /// sent a completed chat. It sends them here now, so the guarantee has to come
  /// too — otherwise the one path that recovers a chat whose titling never
  /// landed would have quietly disappeared along with the dead end it lived in.
  ///
  /// Titling and the memory merge run in a background task after the user leaves
  /// a chat, and the request that starts them can simply not arrive: the app was
  /// killed, the network was down, Render was cold. Opening the chat is the
  /// natural retry, and the API skips whichever half already ran.
  ///
  /// The status guard is what makes this safe to call on a screen the user is
  /// about to talk in: [completeChat] writes `completed`, which would be a lie
  /// about a chat sitting at `awaiting_follow_up` — but it skips that write when
  /// the chat is *already* completed, which is the only case this fires in.
  void _backfill() {
    if (_chat.title != null || _chat.status != ChatStatus.completed) return;
    // Not awaited: the title lands on the next visit to history, and blocking a
    // conversation the user asked to reopen on a model call would be a strange
    // thing to do to them.
    completeChat(_chat);
  }

  void _onDictationChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _dictation.removeListener(_onDictationChanged);
    _dictation.dispose();
    _composer.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    try {
      final messages = await Backend.data.fetchMessages(_chat.id);
      if (!mounted) return;
      setState(() {
        _bubbles
          ..clear()
          ..addAll(_toBubbles(messages));
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  /// The turns worth re-reading, in order.
  ///
  /// The recommendation and everything after it. The free-text description is
  /// the one earlier exception, because it is the thing they actually said in
  /// their own words — and it is what the advice was answering.
  List<_Bubble> _toBubbles(List<Message> messages) {
    final recommendationIndex =
        messages.indexWhere((m) => m.type == MessageType.recommendation);

    final bubbles = <_Bubble>[];
    for (var i = 0; i < messages.length; i++) {
      final message = messages[i];
      final text = (message.answerText ?? '').trim();
      if (text.isEmpty) continue;

      switch (message.type) {
        case MessageType.recommendation:
          bubbles.add(_Bubble(
            text: text,
            fromUser: false,
            headline: (message.metadata['headline'] as String? ?? '').trim(),
          ));
        case MessageType.assistantReply:
          bubbles.add(_Bubble(text: text, fromUser: false));
        case MessageType.freeText:
          // Only the ones after the recommendation are part of this
          // conversation. The original description came before it.
          if (recommendationIndex != -1 && i > recommendationIndex) {
            bubbles.add(_Bubble(text: text, fromUser: true));
          }
        case MessageType.intake:
        case MessageType.adaptiveQuestion:
          break;
      }
    }
    return bubbles;
  }

  /// Scrolls to the newest message.
  ///
  /// `jumpTo(0)` rather than `maxScrollExtent` because the list is reversed —
  /// see the note on the ListView. Offset zero is the bottom.
  void _toNewest({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      if (animate) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOut,
        );
      } else {
        _scrollController.jumpTo(0);
      }
    });
  }

  /// Puts a finished chat back into the conversation before its first new turn.
  ///
  /// Best-effort: if the write fails the message still sends and the reply still
  /// arrives, because refusing to talk to someone over a status flag would be
  /// absurd. The cost of it failing is that this chat's memory merge does not
  /// re-run — which is what [completeChat] would have skipped anyway.
  Future<void> _reopenIfNeeded() async {
    if (_chat.status != ChatStatus.completed) return;
    try {
      final reopened = await Backend.data.reopenChat(_chat.id);
      if (mounted) setState(() => _chat = reopened);
    } catch (e) {
      debugPrint('ThoughtLoom: could not reopen chat ${_chat.id} — $e');
    }
  }

  Future<void> _send({String? retrying}) async {
    final text = retrying ?? _composer.text.trim();
    if (text.isEmpty || _sending) return;

    await _dictation.stop();
    if (!mounted) return;

    setState(() {
      _sending = true;
      _error = null;
      _failedMessage = null;
      // Shown immediately rather than after the round trip: a message that hangs
      // in a text box for thirty seconds feels like it was not sent.
      if (retrying == null) {
        _bubbles.add(_Bubble(text: text, fromUser: true));
        _composer.clear();
      }
    });
    _toNewest();

    await _reopenIfNeeded();
    if (!mounted) return;

    try {
      final reply = await Backend.ai.followUp(chatId: _chat.id, message: text);
      if (!mounted) return;
      setState(() {
        _bubbles.add(_Bubble(text: reply, fromUser: false));
        _sending = false;
      });
      _toNewest();
    } on AiFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = e.message;
        _failedMessage = e.retryable ? text : null;
      });
    }
  }

  /// Leaving ends the chat — see [completeChat], which also asks the API to name
  /// it and fold what it learned into the user's memory. Never throws: the user
  /// asked to leave, and a failed write must not trap them.
  Future<void> _finish() async {
    final navigator = Navigator.of(context);
    await completeChat(_chat);
    if (mounted) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _finish();
      },
      child: AppBackground(
        child: Column(
          children: [
            AppHeader(
              title: _chat.title ?? _chat.category.label,
              subtitle: 'Still talking',
              onBack: _finish,
              actions: [
                HeaderIconButton(
                  icon: Icons.receipt_long_outlined,
                  tooltip: 'The whole conversation',
                  // The full record, including the scripted opening this screen
                  // deliberately hides. Read-only, and it does not end the chat.
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      // No backfill: that exists to finish closing a chat opened
                      // from history, and this one is mid-conversation. Asking
                      // the API to close a chat the user is still typing into
                      // would be a strange thing to do to them.
                      builder: (_) =>
                          ChatTranscriptScreen(chat: _chat, backfill: false),
                    ),
                  ),
                ),
              ],
            ),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(AppTheme.primary),
                      ),
                    )
                  : _bubbles.isEmpty
                      ? const _NothingToContinue()
                      : _buildList(),
            ),
            if (_error != null)
              Padding(
                padding: EdgeInsets.fromLTRB(
                  AppTheme.s5,
                  0,
                  AppTheme.s5,
                  AppTheme.s2,
                ),
                child: Column(
                  children: [
                    ErrorBanner(message: _error!),
                    if (_failedMessage != null) ...[
                      SizedBox(height: AppTheme.s2),
                      TextButton(
                        onPressed: () => _send(retrying: _failedMessage),
                        child: Text(
                          'Try sending again',
                          style: AppTheme.label(context)
                              .copyWith(color: AppTheme.primary),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            _Composer(
              controller: _composer,
              dictation: _dictation,
              enabled: !_sending,
              onChanged: () => setState(() {}),
              onSend: _composer.text.trim().isEmpty || _sending ? null : _send,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList() {
    // reverse: true is what fixes the keyboard.
    //
    // The composer used to rise with the keyboard while the conversation sat
    // exactly where it was, so the message you were replying to went under the
    // keyboard the moment you started replying to it. That is not a scrolling
    // bug to paper over with a scroll-on-focus call — animating against a
    // keyboard that is itself still animating is a race nobody wins.
    //
    // A reversed list is anchored to its bottom, so when the viewport shrinks
    // the newest message stays put and everything older slides up behind it,
    // which is what every chat app does and what the eye expects. It costs one
    // reversed index and buys the whole problem away.
    final items = [
      if (_sending) const _Typing(),
      for (final bubble in _bubbles.reversed) _BubbleView(bubble: bubble),
    ];

    return ListView.builder(
      controller: _scrollController,
      reverse: true,
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        AppTheme.s5,
        AppTheme.s4,
        AppTheme.s5,
        AppTheme.s3,
      ),
      itemCount: items.length,
      itemBuilder: (context, i) => items[i],
    );
  }
}

/// A chat that never got as far as advice. Reachable only if history's routing
/// is wrong, so it says something honest rather than showing an empty box.
class _NothingToContinue extends StatelessWidget {
  const _NothingToContinue();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(AppTheme.s8),
        child: Text(
          'There is nothing to carry on from here yet.',
          textAlign: TextAlign.center,
          style: AppTheme.secondary(context),
        ),
      ),
    );
  }
}

class _Bubble {
  final String text;
  final bool fromUser;

  /// The verdict line, on the recommendation bubble only.
  final String headline;

  const _Bubble({
    required this.text,
    required this.fromUser,
    this.headline = '',
  });
}

class _BubbleView extends StatelessWidget {
  final _Bubble bubble;

  const _BubbleView({required this.bubble});

  @override
  Widget build(BuildContext context) {
    final scale = AppTheme.scaleOf(context);
    final fromUser = bubble.fromUser;

    return Align(
      alignment: fromUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.82,
        ),
        margin: EdgeInsets.only(bottom: AppTheme.s3),
        padding: EdgeInsets.symmetric(
          horizontal: AppTheme.s4,
          vertical: AppTheme.s3 + 2,
        ),
        decoration: BoxDecoration(
          // The user's own words in sage, ours in cream — the same pairing the
          // option rows use for chosen and unchosen.
          color: fromUser ? AppTheme.primary : AppTheme.cardBg,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(AppTheme.rMd),
            topRight: const Radius.circular(AppTheme.rMd),
            // The tail: the corner nearest its owner is squared off, which is
            // what says who said it without a label.
            bottomLeft: Radius.circular(fromUser ? AppTheme.rMd : 4),
            bottomRight: Radius.circular(fromUser ? 4 : AppTheme.rMd),
          ),
          border: fromUser ? null : Border.all(color: AppTheme.border),
          boxShadow: AppTheme.shadowSoft,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (bubble.headline.isNotEmpty) ...[
              Text(
                bubble.headline,
                style: AppTheme.heading(context).copyWith(
                  fontSize: 17 * scale,
                  color: AppTheme.textDark,
                ),
              ),
              SizedBox(height: AppTheme.s3),
            ],
            // The user's own text is not markdown — they typed it, and a stray
            // asterisk in "I *hate* this" is theirs to keep, not ours to style.
            if (fromUser)
              Text(
                bubble.text,
                style: AppTheme.body(context).copyWith(color: Colors.white),
              )
            else
              RichBody(
                markdown: bubble.text,
                baseStyle: AppTheme.body(context),
                allowCallouts: false,
              ),
          ],
        ),
      ),
    );
  }
}

class _Typing extends StatelessWidget {
  const _Typing();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(bottom: AppTheme.s3),
        padding: EdgeInsets.symmetric(
          horizontal: AppTheme.s4,
          vertical: AppTheme.s3 + 2,
        ),
        decoration: BoxDecoration(
          color: AppTheme.cardBg,
          borderRadius: BorderRadius.circular(AppTheme.rMd),
          border: Border.all(color: AppTheme.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primary),
              ),
            ),
            SizedBox(width: AppTheme.s3),
            Text('Thinking...', style: AppTheme.meta(context)),
          ],
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final DictationController dictation;
  final bool enabled;
  final VoidCallback onChanged;
  final VoidCallback? onSend;

  const _Composer({
    required this.controller,
    required this.dictation,
    required this.enabled,
    required this.onChanged,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    final scale = AppTheme.scaleOf(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppTheme.s4,
        0,
        AppTheme.s4,
        AppTheme.s3,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppTheme.rLg),
          boxShadow: AppTheme.shadowLifted,
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            color: AppTheme.cardBg,
            borderRadius: BorderRadius.circular(AppTheme.rLg),
            border: Border.all(
              color: dictation.listening ? AppTheme.live : AppTheme.border,
              width: dictation.listening ? 1.8 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  enabled: enabled,
                  maxLines: 5,
                  minLines: 1,
                  onChanged: (_) => onChanged(),
                  // Reaching for the keyboard turns the mic off — otherwise the
                  // next partial result overwrites what was typed.
                  onTap: dictation.stop,
                  keyboardType: TextInputType.multiline,
                  textCapitalization: TextCapitalization.sentences,
                  cursorColor:
                      dictation.listening ? AppTheme.live : AppTheme.primary,
                  style: AppTheme.body(context),
                  decoration: InputDecoration(
                    hintText: dictation.listening ? 'Listening...' : 'Say more...',
                    hintStyle: AppTheme.body(context)
                        .copyWith(color: AppTheme.textFaint),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.fromLTRB(
                      AppTheme.s4,
                      AppTheme.s3 + 2,
                      AppTheme.s2,
                      AppTheme.s3 + 2,
                    ),
                  ),
                ),
              ),
              if (dictation.available)
                Padding(
                  padding: EdgeInsets.only(bottom: AppTheme.s1 + 2),
                  child: DictationIconButton(
                    controller: dictation,
                    onPressed: enabled
                        ? () {
                            FocusScope.of(context).unfocus();
                            dictation.toggle();
                          }
                        : null,
                  ),
                ),
              Padding(
                padding: EdgeInsets.all(AppTheme.s1 + 2),
                child: Material(
                  color: onSend == null
                      ? AppTheme.primary.withValues(alpha: 0.3)
                      : AppTheme.primary,
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: onSend,
                    child: SizedBox(
                      width: 38 * scale,
                      height: 38 * scale,
                      child: Icon(
                        Icons.arrow_upward_rounded,
                        size: 19 * scale,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
