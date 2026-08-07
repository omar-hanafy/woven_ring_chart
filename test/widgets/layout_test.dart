// Layout under every constraint, and the empty and loading renderings.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woven_ring_chart/woven_ring_chart.dart';

import '../support/chart_harness.dart';

void main() {
  group('layout and fallback state', () {
    testWidgets('normal empty data takes the neutral fallback path safely', (
      WidgetTester tester,
    ) async {
      const ValueKey<String> normalKey = ValueKey<String>('normal-empty');
      const ValueKey<String> explicitKey = ValueKey<String>('explicit-empty');

      await tester.pumpWidget(
        host(
          const Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SizedBox.square(
                dimension: 140,
                child: WovenRingChart(
                  key: normalKey,
                  segments: <WovenSegment>[],
                  animation: WovenRingAnimation.sweep,
                ),
              ),
              SizedBox(width: 20),
              SizedBox.square(
                dimension: 140,
                child: WovenRingChart.empty(key: explicitKey),
              ),
            ],
          ),
        ),
      );

      expect(paintedSegments(tester, find.byKey(normalKey)), isEmpty);
      expect(animationProgress(tester, find.byKey(normalKey)), 1.0);
      expect(paintedSegments(tester, find.byKey(explicitKey)), isEmpty);
      expect(animationProgress(tester, find.byKey(explicitKey)), 1.0);
      expect(
        tester.getSize(customPaintFinder(find.byKey(normalKey))),
        tester.getSize(customPaintFinder(find.byKey(explicitKey))),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('uses the smallest bound and a safe unbounded default', (
      WidgetTester tester,
    ) async {
      const ValueKey<String> boxKey = ValueKey<String>('bounded-box');

      await tester.pumpWidget(
        host(
          const SizedBox(
            key: boxKey,
            width: 320,
            height: 180,
            child: WovenRingChart(
              key: kRingKey,
              segments: kInitialSegments,
              animation: WovenRingAnimation.none,
            ),
          ),
        ),
      );

      final Finder boundedPaint = customPaintFinder(find.byKey(kRingKey));
      expect(tester.getSize(boundedPaint), const Size.square(180));
      expect(
        tester.getCenter(boundedPaint),
        tester.getCenter(find.byKey(boxKey)),
      );

      await tester.pumpWidget(
        host(
          const UnconstrainedBox(
            child: WovenRingChart(
              key: kRingKey,
              segments: kInitialSegments,
              animation: WovenRingAnimation.none,
            ),
          ),
        ),
      );

      expect(
        tester.getSize(customPaintFinder(find.byKey(kRingKey))),
        const Size.square(240),
      );

      await tester.pumpWidget(
        host(
          const UnconstrainedBox(
            child: SizedBox(
              height: 150,
              child: WovenRingChart(
                key: kRingKey,
                segments: kInitialSegments,
                animation: WovenRingAnimation.none,
              ),
            ),
          ),
        ),
      );

      expect(
        tester.getSize(customPaintFinder(find.byKey(kRingKey))),
        const Size.square(150),
      );
      expect(tester.takeException(), isNull);
    });
  });
}
