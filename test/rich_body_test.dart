import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:thoughtloom/theme/app_theme.dart';
import 'package:thoughtloom/widgets/rich_body.dart';

/// The renderer for the Markdown subset the model is allowed to write.
///
/// The grammar is a contract with `recommendation_prompt.py`, which names these
/// exact constructs and bans everything else. Both halves are pinned: the ones
/// listed here have to render, and the ones deliberately left out have to
/// degrade to prose rather than throw in front of someone who was promised
/// advice.
void main() {
  Future<void> pump(WidgetTester tester, String markdown) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.theme,
        home: Scaffold(
          body: SingleChildScrollView(child: RichBody(markdown: markdown)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Every span of a rendered paragraph, with its style — which is the only way
  /// to ask "is this bit actually bold?".
  List<(String, TextStyle?)> spansOf(WidgetTester tester, String plain) {
    final text = tester.widget<Text>(find.text(plain));
    final spans = <(String, TextStyle?)>[];
    (text.textSpan! as TextSpan).visitChildren((span) {
      if (span is TextSpan && span.text != null) {
        spans.add((span.text!, span.style));
      }
      return true;
    });
    return spans;
  }

  group('the grammar the prompt promises', () {
    testWidgets('bold is heavier *and* darker, because weight alone vanishes',
        (tester) async {
      await pump(tester, 'You should **leave**, and soon.');

      final spans = spansOf(tester, 'You should leave, and soon.');
      final bold = spans.firstWhere((s) => s.$1 == 'leave').$2!;

      expect(bold.fontWeight, FontWeight.w700);
      // The half that is easy to forget: at body size on a cream card, weight on
      // its own is nearly invisible, which is what made "make the bold parts
      // bold" worth asking for.
      expect(bold.color, AppTheme.textDark);

      final plain = spans.firstWhere((s) => s.$1 == 'You should ').$2;
      expect(plain?.fontWeight, isNot(FontWeight.w700));
    });

    testWidgets('italic is italic', (tester) async {
      await pump(tester, 'That is *not* the question.');
      final spans = spansOf(tester, 'That is not the question.');
      expect(spans.firstWhere((s) => s.$1 == 'not').$2!.fontStyle,
          FontStyle.italic);
    });

    testWidgets('underscores are literal, because snake_case exists',
        (tester) async {
      // Every renderer that treats _ as emphasis mangles ordinary writing, and
      // the prompt bans it for exactly this reason.
      await pump(tester, 'Ask about the _fee_structure_ before you sign.');
      expect(find.text('Ask about the _fee_structure_ before you sign.'),
          findsOneWidget);
    });

    testWidgets('headings, bullets and numbers render as themselves',
        (tester) async {
      await pump(tester, '''
## What it comes down to

- The money is not the problem
- The timing is

1. Say it on Sunday
2. Do not offer a smaller amount
''');

      expect(find.text('What it comes down to'), findsOneWidget);
      expect(find.text('The money is not the problem'), findsOneWidget);
      expect(find.text('The timing is'), findsOneWidget);
      expect(find.text('Say it on Sunday'), findsOneWidget);
      // The number is drawn, not just the text.
      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('a callout is the one thing not to miss', (tester) async {
      await pump(tester, '> You already know the answer.');
      expect(find.text('You already know the answer.'), findsOneWidget);
    });

    testWidgets('a hard-wrapped paragraph is one paragraph', (tester) async {
      // The model's idea of a line length must not become the phone's.
      await pump(tester, 'Stop lending him money.\nTell him in person,\nthis week.');
      expect(
        find.text('Stop lending him money. Tell him in person, this week.'),
        findsOneWidget,
      );
    });

    testWidgets('a blank line starts a new paragraph', (tester) async {
      await pump(tester, 'First thing.\n\nSecond thing.');
      expect(find.text('First thing.'), findsOneWidget);
      expect(find.text('Second thing.'), findsOneWidget);
    });
  });

  group('what a model does against instructions', () {
    testWidgets('a banned construct degrades to prose rather than throwing',
        (tester) async {
      // The prompt bans tables, links and code fences. A model that emits one
      // anyway must cost the reader a slightly odd line, not an exception where
      // their advice should be.
      await pump(tester, '| a | b |\n|---|---|\n| 1 | 2 |\n\n[link](http://x)');
      expect(tester.takeException(), isNull);
      expect(find.byType(RichBody), findsOneWidget);
    });

    testWidgets('empty renders nothing and does not throw', (tester) async {
      await pump(tester, '');
      expect(tester.takeException(), isNull);
    });

    testWidgets('an unclosed marker is left alone', (tester) async {
      await pump(tester, 'This is **not closed');
      expect(find.text('This is **not closed'), findsOneWidget);
    });
  });

  group('stripMarkdown', () {
    test('leaves the words and takes the marks', () {
      expect(
        stripMarkdown('## Heading\n\n**Leave** him.\n- one\n> note'),
        'Heading\n\nLeave him.\none\nnote',
      );
    });

    test('is what a place that cannot render markers uses', () {
      // A history subtitle or an accessibility label would otherwise read the
      // asterisks out loud.
      expect(stripMarkdown('**Go.**'), 'Go.');
      expect(stripMarkdown('plain'), 'plain');
    });
  });
}
