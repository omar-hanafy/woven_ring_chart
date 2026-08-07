// Reduced motion, ticker lifecycle, and disposal.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woven_ring_chart/woven_ring_chart.dart';

import '../support/chart_harness.dart';

void main() {
  group('motion preferences and ticker lifecycle', () {
    testWidgets(
      'reduced motion completes animations, replays, and transitions',
      (WidgetTester tester) async {
        final WovenRingChartController controller = WovenRingChartController();
        final GlobalKey<MutableRingHarnessState> harnessKey =
            GlobalKey<MutableRingHarnessState>();
        const List<WovenSegment> replacement = <WovenSegment>[
          WovenSegment(value: 9, fill: WovenFill.solid(WovenPalette.navy)),
          WovenSegment(value: 1, fill: WovenFill.solid(WovenPalette.amber)),
        ];

        await tester.pumpWidget(
          host(
            MutableRingHarness(
              key: harnessKey,
              initialSegments: kInitialSegments,
              animation: WovenRingAnimation.sweep,
              controller: controller,
            ),
            disableAnimations: true,
          ),
        );
        expect(animationProgress(tester, find.byKey(kRingKey)), 1.0);

        controller.replay();
        await tester.pump();
        expect(animationProgress(tester, find.byKey(kRingKey)), 1.0);

        harnessKey.currentState!.replace(replacement);
        await tester.pump();
        expect(paintedSegments(tester, find.byKey(kRingKey)), replacement);

        await tester.pumpWidget(
          host(
            const SizedBox.square(
              dimension: 180,
              child: WovenRingChart.loading(key: kRingKey),
            ),
            disableAnimations: true,
          ),
        );
        final double spin = spinProgress(tester, find.byKey(kRingKey));
        await tester.pump(const Duration(seconds: 2));
        expect(spinProgress(tester, find.byKey(kRingKey)), spin);
        expect(tester.binding.transientCallbackCount, 0);

        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
      },
    );

    testWidgets(
      'enabling reduced motion mid-flight completes grow and data motion',
      (WidgetTester tester) async {
        final WovenRingChartController controller = WovenRingChartController();
        final GlobalKey<MutableRingHarnessState> harnessKey =
            GlobalKey<MutableRingHarnessState>();
        const List<WovenSegment> replacement = <WovenSegment>[
          WovenSegment(value: 9, fill: WovenFill.solid(WovenPalette.navy)),
          WovenSegment(value: 1, fill: WovenFill.solid(WovenPalette.amber)),
        ];

        await tester.pumpWidget(
          host(
            MutableRingHarness(
              key: harnessKey,
              initialSegments: kInitialSegments,
              animation: WovenRingAnimation.grow,
              controller: controller,
            ),
          ),
        );
        final Finder ring = find.byKey(kRingKey);

        await tester.pump(const Duration(milliseconds: 250));
        expect(animationProgress(tester, ring), inExclusiveRange(0.0, 1.0));

        harnessKey.currentState!.replace(replacement);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(animationProgress(tester, ring), inExclusiveRange(0.0, 1.0));
        expect(paintedSegments(tester, ring), isNot(replacement));

        await tester.pumpWidget(
          host(
            MutableRingHarness(
              key: harnessKey,
              initialSegments: kInitialSegments,
              animation: WovenRingAnimation.grow,
              controller: controller,
            ),
            disableAnimations: true,
          ),
        );
        expect(animationProgress(tester, ring), 1.0);
        expect(paintedSegments(tester, ring), replacement);

        controller.replay();
        await tester.pump();
        expect(animationProgress(tester, ring), 1.0);
        expect(tester.binding.transientCallbackCount, 0);
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
      },
    );

    testWidgets('loading ticker starts, stops across modes, and disposes', (
      WidgetTester tester,
    ) async {
      final GlobalKey<ModeHarnessState> harnessKey =
          GlobalKey<ModeHarnessState>();

      await tester.pumpWidget(host(ModeHarness(key: harnessKey)));
      final double start = spinProgress(tester, find.byKey(kRingKey));
      await tester.pump(const Duration(milliseconds: 350));
      final double moving = spinProgress(tester, find.byKey(kRingKey));
      expect(moving, isNot(start));
      expect(moving, closeTo(0.25, 0.02));

      harnessKey.currentState!.showData();
      await tester.pump();
      final double stopped = spinProgress(tester, find.byKey(kRingKey));
      await tester.pump(const Duration(milliseconds: 700));
      expect(spinProgress(tester, find.byKey(kRingKey)), stopped);

      harnessKey.currentState!.showLoading();
      await tester.pump();
      final double resumedAt = spinProgress(tester, find.byKey(kRingKey));
      await tester.pump(const Duration(milliseconds: 350));
      expect(spinProgress(tester, find.byKey(kRingKey)), isNot(resumedAt));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
      expect(tester.binding.transientCallbackCount, 0);
    });
  });
}
