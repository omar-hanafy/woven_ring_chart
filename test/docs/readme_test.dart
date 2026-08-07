// Every code block in README.md, compiled, with the numbers it quotes checked.
//
// The README is part of what this package ships. A snippet that no longer
// compiles is a defect, so it fails here rather than in a reader's editor.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woven_ring_chart/woven_ring_chart.dart';

void main() {
  testWidgets('quick start', (WidgetTester tester) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: WovenRingChart(
          segments: <WovenSegment>[
            WovenSegment.solid(37, WovenPalette.purple),
            WovenSegment.solid(19, WovenPalette.green),
            WovenSegment.solid(29, WovenPalette.amber),
            WovenSegment.solid(15, WovenPalette.rose),
          ],
          center: const Text('100'),
          semanticLabel: 'Spending by category',
        ),
      ),
    );
  });

  test('shape', () {
    const WovenRingStyle s = WovenRingStyle(
      thicknessFraction: 0.20,
      overlapFraction: 0.5,
      startAngle: -math.pi / 2,
      clockwise: true,
    );
    expect(s.resolvedThicknessFraction, 0.20);
  });

  test('fills, borders, gradients, shadow, highlight', () {
    final WovenSegment seg = WovenSegment(
      value: 40,
      fill: WovenFill.shaded(WovenPalette.blue, step: 0.04),
      border: const WovenBorder(),
    );
    expect(seg.fill.isSolid, isFalse);
    const WovenRingStyle a = WovenRingStyle(
      gradientAxis: WovenGradientAxis.alongSegment,
      gradientDirection: WovenGradientDirection.headToTail,
    );
    const WovenRingStyle b = WovenRingStyle(
      gradientAxis: WovenGradientAxis.acrossThickness,
    );
    const WovenRingStyle c = WovenRingStyle(shadow: WovenShadow());
    expect(<Object>[a, b, c], hasLength(3));
    const WovenBorder darker = WovenBorder.darkerFill();
    expect(darker.color, isNull);
  });

  test('states and policies', () {
    const WovenRingChart.empty();
    const WovenRingChart.loading();
    const WovenRingStyle jointed = WovenRingStyle(
      singleSegmentStyle: WovenSingleSegmentStyle.jointed,
    );
    expect(jointed.singleSegmentStyle, WovenSingleSegmentStyle.jointed);
    expect(WovenSmallValuePolicy.values, hasLength(2));
    expect(WovenSmallValuePolicy.enforce, isNotNull);
    expect(WovenSmallValuePolicy.allowVanish, isNotNull);
  });

  test('animation and controller', () {
    final WovenRingChartController controller = WovenRingChartController();
    final WovenRingChart chart = WovenRingChart(
      segments: const <WovenSegment>[],
      animation: WovenRingAnimation.sweep,
      animationDuration: const Duration(milliseconds: 1000),
      transitionDuration: const Duration(milliseconds: 450),
      controller: controller,
    );
    expect(chart.animation, WovenRingAnimation.sweep);
    controller.replay();
    controller.dispose();
  });

  test('highlight', () {
    const WovenRingChart chart = WovenRingChart(
      segments: <WovenSegment>[],
      highlightedIndex: 1,
      highlightBorder: WovenBorder(),
    );
    expect(chart.highlightedIndex, 1);
  });

  test('accessibility snippet', () {
    const WovenRingChart chart = WovenRingChart(
      segments: <WovenSegment>[
        WovenSegment(
          value: 37,
          fill: WovenFill.solid(WovenPalette.purple),
          semanticLabel: 'Housing, 37 percent',
        ),
      ],
    );
    expect(chart.segments.single.semanticLabel, 'Housing, 37 percent');
  });

  test('const segment list', () {
    const List<WovenSegment> constSegments = <WovenSegment>[
      WovenSegment(value: 37, fill: WovenFill.solid(WovenPalette.purple)),
      WovenSegment(value: 19, fill: WovenFill.solid(WovenPalette.green)),
    ];
    expect(constSegments, hasLength(2));
  });

  test('palette', () {
    expect(WovenPalette.quartet, hasLength(4));
    expect(WovenPalette.extended, hasLength(10));
    expect(WovenPalette.cycle(WovenPalette.quartet, 7), hasLength(7));
  });

  test('geometry snippet numbers are exact', () {
    const WovenRingStyle style = WovenRingStyle();
    final WovenRingGeometry g = WovenRingGeometry.forSize(
      const Size(240, 240),
      style,
    );
    expect(g.thickness, 48.0);
    expect(g.capRadius, 24.0);
    expect(g.holeDiameter, 144.0);
    expect(g.minimumFraction, greaterThan(0.0));

    final List<double> fractions = wovenSegmentFractions(
      <double>[37, 19, 29, 15],
      minimumFraction: g.minimumFraction,
      policy: style.smallValuePolicy,
    );
    final List<WovenSegmentExtent> extents = g.extents(
      fractions,
      style.resolvedStartAngle,
      clockwise: style.clockwise,
    );
    expect(extents, hasLength(4));
    expect(
      extents.first.headApex(g.capAngle, clockwise: style.clockwise),
      isA<double>(),
    );
  });
}
