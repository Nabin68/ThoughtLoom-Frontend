//rich_body.dart

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Renders the small slice of Markdown the model is allowed to write.
///
/// ### Why this exists rather than a package
///
/// The recommendation was the one screen in the app people actually come back to
/// read, and it rendered as a single undifferentiated `Text` — because the
/// prompt told the model "plain paragraphs, no markdown" and nothing downstream
/// could have rendered any. So the app's whole reason to exist arrived looking
/// like a chat window's worth of grey prose, with the sentence that mattered
/// buried in paragraph three.
///
/// The general-purpose renderers are a poor trade here: `flutter_markdown` is
/// discontinued, and all of them bring a full CommonMark parser to display text
/// whose grammar *we* specify in the prompt. The subset below is the whole
/// contract — and because it is small, every element can be styled to the app's
/// tokens instead of fighting a package's defaults.
///
/// ### The grammar
///
/// ```text
/// ## Heading            a section
/// **bold**              the load-bearing phrase
/// *italic*              emphasis
/// `code`                a literal — a form name, an amount
/// - item                a bullet
/// 1. item               a step, where order matters
/// > line                a callout: the one thing to take away
/// ```
///
/// Anything else is treated as prose, which is the right failure: a model that
/// emits a table gets a slightly odd-looking line, not an exception in front of
/// someone who was told they would be given advice.
class RichBody extends StatelessWidget {
  final String markdown;

  /// The style prose inherits. Bold, headings, and callouts derive from it, so
  /// one call site can render the same grammar in a chat bubble and on a card.
  final TextStyle? baseStyle;

  /// The colour of `**bold**` and headings. Defaults to a deeper tone than the
  /// prose, because "bold" that is only heavier and not darker barely registers
  /// against cream.
  final Color? emphasisColor;

  /// Whether `> callout` blocks may draw their tinted panel. Off inside a chat
  /// bubble, which is already a panel.
  final bool allowCallouts;

  const RichBody({
    super.key,
    required this.markdown,
    this.baseStyle,
    this.emphasisColor,
    this.allowCallouts = true,
  });

  @override
  Widget build(BuildContext context) {
    final base = baseStyle ?? AppTheme.body(context);
    final emphasis = emphasisColor ?? AppTheme.textDark;
    final blocks = _parse(markdown);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < blocks.length; i++)
          Padding(
            padding: EdgeInsets.only(
              // No trailing gap on the last block: the card's own padding is
              // the bottom margin, and a second one reads as a mistake.
              bottom: i == blocks.length - 1 ? 0 : blocks[i].gapAfter,
              top: blocks[i].gapBefore(i == 0),
            ),
            child: blocks[i].build(context, base, emphasis, allowCallouts),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Blocks
// ---------------------------------------------------------------------------

sealed class _Block {
  double get gapAfter => AppTheme.s3;

  double gapBefore(bool isFirst) => 0;

  Widget build(
    BuildContext context,
    TextStyle base,
    Color emphasis,
    bool allowCallouts,
  );
}

class _Paragraph extends _Block {
  final String text;

  _Paragraph(this.text);

  @override
  Widget build(BuildContext context, TextStyle base, Color emphasis, bool _) =>
      Text.rich(_inline(text, base, emphasis), style: base);
}

class _Heading extends _Block {
  final String text;
  final int level;

  _Heading(this.text, this.level);

  // Headings need air above them, not below — a heading glued to the paragraph
  // it introduces and floating away from the one it follows is the single most
  // common way typography goes wrong.
  @override
  double get gapAfter => AppTheme.s2;

  @override
  double gapBefore(bool isFirst) => isFirst ? 0 : AppTheme.s4;

  @override
  Widget build(BuildContext context, TextStyle base, Color emphasis, bool _) {
    final style = (level <= 2 ? AppTheme.heading(context) : AppTheme.label(context))
        .copyWith(color: emphasis);
    return Text.rich(_inline(text, style, emphasis), style: style);
  }
}

class _Bullet extends _Block {
  final String text;

  _Bullet(this.text);

  @override
  double get gapAfter => AppTheme.s2;

  @override
  Widget build(BuildContext context, TextStyle base, Color emphasis, bool _) {
    final scale = AppTheme.scaleOf(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          // Centred on the first line's x-height rather than its box, or the dot
          // sits visibly high against the text it belongs to.
          padding: EdgeInsets.only(top: (base.fontSize ?? 15) * 0.5),
          child: Container(
            width: 5 * scale,
            height: 5 * scale,
            decoration: const BoxDecoration(
              color: AppTheme.primary,
              shape: BoxShape.circle,
            ),
          ),
        ),
        SizedBox(width: AppTheme.s3),
        Expanded(child: Text.rich(_inline(text, base, emphasis), style: base)),
      ],
    );
  }
}

class _Numbered extends _Block {
  final String text;
  final int number;

  _Numbered(this.text, this.number);

  @override
  double get gapAfter => AppTheme.s3;

  @override
  Widget build(BuildContext context, TextStyle base, Color emphasis, bool _) {
    final scale = AppTheme.scaleOf(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22 * scale,
          height: 22 * scale,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: AppTheme.primary,
            shape: BoxShape.circle,
          ),
          child: Text(
            '$number',
            style: TextStyle(
              fontSize: 11 * scale,
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        SizedBox(width: AppTheme.s3),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(top: 2 * scale),
            child: Text.rich(_inline(text, base, emphasis), style: base),
          ),
        ),
      ],
    );
  }
}

/// The one thing to take away, in the logo's tan.
///
/// This is what the accent colour is *for*: something that has to be seen before
/// the paragraph around it, without the alarm that a red or a heavy sage fill
/// would carry.
class _Callout extends _Block {
  final String text;

  _Callout(this.text);

  @override
  double get gapAfter => AppTheme.s4;

  @override
  double gapBefore(bool isFirst) => isFirst ? 0 : AppTheme.s2;

  @override
  Widget build(
    BuildContext context,
    TextStyle base,
    Color emphasis,
    bool allowCallouts,
  ) {
    final body = Text.rich(
      _inline(text, base.copyWith(color: emphasis), emphasis),
      style: base.copyWith(color: emphasis),
    );
    // Inside a chat bubble there is already a panel, and a panel in a panel is
    // just noise — so the accent is carried by the bar alone.
    if (!allowCallouts) {
      return Container(
        padding: EdgeInsets.only(left: AppTheme.s3),
        decoration: const BoxDecoration(
          border: Border(
            left: BorderSide(color: AppTheme.accentDeep, width: 3),
          ),
        ),
        child: body,
      );
    }
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(AppTheme.s4),
      decoration: BoxDecoration(
        color: AppTheme.accentSoft,
        borderRadius: BorderRadius.circular(AppTheme.rSm),
        border: Border(
          left: BorderSide(color: AppTheme.accentDeep, width: 3),
        ),
      ),
      child: body,
    );
  }
}

// ---------------------------------------------------------------------------
// Parsing
// ---------------------------------------------------------------------------

final _headingRe = RegExp(r'^(#{1,4})\s+(.*)$');
final _bulletRe = RegExp(r'^\s*[-*•]\s+(.*)$');
final _numberedRe = RegExp(r'^\s*(\d+)[.)]\s+(.*)$');
final _quoteRe = RegExp(r'^\s*>\s?(.*)$');

List<_Block> _parse(String source) {
  final blocks = <_Block>[];
  final lines = source.replaceAll('\r\n', '\n').trim().split('\n');

  final paragraph = <String>[];
  final quote = <String>[];

  void flushParagraph() {
    if (paragraph.isEmpty) return;
    blocks.add(_Paragraph(paragraph.join(' ').trim()));
    paragraph.clear();
  }

  void flushQuote() {
    if (quote.isEmpty) return;
    blocks.add(_Callout(quote.join(' ').trim()));
    quote.clear();
  }

  void flush() {
    flushParagraph();
    flushQuote();
  }

  for (final raw in lines) {
    final line = raw.trimRight();

    if (line.trim().isEmpty) {
      flush();
      continue;
    }

    final quoted = _quoteRe.firstMatch(line);
    if (quoted != null) {
      flushParagraph();
      quote.add(quoted.group(1) ?? '');
      continue;
    }
    flushQuote();

    final heading = _headingRe.firstMatch(line);
    if (heading != null) {
      flushParagraph();
      blocks.add(_Heading(heading.group(2)!.trim(), heading.group(1)!.length));
      continue;
    }

    final bullet = _bulletRe.firstMatch(line);
    if (bullet != null) {
      flushParagraph();
      blocks.add(_Bullet(bullet.group(1)!.trim()));
      continue;
    }

    final numbered = _numberedRe.firstMatch(line);
    if (numbered != null) {
      flushParagraph();
      blocks.add(_Numbered(
        numbered.group(2)!.trim(),
        int.tryParse(numbered.group(1)!) ?? blocks.whereType<_Numbered>().length + 1,
      ));
      continue;
    }

    // A hard-wrapped paragraph is one paragraph. Joining on a space rather than
    // keeping the model's line breaks means its idea of a line length does not
    // become the phone's.
    paragraph.add(line.trim());
  }

  flush();
  return blocks;
}

/// `**bold**`, `*italic*`, and `` `code` ``.
///
/// Underscores are deliberately not emphasis markers: `snake_case` and
/// `file_name.dart` are ordinary things to write, and every renderer that treats
/// `_` as italic mangles them.
final _inlineRe = RegExp(r'\*\*(.+?)\*\*|\*(.+?)\*|`(.+?)`', dotAll: true);

InlineSpan _inline(String text, TextStyle base, Color emphasis) {
  final spans = <InlineSpan>[];
  var cursor = 0;

  for (final match in _inlineRe.allMatches(text)) {
    if (match.start > cursor) {
      spans.add(TextSpan(text: text.substring(cursor, match.start)));
    }

    final bold = match.group(1);
    final italic = match.group(2);
    final code = match.group(3);

    if (bold != null) {
      spans.add(TextSpan(
        text: bold,
        // Darker as well as heavier. Weight alone is nearly invisible at body
        // size on a cream card, which is what made "make the bold parts bold"
        // worth asking for in the first place.
        style: base.copyWith(fontWeight: FontWeight.w700, color: emphasis),
      ));
    } else if (italic != null) {
      spans.add(TextSpan(
        text: italic,
        style: base.copyWith(fontStyle: FontStyle.italic),
      ));
    } else if (code != null) {
      spans.add(TextSpan(
        text: code,
        style: base.copyWith(
          fontFamily: 'monospace',
          fontFamilyFallback: const ['Courier New', 'monospace'],
          fontSize: (base.fontSize ?? 15) * 0.92,
          color: AppTheme.accentDeep,
        ),
      ));
    }

    cursor = match.end;
  }

  if (cursor < text.length) {
    spans.add(TextSpan(text: text.substring(cursor)));
  }

  return TextSpan(style: base, children: spans);
}

/// Strips the markers, for somewhere that cannot render them — a list subtitle,
/// a search excerpt, an accessibility label.
String stripMarkdown(String source) => source
    .replaceAll(RegExp(r'^\s*[-*•]\s+', multiLine: true), '')
    .replaceAll(RegExp(r'^\s*\d+[.)]\s+', multiLine: true), '')
    .replaceAll(RegExp(r'^\s*>\s?', multiLine: true), '')
    .replaceAll(RegExp(r'^#{1,4}\s+', multiLine: true), '')
    .replaceAllMapped(
      RegExp(r'\*\*(.+?)\*\*|\*(.+?)\*|`(.+?)`', dotAll: true),
      (m) => m.group(1) ?? m.group(2) ?? m.group(3) ?? '',
    )
    .trim();
