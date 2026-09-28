//speech_service.dart

import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// Dictation, behind an interface for the same reason auth and data are: the
/// screens should not know or care what is underneath.
///
/// Every method is written to fail soft. Dictation is a convenience next to a
/// text field that always works, so a missing recogniser, a denied microphone,
/// or a platform channel that does not exist (any test, and desktop without the
/// plugin) must degrade to "no mic button" rather than to an error.
///
/// ### The session model, and why it is shaped like this
///
/// A device recogniser does not listen indefinitely. It ends its own session on
/// a pause, on its listen-window expiring, or on an error — and the *only*
/// honest signal for that is the plugin's status stream. The previous version
/// of this file called its `onDone` immediately after `await _speech.listen()`
/// returned, on the assumption that the future completed when listening
/// finished. It completes when listening *starts*. Every caller was therefore
/// told the microphone had stopped a few milliseconds after it opened, while it
/// went on recording — which is why the mic button never looked live.
///
/// So [listen] reports two things separately: [onResult] for what was heard,
/// and [onSessionEnd] for the recogniser actually stopping. Keeping the
/// microphone open across a pause is the caller's job — see
/// [DictationController], which restarts a session and is where the "one
/// utterance" model turns into "on until you turn it off".
abstract class SpeechService {
  /// Whether dictation can actually run here. Prompts for the microphone the
  /// first time, so call it when the screen opens rather than at launch — a
  /// permission dialog nobody asked for reads as a shakedown.
  Future<bool> initialize();

  bool get isListening;

  /// Opens one recognition session.
  ///
  /// [onResult] fires repeatedly with the best guess for the current utterance,
  /// not once at the end; [isFinal] marks the recogniser committing to it.
  /// [onSessionEnd] fires exactly once, when this session is over for any
  /// reason — pause, timeout, error, or [stop].
  ///
  /// [onAudio] fires on every sound-level reading, which the recogniser only
  /// produces while the microphone is really capturing. It is the one honest
  /// signal that the mic is live: the plugin reports "listening" the moment it
  /// *asks* for a session, before (and whether or not) recording starts.
  ///
  /// [onFatalError] is for failures a retry cannot fix — no permission, no
  /// network, no language pack — with a short message fit for the mic button.
  /// It can arrive after [onSessionEnd], because the plugin reports the status
  /// change before the error behind it.
  ///
  /// Returns whether the session actually started.
  Future<bool> listen({
    required void Function(String transcript, bool isFinal) onResult,
    required VoidCallback onSessionEnd,
    VoidCallback? onAudio,
    void Function(String message)? onFatalError,
  });

  Future<void> stop();

  void dispose();
}

/// [SpeechService] on the device's own recogniser, via `speech_to_text`.
class PluginSpeechService implements SpeechService {
  final _speech = stt.SpeechToText();
  bool _available = false;

  /// The live session's end callback, or null between sessions. Held here
  /// rather than passed through the plugin because the status that ends a
  /// session arrives on the listener registered at [initialize], not on the
  /// call that started it.
  VoidCallback? _onSessionEnd;

  /// The latest listen's fatal-error callback. Kept past the session's end —
  /// see [SpeechService.listen] — and dropped only by [stop] or [dispose].
  void Function(String message)? _onFatalError;

  /// Which session is current. Bumped when one ends, so a result the plugin
  /// emits on the way out cannot be attributed to the session after it.
  ///
  /// The recogniser does not stop cleanly: `notListening`, the final result,
  /// and `done` arrive in an order that differs by platform, and the plugin
  /// also synthesises a "final" result two seconds after listening *starts*
  /// (its `defaultFinalTimeout`) whether or not the speaker has stopped. A
  /// straggler landing after the caller has committed what it heard would be
  /// appended to the text a second time.
  int _session = 0;

  @override
  bool get isListening => _speech.isListening;

  @override
  Future<bool> initialize() async {
    if (_available) return true;
    try {
      _available = await _speech.initialize(
        onError: (e) {
          // Ordinary conditions land here — `error_no_match` when someone
          // pauses to think, `error_speech_timeout` on a quiet room. They end
          // the session; they are not failures worth showing anyone.
          debugPrint('ThoughtLoom: dictation error — $e');
          final fatal = _fatalMessage(e.errorMsg);
          if (fatal != null) _onFatalError?.call(fatal);
          _endSession();
        },
        onStatus: (status) {
          debugPrint('ThoughtLoom: dictation status — $status');
          // `notListening` is the microphone closing; `done` is the session
          // finishing afterwards. Which of the two arrives — and whether both
          // do — differs by platform, so either ends the session and
          // _endSession is written to be safe to call twice.
          if (status == stt.SpeechToText.notListeningStatus ||
              status == stt.SpeechToText.doneStatus) {
            _endSession();
          }
        },
      );
    } catch (e) {
      // MissingPluginException under test, and on any platform without a
      // recogniser installed. Not a failure worth surfacing: it means no mic
      // button, and the text field was always the real input.
      debugPrint('ThoughtLoom: dictation unavailable — $e');
      _available = false;
    }
    return _available;
  }

  /// A message for an error no retry will fix, or null for the ordinary ones.
  ///
  /// `error_no_match` / `error_speech_timeout` are silence, and `error_busy` /
  /// `error_client` are the recogniser not being ready for an immediate
  /// restart — both are the controller's to retry.
  static String? _fatalMessage(String error) => switch (error) {
        'error_permission' => 'Microphone permission is off',
        'error_network' ||
        'error_network_timeout' ||
        'error_server' ||
        'error_server_disconnected' =>
          'Dictation needs an internet connection',
        'error_language_not_supported' ||
        'error_language_unavailable' =>
          'Dictation is not available in your language',
        'error_audio_error' => 'The microphone stopped working',
        'error_too_many_requests' => 'Dictation is busy — try again shortly',
        _ => null,
      };

  /// Fires the current session's end callback, once, and retires the session.
  void _endSession() {
    final callback = _onSessionEnd;
    _onSessionEnd = null;
    if (callback == null) return;
    _session++;
    callback();
  }

  @override
  Future<bool> listen({
    required void Function(String transcript, bool isFinal) onResult,
    required VoidCallback onSessionEnd,
    VoidCallback? onAudio,
    void Function(String message)? onFatalError,
  }) async {
    if (!await initialize()) return false;

    // A session already running would otherwise leave the previous callback
    // orphaned and the plugin throwing "already listening".
    if (_speech.isListening) await stop();

    final session = ++_session;
    _onSessionEnd = onSessionEnd;
    _onFatalError = onFatalError;
    try {
      await _speech.listen(
        onResult: (result) {
          if (session != _session) return; // A straggler from a closed session.
          onResult(result.recognizedWords, result.finalResult);
        },
        onSoundLevelChange: (_) {
          if (session == _session) onAudio?.call();
        },
        listenOptions: stt.SpeechListenOptions(
          // Interim results are what make dictation feel alive rather than
          // frozen; the field shows them as they land.
          partialResults: true,
          listenMode: stt.ListenMode.dictation,
          // False, deliberately. A no-match from a two-second silence is not an
          // error worth tearing the session down for — and when it genuinely is
          // over, onError ends the session anyway.
          cancelOnError: false,
          listenFor: const Duration(minutes: 2),
          // No pauseFor, deliberately. On Android the plugin passes it to the
          // recogniser as its silence length *and* waits that long after the
          // recogniser's end-of-speech before reporting the session over. But
          // Android turns the microphone off at end-of-speech — so with the old
          // five seconds, every pause left the button saying "Listening" over a
          // dead mic for five seconds, and whatever was said then was lost.
          // Without it the session reports its end about a second after speech
          // stops, and DictationController opens the next one straight away.
        ),
      );
      return true;
    } catch (e) {
      debugPrint('ThoughtLoom: could not start dictation — $e');
      _onSessionEnd = null;
      return false;
    }
  }

  @override
  Future<void> stop() async {
    _onFatalError = null;
    try {
      await _speech.stop();
    } catch (e) {
      debugPrint('ThoughtLoom: could not stop dictation — $e');
    }
    // Not left to the status listener: `stop` is a deliberate end, and a
    // platform that does not report a status for it would strand the session.
    _endSession();
  }

  @override
  void dispose() {
    _onSessionEnd = null;
    _onFatalError = null;
    // Best-effort: the screen is going away regardless.
    _speech.cancel().catchError((_) {});
  }
}

/// A [SpeechService] that is never available.
///
/// What tests get, and what any platform without a recogniser effectively has.
/// Callers hide the mic button when [initialize] returns false, so this is the
/// "typing only" configuration.
class NoSpeechService implements SpeechService {
  @override
  Future<bool> initialize() async => false;

  @override
  bool get isListening => false;

  @override
  Future<bool> listen({
    required void Function(String transcript, bool isFinal) onResult,
    required VoidCallback onSessionEnd,
    VoidCallback? onAudio,
    void Function(String message)? onFatalError,
  }) async =>
      false;

  @override
  Future<void> stop() async {}

  @override
  void dispose() {}
}
