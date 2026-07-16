//onboarding_screen.dart

import 'package:flutter/material.dart';

import '../data/onboarding_questions.dart';
import '../models/onboarding_question.dart';
import '../models/user_profile.dart';
import '../services/backend.dart';
import '../services/data_service.dart';
import '../services/session.dart';
import '../theme/app_theme.dart';
import '../widgets/app_background.dart';
import '../widgets/auth_text_field.dart';
import '../widgets/error_banner.dart';
import '../widgets/option_tile.dart';
import '../widgets/primary_button.dart';

/// The one-time basic profile, one question per screen.
///
/// Reached only from [AuthGate], and only while
/// `profile.onboardingCompleted` is false — so it is never navigated to, never
/// popped, and never seen twice. Finishing does not push the dashboard: it
/// flips the flag and calls [SessionScope.reload], and the gate swaps this
/// screen for the dashboard on the next build. One rule decides what a
/// signed-in user sees, rather than this screen and the gate each having an
/// opinion.
///
/// ### Persistence
///
/// Every answer is written to Supabase on Continue, not batched to the end: a
/// dropped connection nine questions in should cost the tenth answer, not the
/// nine before it. Each write is a full upsert of the row through
/// [DataService.saveProfile], so a resumed session cannot end up with a
/// half-written profile.
///
/// The local [UserProfile] is deliberately *not* pushed back through
/// [SessionScope.reload] between questions. Reload rebuilds the tree from
/// [AuthGate] down, which would tear this screen — and the answer in progress —
/// down eleven times on the way through.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();

  late UserProfile _profile;

  /// The answers as last persisted, keyed by question id.
  late Map<String, dynamic> _answers;

  int _index = 0;
  bool _initialised = false;
  bool _saving = false;
  String? _error;

  /// The current question's pending radio selection. Text answers live in
  /// [_textController] instead.
  String? _choice;

  OnboardingQuestion get _question => onboardingQuestions[_index];

  bool get _isLast => _index == onboardingQuestions.length - 1;

  /// Whether the current question has an answer good enough to move on with.
  /// Whitespace is not an answer.
  bool get _answered => _question.kind == OnboardingAnswerKind.text
      ? _textController.text.trim().isNotEmpty
      : _choice != null;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Once only. This runs again whenever an inherited widget above changes,
    // and re-seeding from the profile mid-flow would throw away the answer the
    // user is currently typing.
    if (_initialised) return;
    _initialised = true;

    _profile = SessionScope.of(context).profile;
    _answers = Map<String, dynamic>.from(_profile.onboardingAnswers);

    // Resume where they left off. The clamp covers a profile whose answers are
    // all present but whose completed flag is not set — unreachable through
    // this screen, since the last answer and the flag are written in one
    // upsert, but cheaper to absorb than to leave as a crash.
    _index = firstUnansweredIndex(_answers)
        .clamp(0, onboardingQuestions.length - 1);
    _loadPending();
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Seeds the editing state for [_index] from what is already stored, so
  /// stepping back shows the previous answer rather than a blank screen.
  void _loadPending() {
    final stored = _answers[_question.id];

    if (_question.kind == OnboardingAnswerKind.text) {
      _textController.text = stored is String ? stored : '';
      _choice = null;
      return;
    }

    // An option that is no longer offered is treated as unanswered: the
    // question set is editable, and a stored answer that has since been
    // reworded would otherwise leave a selection the user cannot see.
    _choice =
        stored is String && _question.options.contains(stored) ? stored : null;
    _textController.clear();
  }

  void _back() {
    if (_index == 0 || _saving) return;
    setState(() {
      _error = null;
      _index--;
      _loadPending();
    });
    _scrollToTop();
  }

  void _scrollToTop() {
    if (!_scrollController.hasClients) return;
    _scrollController.jumpTo(0);
  }

  /// Persists the current answer and moves on.
  ///
  /// [skip] records an explicit null for an optional question, which is what
  /// makes the skip stick: [firstUnansweredIndex] tests for the key's presence,
  /// so a skipped question is answered and resume steps past it. Leaving the
  /// key out instead would send a returning user back to the question they
  /// already declined.
  Future<void> _submit({bool skip = false}) async {
    if (_saving) return;
    if (!skip && !_answered) return;

    // Captured before the await: reading an inherited widget off a context
    // whose element may already be gone is a use-after-free waiting to happen.
    final reload = SessionScope.of(context).reload;

    final value = skip
        ? null
        : (_question.kind == OnboardingAnswerKind.text
            ? _textController.text.trim()
            : _choice);
    final next = {..._answers, _question.id: value};
    final finishing = _isLast;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final saved = await Backend.data.saveProfile(
        _applyAnswers(_profile, next, completed: finishing),
      );
      if (!mounted) return;

      _profile = saved;
      _answers = Map<String, dynamic>.from(saved.onboardingAnswers);

      if (finishing) {
        // The gate re-reads the profile, sees the flag, and renders the
        // dashboard in place of this screen. No setState after: this widget is
        // on its way out of the tree.
        await reload();
        return;
      }

      setState(() {
        _saving = false;
        _index++;
        _loadPending();
      });
      _scrollToTop();
    } on DataFailure catch (e) {
      if (!mounted) return;
      // Stay put with the answer intact. Continue re-runs the same write.
      setState(() {
        _saving = false;
        _error = e.message;
      });
    }
  }

  /// Builds the row to write: the answers blob, the promoted columns derived
  /// from it, and the completion flag on the final question.
  ///
  /// Columns are recomputed from [answers] every time rather than patched
  /// per-question. Both the blob and the columns then come from one source, so
  /// they cannot disagree — including on a profile that was resumed, or one
  /// whose columns were somehow written by something else.
  UserProfile _applyAnswers(
    UserProfile profile,
    Map<String, dynamic> answers, {
    required bool completed,
  }) {
    String? column(ProfileColumn which) {
      for (final q in onboardingQuestions) {
        if (q.column != which) continue;
        final value = answers[q.id];
        return value is String && value.isNotEmpty ? value : null;
      }
      return null;
    }

    return profile.copyWith(
      // copyWith keeps the existing value on null, so a not-yet-reached
      // question leaves its column alone instead of blanking it.
      location: column(ProfileColumn.location),
      ageRange: column(ProfileColumn.ageRange),
      occupation: column(ProfileColumn.occupation),
      onboardingAnswers: answers,
      onboardingCompleted: completed ? true : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    final horizontalPadding = screenWidth * 0.06;

    return AppBackground(
      child: Column(
        children: [
          _Header(
            step: _index + 1,
            total: onboardingQuestions.length,
            onBack: _index > 0 ? _back : null,
            padding: horizontalPadding,
          ),
          Expanded(
            child: SingleChildScrollView(
              controller: _scrollController,
              physics: const BouncingScrollPhysics(),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: screenHeight * 0.02),
                    Text(
                      _question.text,
                      style: TextStyle(
                        fontSize: screenWidth * 0.065,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textDark,
                        height: 1.3,
                        letterSpacing: -0.5,
                      ),
                    ),
                    if (_question.helper != null) ...[
                      SizedBox(height: screenHeight * 0.012),
                      Text(
                        _question.helper!,
                        style: TextStyle(
                          fontSize: screenWidth * 0.038,
                          color: AppTheme.textLight,
                          height: 1.4,
                        ),
                      ),
                    ],
                    SizedBox(height: screenHeight * 0.035),
                    if (_question.kind == OnboardingAnswerKind.text)
                      _buildTextInput()
                    else
                      ..._buildOptions(),
                    SizedBox(height: screenHeight * 0.03),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              0,
              horizontalPadding,
              screenHeight * 0.02,
            ),
            child: Column(
              children: [
                if (_error != null) ...[
                  ErrorBanner(message: _error!),
                  SizedBox(height: screenHeight * 0.015),
                ],
                PrimaryButton(
                  label: _isLast ? 'Finish' : 'Continue',
                  icon: Icons.arrow_forward,
                  busy: _saving,
                  // Null disables it: the client-side validation is simply that
                  // an unanswered required question has no way forward.
                  onPressed: _answered ? _submit : null,
                ),
                if (_question.optional) ...[
                  SizedBox(height: screenHeight * 0.008),
                  TextButton(
                    onPressed: _saving ? null : () => _submit(skip: true),
                    child: Text(
                      'Skip this one',
                      style: TextStyle(
                        fontSize: screenWidth * 0.038,
                        color: AppTheme.textLight,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildOptions() => [
        for (final option in _question.options)
          OptionTile(
            label: option,
            selected: _choice == option,
            // Selecting does not advance. An accidental tap on a mis-read
            // option would otherwise be committed to the database before the
            // user finished reading it.
            onTap: _saving ? () {} : () => setState(() => _choice = option),
          ),
      ];

  Widget _buildTextInput() => AuthTextField(
        controller: _textController,
        hintText: _question.hint ?? '',
        icon: _question.icon ?? Icons.short_text,
        enabled: !_saving,
        maxLines: _question.maxLines,
        keyboardType: _question.maxLines > 1
            ? TextInputType.multiline
            : TextInputType.text,
        textInputAction: _question.maxLines > 1
            ? TextInputAction.newline
            : TextInputAction.done,
        // Rebuilds so the Continue button tracks whether the field has content.
        onChanged: (_) => setState(() {}),
        onFieldSubmitted: (_) => _submit(),
      );
}

/// Step counter and back arrow, in the type the flow screens already use.
class _Header extends StatelessWidget {
  final int step;
  final int total;
  final VoidCallback? onBack;
  final double padding;

  const _Header({
    required this.step,
    required this.total,
    required this.onBack,
    required this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: padding,
        vertical: screenHeight * 0.02,
      ),
      child: Row(
        children: [
          // Holds its width when there is nowhere to go back to, so the step
          // counter does not jump left between the first and second question.
          SizedBox(
            width: screenWidth * 0.08,
            child: onBack == null
                ? null
                : GestureDetector(
                    onTap: onBack,
                    behavior: HitTestBehavior.opaque,
                    child: Icon(
                      Icons.arrow_back,
                      size: screenWidth * 0.055,
                      color: AppTheme.textLight,
                    ),
                  ),
          ),
          Text(
            'Step $step of $total',
            style: TextStyle(
              fontSize: screenWidth * 0.038,
              color: AppTheme.textLight,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
