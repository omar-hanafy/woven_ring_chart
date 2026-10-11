import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woven_ring_chart/woven_ring_chart.dart';

const int _side = 480;

void main() {
  for (final int count in <int>[1, 4]) {
    for (final Color surface in <Color>[
      const Color(0x00000000),
      const Color(0x800000FF),
      const Color(0xFFFFFFFF),
    ]) {
      testWidgets('whole segment opacity count=$count surface=$surface', (
        WidgetTester tester,
      ) async {
        WovenRingChart chart(double opacity) => WovenRingChart(
          animation: WovenRingAnimation.none,
          style: WovenRingStyle(startAngle: 0, surfaceColor: surface),
          segments: <WovenSegment>[
            for (var i = 0; i < count; i++)
              WovenSegment.solid(
                1,
                const Color(0xFFFF0000),
                opacity: opacity,
                border: const WovenBorder(
                  color: Color(0xFF000000),
                  widthFraction: .05,
                ),
              ),
          ],
        );
        final Uint8List full = await _render(tester, chart(1));
        // This pixel is fully inside the border, rather than an antialiased
        // edge. The opaque reference proves that no fill should remain.
        expect(_at(full, 476, 240), <int>[0, 0, 0, 255]);
        for (final double opacity in <double>[.25, .5, .75]) {
          final Uint8List faded = await _render(tester, chart(opacity));
          // Layer opacity is represented by a byte. Use that weight before
          // computing the source-over result, retaining a one-byte tolerance.
          final double weight = (opacity * 255).round() / 255;
          final List<int> expected = <int>[
            (surface.r * surface.a * (1 - weight) * 255).round(),
            (surface.g * surface.a * (1 - weight) * 255).round(),
            (surface.b * surface.a * (1 - weight) * 255).round(),
            ((weight + surface.a * (1 - weight)) * 255).round(),
          ];
          final List<int> actual = _at(faded, 476, 240);
          for (var channel = 0; channel < 4; channel++) {
            expect(
              actual[channel],
              closeTo(expected[channel], 1),
              reason:
                  'opacity=$opacity channel=$channel actual=$actual '
                  'expected=$expected',
            );
          }
        }
      });
    }
  }

  testWidgets('single self-joint shares its whole segment opacity', (
    WidgetTester tester,
  ) async {
    const Color surface = Color(0xFFFFFFFF);
    for (final bool clockwise in <bool>[true, false]) {
      for (final WovenFill fill in <WovenFill>[
        const WovenFill.solid(Color(0xFFFF0000)),
        const WovenFill.gradient(
          head: Color(0x80FF0000),
          tail: Color(0x800000FF),
        ),
      ]) {
        WovenRingChart chart(double opacity, {bool jointed = true}) =>
            WovenRingChart(
              animation: WovenRingAnimation.none,
              style: WovenRingStyle(
                startAngle: 0,
                clockwise: clockwise,
                surfaceColor: surface,
                singleSegmentStyle: jointed
                    ? WovenSingleSegmentStyle.jointed
                    : WovenSingleSegmentStyle.smooth,
              ),
              segments: <WovenSegment>[
                WovenSegment(value: 1, fill: fill, opacity: opacity),
              ],
            );
        final Uint8List full = await _render(tester, chart(1));
        final Uint8List plain = await _render(tester, chart(1, jointed: false));
        final Uint8List faded = await _render(tester, chart(.5));
        var checked = 0;
        for (var y = 0; y < _side; y++) {
          for (var x = 0; x < _side; x++) {
            final double radius =
                (Offset(x + .5, y + .5) - const Offset(240, 240)).distance;
            if (radius < 150 || radius > 234) continue;
            final List<int> reference = _at(full, x, y);
            if (listEquals(reference, _at(plain, x, y))) continue;
            final List<int> actual = _at(faded, x, y);
            for (var channel = 0; channel < 4; channel++) {
              // All four white-surface premultiplied channels are 255.
              final int expected = (reference[channel] * 128 / 255 + 127)
                  .round();
              expect(
                actual[channel],
                closeTo(expected, 1),
                reason:
                    'clockwise=$clockwise fill=$fill joint=($x,$y) '
                    'channel=$channel actual=$actual reference=$reference',
              );
            }
            checked++;
          }
        }
        expect(checked, greaterThan(100));
      }
    }
  });

  for (final WovenRingAnimation animation in <WovenRingAnimation>[
    WovenRingAnimation.sweep,
    WovenRingAnimation.grow,
  ]) {
    testWidgets('dropped values cannot expose a track during $animation', (
      WidgetTester tester,
    ) async {
      WovenRingChart chart(List<double> dropped) => WovenRingChart(
        animation: animation,
        style: const WovenRingStyle(startAngle: 0),
        segments: <WovenSegment>[
          WovenSegment.solid(1, const Color(0xFFFF0000)),
          for (final double value in dropped)
            WovenSegment.solid(value, const Color(0xFF0000FF)),
        ],
      );
      final Uint8List plain = await _render(
        tester,
        chart(const <double>[]),
        elapsed: const Duration(milliseconds: 250),
      );
      final Uint8List ignored = await _render(
        tester,
        chart(<double>[0, -1, double.nan, double.infinity]),
        elapsed: const Duration(milliseconds: 250),
      );
      expect(_at(plain, 48, 240), <int>[0, 0, 0, 0]);
      expect(_at(ignored, 48, 240), _at(plain, 48, 240));
      expect(ignored, plain);
    });
  }
}

Future<Uint8List> _render(
  WidgetTester tester,
  WovenRingChart chart, {
  Duration elapsed = Duration.zero,
}) async {
  await tester.pumpWidget(const SizedBox.shrink());
  final GlobalKey key = GlobalKey();
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: RepaintBoundary(
          key: key,
          child: SizedBox.square(dimension: _side.toDouble(), child: chart),
        ),
      ),
    ),
  );
  if (elapsed > Duration.zero) await tester.pump(elapsed);
  return (await tester.runAsync<Uint8List>(() async {
    final RenderRepaintBoundary boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final ui.Image image = await boundary.toImage();
    final ByteData data = (await image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!;
    final Uint8List result = Uint8List.fromList(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
    image.dispose();
    return result;
  }))!;
}

List<int> _at(Uint8List bytes, int x, int y) {
  final int offset = (y * _side + x) * 4;
  return bytes.sublist(offset, offset + 4);
}
