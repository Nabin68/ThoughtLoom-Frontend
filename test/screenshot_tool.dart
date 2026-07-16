import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:thoughtloom/models/chat.dart';
import 'package:thoughtloom/models/chat_category.dart';
import 'package:thoughtloom/models/user_profile.dart';
import 'package:thoughtloom/screens/dashboard_screen.dart';
import 'package:thoughtloom/screens/intake_flow_screen.dart';
import 'package:thoughtloom/screens/recommendation_screen.dart';
import 'package:thoughtloom/services/ai_service.dart';
import 'package:thoughtloom/services/backend.dart';
import 'package:thoughtloom/services/session.dart';
import 'package:thoughtloom/theme/app_theme.dart';

import 'fake_ai.dart';

/// Renders the redesigned screens to PNGs so a human — or the person who wrote
/// them — can actually look at the result.
///
/// Named `_tool` rather than `_test` on purpose: `flutter test` globs
/// `test/**_test.dart`, so this stays out of the default run. It is a developer
/// tool, not an assertion — it writes files and proves nothing.
///
///   flutter test test/screenshot_tool.dart --update-goldens
///
/// Unlike every other suite here, this one loads Inter with a [FontLoader] —
/// without it the fallback draws box glyphs and the output is unreadable, which
/// is fine for measuring layout and useless for looking at it.
void main() {
  setUpAll(() async {
    final loader = FontLoader('Inter');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      loader.addFont(
        File('assets/fonts/Inter-$weight.ttf')
            .readAsBytes()
            .then((b) => ByteData.view(b.buffer)),
      );
    }
    await loader.load();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Backend.init();
  });

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  UserProfile aProfile(String id) => UserProfile(
        id: id,
        displayName: 'Aarav',
        location: 'Pune, India',
        onboardingAnswers: const {
          'gender': 'Man',
          'relationship_status': 'In a long-term relationship',
          'education_level': 'Undergraduate degree finished',
        },
        onboardingCompleted: true,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

  testWidgets('dashboard', (tester) async {
    phone(tester);
    final result = await Backend.auth.signUp(
      email: 'aarav@example.com',
      password: 'hunter2',
      displayName: 'Aarav',
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.theme,
        home: SessionScope(
          user: result.user,
          profile: aProfile(result.user.id),
          reload: () async {},
          child: const DashboardScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(DashboardScreen),
      matchesGoldenFile('goldens/dashboard.png'),
    );
  });

  testWidgets('a multi-select relationship question', (tester) async {
    phone(tester);
    final result = await Backend.auth.signUp(
      email: 'aarav@example.com',
      password: 'hunter2',
      displayName: 'Aarav',
    );
    final profile = aProfile(result.user.id);
    final chat = await Backend.data.createChat(
      userId: result.user.id,
      category: ChatCategory.relationship,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.theme,
        home: IntakeFlowScreen(chat: chat, profile: profile),
      ),
    );
    await tester.pumpAndSettle();

    // Past the first question, so the screenshot shows the checkbox list that is
    // worded around the person it just named.
    await tester.tap(find.text('My girlfriend'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text("She doesn't give me time"));
    await tester.tap(find.text('I do not feel valued'));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(IntakeFlowScreen),
      matchesGoldenFile('goldens/intake_multi.png'),
    );
  });

  testWidgets('the recommendation', (tester) async {
    phone(tester);
    final ai = FakeAi();
    ai.recommendation_ = const Recommendation(
      headline: 'Stop lending Ravi money, and tell him this Sunday.',
      text: '''
You have lent him money four times and been paid back once. That is not a
cash-flow problem, it is **the shape of the friendship** — and you already knew
that, because you described the last conversation before you described the loan.

> A loan he cannot repay is a gift with resentment attached.

The money is gone either way. What is still on the table is whether you spend
another two years quietly keeping score.
''',
      nextSteps: [
        'Say it on Sunday, in person, before he asks',
        'Do not offer a smaller amount as a compromise',
      ],
      confidence: 'Fairly sure. If he has ever paid you back on time, this '
          'changes.',
    );
    Backend.overrideWith(ai: ai, usingSupabase: true);

    final chat = Chat(
      id: 'c1',
      userId: 'u1',
      category: ChatCategory.financial,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.theme, home: RecommendationScreen(chat: chat)),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(RecommendationScreen),
      matchesGoldenFile('goldens/recommendation.png'),
    );
  });
}
