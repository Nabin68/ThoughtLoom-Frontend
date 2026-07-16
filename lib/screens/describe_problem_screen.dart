//describe_problem_screen.dart

import 'package:flutter/material.dart';

import '../models/chat.dart';
import '../models/message.dart';
import '../models/user_profile.dart';
import '../services/backend.dart';
import '../services/data_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_background.dart';
import '../widgets/app_button.dart';
import '../widgets/app_header.dart';
import '../widgets/app_text_field.dart';
import '../widgets/dictation.dart';
import '../widgets/error_banner.dart';
import 'adaptive_flow_screen.dart';

/// The last scripted screen: the user's own account of the problem, typed or
/// dictated.
///
/// The MCQs before this one buy structure; this buys the thing the MCQs cannot —
/// the sentence where someone says what is actually going on. It is saved as a
/// single `free_text` message.
///
/// ### Dictation and the keyboard are one input, not two
///
/// Speech writes into the same controller as the keyboard, so what gets saved is
/// identical either way and someone can dictate a paragraph and then fix a word
/// by hand.
///
/// That only works if the two never fight for the field. They used to: the mic
/// stayed live while the user tapped in to type, and every partial result
/// rewrote the box from the last committed transcript — deleting what they had
/// just typed. So reaching for the field now turns the microphone off. Tapping
/// the text box is a statement of intent, and the intent is "I will type this
/// bit myself".
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
        // documents this type as leaving the question null. The prompt they were
        // answering is a constant of this screen, not data.
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
    final hasText = _controller.text.trim().isNotEmpty;

    return AppBackground(
      child: Column(
        children: [
          AppHeader(
            title: widget.chat.category.label,
            subtitle: 'In your words',
            onBack: () => Navigator.pop(context),
          ),
          Expanded(
            child: SingleChildScrollView(
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
                  Text('So — what is going on?', style: AppTheme.display(context)),
                  SizedBox(height: AppTheme.s3),
                  Text(
                    _dictation.available
                        ? 'Say it however it comes out. Type it, or tap the mic '
                            'and talk — it is the same box either way.'
                        : 'Say it however it comes out — there is no wrong way '
                            'to put it.',
                    style: AppTheme.secondary(context),
                  ),
                  SizedBox(height: AppTheme.s5),
                  AppTextField(
                    controller: _controller,
                    hintText: 'I keep going back and forth on this because...',
                    enabled: !_saving,
                    maxLines: 12,
                    minLines: 7,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    listening: _dictation.listening,
                    onChanged: (_) => setState(() {}),
                    // Reaching for the keyboard turns the mic off. Without this
                    // the recogniser's next partial result overwrites whatever
                    // was typed in the meantime.
                    onTap: _dictation.stop,
                  ),
                  if (_dictation.available) ...[
                    SizedBox(height: AppTheme.s4),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: DictationButton(
                        controller: _dictation,
                        onPressed: _saving
                            ? null
                            : () {
                                // Dismisses the keyboard, which would otherwise
                                // sit over the field the words are landing in —
                                // and which, being focused, is also a race with
                                // the onTap above.
                                FocusScope.of(context).unfocus();
                                _dictation.toggle();
                              },
                      ),
                    ),
                  ],
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
                  label: 'Continue',
                  icon: Icons.arrow_forward_rounded,
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
