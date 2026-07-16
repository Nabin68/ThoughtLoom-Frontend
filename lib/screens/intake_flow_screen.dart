//intake_flow_screen.dart

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/intake_questions.dart';
import '../models/chat.dart';
import '../models/intake_question.dart';
import '../models/message.dart';
import '../models/user_profile.dart';
import '../services/backend.dart';
import '../services/data_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_background.dart';
import '../widgets/app_button.dart';
import '../widgets/app_header.dart';
import '../widgets/app_text_field.dart';
import '../widgets/error_banner.dart';
import '../widgets/option_tile.dart';
import 'describe_problem_screen.dart';

/// A category's scripted opening: a handful of questions, one per screen.
///
/// The chat row already exists by the time this opens — the dashboard creates
/// it, so a user who abandons here leaves a real chat rather than nothing.
///
/// ### Persistence
///
/// Each answer is one `messages` row, written on Continue, typed `intake`.
/// Ordering is the database's job: `addMessage` takes the next `seq` for the
/// chat, so rows read back in the order they were asked without this screen
/// tracking an index for them.
///
/// Stepping back re-opens the row that question already wrote rather than adding
/// a second — see [_written]. Without that, a user who went back to change an
/// answer would leave the chat holding both answers with no way to tell which
/// one they meant.
///
/// ### The question list is not fixed
///
/// It is rebuilt from the answers so far after every Continue, because the
/// relationship set words its later questions around the person the first one
/// established. Answering "My girlfriend" and then going back to "My parents"
/// does not just re-word what is ahead — it invalidates rows already written,
/// which were answers to questions about someone else. Those rows are *wrong*,
/// not stale: the model reads the transcript as a record of what this person
/// said. So [_commit] deletes them. See [_tailChanged].
class IntakeFlowScreen extends StatefulWidget {
  final Chat chat;
  final UserProfile profile;

  const IntakeFlowScreen({super.key, required this.chat, required this.profile});

  @override
  State<IntakeFlowScreen> createState() => _IntakeFlowScreenState();
}

class _IntakeFlowScreenState extends State<IntakeFlowScreen> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();

  /// Answers so far, keyed by question id — what [questionsFor] reads to decide
  /// what comes next.
  final Map<String, String?> _answers = {};

  late List<IntakeQuestion> _questions =
      questionsFor(widget.chat.category, widget.profile, _answers);

  /// The row each answered question wrote, in question order. A question at an
  /// index already in here is being *re-answered*, so its row is updated rather
  /// than a new one appended — which keeps one row per question and leaves `seq`
  /// alone.
  final List<Message> _written = [];

  int _index = 0;
  bool _saving = false;
  String? _error;

  /// The pending selection. A set for both kinds: a single-choice question is
  /// the same thing with a cap of one, and two code paths for "what is ticked"
  /// would drift.
  final Set<String> _choices = {};

  IntakeQuestion get _question => _questions[_index];

  bool get _isLast => _index == _questions.length - 1;

  bool get _answered => _question.kind == IntakeAnswerKind.text
      ? _textController.text.trim().isNotEmpty
      : _choices.isNotEmpty;

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Back a question, or out of the flow entirely from the first one.
  ///
  /// Leaving early is not an error and nothing is rolled back: the chat row and
  /// any answers already given stay as they are, and history shows the chat as
  /// unfinished.
  void _back() {
    if (_saving) return;
    if (_index == 0) {
      Navigator.pop(context);
      return;
    }

    setState(() {
      _error = null;
      _index--;
      _loadPending();
    });
    _toTop();
  }

  /// Seeds the editing state for [_index] from what was stored, so stepping back
  /// shows the previous answer rather than a blank screen.
  void _loadPending() {
    _choices.clear();
    _textController.clear();

    final stored = _answers[_question.id];
    if (stored == null) return;

    if (_question.kind == IntakeAnswerKind.text) {
      _textController.text = stored;
      return;
    }
    // Anything no longer on offer is dropped rather than shown as a ghost tick:
    // the option lists are rebuilt from the profile and from earlier answers, so
    // a stored answer can genuinely no longer exist.
    _choices.addAll(
      stored.split(selectionSeparator).where(_question.options.contains),
    );
  }

  void _toTop() {
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
  }

  void _select(String option) {
    setState(() {
      if (_question.isMulti) {
        // Ticking is a toggle; the last tick can be removed, and the Continue
        // button simply goes inert. Nothing here forces an answer the user does
        // not have.
        _choices.contains(option)
            ? _choices.remove(option)
            : _choices.add(option);
      } else {
        // Selecting does not auto-advance: an accidental tap on a mis-read
        // option would otherwise be committed before the user finished reading
        // it.
        _choices
          ..clear()
          ..add(option);
      }
    });
  }

  /// The answer, as it will be stored.
  ///
  /// Multi-select is joined in *option order* rather than tap order, so two
  /// people who ticked the same three things produce the same string — the
  /// transcript is read by a model, and "A; C; B" and "A; B; C" being different
  /// answers to the same question is noise it does not need.
  String? _answerValue() {
    if (_question.kind == IntakeAnswerKind.text) {
      return _textController.text.trim();
    }
    return joinSelections(_question.options.where(_choices.contains));
  }

  Future<void> _submit({bool skip = false}) async {
    if (_saving) return;
    if (!skip && !_answered) return;

    final question = _question;
    final index = _index;
    final answer = skip ? null : _answerValue();

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await _commit(question: question, index: index, answer: answer);
      if (!mounted) return;

      if (_index >= _questions.length - 1) {
        // pushReplacement: the intake is written and the questions are behind
        // us. Letting Back walk into them again would write a second set of rows
        // for the same chat.
        await Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => DescribeProblemScreen(
              chat: widget.chat,
              profile: widget.profile,
            ),
          ),
        );
        return;
      }

      setState(() {
        _saving = false;
        _index++;
        _loadPending();
      });
      _toTop();
    } on DataFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.message;
      });
    }
  }

  /// Writes the answer, then rebuilds what comes after it.
  Future<void> _commit({
    required IntakeQuestion question,
    required int index,
    required String? answer,
  }) async {
    final metadata = <String, dynamic>{
      'question_id': question.id,
      if (question.isChoice) ...{
        'options': question.options,
        'selected': answer == null || answer.isEmpty
            ? const <String>[]
            : answer.split(selectionSeparator),
        'multi': question.isMulti,
      },
      if (answer == null) 'skipped': true,
    };

    final existing = index < _written.length ? _written[index] : null;
    final saved = existing == null
        ? await Backend.data.addMessage(
            chatId: widget.chat.id,
            type: MessageType.intake,
            // Stored verbatim, so a transcript never has to rebuild the question
            // list to know what was asked — which matters more now that the list
            // depends on answers as well as on a profile that can change.
            questionText: question.text,
            answerText: answer,
            metadata: metadata,
          )
        // Built by hand rather than with copyWith: copyWith reads
        // `answerText ?? this.answerText`, so re-answering with a skip would
        // silently keep the answer being skipped.
        : await Backend.data.saveMessage(
            Message(
              id: existing.id,
              chatId: existing.chatId,
              seq: existing.seq,
              type: existing.type,
              questionText: existing.questionText,
              answerText: answer,
              metadata: metadata,
              createdAt: existing.createdAt,
            ),
          );

    if (existing == null) {
      _written.add(saved);
    } else {
      _written[index] = saved;
    }

    _answers[question.id] = answer;
    final rebuilt =
        questionsFor(widget.chat.category, widget.profile, _answers);

    if (_tailChanged(_questions, rebuilt, index)) {
      // Everything past this question was answering a question that, as of this
      // edit, was never asked. Drop the rows before the list moves on, so the
      // chat cannot hold an answer to a question it does not contain.
      for (var i = index + 1; i < _written.length; i++) {
        await Backend.data.deleteMessage(_written[i].id);
        _answers.remove(_questions[i].id);
      }
      if (_written.length > index + 1) {
        _written.removeRange(index + 1, _written.length);
      }
    }

    _questions = rebuilt;
  }

  /// Whether anything after [from] is a different question than it was.
  ///
  /// Compares what the user would actually see. An id alone is not enough: the
  /// relationship set keeps `rel_spoken` at the same index and the same id while
  /// rewriting it from "Have you told her?" to "Have you told them?", and the
  /// stored answer — "She has no idea" — belongs to neither the new question nor
  /// this chat.
  static bool _tailChanged(
    List<IntakeQuestion> before,
    List<IntakeQuestion> after,
    int from,
  ) {
    if (before.length != after.length) return true;
    for (var i = from + 1; i < before.length; i++) {
      if (before[i].id != after[i].id ||
          before[i].text != after[i].text ||
          !listEquals(before[i].options, after[i].options)) {
        return true;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return AppBackground(
      child: Column(
        children: [
          AppHeader(
            title: widget.chat.category.label,
            subtitle: 'Question ${_index + 1} of ${_questions.length}',
            // Always present, unlike onboarding's: from the first question it
            // leaves the flow, which is the only way out other than the system
            // back gesture.
            onBack: _back,
          ),
          _Progress(step: _index + 1, total: _questions.length),
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
                  Text(_question.text, style: AppTheme.title(context)),
                  if (_question.helper != null) ...[
                    SizedBox(height: AppTheme.s2),
                    Text(
                      _question.helper!,
                      style: AppTheme.secondary(context),
                    ),
                  ],
                  SizedBox(height: AppTheme.s5),
                  if (_question.kind == IntakeAnswerKind.text)
                    AppTextField(
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
                      onChanged: (_) => setState(() {}),
                    )
                  else
                    for (final option in _question.options)
                      OptionTile(
                        label: option,
                        selected: _choices.contains(option),
                        mode: _question.isMulti
                            ? ChoiceMode.multi
                            : ChoiceMode.single,
                        enabled: !_saving,
                        onTap: () => _select(option),
                      ),
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
                  label: _isLast ? 'Continue' : 'Next',
                  icon: Icons.arrow_forward_rounded,
                  busy: _saving,
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
}

/// How far through, as a bar rather than only a number.
///
/// The count in the header answers "which question is this"; the bar answers
/// "how much longer" at a glance, without reading. On a flow someone is doing at
/// 1am about their relationship, that is the difference between finishing and
/// putting the phone down.
class _Progress extends StatelessWidget {
  final int step;
  final int total;

  const _Progress({required this.step, required this.total});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: AppTheme.s5),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: total == 0 ? 0 : step / total),
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOut,
          builder: (context, value, _) => LinearProgressIndicator(
            value: value,
            minHeight: 4,
            backgroundColor: AppTheme.primary.withValues(alpha: 0.14),
            valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primary),
          ),
        ),
      ),
    );
  }
}
