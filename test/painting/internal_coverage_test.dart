import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woven_ring_chart/woven_ring_chart.dart';

void main() {
  for (final Color surface in <Color>[
    const Color(0x00000000),
    WovenPalette.surface,
    const Color(0x800000FF),
    const Color.from(
      alpha: .5,
      red: 0,
      green: 1,
      blue: 0,
      colorSpace: ui.ColorSpace.displayP3,
    ),
  ]) {
    for (final bool clockwise in <bool>[true, false]) {
      testWidgets(
        'internal coverage is continuous on $surface clockwise=$clockwise',
        (WidgetTester tester) async {
          for (final WovenSegment segment in <WovenSegment>[
            WovenSegment.solid(1, const Color(0x80FF0000)),
            WovenSegment.solid(1, const Color(0xFFFF0000), opacity: .5),
            const WovenSegment(
              value: 1,
              fill: WovenFill.gradient(
                head: Color(0x40FF0000),
                tail: Color(0xC00000FF),
              ),
            ),
          ]) {
            final WovenRingStyle style = WovenRingStyle(
              clockwise: clockwise,
              surfaceColor: surface,
              gradientAxis: WovenGradientAxis.acrossThickness,
            );
            final Uint8List single = await _render(tester, segment, style, 1);
            for (final int count in <int>[2, 4, 8]) {
              final Uint8List divided = await _render(
                tester,
                segment,
                style,
                count,
              );
              for (var y = 0; y < 480; y++) {
                for (var x = 0; x < 480; x++) {
                  final double radius =
                      (Offset(x + .5, y + .5) - const Offset(240, 240))
                          .distance;
                  // Only the true outer/hole silhouette is excluded. Every
                  // internal cap and ownership boundary remains in the scan.
                  if (radius < 149 || radius > 235) continue;
                  final int offset = (y * 480 + x) * 4;
                  for (var channel = 0; channel < 4; channel++) {
                    expect(
                      divided[offset + channel],
                      closeTo(single[offset + channel], 1),
                      reason:
                          'count=$count fill=${segment.fill} '
                          'opacity=${segment.opacity} pixel=($x,$y) '
                          'channel=$channel',
                    );
                  }
                  if (surface.a == 1) expect(divided[offset + 3], 255);
                }
              }
            }
          }
        },
      );
    }
  }
}

Future<Uint8List> _render(
  WidgetTester tester,
  WovenSegment segment,
  WovenRingStyle style,
  int count,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  final GlobalKey key = GlobalKey();
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: RepaintBoundary(
          key: key,
          child: SizedBox.square(
            dimension: 480,
            child: WovenRingChart(
              animation: WovenRingAnimation.none,
              style: style,
              segments: List<WovenSegment>.filled(count, segment),
            ),
          ),
        ),
      ),
    ),
  );
  return (await tester.runAsync<Uint8List>(() async {
    final ui.Image image =
        await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary)
            .toImage();
    final ByteData data = (await image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!;
    final Uint8List result = Uint8List.fromList(data.buffer.asUint8List());
    image.dispose();
    return result;
  }))!;
}
