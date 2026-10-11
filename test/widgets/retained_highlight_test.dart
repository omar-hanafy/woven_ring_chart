import 'dart:ui' show ColorSpace;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woven_ring_chart/woven_ring_chart.dart';

import '../support/chart_harness.dart';

const _red = WovenBorder(
  color: Color(0xffff0000),
  widthFraction: .01,
  opacity: .4,
);
const _blue = WovenBorder(
  color: Color(0xff0000ff),
  widthFraction: .03,
  opacity: .7,
);
const _yellow = WovenBorder(
  color: Color(0xffffff00),
  widthFraction: .04,
  opacity: .8,
);
const _p3 = WovenBorder(
  color: Color.from(
    alpha: .7,
    red: .1,
    green: .9,
    blue: .4,
    colorSpace: ColorSpace.displayP3,
  ),
  widthFraction: .05,
  opacity: .3,
);
const _surface = WovenBorder(widthFraction: .02, opacity: .4);
const _dark = WovenBorder.darkerFill(widthFraction: .03, opacity: .6);
const _fills = <WovenFill>[
  WovenFill.solid(Color(0xffb04a71)),
  WovenFill.solid(Color(0xffce9947)),
  WovenFill.gradient(head: Color(0xff1565c0), tail: Color(0xff006644)),
];
const _surfaceColor = Color(0xffdae3e0);

void main() {
  testWidgets(
    'retained highlight replacement preserves endpoint contributions',
    (tester) async {
      final ring = find.byKey(kRingKey);
      for (final normal in <List<WovenBorder?>>[
        [_red, _blue, _yellow],
        [null, _blue, _yellow],
        [_red, null, _yellow],
        [null, null, _yellow],
        [_surface, _dark, _p3],
        [_p3, null, _dark],
      ]) {
        for (final highlight in <WovenBorder>[
          _yellow,
          _p3,
          _surface,
          _dark,
          WovenBorder.lerp(
            _surface,
            _p3,
            .3,
            fill: _fills[0],
            surfaceColor: _surfaceColor,
          )!,
          WovenBorder.lerp(
            _dark,
            _red,
            .3,
            fill: _fills[0],
            surfaceColor: _surfaceColor,
          )!,
          WovenBorder.lerp(
            _dark,
            _p3,
            .3,
            fill: _fills[0],
            surfaceColor: _surfaceColor,
          )!,
        ]) {
          for (final selected in <int>[0, 1, 2]) {
            for (final depth in <int>[1, 3]) {
              Widget chart(int active, int? highlighted) => host(
                SizedBox.square(
                  dimension: 40,
                  child: WovenRingChart(
                    key: kRingKey,
                    animation: WovenRingAnimation.none,
                    transitionDuration: const Duration(seconds: 1),
                    style: const WovenRingStyle(surfaceColor: _surfaceColor),
                    highlightedIndex: highlighted,
                    highlightBorder: highlight,
                    segments: [
                      for (var i = 0; i < 3; i++)
                        WovenSegment(
                          value: i == active ? 1 : 0,
                          fill: _fills[i],
                          border: normal[i],
                        ),
                    ],
                  ),
                ),
              );
              WovenSegment visible() {
                final fractions = paintedFractions(tester, ring);
                return paintedSegments(tester, ring)[fractions.indexWhere(
                  (f) => f > 0,
                )];
              }

              Future<void> prepare() async {
                await tester.pumpWidget(const SizedBox.shrink());
                await tester.pumpWidget(chart(0, null));
                for (var i = 1; i <= depth; i++) {
                  await tester.pumpWidget(chart(i % 3, null));
                  await tester.pump(Duration(milliseconds: 450 - i * 70));
                }
              }

              await prepare();
              await tester.pumpWidget(chart(depth % 3, selected));
              final expected = visible();
              await tester.pumpWidget(chart((depth + 1) % 3, selected));
              expect(
                visible(),
                expected,
                reason: 'unchanged highlight retarget',
              );
              await prepare();
              await tester.pumpWidget(chart((depth + 1) % 3, null));
              await tester.pumpWidget(chart((depth + 1) % 3, selected));
              final actual = visible();
              final reason =
                  'normal=${normal.map((border) => border?.color)} '
                  'highlight=${highlight.color} selected=$selected depth=$depth';
              expect(actual.fill, expected.fill, reason: reason);
              if (expected.border == null) {
                expect(actual.border, isNull, reason: reason);
                continue;
              }
              expect(actual.border, isNotNull, reason: reason);
              expect(
                actual.border!.resolvedWidthFraction,
                closeTo(expected.border!.resolvedWidthFraction, 1e-12),
                reason: 'width $reason',
              );
              expect(
                actual.border!.resolvedOpacity,
                closeTo(expected.border!.resolvedOpacity, 1e-12),
                reason: 'opacity $reason',
              );
              final a = actual.border!.resolve(actual.fill, _surfaceColor);
              final b = expected.border!.resolve(expected.fill, _surfaceColor);
              expect(a.colorSpace, b.colorSpace, reason: reason);
              for (final channels in [
                (a.a, b.a),
                (a.r, b.r),
                (a.g, b.g),
                (a.b, b.b),
              ]) {
                expect(
                  channels.$1,
                  closeTo(channels.$2, 1e-10),
                  reason: reason,
                );
              }
            }
          }
        }
      }
    },
  );

  testWidgets(
    'retained explicit highlights preserve nonlinear gamut interpolation',
    (tester) async {
      final ring = find.byKey(kRingKey);
      const normal = [_blue, _yellow, _p3];
      for (final highlight in [_red, _p3]) {
        for (final selected in [0, 1]) {
          await tester.pumpWidget(const SizedBox.shrink());
          WovenSegment endpoint(int i) => WovenSegment(
            value: 1,
            fill: _fills[i],
            border: i == selected ? highlight : normal[i],
          );
          Widget chart(int active) => host(
            SizedBox.square(
              dimension: 40,
              child: WovenRingChart(
                key: kRingKey,
                animation: WovenRingAnimation.none,
                transitionDuration: const Duration(seconds: 1),
                highlightedIndex: selected,
                highlightBorder: highlight,
                style: const WovenRingStyle(surfaceColor: _surfaceColor),
                segments: [
                  for (var i = 0; i < 3; i++)
                    WovenSegment(
                      value: active == i ? 1 : 0,
                      fill: _fills[i],
                      border: normal[i],
                    ),
                ],
              ),
            ),
          );
          await tester.pumpWidget(chart(0));
          var expected = endpoint(0);
          for (var i = 1; i < 13; i++) {
            await tester.pumpWidget(chart(i % 3));
            await tester.pump(const Duration(milliseconds: 370));
            expected = WovenSegment.lerp(
              expected,
              endpoint(i % 3),
              Curves.easeInOut.transform(.37),
              surfaceColor: _surfaceColor,
            );
            final fractions = paintedFractions(tester, ring);
            final actual = paintedSegments(
              tester,
              ring,
            )[fractions.indexWhere((f) => f > 0)];
            final color = actual.border!.resolve(actual.fill, _surfaceColor);
            final target = expected.border!.resolve(
              expected.fill,
              _surfaceColor,
            );
            expect(color.colorSpace, target.colorSpace);
            for (final channels in [
              (color.a, target.a),
              (color.r, target.r),
              (color.g, target.g),
              (color.b, target.b),
            ]) {
              expect(
                channels.$1,
                closeTo(channels.$2, 1e-12),
                reason: 'selected=$selected retarget=$i',
              );
            }
          }
        }
      }
    },
  );

  testWidgets(
    'a retained highlight fading against absent borders keeps extended color data',
    (tester) async {
      const color = Color.from(
        alpha: .6,
        red: 1.2,
        green: -.1,
        blue: .7,
        colorSpace: ColorSpace.extendedSRGB,
      );
      Widget chart(int active) => host(
        SizedBox.square(
          dimension: 40,
          child: WovenRingChart(
            key: kRingKey,
            animation: WovenRingAnimation.none,
            transitionDuration: const Duration(seconds: 1),
            highlightedIndex: 1,
            highlightBorder: const WovenBorder(color: color),
            segments: [
              for (var i = 0; i < 3; i++)
                WovenSegment(value: i == active ? 1 : 0, fill: _fills[i]),
            ],
          ),
        ),
      );
      await tester.pumpWidget(chart(0));
      await tester.pumpWidget(chart(1));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpWidget(chart(2));
      await tester.pump(const Duration(milliseconds: 200));
      final ring = find.byKey(kRingKey);
      final fractions = paintedFractions(tester, ring);
      final actual = paintedSegments(
        tester,
        ring,
      )[fractions.indexWhere((f) => f > 0)];
      expect(actual.border!.color, color);
      expect(
        actual.border!.resolvedOpacity,
        closeTo(
          Curves.easeInOut.transform(.4) * (1 - Curves.easeInOut.transform(.2)),
          1e-12,
        ),
      );
    },
  );
}
