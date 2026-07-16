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
import '../widgets/app_header.dart';
import '../widgets/app_button.dart';
import '../widgets/app_text_field.dart';
import '../widgets/error_banner.dart';
import '../widgets/option_tile.dart';

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

  /// Where this run started.
  ///
  /// Almost always 0. It is not for a returning user who already finished
  /// onboarding and is being asked only the questions added since — see
  /// `AuthGate._needsOnboarding`. Counting "Step 13 of 14" at someone who
  /// believes they did this months ago is a lie about how long it will take, and
  /// they will put the phone down. The counter is relative to what is actually
  /// left, and [_toppingUp] changes the words around it.
  int _startIndex = 0;

  /// Whether this is a returning user being asked a couple of new questions
  /// rather than a new user being onboarded.
  bool _toppingUp = false;

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
    // The flag says they have been through this before; the index says there is
    // still something to ask. Both together is the top-up case.
    _toppingUp = _profile.onboardingCompleted && _index > 0;
    // Only a top-up gets a relative counter. Someone who abandoned onboarding
    // halfway and came back is still doing all fourteen, and telling them
    // "Step 1 of 12" would restart the count they were already partway through.
    _startIndex = _toppingUp ? _index : 0;
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
    // Never back past where this run began: for a top-up the questions before
    // [_startIndex] were answered in another session, and walking into them here
    // would look like the app had decided to re-onboard them after all.
    if (_index <= _startIndex || _saving) return;
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
    final remaining = onboardingQuestions.length - _startIndex;
    final step = _index - _startIndex + 1;

    return AppBackground(
      child: Column(
        children: [
          AppHeader(
            title: _toppingUp ? 'One or two new things' : 'Getting to know you',
            subtitle: 'Step $step of $remaining',
            onBack: _index > _startIndex ? _back : null,
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: AppTheme.s5),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: step / remaining),
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOut,
                builder: (context, value, _) => LinearProgressIndicator(
                  value: value,
                  minHeight: 4,
                  backgroundColor: AppTheme.primary.withValues(alpha: 0.14),
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(AppTheme.primary),
                ),
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              controller: _scrollController,
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                AppTheme.s5,
                AppTheme.s5,
                AppTheme.s5,
                AppTheme.s6,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Only for a returning user, and only on the first of their new
                  // questions: they finished this months ago and are entitled to
                  // know why they are looking at it again.
                  if (_toppingUp && _index == _startIndex) ...[
                    _NewQuestionsNote(),
                    SizedBox(height: AppTheme.s5),
                  ],
                  Text(_question.text, style: AppTheme.title(context)),
                  if (_question.helper != null) ...[
                    SizedBox(height: AppTheme.s2),
                    Text(_question.helper!, style: AppTheme.secondary(context)),
                  ],
                  SizedBox(height: AppTheme.s5),
                  if (_question.kind == OnboardingAnswerKind.text)
                    _buildTextInput()
                  else
                    ..._buildOptions(),
                ],
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              AppTheme.s5,
              0,
              AppTheme.s5,
              AppTheme.s4,
            ),
            child: Column(
              children: [
                if (_error != null) ...[
                  ErrorBanner(message: _error!),
                  SizedBox(height: AppTheme.s3),
                ],
                AppButton(
                  label: _isLast ? 'Finish' : 'Continue',
                  icon: Icons.arrow_forward_rounded,
                  busy: _saving,
                  // Null disables it: the client-side validation is simply that
                  // an unanswered required question has no way forward.
                  onPressed: _answered ? _submit : null,
                ),
                if (_question.optional) ...[
                  SizedBox(height: AppTheme.s2),
                  AppButton.quiet(
                    label: 'Skip this one',
                    onPressed: _saving ? null : () => _submit(skip: true),
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
            enabled: !_saving,
            // Selecting does not advance. An accidental tap on a mis-read option
            // would otherwise be committed to the database before the user
            // finished reading it.
            onTap: () => setState(() => _choice = option),
          ),
      ];

  Widget _buildTextInput() => AppTextField(
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

/// Why a returning user is seeing this screen again.
class _NewQuestionsNote extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(AppTheme.s4),
      decoration: BoxDecoration(
        color: AppTheme.accentSoft,
        borderRadius: BorderRadius.circular(AppTheme.rSm),
        border: const Border(
          left: BorderSide(color: AppTheme.accentDeep, width: 3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.waving_hand_outlined,
            size: 17,
            color: AppTheme.accentDeep,
          ),
          SizedBox(width: AppTheme.s3),
          Expanded(
            child: Text(
              'ThoughtLoom has learned to ask better questions since you signed '
              'up, and it needs a couple of things it never asked for. Nothing '
              'you already answered is being asked again.',
              style: AppTheme.secondary(context)
                  .copyWith(color: AppTheme.textOnCard),
            ),
          ),
        ],
      ),
    );
  }
}
