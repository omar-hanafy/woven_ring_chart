import 'package:flutter/material.dart';

import 'package:woven_ring_chart/woven_ring_chart.dart';

import '../ui/section.dart';

/// What the chart does when it has nothing, or too little, to draw.
class StatesSection extends StatelessWidget {
  const StatesSection({super.key});

  static const List<double> _tiny = <double>[0.4, 39.6, 25, 35];

  @override
  Widget build(BuildContext context) {
    return Section(
      title: 'Nothing, and nearly nothing',
      lede:
          'Empty and loading keep the thickness and diameter of a chart with '
          'data in it, so nothing on the screen jumps when the data lands. A '
          'segment shorter than one ring-thickness of arc is two overlapping '
          'caps and reads as a blob; there is no answer that is right for '
          'every chart, only two defensible ones, so the chart makes you pick.',
      child: Wrap(
        spacing: 16,
        runSpacing: 16,
        children: <Widget>[
          DemoCard(
            key: const ValueKey<String>('state-card-empty'),
            title: 'No data yet',
            note: 'A flat neutral annulus with no joints.',
            source: 'const WovenRingChart.empty()',
            chart: const WovenRingChart.empty(semanticLabel: 'Empty ring'),
          ),
          DemoCard(
            key: const ValueKey<String>('state-card-loading'),
            title: 'Loading',
            note: 'One neutral segment chasing itself round the track.',
            source: 'const WovenRingChart.loading()',
            chart: const WovenRingChart.loading(
              semanticLabel: 'Loading',
              semanticValue: 'Waiting for data',
            ),
          ),
          DemoCard(
            key: const ValueKey<String>('state-card-single-smooth'),
            title: 'One value, smooth',
            note: 'The default: a single value has no boundary to show.',
            source:
                'WovenSegment.solid(\n'
                '  100, WovenPalette.purple)',
            chart: WovenRingChart(
              segments: <WovenSegment>[
                WovenSegment.solid(100, WovenPalette.purple),
              ],
              animation: WovenRingAnimation.none,
              semanticLabel: 'A single value, smooth',
            ),
          ),
          DemoCard(
            key: const ValueKey<String>('state-card-single-jointed'),
            title: 'One value, jointed',
            note: 'Keeps one hairline self-joint on the head cap.',
            source:
                'singleSegmentStyle:\n'
                '  WovenSingleSegmentStyle.jointed',
            chart: WovenRingChart(
              segments: <WovenSegment>[
                WovenSegment.solid(100, WovenPalette.purple),
              ],
              style: const WovenRingStyle(
                singleSegmentStyle: WovenSingleSegmentStyle.jointed,
              ),
              animation: WovenRingAnimation.none,
              semanticLabel: 'A single value, jointed',
            ),
          ),
          DemoCard(
            key: const ValueKey<String>('state-card-enforce'),
            title: 'Tiny value, enforced',
            note:
                'The default. Raises it to the minimum and rescales the rest, '
                'so do not use it where the arc lengths are the message.',
            source:
                'smallValuePolicy:\n'
                '  WovenSmallValuePolicy.enforce',
            chart: _tinyRing(
              WovenSmallValuePolicy.enforce,
              'A tiny value raised to the minimum',
            ),
          ),
          DemoCard(
            key: const ValueKey<String>('state-card-vanish'),
            title: 'Tiny value, allowed to vanish',
            note:
                'Keeps the proportions honest and drops anything under half '
                'the minimum.',
            source:
                'smallValuePolicy:\n'
                '  WovenSmallValuePolicy.allowVanish',
            chart: _tinyRing(
              WovenSmallValuePolicy.allowVanish,
              'A tiny value allowed to vanish',
            ),
          ),
        ],
      ),
    );
  }

  Widget _tinyRing(WovenSmallValuePolicy policy, String label) {
    return WovenRingChart(
      segments: <WovenSegment>[
        for (int i = 0; i < _tiny.length; i++)
          WovenSegment.solid(_tiny[i], WovenPalette.quartet[i]),
      ],
      style: WovenRingStyle(smallValuePolicy: policy),
      animation: WovenRingAnimation.none,
      semanticLabel: label,
    );
  }
}
