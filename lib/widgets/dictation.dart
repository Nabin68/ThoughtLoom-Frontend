//dictation.dart

import 'package:flutter/material.dart';

import '../services/backend.dart';
import '../theme/app_theme.dart';

/// Drives dictation into a [TextEditingController].
///
/// ### The model: the mic is on until you turn it off
///
/// A device recogniser thinks in *utterances*. It opens, hears a phrase, and
/// closes itself the moment you pause to think — which is exactly when someone
/// describing a hard situation stops talking. The previous version handed that
/// model straight to the user, and it produced the two bugs this class exists to
/// kill:
///
///  * the button showed "off" while the microphone was still recording, because
///    the service reported the session as done the instant it *started* (see
///    [SpeechService]); and
///  * carrying on after a pause wiped what had already been said, because each
///    new session's transcript replaced the field's contents rather than
///    extending them.
///
/// So a session ending is no longer the user's business. [_wantOn] is the user's
/// intent — set by [start] and [stop], and nothing else — and when the
/// recogniser closes a session while that is still true, [_openSession] simply
/// opens another. What was heard is committed to [_committed] first, so the next
/// session appends rather than overwrites.
///
/// Fails soft throughout: if there is no recogniser, [available] stays false and
/// callers do not offer the mic. The text field always works.
class DictationController extends ChangeNotifier {
  final TextEditingController target;

  DictationController(this.target);

  /// How many consecutive sessions may hear nothing before the microphone turns
  /// itself off.
  ///
  /// A session ends after about five seconds of silence, so this is roughly
  /// fifteen. It is a guard against spinning forever on a microphone that will
  /// never hear anything — permission revoked mid-session, a headset unplugged —
  /// and it is also just good manners: a mic that stays live in the background
  /// indefinitely is a thing to be sorry about, not a feature.
  static const _maxSilentSessions = 3;

  bool _available = false;
  bool _used = false;

  /// The user's intent, and the only thing the button reflects. Deliberately
  /// *not* whether a recogniser session happens to be open this millisecond —
  /// sessions churn on every pause, and a button that flickered with them would
  /// be worse than the one that never moved.
  bool _wantOn = false;

  /// Whether a request to open a session is in flight. Two taps in quick
  /// succession would otherwise open two.
  bool _opening = false;

  /// The field's contents before the current utterance. The recogniser reports
  /// the whole phrase each time rather than a delta, so appending to this is
  /// what lets someone dictate, pause, and carry on — and what lets them type a
  /// sentence first and then talk.
  String _committed = '';

  /// Whether [_committed] has been taken for the live session yet.
  ///
  /// It is taken when the session first *hears* something, not when it opens.
  /// The difference is a whole class of bug: sessions are reopened the instant
  /// the recogniser closes one, so a base captured at open time is captured
  /// before the user has had the pause they stopped talking in — and anything
  /// they do with that pause, like fixing the word the recogniser got wrong, is
  /// then overwritten by the next thing they say. Waiting until there is
  /// actually a transcript to append means the base is whatever is really in the
  /// field by then.
  bool _baseTaken = false;

  /// Whether the live session has heard anything at all yet.
  bool _heardThisSession = false;
  int _silentSessions = 0;

  /// Whether dictation can run at all here. False until [init] says otherwise.
  bool get available => _available;

  /// Whether the microphone is on, as the user understands it.
  bool get listening => _wantOn;

  /// Whether speech contributed to the current text. Reported to the API so it
  /// can allow for transcription noise — a recogniser's homophones read very
  /// differently from a typo.
  bool get usedDictation => _used;

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

  Future<void> toggle() => _wantOn ? stop() : start();

  Future<void> start() async {
    if (!_available || _wantOn || _opening) return;

    _wantOn = true;
    _used = true;
    _silentSessions = 0;
    notifyListeners();

    await _openSession();
  }

  Future<void> stop() async {
    if (!_wantOn) return;
    // Cleared before the await, so the session-end this triggers sees the intent
    // already gone and does not helpfully reopen the microphone.
    _wantOn = false;
    notifyListeners();
    await Backend.speech.stop();
  }

  Future<void> _openSession() async {
    if (!_wantOn || _opening) return;
    _opening = true;
    _heardThisSession = false;
    _baseTaken = false;

    final started = await Backend.speech.listen(
      onResult: (transcript, _) => _write(transcript),
      onSessionEnd: _onSessionEnd,
    );

    _opening = false;
    if (!started && _wantOn) {
      // The recogniser would not open. Saying so by turning the button off beats
      // leaving it lit over a microphone that is not running.
      _wantOn = false;
      notifyListeners();
    }
  }

  void _write(String transcript) {
    if (transcript.isEmpty) return;
    if (!_baseTaken) {
      // Taken now rather than when the session opened — see [_baseTaken].
      // Reading the field rather than remembering the last transcript is what
      // makes a correction stick instead of being overwritten by the thing it
      // corrected.
      _committed = target.text;
      _baseTaken = true;
    }
    _heardThisSession = true;

    final prefix = _committed.isEmpty ? '' : '${_committed.trimRight()} ';
    final text = '$prefix$transcript';
    target.value = TextEditingValue(
      text: text,
      // Caret to the end, or the field fights the user for the cursor every time
      // a new partial result lands.
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  /// The recogniser closed a session. Whether that is the end of anything is
  /// decided here, not by the recogniser.
  void _onSessionEnd() {
    if (!_wantOn) {
      notifyListeners();
      return;
    }

    if (_heardThisSession) {
      _silentSessions = 0;
    } else if (++_silentSessions >= _maxSilentSessions) {
      _wantOn = false;
      notifyListeners();
      return;
    }

    _openSession();
  }

  @override
  void dispose() {
    _wantOn = false;
    // stop, not dispose: Backend.speech outlives this screen and the next one
    // will want it.
    Backend.speech.stop();
    super.dispose();
  }
}

/// The live-microphone dot: a red circle that breathes.
///
/// Every voice recorder and every camera has trained people to read this exact
/// mark as "recording now", which is a stronger signal than any colour change to
/// the button around it — and it is *motion*, so it says the app is still
/// listening rather than frozen.
class _LiveDot extends StatefulWidget {
  final double size;
  final Color color;

  const _LiveDot({required this.size, required this.color});

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 1, end: 0.25).animate(
        CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
      ),
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      ),
    );
  }
}

/// The mic as a full-width pill: what the describe screen and the adaptive
/// questions offer under their text box.
///
/// Off and on are two visibly different objects rather than the same pill in two
/// tints — outlined and quiet versus filled, lit, and pulsing. The old version
/// changed only its fill colour, which is why tapping it appeared to do nothing.
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
    final listening = controller.listening;
    final scale = AppTheme.scaleOf(context);

    return Semantics(
      button: true,
      toggled: listening,
      label: listening ? 'Microphone on. Tap to stop.' : 'Start dictation',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(AppTheme.pillRadius),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            padding: EdgeInsets.symmetric(
              horizontal: AppTheme.s5,
              vertical: AppTheme.s3 * scale,
            ),
            decoration: BoxDecoration(
              color: listening ? AppTheme.live : AppTheme.cardBg,
              borderRadius: BorderRadius.circular(AppTheme.pillRadius),
              border: Border.all(
                color: listening ? AppTheme.live : AppTheme.borderStrong,
                width: 1.5,
              ),
              boxShadow: listening
                  ? [
                      BoxShadow(
                        color: AppTheme.live.withValues(alpha: 0.32),
                        offset: const Offset(0, 6),
                        blurRadius: 18,
                        spreadRadius: -4,
                      ),
                    ]
                  : AppTheme.shadowSoft,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (listening)
                  _LiveDot(size: 9 * scale, color: Colors.white)
                else
                  Icon(
                    Icons.mic_none_rounded,
                    size: 19 * scale,
                    color: AppTheme.textOnCard,
                  ),
                SizedBox(width: AppTheme.s2),
                Flexible(
                  child: Text(
                    listening ? 'Listening — tap to stop' : label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.label(context).copyWith(
                      color: listening ? Colors.white : AppTheme.textOnCard,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The mic as a round button, for a chat composer where a pill will not fit.
///
/// Same two-state treatment as [DictationButton]: off is a quiet outline, on is
/// a filled red circle with the recording dot in it.
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
    final listening = controller.listening;
    final scale = AppTheme.scaleOf(context);
    final size = 38.0 * scale;

    return Semantics(
      button: true,
      toggled: listening,
      label: listening ? 'Microphone on. Tap to stop.' : 'Start dictation',
      child: Tooltip(
        message: listening ? 'Stop dictation' : 'Dictate',
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: listening ? AppTheme.live : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(
                  color: listening ? AppTheme.live : AppTheme.borderStrong,
                  width: 1.5,
                ),
              ),
              child: Center(
                child: listening
                    ? _LiveDot(size: 9 * scale, color: Colors.white)
                    : Icon(
                        Icons.mic_none_rounded,
                        size: 19 * scale,
                        color: AppTheme.textOnCard,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
