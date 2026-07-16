//recommendation_screen.dart

import 'dart:async';

import 'package:flutter/material.dart';

import '../models/chat.dart';
import '../services/ai_service.dart';
import '../services/backend.dart';
import '../services/chat_completion.dart';
import '../theme/app_theme.dart';
import '../widgets/app_background.dart';
import '../widgets/app_button.dart';
import '../widgets/app_card.dart';
import '../widgets/app_header.dart';
import '../widgets/error_banner.dart';
import '../widgets/rich_body.dart';
import 'continued_chat_screen.dart';

/// The answer.
///
/// The API has already written it to `messages` and moved the chat to
/// `awaiting_follow_up` by the time this renders — so a user who closes the app
/// here has not lost it.
///
/// Leaving completes the chat. That write is direct Flutter → Supabase: it is a
/// status flag on a row the user owns, RLS covers it, and routing it through the
/// API would be a network round trip to set a boolean.
///
/// ### Why this screen looks different now
///
/// It is the one screen the whole app exists to produce, and it used to render
/// as three hundred words of undifferentiated prose in a single `Text` — the
/// position buried somewhere in the middle, indistinguishable from the reasoning
/// around it. The model is now asked for a `headline` it has to commit to, and a
/// body in a Markdown subset, so the answer can be *seen* as well as read: the
/// verdict at the top in large type, the reasoning under it with the load-bearing
/// phrases actually bold, and one accented callout for the thing not to miss.
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
    final ready = _error == null && !_loading && _recommendation != null;

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
            AppHeader(
              title: widget.chat.category.label,
              subtitle: 'What I think',
              onBack: _finish,
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
            if (ready)
              Padding(
                padding: EdgeInsets.fromLTRB(
                  AppTheme.s5,
                  0,
                  AppTheme.s5,
                  AppTheme.s4,
                ),
                child: Column(
                  children: [
                    AppButton(
                      label: 'Push back on this',
                      icon: Icons.chat_bubble_outline_rounded,
                      // pushReplacement, not push. The chat screen opens with
                      // this very recommendation as its first bubble, so leaving
                      // it should go home rather than reveal a second, frozen
                      // copy of the advice with its own "leave" button — and it
                      // lets ContinuedChatScreen simply pop, which is what makes
                      // the same screen behave correctly when it is reached from
                      // history instead.
                      onPressed: () => Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ContinuedChatScreen(chat: widget.chat),
                        ),
                      ),
                    ),
                    SizedBox(height: AppTheme.s2),
                    AppButton.quiet(
                      label: "That's enough for now",
                      onPressed: _finish,
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
    final result = _recommendation!;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        AppTheme.s5,
        AppTheme.s2,
        AppTheme.s5,
        AppTheme.s6,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The verdict, alone, in display type. Against a server that predates
          // the headline field this is simply absent and the body leads, exactly
          // as it did before.
          if (result.headline.isNotEmpty) ...[
            Text(result.headline, style: AppTheme.display(context)),
            SizedBox(height: AppTheme.s5),
          ],
          AppCard(
            child: RichBody(
              markdown: result.text,
              baseStyle: AppTheme.body(context).copyWith(fontSize: 15.5),
            ),
          ),
          if (result.nextSteps.isNotEmpty) ...[
            SizedBox(height: AppTheme.s4),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionLabel(
                    'Where to start',
                    icon: Icons.play_arrow_rounded,
                  ),
                  SizedBox(height: AppTheme.s4),
                  for (var i = 0; i < result.nextSteps.length; i++) ...[
                    _Step(number: i + 1, text: result.nextSteps[i]),
                    if (i != result.nextSteps.length - 1)
                      SizedBox(height: AppTheme.s4),
                  ],
                ],
              ),
            ),
          ],
          if (result.confidence.isNotEmpty) ...[
            SizedBox(height: AppTheme.s4),
            _Confidence(text: result.confidence),
          ],
          // Only present when the answer actually needed research, which is a
          // minority of the time — and when it did, saying so is the difference
          // between advice and a claim.
          if (result.sources.isNotEmpty) ...[
            SizedBox(height: AppTheme.s5),
            const SectionLabel('What I looked up', icon: Icons.travel_explore),
            SizedBox(height: AppTheme.s3),
            for (final source in result.sources)
              Padding(
                padding: EdgeInsets.only(bottom: AppTheme.s2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Icon(
                        Icons.link_rounded,
                        size: 13,
                        color: AppTheme.textFaint,
                      ),
                    ),
                    SizedBox(width: AppTheme.s2),
                    Expanded(
                      child: Text(
                        source.title.isEmpty ? source.url : source.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.meta(context),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final int number;
  final String text;

  const _Step({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    final scale = AppTheme.scaleOf(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24 * scale,
          height: 24 * scale,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: AppTheme.primary,
            shape: BoxShape.circle,
          ),
          child: Text(
            '$number',
            style: TextStyle(
              fontSize: 12 * scale,
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        SizedBox(width: AppTheme.s3),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: RichBody(
              markdown: text,
              baseStyle: AppTheme.body(context),
              allowCallouts: false,
            ),
          ),
        ),
      ],
    );
  }
}

/// How sure it is, and what would change its mind.
///
/// Deliberately quiet and deliberately present. A model that takes a hard
/// position — which is what this app's prompts now demand — owes the reader the
/// size of its own doubt, or the position is a bluff.
class _Confidence extends StatelessWidget {
  final String text;

  const _Confidence({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(AppTheme.s3),
      decoration: BoxDecoration(
        color: AppTheme.primarySoft.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(AppTheme.rSm),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 15, color: AppTheme.textLight),
          SizedBox(width: AppTheme.s2),
          Expanded(
            child: Text(
              text,
              style: AppTheme.meta(context).copyWith(
                color: AppTheme.textLight,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
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
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: AppTheme.s8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 38,
              height: 38,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primary),
              ),
            ),
            SizedBox(height: AppTheme.s6),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              child: Text(
                _lines[_index],
                key: ValueKey(_index),
                textAlign: TextAlign.center,
                style: AppTheme.body(context).copyWith(
                  color: AppTheme.textDark,
                  fontWeight: FontWeight.w600,
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
    return Center(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.symmetric(horizontal: AppTheme.s5),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ErrorBanner(message: message),
            SizedBox(height: AppTheme.s5),
            Text(
              'Your conversation is saved. Trying again picks up exactly where '
              'it left off.',
              textAlign: TextAlign.center,
              style: AppTheme.secondary(context),
            ),
            SizedBox(height: AppTheme.s5),
            if (onRetry != null) AppButton(label: 'Try again', onPressed: onRetry),
            SizedBox(height: AppTheme.s2),
            AppButton.quiet(label: 'Back to start', onPressed: onLeave),
          ],
        ),
      ),
    );
  }
}
