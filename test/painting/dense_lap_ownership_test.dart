import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woven_ring_chart/woven_ring_chart.dart';

void main() {
  for (final clockwise in [true, false]) {
    testWidgets(
      'R7 dense seam successor remains above last lap CW=$clockwise',
      (tester) async {
        final dir = clockwise ? 1.0 : -1.0;
        const side = 480.0;
        const track = 168.0;
        const cap = 72.0;
        final lag = 144 / track;
        final style = WovenRingStyle(
          thicknessFraction: 0.30,
          overlapFraction: 1,
          startAngle: 0,
          clockwise: clockwise,
        );
        final colors = [
          const Color(0xFFFF0000),
          const Color(0xFF00FF00),
          const Color(0xFF0000FF),
          const Color(0xFFFFFF00),
          const Color(0xFFFF00FF),
          const Color(0xFF00FFFF),
          const Color(0xFFFFFFFF),
          const Color(0xFF000000),
        ];
        final chart = WovenRingChart(
          animation: WovenRingAnimation.none,
          style: style,
          segments: [for (final color in colors) WovenSegment.solid(1, color)],
        );
        final bytes = await _render(tester, chart);
        final requested = Offset(
          240 + track * math.cos(-dir * 0.4),
          240 + track * math.sin(-dir * 0.4),
        );
        final p = Offset(
          (requested.dx - 0.5).round() + 0.5,
          (requested.dy - 0.5).round() + 0.5,
        );
        // Independent capsule-distance membership; no package geometry or ownership oracle.
        double distance(int index, Offset point) {
          final start = dir * (index * math.pi / 4 - lag);
          final end = dir * ((index + 1) * math.pi / 4);
          final radial = point - const Offset(side / 2, side / 2);
          final along =
              (dir * (math.atan2(radial.dy, radial.dx) - start)) %
              (math.pi * 2);
          final span = dir * (end - start);
          if (along <= span) return (radial.distance - track).abs() - cap;
          Offset on(double a) =>
              Offset(240 + track * math.cos(a), 240 + track * math.sin(a));
          return math.min(
                (point - on(start)).distance,
                (point - on(end)).distance,
              ) -
              cap;
        }

        final covered = [
          for (var i = 0; i < 8; i++)
            if (distance(i, p) < 0) i,
        ];
        expect(covered, [0, 1, 6, 7]);
        for (var i = 0; i < 8; i++) {
          expect(
            distance(i, p).abs(),
            greaterThan(5),
            reason: 'sample must be safely away from edge $i',
          );
        }
        final offset = (p.dy.floor() * 480 + p.dx.floor()) * 4;
        expect(bytes.sublist(offset, offset + 4), [0, 255, 0, 255]);
        final bordered = await _render(
          tester,
          WovenRingChart(
            animation: WovenRingAnimation.none,
            style: style,
            segments: [
              for (var i = 0; i < colors.length; i++)
                WovenSegment.solid(
                  1,
                  colors[i],
                  border: WovenBorder(
                    color: i == 1 ? const Color(0xFFFFFFFF) : colors[i],
                    widthFraction: .05,
                  ),
                ),
            ],
          ),
        );
        final borderOffset = ((clockwise ? 172 : 307) * 480 + 367) * 4;
        expect(bordered.sublist(borderOffset, borderOffset + 4), [
          255,
          255,
          255,
          255,
        ]);
        expect(bordered.sublist(offset, offset + 4), [0, 255, 0, 255]);
      },
    );
  }
}

Future<Uint8List> _render(WidgetTester tester, Widget chart) async {
  final GlobalKey key = GlobalKey();
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: RepaintBoundary(
          key: key,
          child: SizedBox.square(dimension: 480, child: chart),
        ),
      ),
    ),
  );
  return (await tester.runAsync(() async {
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
}
