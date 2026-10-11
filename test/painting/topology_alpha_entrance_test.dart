import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woven_ring_chart/woven_ring_chart.dart';

void main() {
  testWidgets('a transparent chart surface preserves its parent backdrop', (
    WidgetTester tester,
  ) async {
    for (final int count in <int>[1, 3]) {
      for (final Color surface in <Color>[
        const Color(0x00000000),
        const Color(0x800000FF),
      ]) {
        await tester.pumpWidget(const SizedBox.shrink());
        final GlobalKey key = GlobalKey();
        await _pump(
          tester,
          key,
          ColoredBox(
            color: const Color(0xFF00FF00),
            child: WovenRingChart(
              animation: WovenRingAnimation.none,
              style: WovenRingStyle(surfaceColor: surface),
              segments: <WovenSegment>[
                for (var i = 0; i < count; i++)
                  const WovenSegment(
                    value: 1,
                    fill: WovenFill.solid(Color(0x80FF0000)),
                  ),
              ],
            ),
          ),
        );
        final Uint8List bytes = await _capture(tester, key);
        const int offset = (120 * 240 + 24) * 4;
        expect(
          bytes.sublist(offset, offset + 4),
          surface.a == 0 ? <int>[128, 127, 0, 255] : <int>[128, 63, 64, 255],
        );
        const int hole = (120 * 240 + 120) * 4;
        expect(bytes.sublist(hole, hole + 4), <int>[0, 255, 0, 255]);
      }
    }
  });

  testWidgets('topology preserves the alpha of an unchanged translucent fill', (
    WidgetTester tester,
  ) async {
    for (final bool clockwise in <bool>[true, false]) {
      for (final bool toMany in <bool>[true, false]) {
        for (final Color surface in <Color>[
          const Color(0x00000000),
          const Color(0x800000FF),
          const Color(0xFFFFFFFF),
        ]) {
          await tester.pumpWidget(const SizedBox.shrink());
          final GlobalKey key = GlobalKey();
          Widget chart(int count) => WovenRingChart(
            animation: WovenRingAnimation.none,
            transitionDuration: const Duration(seconds: 1),
            style: WovenRingStyle(clockwise: clockwise, surfaceColor: surface),
            segments: <WovenSegment>[
              for (var i = 0; i < count; i++)
                const WovenSegment(
                  value: 1,
                  fill: WovenFill.solid(Color(0x80FF0000)),
                ),
            ],
          );
          await _pump(tester, key, chart(toMany ? 1 : 3));
          final Uint8List before = await _capture(tester, key);
          await _pump(tester, key, chart(toMany ? 3 : 1));
          expect(await _capture(tester, key), orderedEquals(before));
          var previous = 0;
          for (final int time in <int>[1, 250, 500, 750, 999, 1000]) {
            await tester.pump(Duration(milliseconds: time - previous));
            previous = time;
            final Uint8List frame = await _capture(tester, key);
            // The opposite track centre is strictly inside both endpoint
            // silhouettes. An unchanged fill/surface has constant RGBA here.
            const int offset = (120 * 240 + 24) * 4;
            for (var channel = 0; channel < 4; channel++) {
              expect(
                frame[offset + channel],
                closeTo(before[offset + channel], 1),
                reason: '$clockwise $toMany $surface at $time channel $channel',
              );
            }
          }
        }
      }
    }
  });

  for (final WovenRingAnimation animation in <WovenRingAnimation>[
    WovenRingAnimation.sweep,
    WovenRingAnimation.grow,
  ]) {
    testWidgets('single gradient $animation closes without changing phase', (
      WidgetTester tester,
    ) async {
      for (final bool clockwise in <bool>[true, false]) {
        for (final WovenGradientAxis axis in WovenGradientAxis.values) {
          for (final WovenSingleSegmentStyle single
              in WovenSingleSegmentStyle.values) {
            await tester.pumpWidget(const SizedBox.shrink());
            final GlobalKey key = GlobalKey();
            await _pump(
              tester,
              key,
              WovenRingChart(
                animation: animation,
                animationDuration: const Duration(seconds: 1),
                style: WovenRingStyle(
                  clockwise: clockwise,
                  gradientAxis: axis,
                  singleSegmentStyle: single,
                ),
                segments: const <WovenSegment>[
                  WovenSegment(
                    value: 1,
                    fill: WovenFill.gradient(
                      head: Color(0xFFFF0000),
                      tail: Color(0xFF0000FF),
                    ),
                    border: WovenBorder(color: Color(0xFF000000)),
                  ),
                ],
              ),
            );
            await tester.pump(const Duration(milliseconds: 999));
            final Uint8List before = await _capture(tester, key);
            await tester.pump(const Duration(milliseconds: 1));
            final Uint8List after = await _capture(tester, key);
            for (var y = 0; y < 240; y++) {
              for (var x = 0; x < 240; x++) {
                final double radius2 =
                    (x + 0.5 - 120) * (x + 0.5 - 120) +
                    (y + 0.5 - 120) * (y + 0.5 - 120);
                if (radius2 < 75 * 75 || radius2 > 117 * 117) continue;
                final int offset = (y * 240 + x) * 4;
                for (var c = 0; c < 4; c++) {
                  expect(
                    after[offset + c],
                    closeTo(before[offset + c], 1),
                    reason: '$clockwise $axis $single ($x,$y) channel $c',
                  );
                }
              }
            }
          }
        }
      }
    });
  }
}

Future<void> _pump(WidgetTester tester, GlobalKey key, Widget chart) =>
    tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: RepaintBoundary(
            key: key,
            child: SizedBox.square(dimension: 240, child: chart),
          ),
        ),
      ),
    );

Future<Uint8List> _capture(WidgetTester tester, GlobalKey key) async =>
    (await tester.runAsync(() async {
      final RenderRepaintBoundary boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final ui.Image image = await boundary.toImage();
      final ByteData data = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      final Uint8List bytes = Uint8List.fromList(data.buffer.asUint8List());
      image.dispose();
      return bytes;
    }))!;
