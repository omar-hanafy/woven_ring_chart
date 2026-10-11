import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woven_ring_chart/woven_ring_chart.dart';

const int _side = 480;

void main() {
  for (final ui.ColorSpace inkSpace in ui.ColorSpace.values) {
    for (final ui.ColorSpace surfaceSpace in ui.ColorSpace.values) {
      for (final bool translucent in <bool>[false, true]) {
        testWidgets(
          'renderer combines $inkSpace border over $surfaceSpace surface '
          'with alpha=$translucent',
          (WidgetTester tester) async {
            final Color ink = Color.from(
              alpha: translucent ? .5 : 1,
              red: inkSpace == ui.ColorSpace.extendedSRGB ? -.08 : 0,
              green: inkSpace == ui.ColorSpace.extendedSRGB ? 1.1 : 1,
              blue: 0,
              colorSpace: inkSpace,
            );
            final Color surface = Color.from(
              alpha: translucent ? .5 : 1,
              red: surfaceSpace == ui.ColorSpace.extendedSRGB ? 1.2 : 1,
              green: surfaceSpace == ui.ColorSpace.extendedSRGB ? -.1 : 0,
              blue: 0,
              colorSpace: surfaceSpace,
            );
            final Color fill = translucent
                ? const Color(0x800000FF)
                : const Color(0xFF0000FF);
            final double lineOpacity = translucent ? .5 : 1;
            for (final double opacity in <double>[.25, .5, .75]) {
              // The canvas converts each paint into its actual rendering
              // space before combining the group and applying its opacity.
              // No CPU color conversion or encoded-channel blend is involved.
              final List<int> expected = await _sample(
                tester,
                CustomPaint(
                  painter: _GroupReference(
                    fill: fill,
                    ink: ink,
                    surface: surface,
                    lineOpacity: lineOpacity,
                    opacity: opacity,
                  ),
                ),
              );
              for (final int count in <int>[1, 4]) {
                for (final bool clockwise in <bool>[true, false]) {
                  final List<int> actual = await _sample(
                    tester,
                    WovenRingChart(
                      animation: WovenRingAnimation.none,
                      style: WovenRingStyle(
                        startAngle: 0,
                        clockwise: clockwise,
                        surfaceColor: surface,
                      ),
                      segments: <WovenSegment>[
                        for (var i = 0; i < count; i++)
                          WovenSegment.solid(
                            1,
                            fill,
                            opacity: opacity,
                            border: WovenBorder(
                              color: ink,
                              widthFraction: .05,
                              opacity: lineOpacity,
                            ),
                          ),
                      ],
                    ),
                  );
                  for (var channel = 0; channel < 4; channel++) {
                    expect(
                      actual[channel],
                      closeTo(expected[channel], 1),
                      reason:
                          'count=$count clockwise=$clockwise opacity=$opacity '
                          'channel=$channel actual=$actual expected=$expected',
                    );
                  }
                }
              }
            }
          },
        );
      }
    }
  }

  testWidgets('wide-gamut receiver opacity retains incoming shadow strength', (
    WidgetTester tester,
  ) async {
    for (final bool clockwise in <bool>[true, false]) {
      final WovenRingStyle style = WovenRingStyle(
        startAngle: 0,
        clockwise: clockwise,
        surfaceColor: const Color(0xFFFFFFFF),
        shadow: const WovenShadow(
          color: Color(0x80000000),
          blurFraction: .12,
          offsetFraction: .12,
        ),
      );
      WovenRingChart chart(double opacity) => WovenRingChart(
        animation: WovenRingAnimation.none,
        style: style,
        segments: <WovenSegment>[
          for (var i = 0; i < 4; i++)
            WovenSegment.solid(
              1,
              const Color(0xFFFFFFFF),
              opacity: i == 0 ? opacity : 1,
              border: const WovenBorder(
                color: Color.from(
                  alpha: 1,
                  red: 1,
                  green: 1,
                  blue: 1,
                  colorSpace: ui.ColorSpace.displayP3,
                ),
                widthFraction: .05,
                opacity: .5,
              ),
            ),
        ],
      );
      final Uint8List full = await _render(tester, chart(1));
      final Uint8List faded = await _render(tester, chart(.5));
      final WovenRingGeometry g = WovenRingGeometry.forSize(
        const Size.square(480),
        style,
      );
      final List<WovenSegmentExtent> extents = g.extents(
        const <double>[.25, .25, .25, .25],
        0,
        clockwise: clockwise,
      );
      final Path owner = g.segmentPath(
        extents[0].start,
        extents[0].end,
        clockwise: clockwise,
      );
      final Path successor = g.segmentPath(
        extents[1].start,
        extents[1].end,
        clockwise: clockwise,
      );
      var checked = 0;
      for (var y = 0; y < _side; y++) {
        for (var x = 0; x < _side; x++) {
          final Offset point = Offset(x + .5, y + .5);
          final double radius = (point - g.center).distance;
          if (radius < g.innerRadius + 2 ||
              radius > g.outerRadius - 2 ||
              !<Offset>[
                for (final double dx in <double>[-2, 0, 2])
                  for (final double dy in <double>[-2, 0, 2])
                    point + Offset(dx, dy),
              ].every(
                (Offset sample) =>
                    owner.contains(sample) && !successor.contains(sample),
              )) {
            continue;
          }
          final int offset = (y * _side + x) * 4;
          if (full[offset] >= 247 || full[offset + 3] != 255) continue;
          // Fill and surface are equal white, so receiver opacity cannot
          // change the unchanged successor's incoming shadow. Its own cast
          // shadow belongs to a different receiver, outside these samples.
          // The complete neighborhood lies inside the receiver, excluding
          // cap-edge pixels that also see its own cast shadow through AA.
          for (var channel = 0; channel < 4; channel++) {
            expect(
              faded[offset + channel],
              closeTo(full[offset + channel], 1),
              reason: 'clockwise=$clockwise pixel=($x,$y) channel=$channel',
            );
          }
          checked++;
        }
      }
      expect(checked, greaterThan(100));
    }
  });
}

class _GroupReference extends CustomPainter {
  const _GroupReference({
    required this.fill,
    required this.ink,
    required this.surface,
    required this.lineOpacity,
    required this.opacity,
  });

  final Color fill;
  final Color ink;
  final Color surface;
  final double lineOpacity;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect bounds = Offset.zero & size;
    canvas.drawRect(bounds, Paint()..color = surface);
    canvas.saveLayer(
      bounds,
      Paint()..color = Color.fromARGB((opacity * 255).round(), 255, 255, 255),
    );
    canvas.drawRect(bounds, Paint()..color = fill);
    canvas.drawRect(
      bounds,
      Paint()..color = ink.withValues(alpha: ink.a * lineOpacity),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GroupReference oldDelegate) => true;
}

Future<List<int>> _sample(WidgetTester tester, Widget child) async {
  final Uint8List bytes = await _render(tester, child);
  final int offset = (240 * _side + 476) * 4;
  return bytes.sublist(offset, offset + 4);
}

Future<Uint8List> _render(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(const SizedBox.shrink());
  final GlobalKey key = GlobalKey();
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: RepaintBoundary(
          key: key,
          child: SizedBox.square(dimension: _side.toDouble(), child: child),
        ),
      ),
    ),
  );
  return (await tester.runAsync<Uint8List>(() async {
    final RenderRepaintBoundary boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final ui.Image image = await boundary.toImage();
    final ByteData data = (await image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!;
    final Uint8List result = Uint8List.fromList(data.buffer.asUint8List());
    image.dispose();
    return result;
  }))!;
}
