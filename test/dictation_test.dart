import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:thoughtloom/services/backend.dart';
import 'package:thoughtloom/services/speech_service.dart';
import 'package:thoughtloom/widgets/dictation.dart';

/// A recogniser whose sessions this test opens and closes by hand.
///
/// The real one cannot be driven: `speech_to_text` sits behind a platform
/// channel that does not exist under test, so [PluginSpeechService.initialize]
/// reports false and the mic is never offered. That is why every dictation bug
/// in this app shipped — the only path the suite could reach was the one where
/// there is no microphone.
///
/// What matters here is the *session* behaviour, because that is where the bugs
/// were: a recogniser ends its own session on a pause, and everything the user
/// complained about came from the app treating that as the user having finished.
class FakeSpeech implements SpeechService {
  bool available = true;

  /// How many sessions have been opened. The count is the point: keeping the
  /// microphone on across a pause *is* opening another one.
  int sessions = 0;

  bool _listening = false;
  void Function(String, bool)? _onResult;
  VoidCallback? _onSessionEnd;

  @override
  Future<bool> initialize() async => available;

  @override
  bool get isListening => _listening;

  @override
  Future<bool> listen({
    required void Function(String transcript, bool isFinal) onResult,
    required VoidCallback onSessionEnd,
  }) async {
    if (!available) return false;
    sessions++;
    _onResult = onResult;
    _onSessionEnd = onSessionEnd;
    _listening = true;
    return true;
  }

  @override
  Future<void> stop() async => endSession();

  @override
  void dispose() {}

  // --- driving it ----------------------------------------------------------

  /// The recogniser reporting what it has heard so far.
  void hear(String transcript) => _onResult?.call(transcript, false);

  /// The recogniser closing the session itself — a pause, or its window
  /// expiring. This is the event the old code could not see.
  void endSession() {
    if (!_listening) return;
    _listening = false;
    final callback = _onSessionEnd;
    _onSessionEnd = null;
    _onResult = null;
    callback?.call();
  }
}

void main() {
  late FakeSpeech speech;
  late TextEditingController field;
  late DictationController dictation;

  setUp(() async {
    speech = FakeSpeech();
    Backend.overrideWith(speech: speech);
    field = TextEditingController();
    dictation = DictationController(field);
    await dictation.init();
  });

  tearDown(() {
    dictation.dispose();
    field.dispose();
  });

  /// The controller reopens a session from a callback without awaiting it, so a
  /// turn of the microtask queue is what lets that land.
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('the mic is off until it is turned on, and says so', () async {
    expect(dictation.available, isTrue);
    expect(dictation.listening, isFalse);
    expect(speech.sessions, 0);

    await dictation.start();
    expect(dictation.listening, isTrue);
    expect(speech.sessions, 1);
  });

  test('it stays on through a pause, which is the whole point', () async {
    // The regression. The service used to report the session as finished the
    // instant it *started* — it called its own onDone right after awaiting
    // `listen()`, whose future completes when listening begins — so the button
    // went dark a few milliseconds after being tapped while the microphone went
    // on recording. Whatever the recogniser does with its sessions is not the
    // user's business; only start() and stop() are.
    await dictation.start();
    speech.hear('I am tired');
    expect(field.text, 'I am tired');

    speech.endSession(); // A five-second silence: they stopped to think.
    await settle();

    expect(dictation.listening, isTrue, reason: 'the user did not stop it');
    expect(speech.sessions, 2, reason: 'a new session, not a dead microphone');
  });

  test('carrying on after a pause extends what was said, never replaces it',
      () async {
    // The second bug, and the one that lost people's words: each session's
    // transcript was written over the field from a base captured when the
    // *button* was last tapped, so a second session started from scratch and
    // deleted the first.
    await dictation.start();
    speech.hear('I am tired');
    speech.endSession();
    await settle();

    speech.hear('and my head hurts');

    expect(field.text, 'I am tired and my head hurts');
  });

  test('it extends what was typed, so speech and the keyboard are one input',
      () async {
    field.text = 'Honestly,';

    await dictation.start();
    speech.hear('I do not know');

    expect(field.text, 'Honestly, I do not know');
  });

  test('a correction typed between two utterances survives the next one',
      () async {
    await dictation.start();
    speech.hear('I am tyred');
    speech.endSession();
    await settle();

    // Fixed by hand while the mic was still on.
    field.text = 'I am tired';
    speech.hear('of all of it');

    // Reads the field rather than remembering the last transcript, which is what
    // makes the fix stick instead of being overwritten by the thing it fixed.
    expect(field.text, 'I am tired of all of it');
  });

  test('stopping stops, and does not helpfully reopen the microphone',
      () async {
    await dictation.start();
    speech.hear('that is all');
    await dictation.stop();
    await settle();

    expect(dictation.listening, isFalse);
    expect(speech.sessions, 1, reason: 'stop must not trigger a restart');
    expect(field.text, 'that is all');
  });

  test('tapping into the text box turns it off, because they mean to type',
      () async {
    // What the screens wire to the field's onTap. Without it the next partial
    // result rewrites the box from under whoever is typing in it.
    await dictation.start();
    expect(dictation.listening, isTrue);

    await dictation.stop();

    expect(dictation.listening, isFalse);
  });

  test('a microphone that hears nothing for long enough turns itself off',
      () async {
    await dictation.start();

    // Three empty sessions is about fifteen seconds of nothing. A mic that spins
    // forever on a revoked permission is a bug; one that stays live in the
    // background indefinitely is worse than a bug.
    for (var i = 0; i < 3; i++) {
      speech.endSession();
      await settle();
    }

    expect(dictation.listening, isFalse);
    expect(speech.sessions, 3, reason: 'it gave up rather than opening a fourth');
  });

  test('hearing something resets the patience', () async {
    await dictation.start();

    speech.endSession(); // silent
    await settle();
    speech.endSession(); // silent
    await settle();

    speech.hear('still here');
    speech.endSession();
    await settle();

    expect(dictation.listening, isTrue);

    speech.endSession();
    await settle();
    expect(dictation.listening, isTrue, reason: 'the count started again');
  });

  test('a recogniser that will not open leaves the button off, not lit',
      () async {
    speech.available = false;

    await dictation.start();

    // Better to say so than to sit lit over a microphone that is not running.
    expect(dictation.listening, isFalse);
  });

  test('usedDictation records how the text got there, for the API', () async {
    expect(dictation.usedDictation, isFalse);
    await dictation.start();
    expect(dictation.usedDictation, isTrue);
  });
}
