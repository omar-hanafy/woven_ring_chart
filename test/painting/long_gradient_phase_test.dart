import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woven_ring_chart/woven_ring_chart.dart';

void main() {
  for (final (double fraction, double thickness, double overlap) config
      in <(double, double, double)>[
        (0.18, 0.2, 0.5),
        (0.55, 0.2, 0.5),
        (0.90, 0.2, 0.5),
        (0.95, 0.2, 0.5),
        (0.975, 0.12, 0.9),
        (0.93, 0.28, 0.8),
      ]) {
    testWidgets('gradient $config keeps head phase and cap-to-cap slope', (
      WidgetTester tester,
    ) async {
      for (final bool clockwise in <bool>[true, false]) {
        for (final WovenGradientDirection gradientDirection
            in WovenGradientDirection.values) {
          for (final double angle in <double>[0, -0.317, 2.81]) {
            for (final int alpha in <int>[255, 128]) {
              final WovenRingStyle style = WovenRingStyle(
                thicknessFraction: config.$2,
                overlapFraction: config.$3,
                startAngle: angle,
                clockwise: clockwise,
                gradientDirection: gradientDirection,
                smallValuePolicy: WovenSmallValuePolicy.allowVanish,
                surfaceColor: const Color(0x00000000),
              );
              final WovenRingGeometry geometry = WovenRingGeometry.forSize(
                const Size.square(480),
                style,
              );
              final double direction = clockwise ? 1 : -1;
              final double head = angle - direction * geometry.jointLag;
              final double span =
                  config.$1 * 2 * math.pi +
                  geometry.jointLag +
                  2 * geometry.capAngularExtent;
              final double origin =
                  head - direction * geometry.capAngularExtent;
              await tester.pumpWidget(const SizedBox.shrink());
              final Uint8List bytes = await _render(
                tester,
                WovenRingChart(
                  animation: WovenRingAnimation.none,
                  style: style,
                  segments: <WovenSegment>[
                    WovenSegment(
                      value: config.$1,
                      fill: WovenFill.gradient(
                        head: Color.fromARGB(alpha, 255, 0, 0),
                        tail: Color.fromARGB(alpha, 0, 0, 255),
                      ),
                      border: const WovenBorder(
                        color: Color(0xFF000000),
                        widthFraction: 0.04,
                      ),
                    ),
                    WovenSegment.solid(1 - config.$1, const Color(0xFF00FF00)),
                  ],
                ),
              );
              for (final double along in <double>[
                -geometry.capAngularExtent * 0.65,
                0,
                (config.$1 * 2 * math.pi - geometry.capAngularExtent) * 0.25,
                (config.$1 * 2 * math.pi - geometry.capAngularExtent) * 0.50,
                (config.$1 * 2 * math.pi - geometry.capAngularExtent) * 0.70,
              ]) {
                final Offset point = geometry.pointOn(
                  geometry.trackRadius,
                  head + direction * along,
                );
                final int x = point.dx.floor();
                final int y = point.dy.floor();
                final double polar = math.atan2(y + 0.5 - 240, x + 0.5 - 240);
                final double progress =
                    ((direction * (polar - origin)) % (2 * math.pi)) / span;
                final double t =
                    gradientDirection == WovenGradientDirection.headToTail
                    ? progress
                    : 1 - progress;
                final int offset = (y * 480 + x) * 4;
                final String label =
                    '$config clockwise=$clockwise $gradientDirection '
                    'angle=$angle alpha=$alpha along=$along ($x,$y)';
                expect(
                  bytes[offset],
                  closeTo(alpha * (1 - t), 1),
                  reason: label,
                );
                expect(bytes[offset + 1], 0, reason: label);
                expect(bytes[offset + 2], closeTo(alpha * t, 1), reason: label);
                expect(bytes[offset + 3], alpha, reason: label);
              }
            }
          }
        }
      }
    });
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
