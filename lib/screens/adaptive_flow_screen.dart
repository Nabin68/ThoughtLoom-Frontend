//adaptive_flow_screen.dart

import 'dart:async';

import 'package:flutter/material.dart';

import '../models/chat.dart';
import '../models/user_profile.dart';
import '../services/ai_service.dart';
import '../services/backend.dart';
import '../theme/app_theme.dart';
import '../widgets/app_background.dart';
import '../widgets/auth_text_field.dart';
import '../widgets/dictation.dart';
import '../widgets/error_banner.dart';
import '../widgets/option_tile.dart';
import '../widgets/primary_button.dart';
import 'recommendation_screen.dart';

/// The generated questions.
///
/// Deliberately indistinguishable from `IntakeFlowScreen`: same header, same
/// cream option rows, same button. To the user this is one conversation that
/// happens to have got more specific — not the moment "the AI mode" starts. The
/// only tell is the wording of the questions, which is the point.
///
/// ### Where the writes happen
///
/// Nowhere in here. The API writes each question when it generates it and fills
/// in the answer when this screen sends it, both with the service-role key.
/// This screen holds a `message_id` and posts an answer against it — it has no
/// [DataService] calls at all, which is why an answer and the next question are
/// one round trip that cannot half-succeed.
///
/// ### Failure
///
/// Every failure lands on the same screen with a retry, and nothing is lost:
/// answers are persisted server-side before the model is asked anything, so a
/// timeout costs the wait, never the conversation.
class AdaptiveFlowScreen extends StatefulWidget {
  final Chat chat;
  final UserProfile profile;

  const AdaptiveFlowScreen({
    super.key,
    required this.chat,
    required this.profile,
  });

  @override
  State<AdaptiveFlowScreen> createState() => _AdaptiveFlowScreenState();
}

class _AdaptiveFlowScreenState extends State<AdaptiveFlowScreen> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  late final _dictation = DictationController(_textController)
    ..addListener(_onDictationChanged);

  AdaptiveTurn? _turn;
  bool _loading = true;
  String? _error;
  bool _errorRetryable = true;

  /// The tapped option, or null. Mutually exclusive with the free-text box:
  /// choosing an option closes it, opening it clears the choice.
  String? _choice;

  /// Whether the free-text escape hatch is open. Always offered, whatever the
  /// model generated — the options are its guesses, and being unable to say
  /// "none of those, actually it's this" would make them a cage.
  bool _writingOwnAnswer = false;

  bool get _answered => _writingOwnAnswer
      ? _textController.text.trim().isNotEmpty
      : _choice != null;

  @override
  void initState() {
    super.initState();
    _dictation.init();
    _load();
  }

  void _onDictationChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _dictation.removeListener(_onDictationChanged);
    _dictation.dispose();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Asks for the next question. [answer] is null on the first call.
  Future<void> _load({String? answer, String? answerTo}) async {
    if (!Backend.usingSupabase) {
      setState(() {
        _loading = false;
        _errorRetryable = false;
        _error = 'The follow-up questions need the app to be connected to '
            'Supabase. Your answers so far are saved on this device.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final turn = await Backend.ai.nextQuestion(
        chatId: widget.chat.id,
        answer: answer,
        answerToMessageId: answerTo,
      );
      if (!mounted) return;

      if (turn.done) {
        await Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => RecommendationScreen(chat: widget.chat),
          ),
        );
        return;
      }

      setState(() {
        _turn = turn;
        _loading = false;
        _choice = null;
        _writingOwnAnswer = false;
        _textController.clear();
      });
      if (_scrollController.hasClients) _scrollController.jumpTo(0);
    } on AiFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
        _errorRetryable = e.retryable;
      });
    }
  }

  /// Retries whatever failed.
  ///
  /// Safe to hit repeatedly. If the answer got through and only the reply was
  /// lost, the API sees the question already answered and moves on; if a
  /// question was already generated and we never showed it, it hands back that
  /// same one rather than inventing a second.
  Future<void> _retry() async {
    if (_pendingAnswer != null && _turn?.messageId != null) {
      await _load(answer: _pendingAnswer, answerTo: _turn!.messageId);
    } else {
      await _load();
    }
  }

  String? _pendingAnswer;

  Future<void> _submit() async {
    if (!_answered || _loading) return;
    await _dictation.stop();
    if (!mounted) return;

    final answer =
        _writingOwnAnswer ? _textController.text.trim() : _choice!;
    _pendingAnswer = answer;
    await _load(answer: answer, answerTo: _turn?.messageId);
    if (mounted && _error == null) _pendingAnswer = null;
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    final horizontalPadding = screenWidth * 0.06;

    return AppBackground(
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: horizontalPadding,
              vertical: screenHeight * 0.02,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${widget.chat.category.label} · A few more questions',
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
            child: _error != null
                ? _Failure(
                    message: _error!,
                    onRetry: _errorRetryable ? _retry : null,
                  )
                : _loading
                    ? const _Thinking()
                    : _buildQuestion(),
          ),
          if (_error == null && !_loading && _turn != null)
            Padding(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                0,
                horizontalPadding,
                screenHeight * 0.02,
              ),
              child: PrimaryButton(
                label: 'Continue',
                icon: Icons.arrow_forward,
                onPressed: _answered ? _submit : null,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildQuestion() {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    final turn = _turn!;

    return SingleChildScrollView(
      controller: _scrollController,
      physics: const BouncingScrollPhysics(),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.06),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: screenHeight * 0.02),
            Text(
              turn.question ?? '',
              style: TextStyle(
                fontSize: screenWidth * 0.065,
                fontWeight: FontWeight.w700,
                color: AppTheme.textDark,
                height: 1.3,
                letterSpacing: -0.5,
              ),
            ),
            SizedBox(height: screenHeight * 0.035),
            for (final option in turn.options)
              OptionTile(
                label: option,
                selected: !_writingOwnAnswer && _choice == option,
                onTap: () => setState(() {
                  _choice = option;
                  _writingOwnAnswer = false;
                  _textController.clear();
                }),
              ),

            // Always present, whatever the model generated.
            OptionTile(
              label: 'Something else — let me explain',
              selected: _writingOwnAnswer,
              onTap: () => setState(() {
                _writingOwnAnswer = true;
                _choice = null;
              }),
            ),

            if (_writingOwnAnswer) ...[
              SizedBox(height: screenHeight * 0.012),
              AuthTextField(
                controller: _textController,
                hintText: 'In your own words...',
                icon: Icons.edit_note_outlined,
                maxLines: 3,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                onChanged: (_) => setState(() {}),
              ),
              if (_dictation.available) ...[
                SizedBox(height: screenHeight * 0.015),
                DictationButton(
                  controller: _dictation,
                  onPressed: _dictation.toggle,
                  label: 'Answer out loud',
                ),
              ],
            ],
            SizedBox(height: screenHeight * 0.03),
          ],
        ),
      ),
    );
  }
}

/// The wait while the model writes the next question.
///
/// Rotating lines rather than a bare spinner: this can sit behind a Render cold
/// start, and thirty silent seconds reads as broken.
class _Thinking extends StatefulWidget {
  const _Thinking();

  @override
  State<_Thinking> createState() => _ThinkingState();
}

class _ThinkingState extends State<_Thinking> {
  static const _lines = [
    'Reading what you said...',
    'Thinking about that...',
    'Working out what to ask next...',
    'Still with you...',
  ];

  int _index = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted) setState(() => _index = (_index + 1) % _lines.length);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: screenWidth * 0.09,
            height: screenWidth * 0.09,
            child: const CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primary),
            ),
          ),
          SizedBox(height: screenWidth * 0.06),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            child: Text(
              _lines[_index],
              key: ValueKey(_index),
              style: TextStyle(
                fontSize: screenWidth * 0.04,
                color: AppTheme.textLight,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A failure with a way out. [onRetry] of null means retrying cannot help.
class _Failure extends StatelessWidget {
  final String message;
  final Future<void> Function()? onRetry;

  const _Failure({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;

    return Center(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.06),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ErrorBanner(message: message),
              SizedBox(height: screenHeight * 0.025),
              // Reassurance, because the honest fear here is that a failure ate
              // the last ten minutes of answering questions. It did not.
              Text(
                'Nothing you have said is lost.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: screenWidth * 0.036,
                  color: AppTheme.textLight,
                ),
              ),
              SizedBox(height: screenHeight * 0.025),
              if (onRetry != null)
                PrimaryButton(label: 'Try again', onPressed: onRetry),
              SizedBox(height: screenHeight * 0.012),
              TextButton(
                onPressed: () =>
                    Navigator.popUntil(context, (route) => route.isFirst),
                child: Text(
                  'Back to start',
                  style: TextStyle(
                    fontSize: screenWidth * 0.038,
                    color: AppTheme.textLight,
                    fontWeight: FontWeight.w600,
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
