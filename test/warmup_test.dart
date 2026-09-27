import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thoughtloom/config/api_config.dart';
import 'package:thoughtloom/main.dart';
import 'package:thoughtloom/services/ai_service.dart';
import 'package:thoughtloom/services/backend.dart';

import 'fake_ai.dart';

/// Waking the backend: when it is worth a ping, and when it is not.
///
/// Render puts a free service back to sleep fifteen minutes after its last
/// request, and nothing about the app being open in front of someone keeps it
/// awake. So "we warmed it at sign-in" has a shelf life, and the bug worth
/// pinning is the quiet one: a user who signs in, reads their dashboard for
/// twenty minutes, then starts a chat meets a *sleeping* server while
/// [backendWarm] still says true — which is worse than not knowing, because the
/// wait then reads as "thinking" instead of as a server starting up.
void main() {
  setUp(() => resetBackendWarmth());
  tearDown(() => resetBackendWarmth());

  group('backendMayHaveSlept', () {
    test('nothing has answered yet, so it is always worth asking', () {
      expect(backendMayHaveSlept(), isTrue);
    });

    test('a reply just now is worth believing', () {
      resetBackendWarmth(lastAnswered: DateTime.now());

      expect(backendMayHaveSlept(), isFalse);
    });

    test('a reply well inside the window is still worth believing', () {
      // This is the case that keeps an app-switch flicker from becoming a
      // network call: a few seconds away cannot age the last reply.
      resetBackendWarmth(
        lastAnswered: DateTime.now().subtract(const Duration(minutes: 1)),
      );

      expect(backendMayHaveSlept(), isFalse);
    });

    test('a reply older than the window is not', () {
      resetBackendWarmth(
        lastAnswered: DateTime.now().subtract(
          ApiConfig.warmthGoesStaleAfter + const Duration(minutes: 1),
        ),
      );

      expect(backendMayHaveSlept(), isTrue);
    });

    test('the window leaves room under Render\'s fifteen minutes', () {
      // The number is only correct relative to when Render actually sleeps. If
      // someone raises it past that, the check stops catching the thing it
      // exists for and this says so.
      expect(
        ApiConfig.warmthGoesStaleAfter,
        lessThan(const Duration(minutes: 15)),
      );
    });

    test('a failed request makes it worth asking again', () {
      resetBackendWarmth(lastAnswered: DateTime.now());
      // What a dropped call leaves behind.
      backendWarm.value = false;

      expect(backendMayHaveSlept(), isTrue);
    });
  });

  group('on resume', () {
    late FakeAi ai;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await Backend.init();
      ai = FakeAi();
      // Local auth and storage, but the app believes it is on Supabase — which
      // is what makes the warm-up path reachable without a network.
      Backend.overrideWith(ai: ai, usingSupabase: true);
    });

    Future<void> signIn() async {
      final result = await Backend.auth.signUp(
        email: 'ada@example.com',
        password: 'hunter2',
        displayName: 'Ada',
      );
      await Backend.data.ensureProfile(result.user.id);
    }

    Future<void> pumpSignedIn(WidgetTester tester) async {
      await signIn();
      await tester.pumpWidget(const ThoughtLoomApp());
      await tester.pumpAndSettle(const Duration(seconds: 1));
    }

    // Flutter will not let a listener see an illegal transition, so these walk
    // the real chain rather than jumping straight to the state under test:
    // going away is resumed -> inactive -> hidden -> paused, and coming back is
    // the reverse. Driving them in pairs also leaves the binding back in
    // `resumed` for the next test, since the lifecycle state outlives one.
    Future<void> background(WidgetTester tester) async {
      for (final state in const [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pump();
    }

    Future<void> foreground(WidgetTester tester) async {
      for (final state in const [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pump();
    }

    testWidgets('signing in warms the backend once', (tester) async {
      await pumpSignedIn(tester);

      expect(ai.warmUpCalls, 1);
    });

    testWidgets('a resume after a long quiet spell warms it again',
        (tester) async {
      await pumpSignedIn(tester);
      expect(ai.warmUpCalls, 1);

      await background(tester);
      // FakeAi.warmUp does not stamp the clock, so put the state where a real
      // one would be twenty minutes after a successful warm-up.
      resetBackendWarmth(
        lastAnswered: DateTime.now().subtract(const Duration(minutes: 20)),
      );
      await foreground(tester);

      expect(ai.warmUpCalls, 2);
    });

    testWidgets('a quick hop to another app and back pings nothing',
        (tester) async {
      await pumpSignedIn(tester);
      expect(ai.warmUpCalls, 1);

      resetBackendWarmth(lastAnswered: DateTime.now());
      await background(tester);
      await foreground(tester);

      expect(ai.warmUpCalls, 1);
    });

    testWidgets('going away does nothing on its own', (tester) async {
      // Only `resumed` is a reason to ping. The three states on the way out
      // reach the observer too and must be ignored.
      await pumpSignedIn(tester);
      resetBackendWarmth();

      await background(tester);
      expect(ai.warmUpCalls, 1);

      await foreground(tester);
    });

    testWidgets('the on-device backend is never pinged', (tester) async {
      // There is no Render service behind it, so a ping would be a network call
      // that can only fail.
      await signIn();
      Backend.overrideWith(ai: ai, usingSupabase: false);
      await tester.pumpWidget(const ThoughtLoomApp());
      await tester.pumpAndSettle(const Duration(seconds: 1));

      await background(tester);
      await foreground(tester);

      expect(ai.warmUpCalls, 0);
    });

    testWidgets('the observer is removed when the gate goes away',
        (tester) async {
      await pumpSignedIn(tester);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();

      resetBackendWarmth();
      await background(tester);
      await foreground(tester);

      // A leaked observer would still be listening, and would still fire.
      expect(ai.warmUpCalls, 1);
      expect(tester.takeException(), isNull);
    });
  });
}
