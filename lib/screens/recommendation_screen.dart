//recommendation_screen.dart

import 'dart:async';

import 'package:flutter/material.dart';

import '../models/chat.dart';
import '../services/ai_service.dart';
import '../services/backend.dart';
import '../services/chat_completion.dart';
import '../theme/app_theme.dart';
import '../widgets/app_background.dart';
import '../widgets/error_banner.dart';
import '../widgets/primary_button.dart';
import 'continued_chat_screen.dart';

/// The answer.
///
/// The API has already written it to `messages` and moved the chat to
/// `awaiting_follow_up` by the time this renders — so a user who closes the app
/// here has not lost it, and Prompt 6 will find it.
///
/// Leaving completes the chat. That write is direct Flutter → Supabase: it is a
/// status flag on a row the user owns, RLS covers it, and routing it through
/// the API would be a network round trip to set a boolean.
class RecommendationScreen extends StatefulWidget {
  final Chat chat;

  const RecommendationScreen({super.key, required this.chat});

  @override
  State<RecommendationScreen> createState() => _RecommendationScreenState();
}

class _RecommendationScreenState extends State<RecommendationScreen> {
  Recommendation? _recommendation;
  bool _loading = true;
  String? _error;
  bool _errorRetryable = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!Backend.usingSupabase) {
      setState(() {
        _loading = false;
        _errorRetryable = false;
        _error = 'The recommendation needs the app to be connected to '
            'Supabase. Everything you said is saved on this device.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final result = await Backend.ai.recommendation(chatId: widget.chat.id);
      if (!mounted) return;
      setState(() {
        _recommendation = result;
        _loading = false;
      });
    } on AiFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
        _errorRetryable = e.retryable;
      });
    }
  }

  /// Ends the chat and goes home.
  ///
  /// Best-effort throughout, and it never throws — see [completeChat], which
  /// also asks the API to name the chat and remember it.
  Future<void> _finish() async {
    final navigator = Navigator.of(context);
    await completeChat(widget.chat);
    if (mounted) navigator.popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    final horizontalPadding = screenWidth * 0.06;

    // Intercepts Back — the system gesture and the button — so leaving by any
    // route ends the chat, rather than only the one we thought of.
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
                horizontal: horizontalPadding,
                vertical: screenHeight * 0.02,
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
                      widget.chat.category.label,
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
                      onRetry: _errorRetryable ? _load : null,
                      onLeave: _finish,
                    )
                  : _loading
                      ? const _Working()
                      : _buildAnswer(),
            ),
            if (_error == null && !_loading && _recommendation != null)
              Padding(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  0,
                  horizontalPadding,
                  screenHeight * 0.02,
                ),
                child: Column(
                  children: [
                    PrimaryButton(
                      label: 'Keep chatting',
                      icon: Icons.chat_bubble_outline,
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ContinuedChatScreen(chat: widget.chat),
                        ),
                      ),
                    ),
                    SizedBox(height: screenHeight * 0.008),
                    TextButton(
                      onPressed: _finish,
                      child: Text(
                        "That's enough for now",
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
          ],
        ),
      ),
    );
  }

  Widget _buildAnswer() {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    final result = _recommendation!;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.06),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Here is what I think',
              style: TextStyle(
                fontSize: screenWidth * 0.08,
                fontWeight: FontWeight.w700,
                color: AppTheme.textDark,
                height: 1.2,
                letterSpacing: -0.5,
              ),
            ),
            SizedBox(height: screenHeight * 0.025),
            _Card(
              child: Text(
                result.text,
                style: TextStyle(
                  fontSize: screenWidth * 0.042,
                  color: AppTheme.textOnCard,
                  height: 1.6,
                ),
              ),
            ),
            if (result.nextSteps.isNotEmpty) ...[
              SizedBox(height: screenHeight * 0.02),
              _Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Where to start',
                      style: TextStyle(
                        fontSize: screenWidth * 0.045,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textOnCard,
                        letterSpacing: -0.2,
                      ),
                    ),
                    SizedBox(height: screenWidth * 0.035),
                    for (var i = 0; i < result.nextSteps.length; i++) ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: screenWidth * 0.055,
                            height: screenWidth * 0.055,
                            alignment: Alignment.center,
                            decoration: const BoxDecoration(
                              color: AppTheme.primary,
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              '${i + 1}',
                              style: TextStyle(
                                fontSize: screenWidth * 0.03,
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          SizedBox(width: screenWidth * 0.03),
                          Expanded(
                            child: Text(
                              result.nextSteps[i],
                              style: TextStyle(
                                fontSize: screenWidth * 0.038,
                                color: AppTheme.textOnCard,
                                height: 1.45,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (i != result.nextSteps.length - 1)
                        SizedBox(height: screenWidth * 0.035),
                    ],
                  ],
                ),
              ),
            ],
            if (result.confidence.isNotEmpty) ...[
              SizedBox(height: screenHeight * 0.02),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline,
                    size: screenWidth * 0.04,
                    color: AppTheme.textLight,
                  ),
                  SizedBox(width: screenWidth * 0.025),
                  Expanded(
                    child: Text(
                      result.confidence,
                      style: TextStyle(
                        fontSize: screenWidth * 0.034,
                        color: AppTheme.textLight,
                        height: 1.4,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            // Only present when the answer actually needed research, which is a
            // minority of the time — and when it did, saying so is the
            // difference between advice and a claim.
            if (result.sources.isNotEmpty) ...[
              SizedBox(height: screenHeight * 0.025),
              Text(
                'What I looked up',
                style: TextStyle(
                  fontSize: screenWidth * 0.036,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textLight,
                ),
              ),
              SizedBox(height: screenWidth * 0.02),
              for (final source in result.sources)
                Padding(
                  padding: EdgeInsets.only(bottom: screenWidth * 0.015),
                  child: Text(
                    '· ${source.title.isEmpty ? source.url : source.title}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: screenWidth * 0.032,
                      color: AppTheme.textLight,
                      height: 1.4,
                    ),
                  ),
                ),
            ],
            SizedBox(height: screenHeight * 0.03),
          ],
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;

  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(screenWidth * 0.055),
      decoration: BoxDecoration(
        color: AppTheme.cardBg.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            offset: const Offset(0, 4),
            blurRadius: 12,
          ),
        ],
      ),
      child: child,
    );
  }
}

/// The long wait. This call searches the web and writes several hundred words,
/// possibly behind a Render cold start — a minute is normal, so the screen has
/// to keep saying something true.
class _Working extends StatefulWidget {
  const _Working();

  @override
  State<_Working> createState() => _WorkingState();
}

class _WorkingState extends State<_Working> {
  static const _lines = [
    'Going back over everything you said...',
    'Weighing it up...',
    'Checking a few things...',
    'Working out what I actually think...',
    'Nearly there — this one takes a moment...',
  ];

  int _index = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
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
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.08),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: screenWidth * 0.1,
              height: screenWidth * 0.1,
              child: const CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primary),
              ),
            ),
            SizedBox(height: screenWidth * 0.07),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              child: Text(
                _lines[_index],
                key: ValueKey(_index),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: screenWidth * 0.042,
                  color: AppTheme.textDark,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Failure extends StatelessWidget {
  final String message;
  final Future<void> Function()? onRetry;
  final Future<void> Function() onLeave;

  const _Failure({
    required this.message,
    required this.onRetry,
    required this.onLeave,
  });

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
              Text(
                'Your conversation is saved. Trying again picks up\nexactly where it left off.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: screenWidth * 0.036,
                  color: AppTheme.textLight,
                  height: 1.4,
                ),
              ),
              SizedBox(height: screenHeight * 0.025),
              if (onRetry != null)
                PrimaryButton(label: 'Try again', onPressed: onRetry),
              SizedBox(height: screenHeight * 0.012),
              TextButton(
                onPressed: onLeave,
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
