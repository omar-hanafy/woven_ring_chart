import 'package:flutter/material.dart';

import '../showcase_theme.dart';
import 'code_block.dart';

/// One band of the page: a heading, an optional paragraph, and a body.
///
/// Every section on the showcase is one of these, so the rhythm down the page
/// is set in a single place rather than negotiated section by section.
class Section extends StatelessWidget {
  const Section({
    required this.title,
    required this.child,
    this.lede,
    this.dividerAbove = true,
    super.key,
  });

  final String title;
  final String? lede;
  final Widget child;
  final bool dividerAbove;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (dividerAbove) const Divider(height: 1, color: ShowcaseColors.line),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 52),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: ShowcaseLayout.maxContentWidth,
              ),
              child: Padding(
                padding: ShowcaseLayout.pagePadding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title, style: ShowcaseText.sectionTitle),
                    if (lede != null) ...<Widget>[
                      const SizedBox(height: 10),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 720),
                        child: Text(lede!, style: ShowcaseText.body),
                      ),
                    ],
                    const SizedBox(height: 28),
                    child,
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A running chart beside the source that produced it.
///
/// Side by side when there is room, stacked when there is not, and the chart
/// always comes first so a narrow screen still leads with the picture.
class DemoBlock extends StatelessWidget {
  const DemoBlock({
    required this.demo,
    required this.source,
    this.codeLabel,
    this.demoFlex = 5,
    this.codeFlex = 6,
    this.alignment = CrossAxisAlignment.center,
    super.key,
  });

  final Widget demo;
  final String source;
  final String? codeLabel;
  final int demoFlex;
  final int codeFlex;

  /// How the code sits against the demo.
  ///
  /// Centred reads best when the two are a similar height. A demo that is much
  /// taller than its snippet wants [CrossAxisAlignment.start], or the code
  /// floats around halfway down with nothing beside its top half.
  final CrossAxisAlignment alignment;

  @override
  Widget build(BuildContext context) {
    final Widget code = CodeBlock(source: source, label: codeLabel);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        if (constraints.maxWidth < ShowcaseLayout.sideBySideBreakpoint) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[demo, const SizedBox(height: 20), code],
          );
        }
        return Row(
          crossAxisAlignment: alignment,
          children: <Widget>[
            Expanded(flex: demoFlex, child: demo),
            const SizedBox(width: 28),
            Expanded(flex: codeFlex, child: code),
          ],
        );
      },
    );
  }
}

/// The white plinth a chart stands on.
class ChartStage extends StatelessWidget {
  const ChartStage({
    required this.child,
    this.size = 300,
    this.padding = 28,
    super.key,
  });

  final Widget child;
  final double size;
  final double padding;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: ShowcaseColors.surface,
        border: Border.all(color: ShowcaseColors.line),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: EdgeInsets.all(padding),
        child: Center(
          child: SizedBox.square(dimension: size, child: child),
        ),
      ),
    );
  }
}

/// A small chart in a card, with a name and a line about what it shows.
///
/// Used wherever several variations are compared at once. The one-line
/// [source] under each is what makes the grid usable rather than decorative.
class DemoCard extends StatelessWidget {
  const DemoCard({
    required this.title,
    required this.chart,
    this.note,
    this.source,
    this.width = 226,
    this.chartSize = 150,
    super.key,
  });

  final String title;
  final Widget chart;
  final String? note;
  final String? source;
  final double width;
  final double chartSize;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: ShowcaseColors.surface,
          border: Border.all(color: ShowcaseColors.line),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Center(
                child: SizedBox.square(dimension: chartSize, child: chart),
              ),
              const SizedBox(height: 14),
              Text(title, style: ShowcaseText.cardTitle),
              if (note != null) ...<Widget>[
                const SizedBox(height: 4),
                Text(note!, style: ShowcaseText.caption),
              ],
              if (source != null) ...<Widget>[
                const SizedBox(height: 12),
                _InlineCode(source!),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One short line of code, tinted but without the panel chrome.
class _InlineCode extends StatelessWidget {
  const _InlineCode(this.source);

  final String source;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: ShowcaseColors.codeBackground,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // One line per authored line, each shrunk to fit rather than
            // wrapped. A card is too narrow to hide an overflow in, and
            // letting the text wrap on its own snaps identifiers in half:
            // "WovenSmallValuePolicy.enforc / e" helps nobody.
            for (final String line in source.split('\n'))
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text.rich(
                  TextSpan(children: highlightDart(line)),
                  maxLines: 1,
                  style: ShowcaseText.code.copyWith(
                    fontSize: 12,
                    height: 1.5,
                    color: ShowcaseColors.codeText,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
