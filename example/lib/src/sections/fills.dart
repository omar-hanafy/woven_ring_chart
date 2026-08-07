import 'package:flutter/material.dart';

import 'package:woven_ring_chart/woven_ring_chart.dart';

import '../ui/section.dart';

/// What a segment can be filled and edged with.
///
/// Every card is the real widget on the same four values, and the line under
/// it is the only part of the configuration that differs from the card before
/// it. `colors` in those lines is `WovenPalette.quartet`.
class FillsSection extends StatelessWidget {
  const FillsSection({super.key});

  static const List<double> _values = <double>[34, 26, 22, 18];
  static const List<Color> _colors = WovenPalette.quartet;

  @override
  Widget build(BuildContext context) {
    return Section(
      title: 'Fills and borders',
      lede:
          'A fill is solid or a gradient between two colours. Borders sit '
          'inside the segment, stroked at double width and clipped to the '
          'silhouette, so a bordered segment is never fatter than an '
          'unbordered one and the outer edge of the ring stays a circle. '
          'Leave a border colour out and it resolves to the surface colour, '
          'which reads as the segments being cut out of each other rather '
          'than merely stacked. Every card below draws the same four values, '
          'and the line under it is the only thing that changed. Where those '
          'lines say colors, they mean WovenPalette.quartet.',
      child: Wrap(
        spacing: 16,
        runSpacing: 16,
        children: <Widget>[
          DemoCard(
            key: const ValueKey<String>('fill-card-solid'),
            title: 'Solid',
            note: 'One flat colour per segment.',
            source: 'WovenFill.solid(colors[i])',
            chart: _ring(
              fill: (int i) => WovenFill.solid(_colors[i]),
              label: 'Solid fill',
            ),
          ),
          DemoCard(
            key: const ValueKey<String>('fill-card-shaded'),
            title: 'Shaded',
            note: 'A deliberately quiet gradient built from one colour.',
            source: 'WovenFill.shaded(colors[i])',
            chart: _ring(
              fill: (int i) => WovenFill.shaded(_colors[i]),
              label: 'Shaded fill',
            ),
          ),
          DemoCard(
            key: const ValueKey<String>('fill-card-gradient'),
            title: 'Gradient',
            note: 'Two colours you pick, running head to tail.',
            source:
                'WovenFill.gradient(\n'
                '  head: colors[i],\n'
                '  tail: colors[i + 1],\n'
                ')',
            chart: _ring(
              fill: (int i) => WovenFill.gradient(
                head: _colors[i],
                tail: _colors[(i + 1) % _colors.length],
              ),
              label: 'Gradient fill',
            ),
          ),
          DemoCard(
            key: const ValueKey<String>('fill-card-across'),
            title: 'Across the thickness',
            note: 'The shaded card again, run radially. A tube, not an arc.',
            source:
                'gradientAxis:\n'
                '  WovenGradientAxis.acrossThickness',
            chart: _ring(
              fill: (int i) => WovenFill.shaded(_colors[i]),
              style: const WovenRingStyle(
                gradientAxis: WovenGradientAxis.acrossThickness,
              ),
              label: 'Across-thickness gradient',
            ),
          ),
          DemoCard(
            key: const ValueKey<String>('border-card-surface'),
            title: 'Surface border',
            note: 'The default hairline: cut out, not stacked.',
            source: 'border: const WovenBorder()',
            chart: _ring(
              fill: (int i) => WovenFill.solid(_colors[i]),
              border: const WovenBorder(),
              label: 'Surface-coloured border',
            ),
          ),
          DemoCard(
            key: const ValueKey<String>('border-card-darker'),
            title: 'Darker fill border',
            note: 'One border colour even on a gradient segment.',
            source:
                'border:\n'
                '  const WovenBorder.darkerFill()',
            chart: _ring(
              fill: (int i) => WovenFill.shaded(_colors[i]),
              border: const WovenBorder.darkerFill(),
              label: 'Darker-fill border',
            ),
          ),
        ],
      ),
    );
  }

  Widget _ring({
    required WovenFill Function(int index) fill,
    required String label,
    WovenBorder? border,
    WovenRingStyle style = const WovenRingStyle(),
  }) {
    return WovenRingChart(
      segments: <WovenSegment>[
        for (int i = 0; i < _values.length; i++)
          WovenSegment(value: _values[i], fill: fill(i), border: border),
      ],
      style: style,
      animation: WovenRingAnimation.none,
      semanticLabel: label,
    );
  }
}
