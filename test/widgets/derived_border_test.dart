import 'dart:ui' show ColorSpace;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woven_ring_chart/woven_ring_chart.dart';

import '../support/chart_harness.dart';

void main() {
  for (final path in <String, List<List<double>>>{
    'ordinary': [
      [1, 1],
      [3, 1],
      [1, 3],
    ],
    'sole': [
      [1, 0, 0],
      [0, 1, 0],
      [0, 0, 1],
    ],
    'collapse': [
      [1, 1, 0],
      [0, 0, 1],
      [1, 0, 0],
    ],
    'expand': [
      [1, 0, 0],
      [1, 1, 1],
      [1, 3, 2],
    ],
  }.entries) {
    testWidgets('${path.key}: retained borders follow the surface', (
      tester,
    ) async {
      Widget chart(List<double> values, Color surface) => host(
        SizedBox.square(
          dimension: 100,
          child: WovenRingChart(
            key: kRingKey,
            animation: WovenRingAnimation.none,
            transitionDuration: const Duration(seconds: 1),
            style: WovenRingStyle(surfaceColor: surface),
            segments: [
              for (final value in values)
                WovenSegment(
                  value: value,
                  fill: const WovenFill.solid(WovenPalette.blue),
                  border: const WovenBorder(),
                ),
            ],
          ),
        ),
      );
      const white = Color(0xffffffff);
      const black = Color(0xff000000);
      await tester.pumpWidget(chart(path.value[0], white));
      await tester.pumpWidget(chart(path.value[1], white));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpWidget(chart(path.value[2], white));
      await tester.pump(const Duration(milliseconds: 100));
      final ring = find.byKey(kRingKey);
      final fractions = paintedFractions(tester, ring);
      await tester.pumpWidget(chart(path.value[2], black));
      expect(paintedFractions(tester, ring), fractions);
      final segments = paintedSegments(tester, ring);
      for (var i = 0; i < segments.length; i++) {
        final segment = segments[i];
        if (fractions[i] > 0 && segment.border != null) {
          expect(
            segment.border!.resolve(segment.fill, black),
            black,
            reason: '${path.key} index $i retains a surface-derived border',
          );
        }
      }
    });
  }

  testWidgets('sole handoff keeps mixed highlight and surface contributions', (
    tester,
  ) async {
    const white = Color(0xffffffff);
    const black = Color(0xff000000);
    const red = Color(0xffff0000);
    Widget chart(int active, Color surface, {int? highlighted = 1}) => host(
      SizedBox.square(
        dimension: 100,
        child: WovenRingChart(
          key: kRingKey,
          animation: WovenRingAnimation.none,
          transitionDuration: const Duration(seconds: 1),
          style: WovenRingStyle(surfaceColor: surface),
          highlightedIndex: highlighted,
          highlightBorder: const WovenBorder(color: red),
          segments: [
            for (var i = 0; i < 3; i++)
              WovenSegment(
                value: active == i ? 1 : 0,
                fill: const WovenFill.solid(WovenPalette.blue),
                border: const WovenBorder(),
              ),
          ],
        ),
      ),
    );
    final ring = find.byKey(kRingKey);
    WovenSegment visible() {
      final fractions = paintedFractions(tester, ring);
      return paintedSegments(tester, ring)[fractions.indexWhere((f) => f > 0)];
    }

    await tester.pumpWidget(chart(0, white));
    await tester.pumpWidget(chart(1, white));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpWidget(chart(2, white));
    await tester.pump(const Duration(milliseconds: 100));
    final before = visible();
    final fractions = paintedFractions(tester, ring);
    await tester.pumpWidget(chart(2, black));
    expect(paintedFractions(tester, ring), fractions);
    expect(visible().fill, before.fill);
    expect(visible().border!.resolvedOpacity, before.border!.resolvedOpacity);
    final share =
        Curves.easeInOut.transform(0.4) * (1 - Curves.easeInOut.transform(0.1));
    _expectColorNear(
      visible().border!.resolve(visible().fill, black),
      Color.lerp(black, red, share)!,
    );
    await tester.pumpWidget(chart(2, black, highlighted: null));
    expect(visible().border!.resolve(visible().fill, black), black);
    await tester.pumpWidget(chart(2, black));
    _expectColorNear(
      visible().border!.resolve(visible().fill, black),
      Color.lerp(black, red, share)!,
    );
  });

  testWidgets(
    'interrupted derived borders adopt a new P3 surface immediately',
    (tester) async {
      const initialSurface = Color(0xffffffff);
      const nextSurface = Color.from(
        alpha: 0.6,
        red: 0.7,
        green: 0.2,
        blue: 0.5,
        colorSpace: ColorSpace.displayP3,
      );
      Widget chart(List<double> values, Color surface) => host(
        SizedBox.square(
          dimension: 100,
          child: WovenRingChart(
            key: kRingKey,
            animation: WovenRingAnimation.none,
            transitionDuration: const Duration(seconds: 1),
            style: WovenRingStyle(surfaceColor: surface),
            highlightedIndex: 0,
            highlightBorder: const WovenBorder(),
            segments: [
              for (final value in values)
                WovenSegment(
                  value: value,
                  fill: const WovenFill.solid(WovenPalette.blue),
                  border: const WovenBorder(),
                ),
            ],
          ),
        ),
      );
      await tester.pumpWidget(chart([1, 0, 0], initialSurface));
      await tester.pumpWidget(chart([0, 1, 0], initialSurface));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpWidget(chart([0, 0, 1], initialSurface));
      await tester.pump(const Duration(milliseconds: 100));
      final ring = find.byKey(kRingKey);
      final fractions = paintedFractions(tester, ring);
      await tester.pumpWidget(chart([0, 0, 1], nextSurface));
      expect(paintedFractions(tester, ring), fractions);
      final segments = paintedSegments(tester, ring);
      for (var i = 0; i < segments.length; i++) {
        if (fractions[i] > 0) {
          expect(
            segments[i].border!.resolve(segments[i].fill, nextSurface),
            nextSurface,
          );
        }
      }
    },
  );
}

void _expectColorNear(Color actual, Color expected) {
  expect(actual.colorSpace, expected.colorSpace);
  expect(actual.a, closeTo(expected.a, 1e-12));
  expect(actual.r, closeTo(expected.r, 1e-12));
  expect(actual.g, closeTo(expected.g, 1e-12));
  expect(actual.b, closeTo(expected.b, 1e-12));
}
