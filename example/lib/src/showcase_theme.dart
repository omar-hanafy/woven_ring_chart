import 'package:flutter/material.dart';

/// The showcase palette, in one place.
///
/// The rings are the only things on the page allowed to be colourful.
/// Everything around them is paper, ink, and one hairline, so nothing competes
/// with the charts for attention. The single exception is the code panel,
/// which is dark on purpose: it is the other thing a visitor came to read.
abstract final class ShowcaseColors {
  /// The page behind the cards, a shade darker than they are.
  static const Color page = Color(0xFFF3F1EA);

  /// Every card a chart stands on.
  ///
  /// This is exactly `WovenPalette.surface`, which is what
  /// `WovenRingStyle.surfaceColor` already defaults to. Because a ring's card
  /// is the colour the chart assumes it is sitting on, an uncoloured border
  /// reads as the segments being cut out of each other, and no snippet on this
  /// page ever has to mention `surfaceColor` to make its chart look right.
  static const Color surface = Color(0xFFFBFAF7);

  /// Headings and body text.
  static const Color ink = Color(0xFF202532);

  /// Captions, notes, and anything explaining rather than stating.
  static const Color muted = Color(0xFF667085);

  /// Dividers, card outlines, and the install chip.
  static const Color line = Color(0xFFE7E3DA);

  /// The code panel's background.
  static const Color codeBackground = Color(0xFF1B1F2E);

  /// Ordinary code text.
  static const Color codeText = Color(0xFFD8DCE8);

  /// `const`, `true`, `false`, and friends.
  static const Color codeKeyword = Color(0xFF7FA6F0);

  /// Anything starting with `Woven`.
  static const Color codeType = Color(0xFFB49CF5);

  /// Numeric literals.
  static const Color codeNumber = Color(0xFFEFB366);

  /// String literals.
  static const Color codeString = Color(0xFF7FD4A8);

  /// Comments.
  static const Color codeComment = Color(0xFF6B7590);
}

/// Type and spacing the whole page shares.
abstract final class ShowcaseText {
  static const TextStyle wordmark = TextStyle(
    color: ShowcaseColors.ink,
    fontSize: 40,
    height: 1.05,
    fontWeight: FontWeight.w800,
    letterSpacing: -1,
  );

  static const TextStyle lede = TextStyle(
    color: ShowcaseColors.muted,
    fontSize: 18,
    height: 1.5,
  );

  static const TextStyle sectionTitle = TextStyle(
    color: ShowcaseColors.ink,
    fontSize: 26,
    height: 1.2,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.4,
  );

  static const TextStyle body = TextStyle(
    color: ShowcaseColors.muted,
    fontSize: 15.5,
    height: 1.55,
  );

  static const TextStyle cardTitle = TextStyle(
    color: ShowcaseColors.ink,
    fontSize: 15,
    fontWeight: FontWeight.w700,
  );

  static const TextStyle caption = TextStyle(
    color: ShowcaseColors.muted,
    fontSize: 13,
    height: 1.4,
  );

  static const TextStyle code = TextStyle(
    fontFamily: 'monospace',
    fontFamilyFallback: <String>['Menlo', 'Consolas', 'Courier'],
    fontSize: 13.5,
    height: 1.55,
  );
}

/// Layout constants shared by every section.
abstract final class ShowcaseLayout {
  /// The widest the text column ever gets. Past this, lines stop being
  /// comfortable to read and the page just looks stretched.
  static const double maxContentWidth = 1120;

  /// Below this, a demo and its code stack instead of sitting side by side.
  static const double sideBySideBreakpoint = 880;

  /// The page's horizontal breathing room.
  static const EdgeInsets pagePadding = EdgeInsets.symmetric(horizontal: 24);
}
