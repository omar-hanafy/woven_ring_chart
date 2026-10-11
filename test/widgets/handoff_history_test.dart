import 'dart:ui' show ColorSpace;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woven_ring_chart/woven_ring_chart.dart';

import '../support/chart_harness.dart';

void main() {
  testWidgets(
    'sustained sole-index retargets do not retain recursive history',
    (WidgetTester tester) async {
      final _CountingColor highlightColor = _CountingColor();
      Widget chart(int active) => Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox.square(
            dimension: 24,
            child: WovenRingChart(
              animation: WovenRingAnimation.none,
              transitionDuration: const Duration(milliseconds: 480),
              highlightedIndex: 1,
              highlightBorder: WovenBorder(color: highlightColor),
              segments: <WovenSegment>[
                WovenSegment(
                  value: active == 0 ? 100 : 0,
                  fill: const WovenFill.gradient(
                    head: Color(0xFFFF0000),
                    tail: Color(0xFF0000FF),
                  ),
                ),
                WovenSegment(
                  value: active == 1 ? 100 : 0,
                  fill: const WovenFill.gradient(
                    head: Color(0xFF00FF00),
                    tail: Color(0xFF000000),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      await tester.pumpWidget(chart(0));
      // Ten minutes of 10 Hz data: every update interrupts the 480 ms handoff.
      // Rendering must not accumulate one recursive border node per update.
      for (var update = 0; update < 6000; update++) {
        await tester.pumpWidget(chart((update + 1) % 2));
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.takeException(), isNull, reason: 'retarget=$update');
      }
      highlightColor.reads = 0;
      await tester.pump(const Duration(milliseconds: 1));
      expect(
        highlightColor.reads,
        lessThan(64),
        reason: 'one frame must not re-resolve all 6000 prior highlights',
      );
      await tester.pump(const Duration(milliseconds: 480));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'sole retarget snapshots preserve color space and live highlight',
    (WidgetTester tester) async {
      const List<WovenSegment> segments = <WovenSegment>[
        WovenSegment(
          value: 100,
          fill: WovenFill.gradient(
            head: Color(0xFFFF0000),
            tail: Color(0xFF0000FF),
          ),
          border: WovenBorder.darkerFill(),
        ),
        WovenSegment(
          value: 100,
          fill: WovenFill.gradient(
            head: Color.from(
              alpha: 0.6,
              red: 0.8,
              green: 0.4,
              blue: 0.1,
              colorSpace: ColorSpace.displayP3,
            ),
            tail: Color.from(
              alpha: 0.8,
              red: 0.1,
              green: 0.8,
              blue: 0.7,
              colorSpace: ColorSpace.displayP3,
            ),
          ),
          border: WovenBorder(),
        ),
        WovenSegment(
          value: 100,
          fill: WovenFill.solid(Color(0xFFFFD060)),
          border: WovenBorder(color: Color(0x80010203), opacity: 0.6),
          opacity: 0.7,
        ),
      ];
      const WovenRingStyle style = WovenRingStyle(
        surfaceColor: Color.from(
          alpha: 0.5,
          red: 0.1,
          green: 0.2,
          blue: 0.3,
          colorSpace: ColorSpace.displayP3,
        ),
      );
      const WovenBorder nextHighlight = WovenBorder(
        color: Color.from(
          alpha: 0.7,
          red: 0,
          green: 1,
          blue: 0,
          colorSpace: ColorSpace.displayP3,
        ),
        widthFraction: 0.05,
        opacity: 0.3,
      );
      final Finder ring = find.byKey(kRingKey);
      for (final WovenBorder initialHighlight in <WovenBorder>[
        nextHighlight,
        const WovenBorder.darkerFill(opacity: 0.8),
        const WovenBorder(opacity: 0.5),
      ]) {
        await tester.pumpWidget(const SizedBox.shrink());
        Widget chart(int active, int? highlighted, WovenBorder border) => host(
          SizedBox.square(
            dimension: 48,
            child: WovenRingChart(
              key: kRingKey,
              style: style,
              animation: WovenRingAnimation.none,
              transitionDuration: const Duration(milliseconds: 480),
              highlightedIndex: highlighted,
              highlightBorder: border,
              segments: <WovenSegment>[
                for (var i = 0; i < segments.length; i++)
                  segments[i].copyWith(value: i == active ? 100 : 0),
              ],
            ),
          ),
        );

        WovenSegment visible() {
          final List<WovenSegment> painted = paintedSegments(tester, ring);
          final List<double> fractions = paintedFractions(tester, ring);
          return painted[fractions.indexWhere((double share) => share > 0)];
        }

        await tester.pumpWidget(chart(0, 1, initialHighlight));
        await tester.pumpWidget(chart(1, 1, initialHighlight));
        await tester.pump(const Duration(milliseconds: 192));
        WovenSegment normal = WovenSegment.lerp(
          segments[0],
          segments[1],
          Curves.easeInOut.transform(0.4),
          surfaceColor: style.surfaceColor,
        );
        expect(visible().fill.head.colorSpace, ColorSpace.displayP3);
        expect(visible().fill.tail.colorSpace, ColorSpace.displayP3);
        for (final int destination in <int>[2, 0, 1, 2]) {
          final WovenSegment before = visible();
          await tester.pumpWidget(chart(destination, 1, initialHighlight));
          expect(
            visible(),
            before,
            reason: 'retarget must preserve all channels',
          );
          await tester.pump(const Duration(milliseconds: 100));
          normal = WovenSegment.lerp(
            normal,
            segments[destination],
            Curves.easeInOut.transform(100 / 480),
            surfaceColor: style.surfaceColor,
          );
        }

        final WovenSegment beforeChange = visible();
        final List<double> fractions = paintedFractions(tester, ring);
        await tester.pumpWidget(chart(2, null, initialHighlight));
        expect(visible().fill, beforeChange.fill);
        expect(visible().opacity, beforeChange.opacity);
        expect(paintedFractions(tester, ring), fractions);
        expect(
          visible().border,
          normal.border,
          reason: 'clearing is immediate',
        );
        await tester.pumpWidget(chart(2, 1, nextHighlight));
        expect(visible().fill, beforeChange.fill);
        expect(visible().opacity, beforeChange.opacity);
        expect(paintedFractions(tester, ring), fractions);
        expect(visible().border, isNot(normal.border));
        expect(visible().border!.color!.colorSpace, ColorSpace.displayP3);
        await tester.pumpWidget(chart(2, 999, nextHighlight));
        expect(visible().border, normal.border);
        await tester.pump(const Duration(milliseconds: 480));
        expect(visible(), segments[2]);
      }
    },
  );
}

class _CountingColor extends Color {
  _CountingColor() : super(0xFFFFD060);

  int reads = 0;

  @override
  double get a {
    reads++;
    return super.a;
  }

  @override
  double get r {
    reads++;
    return super.r;
  }

  @override
  double get g {
    reads++;
    return super.g;
  }

  @override
  double get b {
    reads++;
    return super.b;
  }
}
