import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:thoughtloom/data/onboarding_questions.dart';
import 'package:thoughtloom/main.dart';
import 'package:thoughtloom/screens/login_screen.dart';
import 'package:thoughtloom/screens/register_screen.dart';
import 'package:thoughtloom/services/backend.dart';

void main() {
  // No --dart-define credentials under test, so Backend.init selects the
  // on-device services and the whole app is exercisable without a network.
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Backend.init();
  });

  /// Left on the default 800x600 viewport deliberately.
  ///
  /// Inter ships in the bundle now, but `flutter test` does not register a
  /// pubspec font without a FontLoader — so text here is still measured in a
  /// fallback whose glyphs are wider than the real thing, and pinning a phone
  /// viewport would report overflows no user can hit. These tests cover
  /// behaviour, not layout; `history_test.dart` does the layout pass.
  Future<void> pumpApp(WidgetTester tester) =>
      tester.pumpWidget(const ThoughtLoomApp());

  Future<void> openRegister(WidgetTester tester) async {
    await pumpApp(tester);
    await tester.pumpAndSettle(const Duration(seconds: 1));
    // Landing now leads with "Sign in" — registering is the second button,
    // because signing up is the thing you do once and signing in is the thing
    // you do forever afterwards.
    await tester.tap(find.text('Create an account'));
    await tester.pumpAndSettle();
  }

  Future<void> fillRegister(
    WidgetTester tester, {
    String email = 'ada@example.com',
    String password = 'hunter2',
    String? confirm,
  }) async {
    // Fields in order: name, email, password, confirm.
    await tester.enterText(find.byType(TextFormField).at(1), email);
    await tester.enterText(find.byType(TextFormField).at(2), password);
    await tester.enterText(find.byType(TextFormField).at(3), confirm ?? password);
  }

  Future<void> tapCreateAccount(WidgetTester tester) async {
    final button = find.text('Create account');
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  testWidgets('Landing screen shows branding and reveals both ways in',
      (tester) async {
    await pumpApp(tester);

    expect(find.text('ThoughtLoom'), findsOneWidget);
    expect(find.text('Weave clarity into your decisions.'), findsOneWidget);

    // The CTAs fade in on a delay, so settle the animation before asserting.
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Create an account'), findsOneWidget);
  });

  testWidgets('Signing in is the primary way back in', (tester) async {
    await pumpApp(tester);
    await tester.pumpAndSettle(const Duration(seconds: 1));
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    // The regression this pins: the landing page used to offer one button and it
    // went to the sign-up form, so a returning user whose session had expired was
    // shown a registration form and had to find the way to their own account in
    // a link underneath it.
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('Creating an account opens the register screen', (tester) async {
    await openRegister(tester);
    expect(find.byType(RegisterScreen), findsOneWidget);
  });

  /// The first thing a brand-new account sees, now that AuthGate routes an
  /// unfinished profile into the basic-profile questions.
  final firstQuestion = onboardingQuestions.first.text;

  testWidgets('Registering routes into the app and survives a restart',
      (tester) async {
    await openRegister(tester);
    await fillRegister(tester);
    await tapCreateAccount(tester);

    // AuthGate has swapped the landing page for the signed-in app.
    expect(find.text(firstQuestion), findsOneWidget);

    // Relaunching with a session already on disk must land straight in the app
    // rather than flashing the landing page while the profile loads.
    await Backend.init();
    await pumpApp(tester);
    await tester.pumpAndSettle();

    expect(find.text('Sign in'), findsNothing);
    expect(find.text(firstQuestion), findsOneWidget);
  });

  testWidgets('Mismatched passwords keep the user on the form', (tester) async {
    await openRegister(tester);
    await fillRegister(tester, password: 'hunter2', confirm: 'hunter3');
    await tapCreateAccount(tester);

    expect(find.text('Passwords do not match'), findsOneWidget);
    expect(find.byType(RegisterScreen), findsOneWidget);
  });

  testWidgets('A duplicate email is reported on the form', (tester) async {
    await openRegister(tester);
    await fillRegister(tester);
    await tapCreateAccount(tester);
    expect(find.text(firstQuestion), findsOneWidget);

    await Backend.auth.signOut();
    await tester.pumpAndSettle();

    await openRegister(tester);
    await fillRegister(tester);
    await tapCreateAccount(tester);

    expect(
      find.text('An account with that email already exists.'),
      findsOneWidget,
    );
  });

  testWidgets('Signing out returns to the landing page', (tester) async {
    await openRegister(tester);
    await fillRegister(tester);
    await tapCreateAccount(tester);
    expect(find.text(firstQuestion), findsOneWidget);

    await Backend.auth.signOut();
    // Staged deliberately. The auth event needs one frame to arrive and another
    // for StreamBuilder to remount Landing, and only that second frame starts
    // its 500ms reveal — so the clock can only be advanced past the timer once
    // the timer exists.
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    expect(find.text('Weave clarity into your decisions.'), findsOneWidget);
  });
}
