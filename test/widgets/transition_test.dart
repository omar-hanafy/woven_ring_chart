// Data changes: segments stretch and shrink in place, and the chart never blinks.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woven_ring_chart/woven_ring_chart.dart';

import '../support/chart_harness.dart';

void main() {
  group('data transitions', () {
    testWidgets('stretches and crossfades replacement data in place', (
      WidgetTester tester,
    ) async {
      final GlobalKey<MutableRingHarnessState> harnessKey =
          GlobalKey<MutableRingHarnessState>();
      const List<WovenSegment> replacement = <WovenSegment>[
        WovenSegment(value: 3, fill: WovenFill.solid(WovenPalette.blue)),
        WovenSegment(value: 1, fill: WovenFill.solid(WovenPalette.amber)),
      ];

      await tester.pumpWidget(
        host(
          MutableRingHarness(
            key: harnessKey,
            initialSegments: kInitialSegments,
          ),
        ),
      );

      harnessKey.currentState!.replace(replacement);
      await tester.pump();
      List<WovenSegment> painted = paintedSegments(
        tester,
        find.byKey(kRingKey),
      );
      expect(painted[0].value, 1.0);
      expect(painted[0].fill, kInitialSegments[0].fill);

      await tester.pump(const Duration(milliseconds: 500));
      painted = paintedSegments(tester, find.byKey(kRingKey));
      expect(painted[0].value, closeTo(2.0, 0.001));
      expect(painted[0].fill.head, isNot(kInitialSegments[0].fill.head));
      expect(painted[0].fill.head, isNot(replacement[0].fill.head));

      await tester.pump(const Duration(milliseconds: 500));
      painted = paintedSegments(tester, find.byKey(kRingKey));
      expect(painted, replacement);
    });

    testWidgets(
      'CW, CCW, and ring style switches preserve an active data frame',
      (WidgetTester tester) async {
        final GlobalKey<MutableRingHarnessState> harnessKey =
            GlobalKey<MutableRingHarnessState>();
        const WovenRingStyle initialStyle = WovenRingStyle(
          clockwise: true,
          gradientAxis: WovenGradientAxis.alongSegment,
          gradientDirection: WovenGradientDirection.headToTail,
        );
        const List<WovenSegment> styled = <WovenSegment>[
          WovenSegment(
            value: 3,
            fill: WovenFill.gradient(
              head: WovenPalette.blue,
              tail: WovenPalette.purple,
            ),
            border: WovenBorder(),
          ),
          WovenSegment(
            value: 1,
            fill: WovenFill.gradient(
              head: WovenPalette.amber,
              tail: WovenPalette.rose,
            ),
            border: WovenBorder.darkerFill(),
          ),
        ];

        await tester.pumpWidget(
          host(
            MutableRingHarness(
              key: harnessKey,
              initialSegments: kInitialSegments,
              initialStyle: initialStyle,
            ),
          ),
        );
        final Finder ring = find.byKey(kRingKey);

        harnessKey.currentState!.replace(styled);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        final List<WovenSegment> beforeCcw = paintedSegments(tester, ring);
        final List<double> fractionsBeforeCcw = paintedFractions(tester, ring);
        expect(
          beforeCcw.any((WovenSegment segment) => segment.border != null),
          isTrue,
        );
        expect(beforeCcw, isNot(styled));

        harnessKey.currentState!.restyle(
          initialStyle.copyWith(
            clockwise: false,
            overlapFraction: 0.90,
            startAngle: math.pi / 8,
            gradientAxis: WovenGradientAxis.acrossThickness,
            gradientDirection: WovenGradientDirection.tailToHead,
            shadow: const WovenShadow(),
          ),
        );
        await tester.pump();
        expectSegmentContinuity(beforeCcw, paintedSegments(tester, ring));
        expectFractionContinuity(
          fractionsBeforeCcw,
          paintedFractions(tester, ring),
        );
        WovenRingStyle observedStyle = paintedStyle(tester, ring);
        expect(observedStyle.clockwise, isFalse);
        expect(observedStyle.gradientAxis, WovenGradientAxis.acrossThickness);
        expect(
          observedStyle.gradientDirection,
          WovenGradientDirection.tailToHead,
        );
        expect(observedStyle.resolvedOverlapFraction, 0.90);
        expect(observedStyle.resolvedStartAngle, closeTo(math.pi / 8, 1e-12));
        expect(observedStyle.shadow, isNotNull);

        await tester.pump(const Duration(milliseconds: 125));
        final List<WovenSegment> beforeCw = paintedSegments(tester, ring);
        final List<double> fractionsBeforeCw = paintedFractions(tester, ring);
        harnessKey.currentState!.restyle(
          initialStyle.copyWith(
            overlapFraction: 0.30,
            startAngle: -math.pi / 2,
          ),
        );
        await tester.pump();
        expectSegmentContinuity(beforeCw, paintedSegments(tester, ring));
        expectFractionContinuity(
          fractionsBeforeCw,
          paintedFractions(tester, ring),
        );
        observedStyle = paintedStyle(tester, ring);
        expect(observedStyle.clockwise, isTrue);
        expect(observedStyle.gradientAxis, WovenGradientAxis.alongSegment);
        expect(
          observedStyle.gradientDirection,
          WovenGradientDirection.headToTail,
        );
        expect(observedStyle.resolvedOverlapFraction, 0.30);
        expect(observedStyle.resolvedStartAngle, closeTo(-math.pi / 2, 1e-12));
        expect(observedStyle.shadow, isNull);

        await tester.pump(const Duration(milliseconds: 625));
        expect(paintedSegments(tester, ring), styled);
        expectPaintedFractions(paintedFractions(tester, ring), const <double>[
          0.75,
          0.25,
        ]);
        await tester.pumpAndSettle();
        expect(tester.binding.transientCallbackCount, 0);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'detects mutation when the caller reuses the same List object',
      (WidgetTester tester) async {
        final GlobalKey<MutableRingHarnessState> harnessKey =
            GlobalKey<MutableRingHarnessState>();
        const WovenSegment mutated = WovenSegment(
          value: 5,
          fill: WovenFill.solid(WovenPalette.rose),
          semanticLabel: 'Mutated, 5',
        );

        await tester.pumpWidget(
          host(
            MutableRingHarness(
              key: harnessKey,
              initialSegments: kInitialSegments,
            ),
          ),
        );
        final List<WovenSegment> originalListObject =
            harnessKey.currentState!.segments;

        harnessKey.currentState!.mutateFirstInPlace(mutated);
        await tester.pump();
        expect(
          identical(harnessKey.currentState!.segments, originalListObject),
          isTrue,
        );
        expect(
          paintedSegments(tester, find.byKey(kRingKey))[0].value,
          kInitialSegments[0].value,
        );

        await tester.pump(const Duration(milliseconds: 500));
        expect(
          paintedSegments(tester, find.byKey(kRingKey))[0].value,
          closeTo(3.0, 0.001),
        );

        await tester.pump(const Duration(milliseconds: 500));
        final WovenSegment painted = paintedSegments(
          tester,
          find.byKey(kRingKey),
        ).first;
        expect(painted.value, mutated.value);
        expect(painted.fill, mutated.fill);
        expect(painted.semanticLabel, mutated.semanticLabel);
      },
    );

    testWidgets(
      'animates entering and leaving fractions without opacity popping',
      (WidgetTester tester) async {
        final GlobalKey<MutableRingHarnessState> harnessKey =
            GlobalKey<MutableRingHarnessState>();
        const List<WovenSegment> one = <WovenSegment>[
          WovenSegment(value: 1, fill: WovenFill.solid(WovenPalette.purple)),
        ];
        const List<WovenSegment> three = <WovenSegment>[
          WovenSegment(value: 1, fill: WovenFill.solid(WovenPalette.purple)),
          WovenSegment(value: 1, fill: WovenFill.solid(WovenPalette.green)),
          WovenSegment(value: 1, fill: WovenFill.solid(WovenPalette.amber)),
        ];

        await tester.pumpWidget(
          host(MutableRingHarness(key: harnessKey, initialSegments: one)),
        );
        final Finder ring = find.byKey(kRingKey);

        expect(paintedSegments(tester, ring), one);
        expectPaintedFractions(paintedFractions(tester, ring), const <double>[
          1.0,
        ]);

        harnessKey.currentState!.replace(three);
        await tester.pump();
        expect(
          paintedSegments(tester, ring),
          one,
          reason: 't0 is the exact source endpoint, without padded entries',
        );
        expectPaintedFractions(paintedFractions(tester, ring), const <double>[
          1.0,
        ]);

        await tester.pump(const Duration(milliseconds: 500));
        List<WovenSegment> painted = paintedSegments(tester, ring);
        List<double> fractions = paintedFractions(tester, ring);
        expect(painted, hasLength(3));
        expect(
          painted.every((WovenSegment segment) => segment.opacity == 1.0),
          isTrue,
        );
        expect(fractions, hasLength(3));
        expect(fractions[0], inExclusiveRange(1 / 3, 1.0));
        expect(fractions[1], inExclusiveRange(0.0, 1 / 3));
        expect(fractions[2], inExclusiveRange(0.0, 1 / 3));
        expect(
          fractions.reduce((double a, double b) => a + b),
          closeTo(1, 1e-9),
        );

        await tester.pump(const Duration(milliseconds: 500));
        expect(paintedSegments(tester, ring), three);
        expectPaintedFractions(paintedFractions(tester, ring), const <double>[
          1 / 3,
          1 / 3,
          1 / 3,
        ]);

        harnessKey.currentState!.replace(one);
        await tester.pump();
        expect(
          paintedSegments(tester, ring),
          three,
          reason: 't0 is the exact source endpoint, without padded entries',
        );
        expectPaintedFractions(paintedFractions(tester, ring), const <double>[
          1 / 3,
          1 / 3,
          1 / 3,
        ]);

        await tester.pump(const Duration(milliseconds: 500));
        painted = paintedSegments(tester, ring);
        fractions = paintedFractions(tester, ring);
        expect(painted, hasLength(3));
        expect(
          painted.every((WovenSegment segment) => segment.opacity == 1.0),
          isTrue,
        );
        expect(fractions[0], inExclusiveRange(1 / 3, 1.0));
        expect(fractions[1], inExclusiveRange(0.0, 1 / 3));
        expect(fractions[2], inExclusiveRange(0.0, 1 / 3));
        expect(
          fractions.reduce((double a, double b) => a + b),
          closeTo(1, 1e-9),
        );

        await tester.pump(const Duration(milliseconds: 500));
        expect(
          paintedSegments(tester, ring),
          one,
          reason: 'completion drops transition-only padded entries',
        );
        expectPaintedFractions(paintedFractions(tester, ring), const <double>[
          1.0,
        ]);
      },
    );
  });
}
