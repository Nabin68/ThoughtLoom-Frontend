//describe_problem_screen.dart

import 'package:flutter/material.dart';

import '../models/chat.dart';
import '../models/message.dart';
import '../models/user_profile.dart';
import '../services/backend.dart';
import '../services/data_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_background.dart';
import '../widgets/dictation.dart';
import '../widgets/error_banner.dart';
import '../widgets/primary_button.dart';
import 'adaptive_flow_screen.dart';

/// The last scripted screen: the user's own account of the problem, typed or
/// dictated.
///
/// The MCQs before this one buy structure; this buys the thing the MCQs cannot
/// — the sentence where someone says what is actually going on. It is saved as
/// a single `free_text` message.
///
/// Dictation writes into the same controller as the keyboard. There is no
/// separate voice path and no voice-only state: speech is an input method for
/// the text field, so what gets saved is identical either way and the user can
/// dictate a paragraph and then fix a word by hand.
class DescribeProblemScreen extends StatefulWidget {
  final Chat chat;

  /// Not used here — carried through to the screen after this one, which is a
  /// pushed route and so cannot reach `SessionScope` for it.
  final UserProfile profile;

  const DescribeProblemScreen({
    super.key,
    required this.chat,
    required this.profile,
  });

  @override
  State<DescribeProblemScreen> createState() => _DescribeProblemScreenState();
}

class _DescribeProblemScreenState extends State<DescribeProblemScreen> {
  final _controller = TextEditingController();
  late final _dictation = DictationController(_controller)
    ..addListener(_onDictationChanged);

  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _dictation.init();
  }

  void _onDictationChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _dictation.removeListener(_onDictationChanged);
    _dictation.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _saving) return;

    await _dictation.stop();
    if (!mounted) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await Backend.data.addMessage(
        chatId: widget.chat.id,
        type: MessageType.freeText,
        // No questionText: free_text means the user's own words, and the model
        // documents this type as leaving the question null. The prompt they
        // were answering is a constant of this screen, not data.
        answerText: text,
        metadata: {
          'input_method': _dictation.usedDictation ? 'voice' : 'typed',
        },
      );
      if (!mounted) return;

      // The scripted part is over and saved. Everything past here is generated,
      // and pushReplacement keeps Back from walking into a screen that would
      // write a second description for the same chat.
      await Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => AdaptiveFlowScreen(
            chat: widget.chat,
            profile: widget.profile,
          ),
        ),
      );
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
    final hasText = _controller.text.trim().isNotEmpty;

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
                // Expanded + ellipsis rather than a bare Text: the label is
                // sized off screen width, so a wide viewport or a large system
                // font would otherwise overflow the row.
                Expanded(
                  child: Text(
                    '${widget.chat.category.label} · In your words',
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
              physics: const BouncingScrollPhysics(),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: screenHeight * 0.01),
                    Text(
                      'So — what is going on?',
                      style: TextStyle(
                        fontSize: screenWidth * 0.08,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textDark,
                        height: 1.2,
                        letterSpacing: -0.5,
                      ),
                    ),
                    SizedBox(height: screenHeight * 0.015),
                    Text(
                      _dictation.available
                          ? 'Say it however it comes out. Type, or tap the mic\nand talk.'
                          : 'Say it however it comes out — there is no wrong way\nto put it.',
                      style: TextStyle(
                        fontSize: screenWidth * 0.038,
                        color: AppTheme.textLight,
                        height: 1.4,
                      ),
                    ),
                    SizedBox(height: screenHeight * 0.03),
                    _ProblemField(
                      controller: _controller,
                      enabled: !_saving,
                      listening: _dictation.listening,
                      onChanged: () => setState(() {}),
                    ),
                    SizedBox(height: screenHeight * 0.02),
                    if (_dictation.available)
                      DictationButton(
                        controller: _dictation,
                        onPressed: _saving ? null : _dictation.toggle,
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
                  label: 'Continue',
                  icon: Icons.arrow_forward,
                  busy: _saving,
                  onPressed: hasText ? _submit : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The big cream paragraph box, in the shape the old summary screen used.
class _ProblemField extends StatelessWidget {
  final TextEditingController controller;
  final bool enabled;
  final bool listening;
  final VoidCallback onChanged;

  const _ProblemField({
    required this.controller,
    required this.enabled,
    required this.listening,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;

    return Container(
      constraints: BoxConstraints(minHeight: screenHeight * 0.22),
      decoration: BoxDecoration(
        color: AppTheme.cardBg.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(24),
        // Lights up while the mic is live, so the field itself shows where the
        // words are coming from.
        border: listening
            ? Border.all(color: AppTheme.primary.withValues(alpha: 0.6), width: 2)
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            offset: const Offset(0, 4),
            blurRadius: 12,
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        enabled: enabled,
        maxLines: null,
        minLines: 7,
        onChanged: (_) => onChanged(),
        keyboardType: TextInputType.multiline,
        style: TextStyle(
          fontSize: screenWidth * 0.042,
          color: AppTheme.textOnCard,
          height: 1.5,
        ),
        decoration: InputDecoration(
          hintText: "I keep going back and forth on this because...",
          hintStyle: TextStyle(
            fontSize: screenWidth * 0.04,
            color: AppTheme.textLight.withValues(alpha: 0.5),
            height: 1.5,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide.none,
          ),
          contentPadding: EdgeInsets.symmetric(
            horizontal: screenWidth * 0.05,
            vertical: screenHeight * 0.022,
          ),
        ),
      ),
    );
  }
}

