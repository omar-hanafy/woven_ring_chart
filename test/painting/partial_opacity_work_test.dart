import 'dart:ui' show ColorSpace;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woven_ring_chart/src/model/chart_mode.dart';
import 'package:woven_ring_chart/src/painting/ring_painter.dart';
import 'package:woven_ring_chart/woven_ring_chart.dart';

void main() {
  test(
    'partial border composition has bounded layers and linear clip work',
    () {
      for (final int count in <int>[100, 300, 1000]) {
        for (final bool mixed in <bool>[false, true]) {
          for (final bool clockwise in <bool>[true, false]) {
            final _WorkCounter canvas = _WorkCounter();
            WovenRingChartPainter(
              segments: <WovenSegment>[
                for (var i = 0; i < count; i++)
                  WovenSegment.solid(
                    1,
                    const Color(0x80FF0000),
                    opacity: mixed && i.isEven ? 1 : .5,
                    border: const WovenBorder(color: Color(0xFF000000)),
                  ),
              ],
              fractions: List<double>.filled(count, 1 / count),
              style: WovenRingStyle(
                thicknessFraction: .3,
                overlapFraction: 1,
                clockwise: clockwise,
                surfaceColor: const Color(0x00000000),
              ),
              mode: WovenRingChartMode.data,
              animation: WovenRingAnimation.none,
              animationProgress: 1,
              spin: 0,
              highlightedIndex: null,
              highlightBorder: const WovenBorder(),
              topologyMerge: 0,
              topologyAnchor: null,
            ).paint(canvas, const Size.square(480));
            final String reason = 'n=$count mixed=$mixed clockwise=$clockwise';
            // One outer surface isolation, then two partial-border layers. A
            // mixed chart also retains the ordinary source-over border layer.
            expect(canvas.layers, mixed ? 4 : 3, reason: reason);
            expect(canvas.maxDepth, 2, reason: reason);
            expect(canvas.depth, 0, reason: reason);
            // The unchanged pruned owner masks cost at most six fill clips and
            // eight clips per border pass for each segment.
            expect(
              canvas.clips,
              lessThanOrEqualTo((mixed ? 30 : 22) * count),
              reason: reason,
            );
          }
        }
      }
    },
  );

  test('wide-gamut owner groups have bounded layers and clip work', () {
    for (final int count in <int>[100, 300, 1000]) {
      for (final bool mixed in <bool>[false, true]) {
        for (final bool shadow in <bool>[false, true]) {
          for (final bool clockwise in <bool>[true, false]) {
            final _WorkCounter canvas = _WorkCounter();
            WovenRingChartPainter(
              segments: <WovenSegment>[
                for (var i = 0; i < count; i++)
                  WovenSegment.solid(
                    1,
                    const Color(0x800000FF),
                    opacity: mixed && i % 3 == 2 ? 1 : .5,
                    border: WovenBorder(
                      color: !mixed || i % 3 == 0
                          ? const Color.from(
                              alpha: 1,
                              red: 0,
                              green: 1,
                              blue: 0,
                              colorSpace: ColorSpace.displayP3,
                            )
                          : const Color(0xFF000000),
                    ),
                  ),
              ],
              fractions: List<double>.filled(count, 1 / count),
              style: WovenRingStyle(
                thicknessFraction: .3,
                overlapFraction: 1,
                clockwise: clockwise,
                surfaceColor: const Color(0x00000000),
                shadow: shadow ? const WovenShadow() : null,
              ),
              mode: WovenRingChartMode.data,
              animation: WovenRingAnimation.none,
              animationProgress: 1,
              spin: 0,
              highlightedIndex: null,
              highlightBorder: const WovenBorder(),
              topologyMerge: 0,
              topologyAnchor: null,
            ).paint(canvas, const Size.square(480));
            final String reason =
                'n=$count mixed=$mixed shadow=$shadow clockwise=$clockwise';
            // Outer isolation + shared owner group, plus its nested shadow
            // correction when needed. The fallback handles every visible
            // owner, including ordinary colors, in these same shared layers.
            expect(canvas.layers, 2 + (shadow ? 1 : 0), reason: reason);
            expect(canvas.maxDepth, shadow ? 3 : 2, reason: reason);
            expect(canvas.depth, 0, reason: reason);
            // The fixed owner replays cost at most 20n clips without shadows.
            // Existing caster clipping plus
            // its two group replays and correction add at most28n.
            expect(
              canvas.clips,
              lessThanOrEqualTo((20 + (shadow ? 28 : 0)) * count),
              reason: reason,
            );
          }
        }
      }
    }
  });
}

class _WorkCounter extends TestRecordingCanvas {
  int clips = 0;
  int layers = 0;
  int depth = 0;
  int maxDepth = 0;
  final List<bool> _stack = <bool>[];

  @override
  void clipPath(Path path, {bool doAntiAlias = true}) {
    clips++;
  }

  @override
  void save() {
    _stack.add(false);
  }

  @override
  void saveLayer(Rect? bounds, Paint paint) {
    expect(bounds, const Rect.fromLTWH(0, 0, 480, 480));
    _stack.add(true);
    layers++;
    depth++;
    if (depth > maxDepth) maxDepth = depth;
  }

  @override
  void restore() {
    if (_stack.removeLast()) depth--;
  }
}
