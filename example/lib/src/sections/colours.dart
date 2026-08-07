import 'package:flutter/material.dart';

import 'package:woven_ring_chart/woven_ring_chart.dart';

import '../showcase_theme.dart';
import '../ui/section.dart';

/// The reference palette, and what `cycle` is for.
class ColoursSection extends StatelessWidget {
  const ColoursSection({super.key});

  static const String _source = '''
WovenPalette.quartet    // four colours
WovenPalette.extended   // ten, with one dark anchor among the brights

// Repeats a palette up to a count without letting a colour touch itself,
// including where the ring closes:
WovenPalette.cycle(WovenPalette.quartet, 7)''';

  @override
  Widget build(BuildContext context) {
    return Section(
      title: 'Colours',
      lede:
          'WovenPalette is a reference set of mid-saturation colours that stay '
          'distinct where two of them meet on a cap. The chart never reaches '
          'for them on its own: a ring paints exactly the colours its segments '
          'carry.',
      child: DemoBlock(
        demoFlex: 4,
        codeFlex: 5,
        alignment: CrossAxisAlignment.start,
        source: _source,
        demo: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const _Swatches(name: 'quartet', colors: WovenPalette.quartet),
            const SizedBox(height: 18),
            const _Swatches(name: 'extended', colors: WovenPalette.extended),
            const SizedBox(height: 18),
            _Swatches(
              name: 'cycle(quartet, 7)',
              colors: WovenPalette.cycle(WovenPalette.quartet, 7),
            ),
            const SizedBox(height: 22),
            ChartStage(
              size: 170,
              padding: 20,
              child: WovenRingChart(
                key: const ValueKey<String>('cycle-ring'),
                segments: <WovenSegment>[
                  for (final Color color in WovenPalette.cycle(
                    WovenPalette.quartet,
                    7,
                  ))
                    WovenSegment.solid(1, color),
                ],
                animation: WovenRingAnimation.none,
                semanticLabel: 'Seven segments cycled from a palette of four',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Swatches extends StatelessWidget {
  const _Swatches({required this.name, required this.colors});

  final String name;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(name, style: ShowcaseText.cardTitle),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: <Widget>[
            for (final Color color in colors)
              DecoratedBox(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const SizedBox(width: 34, height: 34),
              ),
          ],
        ),
      ],
    );
  }
}
