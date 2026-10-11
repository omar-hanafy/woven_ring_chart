// Reduced motion, ticker lifecycle, and disposal.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woven_ring_chart/woven_ring_chart.dart';

import '../support/chart_harness.dart';

void main() {
  group('motion preferences and ticker lifecycle', () {
    for (final WovenRingAnimation animation in <WovenRingAnimation>[
      WovenRingAnimation.sweep,
      WovenRingAnimation.grow,
    ]) {
      for (final bool clearList in <bool>[true, false]) {
        testWidgets('${animation.name} ends its ticker after fading to '
            '${clearList ? 'an empty list' : 'all-zero data'}', (
          WidgetTester tester,
        ) async {
          Future<void> pumpData(List<WovenSegment> segments) =>
              tester.pumpWidget(
                host(
                  SizedBox.square(
                    dimension: 180,
                    child: WovenRingChart(
                      key: kRingKey,
                      segments: segments,
                      animation: animation,
                      animationDuration: const Duration(seconds: 10),
                    ),
                  ),
                ),
              );

          final List<WovenSegment> empty = clearList
              ? const <WovenSegment>[]
              : <WovenSegment>[
                  for (final WovenSegment segment in kInitialSegments)
                    segment.copyWith(value: 0),
                ];
          final Finder ring = find.byKey(kRingKey);
          await pumpData(kInitialSegments);
          await tester.pump(const Duration(milliseconds: 100));
          final double beforeClear = animationProgress(tester, ring);
          final List<double> fractionsBeforeClear = paintedFractions(
            tester,
            ring,
          );

          await pumpData(empty);
          expect(animationProgress(tester, ring), beforeClear);
          expectFractionContinuity(
            fractionsBeforeClear,
            paintedFractions(tester, ring),
          );
          await tester.pump(const Duration(milliseconds: 225));
          expect(
            paintedFractions(tester, ring).fold<double>(
              0,
              (double total, double fraction) => total + fraction,
            ),
            closeTo(0.5, 0.001),
            reason: 'the data fade must finish on its own 450ms timeline',
          );
          expect(animationProgress(tester, ring), lessThan(1));

          await tester.pump(const Duration(milliseconds: 225));
          expect(paintedFractions(tester, ring), everyElement(0));
          expect(
            tester.binding.transientCallbackCount,
            0,
            reason: 'no drawing remains for the entrance ticker to advance',
          );
          expect(animationProgress(tester, ring), 1);

          await pumpData(kInitialSegments);
          expect(animationProgress(tester, ring), 0);
          expect(tester.binding.transientCallbackCount, greaterThan(0));
          await tester.pump(const Duration(milliseconds: 100));
          expect(animationProgress(tester, ring), inExclusiveRange(0, 1));
          await tester.pumpWidget(const SizedBox.shrink());
        });
      }

      testWidgets(
        '${animation.name} keeps its entrance when an empty fade is retargeted',
        (WidgetTester tester) async {
          Future<void> pumpData(List<WovenSegment> segments) =>
              tester.pumpWidget(
                host(
                  SizedBox.square(
                    dimension: 180,
                    child: WovenRingChart(
                      key: kRingKey,
                      segments: segments,
                      animation: animation,
                      animationDuration: const Duration(seconds: 10),
                    ),
                  ),
                ),
              );

          final Finder ring = find.byKey(kRingKey);
          await pumpData(kInitialSegments);
          await tester.pump(const Duration(milliseconds: 100));
          await pumpData(const <WovenSegment>[]);
          await tester.pump(const Duration(milliseconds: 225));
          final double beforeRetarget = animationProgress(tester, ring);
          final List<double> fractionsBeforeRetarget = paintedFractions(
            tester,
            ring,
          );

          await pumpData(kInitialSegments);
          expect(animationProgress(tester, ring), beforeRetarget);
          expectFractionContinuity(
            fractionsBeforeRetarget,
            paintedFractions(tester, ring),
          );
          await tester.pump(const Duration(milliseconds: 450));
          expect(paintedFractions(tester, ring), <double>[0.5, 0.5]);
          expect(animationProgress(tester, ring), greaterThan(beforeRetarget));
          expect(animationProgress(tester, ring), lessThan(1));
          expect(tester.binding.transientCallbackCount, greaterThan(0));
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }

    testWidgets('changes between empty and invalid data remain idle', (
      WidgetTester tester,
    ) async {
      final GlobalKey<MutableRingHarnessState> harnessKey =
          GlobalKey<MutableRingHarnessState>();
      await tester.pumpWidget(
        host(
          MutableRingHarness(
            key: harnessKey,
            initialSegments: const <WovenSegment>[],
            animation: WovenRingAnimation.sweep,
          ),
        ),
      );
      final Finder ring = find.byKey(kRingKey);
      expect(animationProgress(tester, ring), 1.0);
      expect(tester.binding.transientCallbackCount, 0);

      for (final List<WovenSegment> segments in <List<WovenSegment>>[
        const <WovenSegment>[
          WovenSegment(value: 0, fill: WovenFill.solid(WovenPalette.blue)),
          WovenSegment(
            value: double.nan,
            fill: WovenFill.solid(WovenPalette.rose),
          ),
        ],
        const <WovenSegment>[
          WovenSegment(value: -2, fill: WovenFill.solid(WovenPalette.amber)),
          WovenSegment(
            value: double.infinity,
            fill: WovenFill.solid(WovenPalette.green),
          ),
        ],
        const <WovenSegment>[],
      ]) {
        harnessKey.currentState!.replace(segments);
        await tester.pump();
        expect(paintedFractions(tester, ring), everyElement(0.0));
        expect(animationProgress(tester, ring), 1.0);
        expect(tester.binding.transientCallbackCount, 0);
      }

      harnessKey.currentState!.replace(kInitialSegments);
      await tester.pump();
      expect(animationProgress(tester, ring), 0.0);
      await tester.pumpAndSettle();
      expect(paintedSegments(tester, ring), kInitialSegments);
      expect(animationProgress(tester, ring), 1.0);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('invalid data waits finished until the first usable values', (
      WidgetTester tester,
    ) async {
      final WovenRingChartController controller = WovenRingChartController();
      final GlobalKey<MutableRingHarnessState> harnessKey =
          GlobalKey<MutableRingHarnessState>();
      await tester.pumpWidget(
        host(
          MutableRingHarness(
            key: harnessKey,
            initialSegments: const <WovenSegment>[
              WovenSegment(value: 0, fill: WovenFill.solid(WovenPalette.blue)),
              WovenSegment(
                value: -1,
                fill: WovenFill.solid(WovenPalette.green),
              ),
              WovenSegment(
                value: double.nan,
                fill: WovenFill.solid(WovenPalette.rose),
              ),
              WovenSegment(
                value: double.infinity,
                fill: WovenFill.solid(WovenPalette.amber),
              ),
            ],
            animation: WovenRingAnimation.sweep,
            controller: controller,
          ),
        ),
      );
      final Finder ring = find.byKey(kRingKey);
      expect(paintedFractions(tester, ring), everyElement(0.0));
      expect(animationProgress(tester, ring), 1.0);
      expect(tester.binding.transientCallbackCount, 0);

      controller.replay();
      await tester.pump();
      expect(animationProgress(tester, ring), 1.0);
      expect(tester.binding.transientCallbackCount, 0);

      harnessKey.currentState!.replace(kInitialSegments);
      await tester.pump();
      expect(animationProgress(tester, ring), 0.0);
      await tester.pump(const Duration(seconds: 1));
      expect(animationProgress(tester, ring), 1.0);
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    });

    testWidgets('changing to no entrance stops an active entrance ticker', (
      WidgetTester tester,
    ) async {
      Future<void> pumpAnimation(WovenRingAnimation animation) =>
          tester.pumpWidget(
            host(
              SizedBox.square(
                dimension: 180,
                child: WovenRingChart(
                  key: kRingKey,
                  segments: kInitialSegments,
                  animation: animation,
                ),
              ),
            ),
          );

      await pumpAnimation(WovenRingAnimation.sweep);
      await tester.pump(const Duration(milliseconds: 250));
      expect(
        animationProgress(tester, find.byKey(kRingKey)),
        inExclusiveRange(0, 1),
      );
      await pumpAnimation(WovenRingAnimation.none);
      expect(animationProgress(tester, find.byKey(kRingKey)), 1.0);
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    });

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
