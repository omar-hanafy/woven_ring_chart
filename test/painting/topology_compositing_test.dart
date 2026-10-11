import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woven_ring_chart/src/model/chart_mode.dart';
import 'package:woven_ring_chart/src/painting/ring_painter.dart';
import 'package:woven_ring_chart/woven_ring_chart.dart';

void main() {
  testWidgets('topology interpolates complete premultiplied renders once', (
    WidgetTester tester,
  ) async {
    for (final bool clockwise in <bool>[true, false]) {
      for (final WovenGradientAxis axis in WovenGradientAxis.values) {
        for (final WovenSingleSegmentStyle single
            in WovenSingleSegmentStyle.values) {
          for (final Color surface in <Color>[
            const Color(0x00000000),
            const Color(0x80102030),
            const Color(0xFFFFFFFF),
          ]) {
            for (final double coverage in <double>[1, 0.6]) {
              WovenRingChartPainter painter(double merge) =>
                  WovenRingChartPainter(
                    segments: const <WovenSegment>[
                      WovenSegment(
                        value: 5,
                        fill: WovenFill.gradient(
                          head: Color(0x80FF0000),
                          tail: Color(0x400000FF),
                        ),
                        border: WovenBorder(
                          color: Color(0x80000000),
                          opacity: 0.5,
                        ),
                      ),
                      WovenSegment(
                        value: 3,
                        fill: WovenFill.solid(Color(0x8000FF00)),
                        opacity: 0.7,
                      ),
                      WovenSegment(
                        value: 2,
                        fill: WovenFill.solid(Color(0xFFFFAA00)),
                        border: WovenBorder(color: Color(0xFFFFFFFF)),
                      ),
                    ],
                    fractions: <double>[
                      0.5 * coverage,
                      0.3 * coverage,
                      0.2 * coverage,
                    ],
                    style: WovenRingStyle(
                      clockwise: clockwise,
                      gradientAxis: axis,
                      singleSegmentStyle: single,
                      surfaceColor: surface,
                      shadow: const WovenShadow(),
                    ),
                    mode: WovenRingChartMode.data,
                    animation: WovenRingAnimation.none,
                    animationProgress: 1,
                    spin: 0,
                    highlightedIndex: 0,
                    highlightBorder: const WovenBorder(
                      color: Color(0xFF000000),
                      opacity: 0.5,
                    ),
                    topologyMerge: merge,
                    topologyAnchor: 0,
                  );
              final Uint8List woven = await _render(tester, painter(0));
              final Uint8List canonical = await _render(tester, painter(1));
              for (final double merge in <double>[0.25, 0.5, 0.75]) {
                final Uint8List actual = await _render(tester, painter(merge));
                final int weight = (255 * merge).round();
                var worst = 0;
                var location = 0;
                for (var byte = 0; byte < actual.length; byte++) {
                  final double expected =
                      (woven[byte] * (255 - weight) +
                          canonical[byte] * weight) /
                      255;
                  final int difference = (actual[byte] - expected.round())
                      .abs();
                  if (difference > worst) {
                    worst = difference;
                    location = byte;
                  }
                }
                expect(
                  worst,
                  lessThanOrEqualTo(1),
                  reason:
                      '$clockwise $axis $single surface=$surface '
                      'coverage=$coverage merge=$merge byte=$location',
                );
              }
            }
          }
        }
      }
    }
  });
}

Future<Uint8List> _render(
  WidgetTester tester,
  WovenRingChartPainter painter,
) async => (await tester.runAsync<Uint8List>(() async {
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), const Size.square(240));
  final ui.Picture picture = recorder.endRecording();
  final ui.Image image = await picture.toImage(240, 240);
  final ByteData data = (await image.toByteData(
    format: ui.ImageByteFormat.rawRgba,
  ))!;
  final Uint8List result = Uint8List.fromList(data.buffer.asUint8List());
  image.dispose();
  picture.dispose();
  return result;
}))!;
