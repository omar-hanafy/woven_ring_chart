import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woven_ring_chart/src/model/chart_mode.dart';
import 'package:woven_ring_chart/src/painting/ring_painter.dart';
import 'package:woven_ring_chart/woven_ring_chart.dart';

void main() {
  test('dense equal and clustered heads keep clip work linear', () {
    for (final count in <int>[100, 300, 1000]) {
      for (final clockwise in <bool>[true, false]) {
        for (final cluster in <bool>[false, true]) {
          for (final progress in <double>[.1, .5, .99, 1]) {
            final values = <double>[
              for (var i = 0; i < count; i++)
                cluster && i != count - 1 ? .000001 : 1,
            ];
            final total = values.reduce((a, b) => a + b);
            final canvas = _ClipCounter();
            WovenRingChartPainter(
              segments: <WovenSegment>[
                for (final value in values)
                  WovenSegment.solid(
                    value,
                    const Color(0x80FF0000),
                    border: const WovenBorder(color: Color(0xFF000000)),
                  ),
              ],
              fractions: <double>[for (final value in values) value / total],
              style: WovenRingStyle(
                thicknessFraction: .3,
                overlapFraction: 1,
                clockwise: clockwise,
                surfaceColor: const Color(0x00000000),
              ),
              mode: WovenRingChartMode.data,
              animation: WovenRingAnimation.grow,
              animationProgress: progress,
              spin: 0,
              highlightedIndex: null,
              highlightBorder: const WovenBorder(),
              topologyMerge: 0,
              topologyAnchor: null,
            ).paint(canvas, const Size.square(480));
            // Equal heads need at most one retained mask. In the cluster,
            // the first small successor contains the remaining smaller arcs;
            // only the final large successor can add a second mask. Thus each
            // segment needs at most: body2 + fill-lap(2+2) + border-body(2+1)
            // + border-lap(2+2+1) = fourteen clips across all four passes.
            expect(
              canvas.clips,
              lessThanOrEqualTo(14 * count),
              reason:
                  'n=$count clockwise=$clockwise cluster=$cluster progress=$progress',
            );
          }
        }
      }
    }
  });
}

class _ClipCounter extends TestRecordingCanvas {
  int clips = 0;

  @override
  void clipPath(Path path, {bool doAntiAlias = true}) {
    clips++;
  }
}
