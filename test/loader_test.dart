import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thoughtloom/services/ai_service.dart';
import 'package:thoughtloom/widgets/app_loader.dart';

/// The loading animation, and the one thing it has to get right beyond looking
/// pleasant: while the backend is still waking, the copy must say so.
///
/// A sleeping Render instance is a 30-50 second wait with a cause, and "the
/// model is thinking" is not that cause. Telling someone the server is starting
/// up is the difference between a wait and a bug — so it is pinned here rather
/// than left to whoever next edits the widget.
void main() {
  setUp(() => backendWarm.value = false);
  tearDown(() => backendWarm.value = false);

  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  /// Run an [AnimatedSwitcher] crossfade to completion.
  ///
  /// Never `pumpAndSettle`: [AppLoader] repeats for as long as it is mounted,
  /// so there is no settled state to wait for and settling times out.
  ///
  /// Three frames, and each one is needed. The switcher does not begin a
  /// transition until the frame that builds the new child, so a single
  /// `pump(500ms)` would advance the clock past a crossfade that had not
  /// started yet - and the outgoing child is dropped in a `setState` fired by
  /// the transition completing, which needs a frame of its own.
  Future<void> crossfade(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
  }

  group('AppLoader', () {
    testWidgets('paints, and keeps painting, without rebuilding the tree',
        (tester) async {
      await tester.pumpWidget(wrap(const AppLoader()));

      expect(find.byType(CustomPaint), findsWidgets);

      // Half a second of frames. The point is that the ticker is running and
      // nothing throws mid-animation: the painter reads the controller through
      // `repaint`, so a frame is a repaint and not a build.
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a tiny one still paints', (tester) async {
      // Inside a button, and beside the "Thinking..." bubble. The inner arc is
      // dropped below 24 and the stroke is clamped, so the small sizes must not
      // end up with a negative radius.
      await tester.pumpWidget(wrap(const AppLoader(size: 14)));
      await tester.pump(const Duration(milliseconds: 200));

      expect(tester.takeException(), isNull);
    });

    testWidgets('disposes its ticker', (tester) async {
      await tester.pumpWidget(wrap(const AppLoader()));
      await tester.pumpWidget(wrap(const SizedBox()));

      // A leaked AnimationController fails the test binding at teardown.
      expect(tester.takeException(), isNull);
    });
  });

  group('AppWaiting', () {
    const lines = ['First line...', 'Second line...'];

    testWidgets('says the server is waking, not that it is thinking',
        (tester) async {
      await tester.pumpWidget(wrap(const AppWaiting(lines: lines)));

      expect(find.textContaining('Waking the server up'), findsOneWidget);
      expect(find.text('First line...'), findsNothing);
    });

    testWidgets('switches to the screen\'s own copy once the backend answers',
        (tester) async {
      await tester.pumpWidget(wrap(const AppWaiting(lines: lines)));

      backendWarm.value = true;
      await crossfade(tester);

      expect(find.text('First line...'), findsOneWidget);
      expect(find.textContaining('Waking the server up'), findsNothing);
    });

    testWidgets('rotates through the lines while it waits', (tester) async {
      backendWarm.value = true;
      await tester.pumpWidget(wrap(
        const AppWaiting(lines: lines, interval: Duration(seconds: 1)),
      ));

      expect(find.text('First line...'), findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
      await crossfade(tester);
      expect(find.text('Second line...'), findsOneWidget);

      // Wraps rather than running off the end of the list.
      await tester.pump(const Duration(seconds: 1));
      await crossfade(tester);
      expect(find.text('First line...'), findsOneWidget);
    });

    testWidgets('cancels its timer on dispose', (tester) async {
      await tester.pumpWidget(wrap(
        const AppWaiting(lines: lines, interval: Duration(milliseconds: 100)),
      ));
      await tester.pumpWidget(wrap(const SizedBox()));
      await tester.pump(const Duration(milliseconds: 300));

      // A Timer still calling setState on an unmounted State throws.
      expect(tester.takeException(), isNull);
    });
  });
}
