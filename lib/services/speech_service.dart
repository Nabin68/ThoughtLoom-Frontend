//speech_service.dart

import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// Dictation, behind an interface for the same reason auth and data are: the
/// screens should not know or care what is underneath.
///
/// Every method is written to fail soft. Dictation is a convenience next to a
/// text field that always works, so a missing recogniser, a denied microphone,
/// or a platform channel that does not exist (any test, and desktop without
/// the plugin) must degrade to "no mic button" rather than to an error.
abstract class SpeechService {
  /// Whether dictation can actually run here. Prompts for the microphone the
  /// first time, so call it when the user reaches for the mic, not on launch —
  /// a permission dialog nobody asked for reads as a shakedown.
  Future<bool> initialize();

  bool get isListening;

  /// Streams what it hears to [onTranscript] until [stop], a pause, or the
  /// recogniser's own timeout. [onTranscript] fires repeatedly with the best
  /// guess so far, not once at the end.
  Future<void> listen({
    required ValueChanged<String> onTranscript,
    VoidCallback? onDone,
  });

  Future<void> stop();

  void dispose();
}

/// [SpeechService] on the device's own recogniser, via `speech_to_text`.
class PluginSpeechService implements SpeechService {
  final _speech = stt.SpeechToText();
  bool _available = false;

  @override
  bool get isListening => _speech.isListening;

  @override
  Future<bool> initialize() async {
    if (_available) return true;
    try {
      _available = await _speech.initialize(
        // Both fire for ordinary conditions — no speech detected, a network
        // blip mid-phrase. The UI reads isListening to right itself, so
        // logging is all these owe anyone.
        onError: (e) => debugPrint('ThoughtLoom: dictation error — $e'),
        onStatus: (s) => debugPrint('ThoughtLoom: dictation status — $s'),
      );
    } catch (e) {
      // MissingPluginException under test, and on any platform without a
      // recogniser installed. Not a failure worth surfacing: it just means no
      // mic button.
      debugPrint('ThoughtLoom: dictation unavailable — $e');
      _available = false;
    }
    return _available;
  }

  @override
  Future<void> listen({
    required ValueChanged<String> onTranscript,
    VoidCallback? onDone,
  }) async {
    if (!await initialize()) return;
    try {
      await _speech.listen(
        onResult: (result) => onTranscript(result.recognizedWords),
        listenOptions: stt.SpeechListenOptions(
          // Interim results are what make dictation feel alive rather than
          // frozen; the screen shows them as they land.
          partialResults: true,
          cancelOnError: true,
          // Generous: someone describing a problem they have been chewing on
          // for months will pause to think, and the defaults cut them off.
          listenFor: const Duration(minutes: 2),
          pauseFor: const Duration(seconds: 5),
        ),
      );
    } catch (e) {
      debugPrint('ThoughtLoom: could not start dictation — $e');
    }
    onDone?.call();
  }

  @override
  Future<void> stop() async {
    try {
      await _speech.stop();
    } catch (e) {
      debugPrint('ThoughtLoom: could not stop dictation — $e');
    }
  }

  @override
  void dispose() {
    // Best-effort: the screen is going away regardless.
    _speech.cancel().catchError((_) {});
  }
}

/// A [SpeechService] that is never available.
///
/// What tests get, and what any platform without a recogniser effectively has.
/// The describe screen hides its mic button when [initialize] returns false, so
/// this is the "typing only" configuration.
class NoSpeechService implements SpeechService {
  @override
  Future<bool> initialize() async => false;

  @override
  bool get isListening => false;

  @override
  Future<void> listen({
    required ValueChanged<String> onTranscript,
    VoidCallback? onDone,
  }) async {}

  @override
  Future<void> stop() async {}

  @override
  void dispose() {}
}
