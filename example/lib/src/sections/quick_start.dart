import 'package:flutter/material.dart';

import 'package:woven_ring_chart/woven_ring_chart.dart';

import '../showcase_theme.dart';
import '../ui/section.dart';

/// The shortest thing that draws a woven ring, beside its chart.
///
/// [_source] and [_QuickStartChart] are deliberately kept next to each other
/// so that the one cannot be edited without the other being right there.
class QuickStartSection extends StatelessWidget {
  const QuickStartSection({super.key});

  static const String _source = '''
WovenRingChart(
  segments: <WovenSegment>[
    WovenSegment.solid(37, WovenPalette.purple),
    WovenSegment.solid(19, WovenPalette.green),
    WovenSegment.solid(29, WovenPalette.amber),
    WovenSegment.solid(15, WovenPalette.rose),
  ],
  center: const Text('100'),
  semanticLabel: 'Spending by category',
)''';

  @override
  Widget build(BuildContext context) {
    return const Section(
      title: 'Quick start',
      lede:
          'Values are yours to pick: percentages, counts, currency, anything. '
          'They are normalized against each other, and the order you write '
          'them is the order they are drawn. The chart is square, takes the '
          'smaller of whatever constraints it is given, and settles at 240 '
          'logical pixels with nothing bounded on either side.',
      dividerAbove: false,
      child: DemoBlock(
        demo: ChartStage(size: 260, child: _QuickStartChart()),
        source: _source,
      ),
    );
  }
}

class _QuickStartChart extends StatelessWidget {
  const _QuickStartChart();

  @override
  Widget build(BuildContext context) {
    return WovenRingChart(
      key: const ValueKey<String>('quick-start-ring'),
      segments: <WovenSegment>[
        WovenSegment.solid(37, WovenPalette.purple),
        WovenSegment.solid(19, WovenPalette.green),
        WovenSegment.solid(29, WovenPalette.amber),
        WovenSegment.solid(15, WovenPalette.rose),
      ],
      center: const Text(
        '100',
        style: TextStyle(
          color: ShowcaseColors.ink,
          fontSize: 42,
          fontWeight: FontWeight.w800,
        ),
      ),
      semanticLabel: 'Spending by category',
    );
  }
}
