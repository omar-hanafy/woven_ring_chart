// The entrance animation: both styles, replay, and retargeting mid-flight.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woven_ring_chart/woven_ring_chart.dart';

import '../support/chart_harness.dart';

void main() {
  group('animation', () {
    for (final WovenRingAnimation animation in <WovenRingAnimation>[
      WovenRingAnimation.sweep,
      WovenRingAnimation.grow,
    ]) {
      testWidgets(
        '$animation advances from an unfinished to a completed drawing',
        (WidgetTester tester) async {
          await tester.pumpWidget(
            host(
              SizedBox.square(
                dimension: 180,
                child: WovenRingChart(
                  key: kRingKey,
                  segments: kInitialSegments,
                  animation: animation,
                  animationDuration: const Duration(seconds: 1),
                ),
              ),
            ),
          );

          final dynamic startPainter = painterOf(tester, find.byKey(kRingKey));
          expect(paintedAnimation(tester, find.byKey(kRingKey)), animation);
          expect(animationProgress(tester, find.byKey(kRingKey)), 0.0);

          await tester.pump(const Duration(milliseconds: 500));
          final dynamic middlePainter = painterOf(tester, find.byKey(kRingKey));
          expect(
            animationProgress(tester, find.byKey(kRingKey)),
            inExclusiveRange(0.45, 0.60),
          );
          // ignore: avoid_dynamic_calls
          expect(middlePainter.shouldRepaint(startPainter), isTrue);

          await tester.pump(const Duration(milliseconds: 500));
          final dynamic endPainter = painterOf(tester, find.byKey(kRingKey));
          expect(animationProgress(tester, find.byKey(kRingKey)), 1.0);
          // ignore: avoid_dynamic_calls
          expect(endPainter.shouldRepaint(middlePainter), isTrue);
        },
      );
    }

    for (final WovenRingAnimation animation in <WovenRingAnimation>[
      WovenRingAnimation.sweep,
      WovenRingAnimation.grow,
    ]) {
      testWidgets(
        '$animation keeps its timeline through a mid-flight retarget',
        (WidgetTester tester) async {
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
                animation: animation,
              ),
            ),
          );
          final Finder ring = find.byKey(kRingKey);

          await tester.pump(const Duration(milliseconds: 250));
          final double animationBeforeData = animationProgress(tester, ring);
          expect(animationBeforeData, inExclusiveRange(0.0, 1.0));

          harnessKey.currentState!.replace(replacement);
          await tester.pump();
          expect(paintedSegments(tester, ring), kInitialSegments);
          expect(animationProgress(tester, ring), animationBeforeData);

          await tester.pump(const Duration(milliseconds: 200));
          final List<WovenSegment> beforeRetarget = paintedSegments(
            tester,
            ring,
          );
          final List<double> fractionsBeforeRetarget = paintedFractions(
            tester,
            ring,
          );
          final double animationBeforeRetarget = animationProgress(
            tester,
            ring,
          );
          expect(segmentValuesEqual(beforeRetarget, <double>[1, 1]), isFalse);
          expect(segmentValuesEqual(beforeRetarget, <double>[3, 1]), isFalse);
          expect(animationBeforeRetarget, greaterThan(animationBeforeData));
          expect(animationBeforeRetarget, lessThan(1.0));
          expectVisibleDataFrame(
            tester,
            ring,
            count: 2,
            expectAnimationComplete: false,
          );

          harnessKey.currentState!.replace(kInitialSegments);
          await tester.pump();
          expectSegmentContinuity(
            beforeRetarget,
            paintedSegments(tester, ring),
          );
          expectFractionContinuity(
            fractionsBeforeRetarget,
            paintedFractions(tester, ring),
          );
          expect(animationProgress(tester, ring), animationBeforeRetarget);
          expect(paintedAnimation(tester, ring), animation);
          expectVisibleDataFrame(
            tester,
            ring,
            count: 2,
            expectAnimationComplete: false,
          );

          await tester.pump(const Duration(seconds: 1));
          expect(animationProgress(tester, ring), 1.0);
          expect(paintedSegments(tester, ring), kInitialSegments);
          await tester.pumpAndSettle();
          expect(tester.binding.transientCallbackCount, 0);
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets(
      'cyclic owner masks stay identical across sweep frames 59 and 60',
      (WidgetTester tester) async {
        const List<WovenSegment> segments = <WovenSegment>[
          WovenSegment(value: 25, fill: WovenFill.solid(WovenPalette.purple)),
          WovenSegment(value: 25, fill: WovenFill.solid(WovenPalette.green)),
          WovenSegment(value: 25, fill: WovenFill.solid(WovenPalette.amber)),
          WovenSegment(value: 25, fill: WovenFill.solid(WovenPalette.rose)),
        ];

        await tester.pumpWidget(
          host(
            const SizedBox.square(
              dimension: 180,
              child: WovenRingChart(
                key: kRingKey,
                segments: segments,
                animation: WovenRingAnimation.sweep,
                animationDuration: Duration(seconds: 1),
              ),
            ),
          ),
        );

        await tester.pump(const Duration(milliseconds: 966));
        expect(
          animationProgress(tester, find.byKey(kRingKey)),
          inExclusiveRange(0.0, 1.0),
        );
        final List<String> frame59 = expectCyclicOwnerMaskCompositor(
          tester,
          find.byKey(kRingKey),
        );

        await tester.pump(const Duration(milliseconds: 34));
        expect(animationProgress(tester, find.byKey(kRingKey)), 1.0);
        final List<String> frame60 = expectCyclicOwnerMaskCompositor(
          tester,
          find.byKey(kRingKey),
        );
        expect(frame60, orderedEquals(frame59));
      },
    );

    testWidgets('controller replay restarts a completed sweep exactly once', (
      WidgetTester tester,
    ) async {
      final WovenRingChartController controller = WovenRingChartController();

      await tester.pumpWidget(
        host(
          SizedBox.square(
            dimension: 180,
            child: WovenRingChart(
              key: kRingKey,
              segments: kInitialSegments,
              animation: WovenRingAnimation.sweep,
              animationDuration: const Duration(seconds: 1),
              controller: controller,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(animationProgress(tester, find.byKey(kRingKey)), 1.0);

      controller.replay();
      await tester.pump();
      expect(animationProgress(tester, find.byKey(kRingKey)), 0.0);

      await tester.pump(const Duration(milliseconds: 250));
      expect(
        animationProgress(tester, find.byKey(kRingKey)),
        inExclusiveRange(0.0, 0.5),
      );
      await tester.pump(const Duration(milliseconds: 750));
      expect(animationProgress(tester, find.byKey(kRingKey)), 1.0);

      await tester.pumpWidget(const SizedBox.shrink());
      controller.replay();
      expect(tester.takeException(), isNull);
      controller.dispose();
    });

    testWidgets(
      'empty to data uses the configured animation instead of blinking',
      (WidgetTester tester) async {
        final GlobalKey<MutableRingHarnessState> harnessKey =
            GlobalKey<MutableRingHarnessState>();

        await tester.pumpWidget(
          host(
            MutableRingHarness(
              key: harnessKey,
              initialSegments: const <WovenSegment>[],
              animation: WovenRingAnimation.grow,
            ),
          ),
        );
        expect(animationProgress(tester, find.byKey(kRingKey)), 1.0);

        harnessKey.currentState!.replace(kInitialSegments);
        await tester.pump();
        expect(animationProgress(tester, find.byKey(kRingKey)), 0.0);
        expect(paintedSegments(tester, find.byKey(kRingKey)), kInitialSegments);

        await tester.pump(const Duration(milliseconds: 500));
        expect(
          animationProgress(tester, find.byKey(kRingKey)),
          inExclusiveRange(0.45, 0.60),
        );
        await tester.pump(const Duration(milliseconds: 500));
        expect(animationProgress(tester, find.byKey(kRingKey)), 1.0);
      },
    );
  });
}
