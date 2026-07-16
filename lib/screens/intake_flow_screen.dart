//intake_flow_screen.dart

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
import '../widgets/auth_text_field.dart';
import '../widgets/error_banner.dart';
import '../widgets/option_tile.dart';
import '../widgets/primary_button.dart';
import 'describe_problem_screen.dart';

/// A category's scripted opening: four or five questions, one per screen.
///
/// The chat row already exists by the time this opens — the dashboard creates
/// it, so a user who abandons here leaves a real, resumable chat rather than
/// nothing.
///
/// ### Persistence
///
/// Each answer is one `messages` row, written on Continue, typed `intake`. The
/// schema's `intake` is exactly this — "fixed per-category MCQ from the
/// scripted opening" — so no new enum value was needed for what Prompt 3 calls
/// hardcoded-intake.
///
/// Ordering is the database's job, not this screen's: `addMessage` takes the
/// next `seq` for the chat, so rows read back in the order they were asked
/// without this screen tracking an index for them.
///
/// Stepping back re-opens the row that question already wrote, rather than
/// adding a second one — see [_written]. Without that, a user who went back to
/// change an answer would leave the chat holding both answers with no way to
/// tell which one they meant.
///
/// Resuming a chat *across launches* is deliberately not handled here. That is
/// Prompt 6's, which will know how many intake rows a chat already has; a
/// second, screen-local resume rule now would only be something to unpick.
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

  /// Built once, from the profile, at the top of the flow. Rebuilding it per
  /// frame would let a question change out from under a half-typed answer.
  late final List<IntakeQuestion> _questions =
      questionsFor(widget.chat.category, widget.profile);

  /// The row each answered question wrote, in question order. A question at an
  /// index already in here is being *re-answered*, so its row is updated rather
  /// than a new one appended — which keeps one row per question and leaves
  /// `seq` alone.
  final List<Message> _written = [];

  int _index = 0;
  bool _saving = false;
  String? _error;
  String? _choice;

  IntakeQuestion get _question => _questions[_index];

  bool get _isLast => _index == _questions.length - 1;

  bool get _answered => _question.kind == IntakeAnswerKind.text
      ? _textController.text.trim().isNotEmpty
      : _choice != null;

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Back a question, or out of the flow entirely from the first one.
  ///
  /// Leaving early is not an error and nothing is rolled back: the chat row and
  /// any answers already given stay exactly as they are, and history shows the
  /// chat as unfinished. Prompt 6 picks it up from there.
  void _back() {
    if (_saving) return;
    if (_index == 0) {
      Navigator.pop(context);
      return;
    }

    setState(() {
      _error = null;
      _index--;
      final previous = _written[_index].answerText;
      if (_question.kind == IntakeAnswerKind.text) {
        _textController.text = previous ?? '';
        _choice = null;
      } else {
        _choice = previous;
        _textController.clear();
      }
    });
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
  }

  Future<void> _submit({bool skip = false}) async {
    if (_saving) return;
    if (!skip && !_answered) return;

    final question = _question;
    final index = _index;
    final answer = skip
        ? null
        : (question.kind == IntakeAnswerKind.text
            ? _textController.text.trim()
            : _choice);
    final metadata = <String, dynamic>{
      'question_id': question.id,
      if (question.kind == IntakeAnswerKind.choice) 'options': question.options,
      if (skip) 'skipped': true,
    };

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final existing = index < _written.length ? _written[index] : null;
      final saved = existing == null
          ? await Backend.data.addMessage(
              chatId: widget.chat.id,
              type: MessageType.intake,
              // Stored verbatim, so a transcript never has to rebuild the
              // question list to know what was asked — which matters because
              // the list depends on a profile that can change.
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
      if (!mounted) return;

      if (existing == null) {
        _written.add(saved);
      } else {
        _written[index] = saved;
      }

      if (_isLast) {
        // pushReplacement: the intake is written and the questions are behind
        // us. Letting Back walk into them again would write a second set of
        // rows for the same chat.
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
        _choice = null;
        _textController.clear();
      });
      if (_scrollController.hasClients) _scrollController.jumpTo(0);
    } on DataFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.message;
      });
    }
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
                // Always present, unlike onboarding's: from the first question
                // it leaves the flow, which is the only way out other than the
                // system back gesture.
                GestureDetector(
                  onTap: _back,
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
                    '${widget.chat.category.label} · Step ${_index + 1} of ${_questions.length}',
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
                    if (_question.kind == IntakeAnswerKind.text)
                      AuthTextField(
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
                          selected: _choice == option,
                          onTap: _saving
                              ? () {}
                              : () => setState(() => _choice = option),
                        ),
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
                  label: _isLast ? 'Continue' : 'Next',
                  icon: Icons.arrow_forward,
                  busy: _saving,
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
}
