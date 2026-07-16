//app_theme.dart

import 'package:flutter/material.dart';

/// The app's design tokens.
///
/// ### What changed, and why
///
/// The palette is unchanged — the sage and the cream are the product's face and
/// were never the problem. What was missing is *hierarchy*. Every element in the
/// app was the same cream fill, the same 30pt radius, and the same shadow: a
/// card, a tappable option, a search box, a chat row, and the mic were
/// indistinguishable, so nothing on screen said what could be pressed, what was
/// chosen, or what was merely a container. That reads as "confusing" long before
/// anyone can name why.
///
/// So the tokens below are deliberately *scales* rather than single values:
/// three radii, three elevations, and a type ramp. An element's job is now
/// legible from its shape.
class AppTheme {
  // --- colour --------------------------------------------------------------

  /// The sage. Sampled from the logo's blue ribbon (#7B98A5) and unchanged from
  /// Prompt 1 — it is the brand.
  static const Color primary = Color(0xFF6F8F9B);

  /// Pressed states and emphasis. A darker sage rather than an opacity shift,
  /// which over cream turns muddy rather than deeper.
  static const Color primaryDeep = Color(0xFF56747F);

  /// A sage wash for tinted fills — selected chips, quiet highlights.
  static const Color primarySoft = Color(0xFFE4EBEE);

  /// The tan from the logo's second ribbon. The app shipped without it and was
  /// monochrome as a result: with only one colour, "chosen" and "important" and
  /// "tappable" all had to be said with the same sage. This is the accent that
  /// lets the recommendation highlight something without shouting.
  static const Color accent = Color(0xFFE3C7A3);

  /// The tan, dark enough to read as text or an icon on cream.
  static const Color accentDeep = Color(0xFF9C7440);

  /// A tan wash, for highlighted passages behind text.
  static const Color accentSoft = Color(0xFFF6EDE0);

  static const Color textDark = Color(0xFF2E3A3F);
  static const Color textLight = Color(0xFF5F6F78);

  /// Timestamps, counters, the third line of a row — present but never
  /// competing.
  static const Color textFaint = Color(0xFF8A979E);

  static const Color cardBg = Color(0xFFF5F1E8);
  static const Color textOnCard = Color(0xFF3D4F56);

  /// The sage an option row takes when chosen.
  static const Color selected = Color(0xFF9FB6C2);

  /// Hairlines. The single highest-leverage addition here: a 1px edge is what
  /// separates "you may press this" from "this is a box with words in it",
  /// which no amount of shadow was managing.
  static const Color border = Color(0x1A3D4F56);
  static const Color borderStrong = Color(0x3D3D4F56);

  /// The clay red — the app's only alarm colour, kept muted so it reads as part
  /// of the same palette. [danger] is the mark, [dangerText] the darker tone
  /// that stays legible on cream.
  static const Color danger = Color(0xFFC0574E);
  static const Color dangerText = Color(0xFF8F3F38);

  /// The live-microphone red. Distinct from [danger] — nothing is wrong, it is
  /// simply recording, and a warning colour would read as an error. This is the
  /// record dot every camera and voice recorder has trained people to know.
  static const Color live = Color(0xFFD2564A);

  // --- radius --------------------------------------------------------------

  /// Chips, badges, the small stuff.
  static const double rSm = 12;

  /// Rows and fields — a tappable line of text.
  static const double rMd = 18;

  /// Cards and sheets — a container holding other things.
  static const double rLg = 26;

  /// Buttons and anything genuinely pill-shaped. Kept at 30 under its original
  /// name because the whole app already refers to it.
  static const double pillRadius = 30;

  // --- spacing -------------------------------------------------------------
  //
  // A 4pt ramp. Screens previously spaced everything off `screenHeight * 0.018`
  // and similar, which is why no two gaps in the app were the same size.

  static const double s1 = 4;
  static const double s2 = 8;
  static const double s3 = 12;
  static const double s4 = 16;
  static const double s5 = 20;
  static const double s6 = 24;
  static const double s8 = 32;
  static const double s10 = 40;

  // --- elevation -----------------------------------------------------------

  /// Flat-ish: a row in a list. Present, not floating.
  static List<BoxShadow> get shadowSoft => const [
        BoxShadow(
          color: Color(0x0F000000),
          offset: Offset(0, 2),
          blurRadius: 8,
        ),
      ];

  /// A card that holds content.
  static List<BoxShadow> get shadowCard => const [
        BoxShadow(
          color: Color(0x14000000),
          offset: Offset(0, 6),
          blurRadius: 18,
          spreadRadius: -2,
        ),
      ];

  /// Something that sits above the page — a composer, a dialog, the CTA.
  static List<BoxShadow> get shadowLifted => const [
        BoxShadow(
          color: Color(0x1F000000),
          offset: Offset(0, 12),
          blurRadius: 28,
          spreadRadius: -6,
        ),
      ];

  /// The sage glow under the primary button, so the one thing you are meant to
  /// press looks like it is being lit from underneath.
  static List<BoxShadow> get shadowPrimary => [
        BoxShadow(
          color: primary.withValues(alpha: 0.34),
          offset: const Offset(0, 8),
          blurRadius: 20,
          spreadRadius: -4,
        ),
      ];

  // --- type ----------------------------------------------------------------

  /// How much to scale text for this viewport.
  ///
  /// The app sized every font as `screenWidth * 0.04x`. On the 390pt phone it
  /// was designed against that is right; on a 320pt phone it is unreadably
  /// small, and on an 800pt tablet the same style renders at 34pt — which is
  /// why the app looked like a phone screen someone had zoomed into. Scaling
  /// against the design width and clamping keeps the intent without the
  /// extremes.
  static double scaleOf(BuildContext context) =>
      (MediaQuery.sizeOf(context).width / 390).clamp(0.85, 1.15);

  /// The big line at the top of a screen.
  static TextStyle display(BuildContext context) => TextStyle(
        fontSize: 30 * scaleOf(context),
        fontWeight: FontWeight.w700,
        color: textDark,
        height: 1.2,
        letterSpacing: -0.8,
      );

  /// A question, or a screen's subject.
  static TextStyle title(BuildContext context) => TextStyle(
        fontSize: 24 * scaleOf(context),
        fontWeight: FontWeight.w700,
        color: textDark,
        height: 1.3,
        letterSpacing: -0.5,
      );

  /// A card heading.
  static TextStyle heading(BuildContext context) => TextStyle(
        fontSize: 17 * scaleOf(context),
        fontWeight: FontWeight.w700,
        color: textOnCard,
        height: 1.35,
        letterSpacing: -0.2,
      );

  /// Running text.
  static TextStyle body(BuildContext context) => TextStyle(
        fontSize: 15 * scaleOf(context),
        color: textOnCard,
        height: 1.55,
      );

  /// Explanatory text under a heading.
  static TextStyle secondary(BuildContext context) => TextStyle(
        fontSize: 14 * scaleOf(context),
        color: textLight,
        height: 1.45,
      );

  /// Buttons and option rows.
  static TextStyle label(BuildContext context) => TextStyle(
        fontSize: 15 * scaleOf(context),
        fontWeight: FontWeight.w600,
        color: textOnCard,
        letterSpacing: -0.1,
      );

  /// Timestamps, counters, captions.
  static TextStyle meta(BuildContext context) => TextStyle(
        fontSize: 12.5 * scaleOf(context),
        color: textFaint,
        height: 1.35,
      );

  /// The all-caps micro-label above a section.
  static TextStyle overline(BuildContext context) => TextStyle(
        fontSize: 11 * scaleOf(context),
        fontWeight: FontWeight.w700,
        color: textFaint,
        letterSpacing: 0.8,
      );

  static ThemeData theme = ThemeData(
    scaffoldBackgroundColor: Colors.transparent,
    fontFamily: 'Inter',
    colorScheme: ColorScheme.fromSeed(
      seedColor: primary,
      primary: primary,
      surface: cardBg,
      error: danger,
    ),
    // The app draws its own background image; a themed surface behind it would
    // only ever be seen as a flash on push.
    canvasColor: Colors.transparent,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      foregroundColor: textDark,
    ),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: primary,
      selectionColor: Color(0x406F8F9B),
      selectionHandleColor: primary,
    ),
    splashFactory: InkSparkle.splashFactory,
  );
}
