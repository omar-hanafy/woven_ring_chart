import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woven_ring_chart/woven_ring_chart.dart';

const List<Color> _colors = <Color>[
  Color(0xFFFF0000),
  Color(0xFF00FF00),
  Color(0xFF0000FF),
  Color(0xFFFF00FF),
];

void main() {
  for (final int count in <int>[0, 1, 2]) {
    testWidgets('highlights use current bounds while shrinking to $count', (
      WidgetTester tester,
    ) async {
      for (final bool clockwise in <bool>[true, false]) {
        await tester.pumpWidget(const SizedBox.shrink());
        final GlobalKey key = GlobalKey();
        Widget chart(int length, int? highlight) => Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: RepaintBoundary(
              key: key,
              child: SizedBox.square(
                dimension: 200,
                child: WovenRingChart(
                  style: WovenRingStyle(clockwise: clockwise),
                  animation: WovenRingAnimation.none,
                  transitionDuration: const Duration(seconds: 1),
                  highlightedIndex: highlight,
                  highlightBorder: const WovenBorder(
                    color: Color(0xFF000000),
                    widthFraction: .05,
                  ),
                  segments: <WovenSegment>[
                    for (var i = 0; i < length; i++)
                      WovenSegment.solid(1, _colors[i]),
                  ],
                ),
              ),
            ),
          ),
        );

        await tester.pumpWidget(chart(4, null));
        await tester.pumpWidget(chart(count, null));
        await tester.pump(const Duration(milliseconds: 300));
        final Uint8List expected = await _capture(tester, key);
        for (final int invalid in <int>[-1, count, 3, 999]) {
          await tester.pumpWidget(chart(count, invalid));
          expect(
            await _capture(tester, key),
            orderedEquals(expected),
            reason: 'count=$count clockwise=$clockwise index=$invalid',
          );
        }
        if (count > 0) {
          await tester.pumpWidget(chart(count, 0));
          expect(await _capture(tester, key), isNot(orderedEquals(expected)));
        }

        // Retargeting a topology transition carries visual styles from the
        // current frame. Those retained entries still cannot expand the
        // caller's valid index range.
        await tester.pumpWidget(chart(count, null));
        final int retargetCount = count == 1 ? 2 : 1;
        await tester.pumpWidget(chart(retargetCount, null));
        await tester.pump(const Duration(milliseconds: 200));
        final Uint8List retargeted = await _capture(tester, key);
        await tester.pumpWidget(chart(retargetCount, 3));
        expect(await _capture(tester, key), orderedEquals(retargeted));
      }
    });
  }
}

Future<Uint8List> _capture(WidgetTester tester, GlobalKey key) async =>
    (await tester.runAsync<Uint8List>(() async {
      final RenderRepaintBoundary boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final ui.Image image = await boundary.toImage();
      final ByteData data = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      final Uint8List bytes = Uint8List.fromList(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
      image.dispose();
      return bytes;
    }))!;
