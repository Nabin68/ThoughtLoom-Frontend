//adaptive_flow_screen.dart

import 'dart:async';

import 'package:flutter/material.dart';

import '../models/chat.dart';
import '../models/intake_question.dart';
import '../models/user_profile.dart';
import '../services/ai_service.dart';
import '../services/backend.dart';
import '../theme/app_theme.dart';
import '../widgets/app_background.dart';
import '../widgets/app_button.dart';
import '../widgets/app_header.dart';
import '../widgets/app_text_field.dart';
import '../widgets/dictation.dart';
import '../widgets/error_banner.dart';
import '../widgets/option_tile.dart';
import 'recommendation_screen.dart';

/// The generated questions.
///
/// Deliberately indistinguishable from `IntakeFlowScreen`: same header, same
/// option rows, same button. To the user this is one conversation that happens
/// to have got more specific — not the moment "the AI mode" starts. The only
/// tell is the wording of the questions, which is the point.
///
/// ### Where the writes happen
///
/// Nowhere in here. The API writes each question when it generates it and fills
/// in the answer when this screen sends it, both with the service-role key. This
/// screen holds a `message_id` and posts an answer against it — it has no
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

  /// The ticked options. A set for both kinds — the model decides per question
  /// whether more than one may be chosen, and a single-choice question is just a
  /// cap of one.
  final Set<String> _choices = {};

  /// Whether the free-text escape hatch is open. Always offered, whatever the
  /// model generated — the options are its guesses, and being unable to say
  /// "none of those, actually it's this" would make them a cage.
  bool _writingOwnAnswer = false;

  bool get _answered => _writingOwnAnswer
      ? _textController.text.trim().isNotEmpty
      : _choices.isNotEmpty;

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
  Future<void> _load({
    String? answer,
    String? answerTo,
    List<String>? selections,
  }) async {
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
        selections: selections,
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
        _choices.clear();
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
  /// lost, the API sees the question already answered and moves on; if a question
  /// was already generated and we never showed it, it hands back that same one
  /// rather than inventing a second.
  Future<void> _retry() async {
    if (_pending != null && _turn?.messageId != null) {
      await _load(
        answer: _pending,
        answerTo: _turn!.messageId,
        selections: _pendingSelections,
      );
    } else {
      await _load();
    }
  }

  String? _pending;
  List<String>? _pendingSelections;

  void _select(String option) {
    setState(() {
      _writingOwnAnswer = false;
      _textController.clear();
      if (_turn?.multi ?? false) {
        _choices.contains(option)
            ? _choices.remove(option)
            : _choices.add(option);
      } else {
        _choices
          ..clear()
          ..add(option);
      }
    });
  }

  Future<void> _submit() async {
    if (!_answered || _loading) return;
    await _dictation.stop();
    if (!mounted) return;

    final turn = _turn;
    final List<String>? selections;
    final String answer;

    if (_writingOwnAnswer) {
      answer = _textController.text.trim();
      selections = null;
    } else {
      // Option order, not tap order — see IntakeFlowScreen. The model wrote the
      // list; it should read the answer back in the order it wrote it.
      final chosen =
          (turn?.options ?? const <String>[]).where(_choices.contains).toList();
      answer = joinSelections(chosen);
      selections = chosen.length > 1 ? chosen : null;
    }

    _pending = answer;
    _pendingSelections = selections;
    await _load(
      answer: answer,
      answerTo: turn?.messageId,
      selections: selections,
    );
    if (mounted && _error == null) {
      _pending = null;
      _pendingSelections = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppBackground(
      child: Column(
        children: [
          AppHeader(
            title: widget.chat.category.label,
            subtitle: 'A few more questions',
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
                AppTheme.s5,
                0,
                AppTheme.s5,
                AppTheme.s4,
              ),
              child: AppButton(
                label: 'Continue',
                icon: Icons.arrow_forward_rounded,
                onPressed: _answered ? _submit : null,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildQuestion() {
    final turn = _turn!;
    final multi = turn.multi;

    return SingleChildScrollView(
      controller: _scrollController,
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        AppTheme.s5,
        AppTheme.s4,
        AppTheme.s5,
        AppTheme.s6,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(turn.question ?? '', style: AppTheme.title(context)),
          if (multi) ...[
            SizedBox(height: AppTheme.s2),
            Text(
              'Pick everything that is true.',
              style: AppTheme.secondary(context),
            ),
          ],
          SizedBox(height: AppTheme.s5),
          for (final option in turn.options)
            OptionTile(
              label: option,
              selected: !_writingOwnAnswer && _choices.contains(option),
              mode: multi ? ChoiceMode.multi : ChoiceMode.single,
              onTap: () => _select(option),
            ),

          // Always present, whatever the model generated.
          OptionTile(
            label: 'Something else — let me explain',
            selected: _writingOwnAnswer,
            onTap: () => setState(() {
              _writingOwnAnswer = true;
              _choices.clear();
            }),
          ),

          if (_writingOwnAnswer) ...[
            SizedBox(height: AppTheme.s2),
            AppTextField(
              controller: _textController,
              hintText: 'In your own words...',
              icon: Icons.edit_note_outlined,
              maxLines: 4,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              listening: _dictation.listening,
              onChanged: (_) => setState(() {}),
              onTap: _dictation.stop,
            ),
            if (_dictation.available) ...[
              SizedBox(height: AppTheme.s3),
              Align(
                alignment: Alignment.centerLeft,
                child: DictationButton(
                  controller: _dictation,
                  label: 'Answer out loud',
                  onPressed: () {
                    FocusScope.of(context).unfocus();
                    _dictation.toggle();
                  },
                ),
              ),
            ],
          ],
        ],
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
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 34,
            height: 34,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primary),
            ),
          ),
          SizedBox(height: AppTheme.s5),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            child: Text(
              _lines[_index],
              key: ValueKey(_index),
              style: AppTheme.secondary(context),
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
    return Center(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.symmetric(horizontal: AppTheme.s5),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ErrorBanner(message: message),
            SizedBox(height: AppTheme.s5),
            // Reassurance, because the honest fear here is that a failure ate the
            // last ten minutes of answering questions. It did not.
            Text(
              'Nothing you have said is lost.',
              textAlign: TextAlign.center,
              style: AppTheme.secondary(context),
            ),
            SizedBox(height: AppTheme.s5),
            if (onRetry != null) AppButton(label: 'Try again', onPressed: onRetry),
            SizedBox(height: AppTheme.s2),
            AppButton.quiet(
              label: 'Back to start',
              onPressed: () => Navigator.popUntil(context, (r) => r.isFirst),
            ),
          ],
        ),
      ),
    );
  }
}
