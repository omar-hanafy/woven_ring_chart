import 'package:flutter/material.dart';

import 'package:woven_ring_chart/woven_ring_chart.dart';

import '../showcase_theme.dart';
import '../ui/section.dart';

/// Labelling a chart for assistive technology.
class AccessibilitySection extends StatelessWidget {
  const AccessibilitySection({super.key});

  static const String _source = '''
WovenRingChart(
  segments: const <WovenSegment>[
    WovenSegment(
      value: 37,
      fill: WovenFill.solid(WovenPalette.purple),
      semanticLabel: 'Housing, 37 percent',
    ),
    WovenSegment(
      value: 19,
      fill: WovenFill.solid(WovenPalette.green),
      semanticLabel: 'Food, 19 percent',
    ),
    // ...
  ],
  center: const Text('100'),
)''';

  @override
  Widget build(BuildContext context) {
    return Section(
      title: 'Accessibility',
      lede:
          'Give the chart a semanticLabel and semanticValue, or label the '
          'segments individually and let their labels be joined. Labelling the '
          'segments does not take the centre widget out of the accessibility '
          'tree, because a segment label describes a segment and says nothing '
          'about the total. A loading chart with a label announces itself as a '
          'live region.',
      child: DemoBlock(
        source: _source,
        demo: ChartStage(
          size: 230,
          child: WovenRingChart(
            key: const ValueKey<String>('accessibility-ring'),
            segments: const <WovenSegment>[
              WovenSegment(
                value: 37,
                fill: WovenFill.solid(WovenPalette.purple),
                semanticLabel: 'Housing, 37 percent',
              ),
              WovenSegment(
                value: 19,
                fill: WovenFill.solid(WovenPalette.green),
                semanticLabel: 'Food, 19 percent',
              ),
              WovenSegment(
                value: 29,
                fill: WovenFill.solid(WovenPalette.amber),
                semanticLabel: 'Transport, 29 percent',
              ),
              WovenSegment(
                value: 15,
                fill: WovenFill.solid(WovenPalette.rose),
                semanticLabel: 'Everything else, 15 percent',
              ),
            ],
            center: const Text(
              '100',
              style: TextStyle(
                color: ShowcaseColors.ink,
                fontSize: 38,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
