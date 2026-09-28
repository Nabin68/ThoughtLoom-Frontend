//dictation.dart

import 'dart:async';

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
/// ### Honest about the microphone
///
/// "The user wants it on" and "the microphone is recording" are different
/// facts, and the button used to show only the first. Android turns the mic off
/// at every end of speech and between sessions, and a session can die without
/// saying so, so the button could say "Listening" over a mic that was off.
/// Now:
///
///  * [micLive] is driven by the recogniser's sound-level readings, which only
///    exist while audio is really being captured. The button pulses on that and
///    says "Starting the mic…" when it is false.
///  * a watchdog restarts a session that goes quiet without ending, and one that
///    never goes live at all;
///  * after [_maxFailedStarts] sessions in a row that never went live, or on an
///    error no retry fixes, it turns itself off and says why in [problem].
///
/// Fails soft throughout: if there is no recogniser, [available] stays false and
/// callers do not offer the mic. The text field always works.
class DictationController extends ChangeNotifier {
  final TextEditingController target;

  DictationController(this.target);

  /// How many consecutive sessions may hear no words before the microphone
  /// turns itself off.
  ///
  /// Android ends a session after about five seconds with no speech, so this
  /// is roughly fifteen. A mic that stays live in the background indefinitely is
  /// a thing to be sorry about, not a feature.
  static const _maxSilentSessions = 3;

  /// How many sessions in a row may fail to start recording before giving up.
  static const _maxFailedStarts = 3;

  /// How long a new session has to produce audio before it counts as dead.
  static const _startTimeout = Duration(milliseconds: 2500);

  /// How long a live session may go without a sound-level reading before it
  /// counts as stalled. Readings arrive many times a second while recording,
  /// and the plugin reports a session's end about a second after the
  /// recogniser's end-of-speech, so anything past this is a session that died
  /// without saying so.
  static const _stallTimeout = Duration(seconds: 3);

  /// How long the mic may be off between sessions before the button admits it.
  /// Shorter than a person notices, longer than a healthy restart takes, so the
  /// label does not flicker on every pause.
  static const _quietGrace = Duration(milliseconds: 600);

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

  /// The live utterance's transcript as last written, or '' between
  /// utterances. What a new result is compared against to tell a revision of
  /// the same phrase from the start of a new one.
  String _utterance = '';

  /// Whether the live session has heard any words yet.
  bool _heardThisSession = false;
  int _silentSessions = 0;

  /// Whether the live session has produced any audio at all — whether the
  /// microphone ever actually opened.
  bool _audioThisSession = false;
  int _failedStarts = 0;

  bool _micLive = false;
  String? _problem;
  Timer? _watchdog;
  Timer? _quietTimer;
  Timer? _retryTimer;
  bool _reopenWhenOpen = false;

  /// Whether dictation can run at all here. False until [init] says otherwise.
  bool get available => _available;

  /// Whether the microphone is on, as the user understands it.
  bool get listening => _wantOn;

  /// Whether audio is actually being captured right now, as opposed to the mic
  /// being wanted on. False briefly between sessions; false for longer when
  /// something is wrong.
  bool get micLive => _wantOn && _micLive;

  /// Why the mic turned itself off, if it did — shown on the button until the
  /// next [start].
  String? get problem => _problem;

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
    _problem = null;
    _silentSessions = 0;
    _failedStarts = 0;
    notifyListeners();

    await _openSession();
  }

  Future<void> stop() async {
    if (!_wantOn) return;
    // Cleared before the await, so the session-end this triggers sees the intent
    // already gone and does not helpfully reopen the microphone.
    _wantOn = false;
    _micLive = false;
    _cancelTimers();
    notifyListeners();
    await Backend.speech.stop();
  }

  /// Turns the mic off because it cannot work right now, and says why.
  void _fail(String message) {
    if (!_wantOn) return;
    debugPrint('ThoughtLoom: dictation gave up — $message');
    _problem = message;
    stop();
  }

  void _cancelTimers() {
    _watchdog?.cancel();
    _quietTimer?.cancel();
    _retryTimer?.cancel();
  }

  void _arm(Duration timeout) {
    _watchdog?.cancel();
    _watchdog = Timer(timeout, _onStalled);
  }

  /// A session that never started recording, or stopped recording without
  /// ending. Ending it from here sends it through [_onSessionEnd], which opens
  /// the next one — or gives up, if this keeps happening.
  void _onStalled() {
    if (!_wantOn) return;
    debugPrint(_audioThisSession
        ? 'ThoughtLoom: dictation stalled — restarting'
        : 'ThoughtLoom: dictation mic never opened — restarting');
    Backend.speech.stop();
  }

  /// A sound-level reading: the microphone is recording.
  void _onAudio() {
    if (!_wantOn) return;
    _audioThisSession = true;
    _failedStarts = 0;
    _arm(_stallTimeout);
    if (!_micLive) {
      _micLive = true;
      _quietTimer?.cancel();
      notifyListeners();
    }
  }

  Future<void> _openSession() async {
    if (!_wantOn || _opening) return;
    _opening = true;
    _heardThisSession = false;
    _audioThisSession = false;
    _baseTaken = false;
    _utterance = '';
    _arm(_startTimeout);

    final started = await Backend.speech.listen(
      onResult: _write,
      onSessionEnd: _onSessionEnd,
      onAudio: _onAudio,
      onFatalError: _fail,
    );

    _opening = false;
    if (!started) {
      // The recogniser would not open. Saying so by turning the button off beats
      // leaving it lit over a microphone that is not running.
      _fail('The mic would not start — tap to try again');
    } else if (_reopenWhenOpen) {
      // The recogniser ended a session while this one was still opening.
      _reopenWhenOpen = false;
      _reopen();
    }
  }

  /// Opens the next session — or, if one is mid-open, as soon as it is. Just
  /// calling [_openSession] would be silently ignored then, and the mic would
  /// sit "on" with no session behind it.
  void _reopen() {
    if (_opening) {
      _reopenWhenOpen = true;
    } else {
      _openSession();
    }
  }

  /// Writes one recogniser result into the field.
  ///
  /// A result is the whole of the *current utterance*, not a delta, so each one
  /// replaces the last on top of [_committed]. What decides whether the words
  /// before it survive is when [_committed] moves forward, and there are three
  /// moments:
  ///
  ///  * **a new session** — see [_baseTaken];
  ///  * **a final result** — the recogniser has committed to that utterance.
  ///    Anything after it in the same session is a new one, so the field as it
  ///    now reads becomes the base;
  ///  * **a restart with no final** — some recognisers (Android 13+'s, notably)
  ///    begin a new utterance after a one- or two-second pause *inside* the same
  ///    session, and the next result simply starts over: "I am tired" is
  ///    followed by "and", not "I am tired and". Written over the same base,
  ///    that erased the first sentence — the bug a pause used to cause. See
  ///    [_isNewUtterance].
  void _write(String transcript, bool isFinal) {
    // Words are proof the mic is live, as much as a sound level is. Some
    // recognisers report no levels at all, and none do while a slow connection
    // returns the final — without this the watchdog cut those sessions off
    // mid-sentence and dropped the final as a straggler.
    _onAudio();
    transcript = transcript.trim();
    if (transcript.isEmpty) return;
    if (!_baseTaken) {
      // Taken now rather than when the session opened — see [_baseTaken].
      // Reading the field rather than remembering the last transcript is what
      // makes a correction stick instead of being overwritten by the thing it
      // corrected.
      _committed = target.text;
      _baseTaken = true;
    } else if (_isNewUtterance(_utterance, transcript)) {
      // The previous utterance is already in the field; keep it.
      _committed = target.text;
    }
    _heardThisSession = true;

    final prefix = _committed.trim().isEmpty ? '' : '${_committed.trimRight()} ';
    final text = '$prefix$transcript';
    target.value = TextEditingValue(
      text: text,
      // Caret to the end, or the field fights the user for the cursor every time
      // a new partial result lands.
      selection: TextSelection.collapsed(offset: text.length),
    );

    if (isFinal) {
      _committed = text;
      _utterance = '';
    } else {
      _utterance = transcript;
    }
  }

  /// Whether [next] starts a new utterance rather than revising [previous].
  ///
  /// A revision grows or rewrites the same phrase and so shares its opening
  /// words: "I am" → "I am tired" → "I am tired of". A restart is short and
  /// begins somewhere else: "I am tired of it" → "and". So: a restart is a
  /// result with fewer words than the last one that does not share its first
  /// two words (or its only word).
  ///
  /// ponytail: word-prefix heuristic. A recogniser that shrinks *and* rewrites
  /// the opening word of a phrase ("I am tired" → "I'm tired") is misread as a
  /// restart and the phrase appears twice — a duplicate the user can delete,
  /// where the old failure deleted what they said. If a platform reports
  /// segment boundaries, use those instead.
  static bool _isNewUtterance(String previous, String next) {
    if (previous.isEmpty) return false;
    List<String> words(String s) => s.toLowerCase().split(RegExp(r'\s+'));
    final before = words(previous);
    final after = words(next);
    if (after.length >= before.length) return false;

    final need = before.length < 2 ? 1 : 2;
    var shared = 0;
    while (shared < after.length &&
        shared < need &&
        after[shared] == before[shared]) {
      shared++;
    }
    return shared < need;
  }

  /// The recogniser closed a session. Whether that is the end of anything is
  /// decided here, not by the recogniser.
  void _onSessionEnd() {
    _watchdog?.cancel();
    if (!_wantOn) {
      notifyListeners();
      return;
    }

    // The mic is off until the next session produces audio. Admitted on the
    // button only if that takes longer than a healthy restart does.
    _micLive = false;
    _quietTimer?.cancel();
    _quietTimer = Timer(_quietGrace, () {
      if (_wantOn && !_micLive) notifyListeners();
    });

    if (!_audioThisSession) {
      // Never recorded anything: the recogniser was busy, or would not open.
      // Back off a little each time rather than hammering it.
      if (++_failedStarts >= _maxFailedStarts) {
        _fail('The mic would not start — tap to try again');
        return;
      }
      _retryTimer?.cancel();
      _retryTimer =
          Timer(Duration(milliseconds: 300 * _failedStarts), _reopen);
      return;
    }

    if (_heardThisSession) {
      _silentSessions = 0;
    } else if (++_silentSessions >= _maxSilentSessions) {
      _problem = 'Stopped after a long silence';
      _wantOn = false;
      _micLive = false;
      _cancelTimers();
      notifyListeners();
      return;
    }

    // Straight away: every millisecond here is speech that is not captured.
    _reopen();
  }

  @override
  void dispose() {
    _wantOn = false;
    _cancelTimers();
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
///
/// It breathes only while audio is really being captured. Between sessions, or
/// while the mic is still opening, it sits dim and still — so the dot never
/// claims a recording that is not happening.
class _LiveDot extends StatefulWidget {
  final double size;
  final Color color;
  final bool pulsing;

  const _LiveDot({
    required this.size,
    required this.color,
    this.pulsing = true,
  });

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
    if (!widget.pulsing) {
      return Opacity(
        opacity: 0.4,
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration:
              BoxDecoration(color: widget.color, shape: BoxShape.circle),
        ),
      );
    }
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
    final live = controller.micLive;
    final scale = AppTheme.scaleOf(context);

    // Three honest states: off, on and recording, on but not recording yet.
    final String text;
    if (!listening) {
      text = controller.problem ?? label;
    } else if (live) {
      text = 'Listening — tap to stop';
    } else {
      text = 'Starting the mic…';
    }

    return Semantics(
      button: true,
      toggled: listening,
      label: listening ? '$text. Tap to stop.' : text,
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
                  _LiveDot(size: 9 * scale, color: Colors.white, pulsing: live)
                else
                  Icon(
                    Icons.mic_none_rounded,
                    size: 19 * scale,
                    color: AppTheme.textOnCard,
                  ),
                SizedBox(width: AppTheme.s2),
                Flexible(
                  child: Text(
                    text,
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
    final live = controller.micLive;
    final scale = AppTheme.scaleOf(context);
    final size = 38.0 * scale;
    final status = !listening
        ? (controller.problem ?? 'Dictate')
        : live
            ? 'Listening — tap to stop'
            : 'Starting the mic…';

    return Semantics(
      button: true,
      toggled: listening,
      label: status,
      child: Tooltip(
        message: status,
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
                    ? _LiveDot(
                        size: 9 * scale, color: Colors.white, pulsing: live)
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
