//dictation.dart

import 'package:flutter/material.dart';

import '../services/backend.dart';
import '../theme/app_theme.dart';

/// Drives dictation into a [TextEditingController].
///
/// Extracted from the describe-your-problem screen once the adaptive flow and
/// the continued chat needed the same behaviour. Three copies of "remember what
/// was typed, append what was heard, keep the caret at the end" would have
/// drifted apart by the second one.
///
/// Fails soft throughout: if there is no recogniser, [available] stays false
/// and callers simply do not offer the mic. The text field always works.
class DictationController extends ChangeNotifier {
  final TextEditingController target;

  DictationController(this.target);

  bool _available = false;
  bool _listening = false;
  bool _used = false;

  /// Whether dictation can run at all here. False until [init] says otherwise.
  bool get available => _available;

  bool get listening => _listening;

  /// Whether speech contributed to the current text. Reported to the API so it
  /// can allow for transcription noise — a recogniser's homophones read very
  /// differently from a typo.
  bool get usedDictation => _used;

  /// What was in the field when listening started. The recogniser reports the
  /// whole phrase each time rather than a delta, so appending to this is what
  /// lets someone dictate after already typing.
  String _before = '';

  /// Asks the plugin whether it can run, which is also where the microphone
  /// permission is requested.
  ///
  /// Call it when the screen opens, not at launch: a permission dialog nobody
  /// asked for reads as a shakedown. But not on first tap either — a mic button
  /// that appears and then fails is worse than one never offered, so its
  /// presence is itself the honest signal.
  Future<void> init() async {
    final available = await Backend.speech.initialize();
    _available = available;
    notifyListeners();
  }

  Future<void> toggle() async {
    if (_listening) {
      await stop();
      return;
    }

    _before = target.text;
    _listening = true;
    _used = true;
    notifyListeners();

    await Backend.speech.listen(
      onTranscript: (transcript) {
        final prefix = _before.isEmpty ? '' : '${_before.trimRight()} ';
        target.value = TextEditingValue(
          text: '$prefix$transcript',
          // Caret to the end, or the field fights the user for the cursor every
          // time a new partial result lands.
          selection:
              TextSelection.collapsed(offset: prefix.length + transcript.length),
        );
      },
      // Fires when the recogniser stops on its own — a long pause, or the
      // listen window expiring — so the button does not stay lit over a
      // microphone that is off.
      onDone: () {
        _listening = false;
        notifyListeners();
      },
    );
  }

  Future<void> stop() async {
    if (!_listening) return;
    await Backend.speech.stop();
    _listening = false;
    notifyListeners();
  }

  @override
  void dispose() {
    // stop, not dispose: Backend.speech outlives this screen and the next one
    // will want it.
    Backend.speech.stop();
    super.dispose();
  }
}

/// Mic toggle, in the cream pill the option rows use.
class DictationButton extends StatelessWidget {
  final DictationController controller;
  final VoidCallback? onPressed;

  /// What it says when idle. The wording differs by screen — "Or say it out
  /// loud" under a blank page, "Answer out loud" beside a question.
  final String label;

  const DictationButton({
    super.key,
    required this.controller,
    required this.onPressed,
    this.label = 'Or say it out loud',
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final listening = controller.listening;

    return GestureDetector(
      onTap: onPressed,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(
          horizontal: screenWidth * 0.05,
          vertical: screenWidth * 0.035,
        ),
        decoration: BoxDecoration(
          color: listening
              ? AppTheme.selected
              : AppTheme.cardBg.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(AppTheme.pillRadius),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              offset: const Offset(0, 4),
              blurRadius: 12,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              listening ? Icons.stop_rounded : Icons.mic_none_rounded,
              size: screenWidth * 0.05,
              color: listening ? Colors.white : AppTheme.textOnCard,
            ),
            SizedBox(width: screenWidth * 0.025),
            Text(
              listening ? 'Listening — tap to stop' : label,
              style: TextStyle(
                fontSize: screenWidth * 0.038,
                color: listening ? Colors.white : AppTheme.textOnCard,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A round mic button for a chat composer, where a pill would not fit.
class DictationIconButton extends StatelessWidget {
  final DictationController controller;
  final VoidCallback? onPressed;

  const DictationIconButton({
    super.key,
    required this.controller,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final listening = controller.listening;

    return GestureDetector(
      onTap: onPressed,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: screenWidth * 0.11,
        height: screenWidth * 0.11,
        decoration: BoxDecoration(
          color: listening ? AppTheme.selected : Colors.transparent,
          shape: BoxShape.circle,
        ),
        child: Icon(
          listening ? Icons.stop_rounded : Icons.mic_none_rounded,
          size: screenWidth * 0.055,
          color: listening ? Colors.white : AppTheme.textOnCard,
        ),
      ),
    );
  }
}
