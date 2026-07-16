//continued_chat_screen.dart

import 'package:flutter/material.dart';

import '../models/chat.dart';
import '../models/message.dart';
import '../services/ai_service.dart';
import '../services/backend.dart';
import '../services/chat_completion.dart';
import '../theme/app_theme.dart';
import '../widgets/app_background.dart';
import '../widgets/dictation.dart';
import '../widgets/error_banner.dart';

/// The back-and-forth after the recommendation.
///
/// Loads the chat's real history so the recommendation is the first thing on
/// screen — this is a continuation, not a fresh window. Only the turns worth
/// re-reading are shown: the scripted Q&A is scaffolding the user already
/// walked through, and replaying twelve of them above the answer would bury it.
///
/// Both sides of each turn are written by the API, so nothing here writes a
/// message. Leaving completes the chat.
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

  bool _loading = true;
  bool _sending = false;
  String? _error;

  /// Kept so a failed send can be retried with one tap instead of retyping.
  String? _failedMessage;

  @override
  void initState() {
    super.initState();
    _dictation.init();
    _loadHistory();
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
      final messages = await Backend.data.fetchMessages(widget.chat.id);
      if (!mounted) return;
      setState(() {
        _bubbles
          ..clear()
          ..addAll(_toBubbles(messages));
        _loading = false;
      });
      _scrollToEnd();
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
  /// The recommendation and everything after it. The intake and the adaptive
  /// questions are how we got here, not part of the conversation the user is
  /// now having — and the free-text description is the one exception, because
  /// it is the thing they actually said in their own words.
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

  void _scrollToEnd() {
    // After the frame the new bubble is laid out in, or maxScrollExtent is
    // still the old one and the newest message stays just below the fold.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
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
      // Shown immediately rather than after the round trip: a message that
      // hangs in a text box for thirty seconds feels like it was not sent.
      if (retrying == null) {
        _bubbles.add(_Bubble(text: text, fromUser: true));
        _composer.clear();
      }
    });
    _scrollToEnd();

    try {
      final reply =
          await Backend.ai.followUp(chatId: widget.chat.id, message: text);
      if (!mounted) return;
      setState(() {
        _bubbles.add(_Bubble(text: reply, fromUser: false));
        _sending = false;
      });
      _scrollToEnd();
    } on AiFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = e.message;
        _failedMessage = e.retryable ? text : null;
      });
    }
  }

  /// Leaving ends the chat — see [completeChat], which also asks the API to
  /// name it and fold what it learned into the user's memory. Never throws: the
  /// user asked to leave, and a failed write must not trap them.
  Future<void> _finish() async {
    final navigator = Navigator.of(context);
    await completeChat(widget.chat);
    if (mounted) navigator.popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _finish();
      },
      child: AppBackground(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: screenWidth * 0.06,
                vertical: screenHeight * 0.015,
              ),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: _finish,
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
                  Expanded(
                    child: Text(
                      '${widget.chat.category.label} · Still talking',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: screenWidth * 0.038,
                        color: AppTheme.textLight,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
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
                  : ListView.builder(
                      controller: _scrollController,
                      physics: const BouncingScrollPhysics(),
                      padding: EdgeInsets.symmetric(
                        horizontal: screenWidth * 0.06,
                      ),
                      itemCount: _bubbles.length + (_sending ? 1 : 0),
                      itemBuilder: (context, i) {
                        if (i == _bubbles.length) return const _Typing();
                        return _BubbleView(bubble: _bubbles[i]);
                      },
                    ),
            ),
            if (_error != null)
              Padding(
                padding: EdgeInsets.fromLTRB(
                  screenWidth * 0.06,
                  0,
                  screenWidth * 0.06,
                  screenHeight * 0.012,
                ),
                child: Column(
                  children: [
                    ErrorBanner(message: _error!),
                    if (_failedMessage != null) ...[
                      SizedBox(height: screenHeight * 0.008),
                      TextButton(
                        onPressed: () => _send(retrying: _failedMessage),
                        child: Text(
                          'Try sending again',
                          style: TextStyle(
                            fontSize: screenWidth * 0.036,
                            color: AppTheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
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
}

class _Bubble {
  final String text;
  final bool fromUser;

  const _Bubble({required this.text, required this.fromUser});
}

class _BubbleView extends StatelessWidget {
  final _Bubble bubble;

  const _BubbleView({required this.bubble});

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Align(
      alignment: bubble.fromUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: screenWidth * 0.78),
        margin: EdgeInsets.only(bottom: screenWidth * 0.03),
        padding: EdgeInsets.symmetric(
          horizontal: screenWidth * 0.045,
          vertical: screenWidth * 0.035,
        ),
        decoration: BoxDecoration(
          // The user's own words in sage, ours in cream — the same pairing the
          // option rows use for chosen and unchosen.
          color: bubble.fromUser
              ? AppTheme.primary
              : AppTheme.cardBg.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              offset: const Offset(0, 3),
              blurRadius: 10,
            ),
          ],
        ),
        child: Text(
          bubble.text,
          style: TextStyle(
            fontSize: screenWidth * 0.038,
            color: bubble.fromUser ? Colors.white : AppTheme.textOnCard,
            height: 1.5,
          ),
        ),
      ),
    );
  }
}

class _Typing extends StatelessWidget {
  const _Typing();

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(bottom: screenWidth * 0.03),
        padding: EdgeInsets.symmetric(
          horizontal: screenWidth * 0.045,
          vertical: screenWidth * 0.04,
        ),
        decoration: BoxDecoration(
          color: AppTheme.cardBg.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: screenWidth * 0.04,
              height: screenWidth * 0.04,
              child: const CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primary),
              ),
            ),
            SizedBox(width: screenWidth * 0.03),
            Text(
              'Thinking...',
              style: TextStyle(
                fontSize: screenWidth * 0.036,
                color: AppTheme.textLight,
              ),
            ),
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
    final screenWidth = MediaQuery.of(context).size.width;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        screenWidth * 0.06,
        0,
        screenWidth * 0.06,
        screenWidth * 0.04,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.cardBg.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(AppTheme.pillRadius),
          border: dictation.listening
              ? Border.all(
                  color: AppTheme.primary.withValues(alpha: 0.6),
                  width: 2,
                )
              : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              offset: const Offset(0, 4),
              blurRadius: 12,
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            SizedBox(width: screenWidth * 0.04),
            Expanded(
              child: TextField(
                controller: controller,
                enabled: enabled,
                maxLines: 4,
                minLines: 1,
                onChanged: (_) => onChanged(),
                keyboardType: TextInputType.multiline,
                style: TextStyle(
                  fontSize: screenWidth * 0.04,
                  color: AppTheme.textOnCard,
                  height: 1.4,
                ),
                decoration: InputDecoration(
                  hintText: 'Say more...',
                  hintStyle: TextStyle(
                    fontSize: screenWidth * 0.04,
                    color: AppTheme.textLight.withValues(alpha: 0.5),
                  ),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    vertical: screenWidth * 0.035,
                  ),
                ),
              ),
            ),
            if (dictation.available)
              DictationIconButton(
                controller: dictation,
                onPressed: enabled ? dictation.toggle : null,
              ),
            GestureDetector(
              onTap: onSend,
              behavior: HitTestBehavior.opaque,
              child: Container(
                margin: EdgeInsets.all(screenWidth * 0.015),
                width: screenWidth * 0.11,
                height: screenWidth * 0.11,
                decoration: BoxDecoration(
                  color: onSend == null
                      ? AppTheme.primary.withValues(alpha: 0.35)
                      : AppTheme.primary,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.arrow_upward,
                  size: screenWidth * 0.05,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
