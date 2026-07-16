import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:thoughtloom/data/onboarding_questions.dart';
import 'package:thoughtloom/models/auth_user.dart';
import 'package:thoughtloom/models/chat.dart';
import 'package:thoughtloom/models/chat_category.dart';
import 'package:thoughtloom/models/user_profile.dart';
import 'package:thoughtloom/screens/memory_screen.dart';
import 'package:thoughtloom/screens/profile_screen.dart';
import 'package:thoughtloom/screens/recommendation_screen.dart';
import 'package:thoughtloom/services/ai_service.dart';
import 'package:thoughtloom/services/backend.dart';
import 'package:thoughtloom/theme/app_theme.dart';

import 'fake_ai.dart';

/// Does it fit on a phone?
///
/// Every screen in this app is laid out against a 390pt design width, and until
/// now the suites deliberately ran on the default 800x600 desktop viewport to
/// avoid false overflows. That is fine for behaviour and useless for layout —
/// and layout is exactly what these screens are.
///
/// So: 360x780, which is a small-but-real Android phone, and 320x568, which is
/// the smallest thing anyone still ships. An overflow surfaces as an exception
/// from the render pass, so `takeException()` is the whole assertion.
///
/// These are conservative rather than exact. `flutter test` does not register a
/// pubspec font without a FontLoader, so text is measured in a fallback whose
/// glyphs are wider than Inter's — anything that fits here fits on a device.
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Backend.init();
  });

  void sized(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  const phone = Size(360, 780);
  const smallest = Size(320, 568);

  Future<void> show(WidgetTester tester, Widget screen) async {
    await tester.pumpWidget(MaterialApp(theme: AppTheme.theme, home: screen));
    await tester.pumpAndSettle();
  }

  UserProfile profileWithEverything(String id) => UserProfile(
        id: id,
        displayName: 'Aaradhya Venkataraman',
        location: 'Pune, India',
        ageRange: '22–25',
        occupation: 'Preparing for exams or applications',
        onboardingAnswers: {
          // Every question answered, and with the longest option each offers —
          // the realistic worst case for a row that has to hold a question and
          // its answer side by side.
          for (final q in onboardingQuestions)
            q.id: q.options.isEmpty
                ? 'Dad runs a shop in Kothrud, Mum teaches at a school nearby, '
                    'and my younger sister is still in college'
                : q.options.reduce((a, b) => a.length >= b.length ? a : b),
        },
        onboardingCompleted: true,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

  group('the profile screen', () {
    for (final size in [phone, smallest]) {
      testWidgets('fits at ${size.width.toInt()}x${size.height.toInt()}',
          (tester) async {
        sized(tester, size);
        final user = AuthUser(
          id: 'u1',
          email: 'aaradhya.venkataraman@somewhere.example.com',
        );
        await show(
          tester,
          ProfileScreen(
            user: user,
            profile: profileWithEverything('u1'),
            onSaved: () async {},
          ),
        );

        expect(tester.takeException(), isNull);
        // Scrolling to the bottom lays out every row, not just the first screen
        // of them — an overflow twelve rows down is still an overflow.
        await tester.dragUntilVisible(
          find.text('Sign out'),
          find.byType(ListView),
          const Offset(0, -300),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('the memory screen', () {
    Future<void> withMemory(WidgetTester tester) async {
      final result = await Backend.auth.signUp(
        email: 'ada@example.com',
        password: 'hunter2',
        displayName: 'Ada',
      );
      final userId = result.user.id;
      await Backend.data.saveMemory(
        userId: userId,
        summary: 'Lives in Pune with her parents and is the first person in her '
            'family to finish a degree. Decides slowly and then second-guesses.',
        facts: const [
          'Her father runs a shop in Kothrud and expects her to help with it',
          'Finished a BTech in 2025 and has not worked since',
          'Has been weighing the same move to Bangalore since March',
        ],
      );
      await Backend.data.saveMemory(
        userId: userId,
        category: ChatCategory.relationship,
        summary: 'Has been with the same partner for three years; the question '
            'of moving cities keeps coming back to what it would cost them.',
        facts: const ['Partner is in Pune and does not want to leave'],
      );
      await show(tester, MemoryScreen(userId: userId));
    }

    for (final size in [phone, smallest]) {
      testWidgets('fits at ${size.width.toInt()}x${size.height.toInt()}',
          (tester) async {
        sized(tester, size);
        await withMemory(tester);
        expect(tester.takeException(), isNull);
        await tester.drag(find.byType(ListView), const Offset(0, -600));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('the recommendation', () {
    testWidgets('a long, fully-marked-up answer fits a phone', (tester) async {
      sized(tester, phone);

      final ai = FakeAi();
      ai.recommendation_ = const Recommendation(
        headline: 'Stop lending Ravi money, and tell him this week.',
        text: '''
You have lent him money four times and been paid back once. That is not a
cash-flow problem, it is **the shape of the friendship** — and you already know
it, because you described the last conversation before you described the loan.

## What it actually costs

> A loan he cannot repay is a gift with resentment attached.

- The money is gone either way
- The friendship is what is still on the table

Say it in person, once, and do not negotiate a smaller amount.
''',
        nextSteps: [
          'Say it on Sunday, in person, before he asks',
          'Do not offer a smaller amount as a compromise',
          'Write down what he already owes, for yourself, and then let it go',
        ],
        confidence: 'Fairly sure. If he has ever paid you back on time, this '
            'changes.',
        sources: [
          Source(
            title: 'A very long source title of the kind a search result '
                'actually returns, which will wrap',
            url: 'https://example.com/a/very/long/url',
          ),
        ],
      );
      Backend.overrideWith(ai: ai, usingSupabase: true);

      final chat = Chat(
        id: 'c1',
        userId: 'u1',
        category: ChatCategory.financial,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await show(tester, RecommendationScreen(chat: chat));

      expect(tester.takeException(), isNull);
      expect(
        find.text('Stop lending Ravi money, and tell him this week.'),
        findsOneWidget,
      );

      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -900),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
