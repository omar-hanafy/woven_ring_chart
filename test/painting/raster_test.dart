import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woven_ring_chart/woven_ring_chart.dart';

const double _side = 240;
const double _center = _side / 2;

void main() {
  testWidgets('the painted centerline has no gap at any joint or seam', (
    WidgetTester tester,
  ) async {
    for (final bool clockwise in <bool>[true, false]) {
      for (final double startAngle in <double>[-math.pi / 2, 0.217, 2.431]) {
        final _Raster raster = await _render(
          tester,
          WovenRingChart(
            animation: WovenRingAnimation.none,
            style: WovenRingStyle(startAngle: startAngle, clockwise: clockwise),
            segments: const <WovenSegment>[
              WovenSegment(value: 37, fill: WovenFill.solid(Color(0xFFE13D59))),
              WovenSegment(
                value: 19,
                fill: WovenFill.gradient(
                  head: Color(0xFF4FBF76),
                  tail: Color(0xFF168B55),
                ),
              ),
              WovenSegment(
                value: 29,
                fill: WovenFill.solid(Color(0xFF3978E6)),
                border: WovenBorder(color: Color(0xFFFFFFFF)),
              ),
              WovenSegment(value: 15, fill: WovenFill.solid(Color(0xFFF1A52B))),
            ],
          ),
        );

        final double trackRadius = WovenRingGeometry.forSize(
          const Size.square(_side),
          WovenRingStyle(startAngle: startAngle, clockwise: clockwise),
        ).trackRadius;
        var minimumAlpha = 255;
        var minimumAngle = 0.0;
        _Rgba minimumPixel = raster.at(0, 0);
        for (var sample = 0; sample < 2880; sample++) {
          final double angle = sample * math.pi * 2 / 2880;
          final _Rgba pixel = raster.atPolar(trackRadius, angle);
          if (pixel.alpha < minimumAlpha) {
            minimumAlpha = pixel.alpha;
            minimumAngle = angle;
            minimumPixel = pixel;
          }
        }
        expect(
          minimumAlpha,
          255,
          reason:
              'centerline gap at angle $minimumAngle '
              '(start=$startAngle, clockwise=$clockwise, '
              'pixel=$minimumPixel)',
        );
      }
    }
  });

  testWidgets('an inside border does not change the alpha silhouette', (
    WidgetTester tester,
  ) async {
    const List<WovenSegment> plain = <WovenSegment>[
      WovenSegment(value: 41, fill: WovenFill.solid(Color(0xFFD64263))),
      WovenSegment(value: 23, fill: WovenFill.solid(Color(0xFF20A273))),
      WovenSegment(value: 36, fill: WovenFill.solid(Color(0xFF426ED5))),
    ];
    const WovenBorder border = WovenBorder(
      color: Color(0xFFFFFEFC),
      widthFraction: 0.02,
    );
    const List<WovenSegment> bordered = <WovenSegment>[
      WovenSegment(
        value: 41,
        fill: WovenFill.solid(Color(0xFFD64263)),
        border: border,
      ),
      WovenSegment(
        value: 23,
        fill: WovenFill.solid(Color(0xFF20A273)),
        border: border,
      ),
      WovenSegment(
        value: 36,
        fill: WovenFill.solid(Color(0xFF426ED5)),
        border: border,
      ),
    ];
    const WovenRingStyle style = WovenRingStyle(
      thicknessFraction: 0.23,
      startAngle: 0.638,
    );

    final _Raster withoutBorders = await _render(
      tester,
      const WovenRingChart(
        segments: plain,
        style: style,
        animation: WovenRingAnimation.none,
      ),
    );
    final _Raster withBorders = await _render(
      tester,
      const WovenRingChart(
        segments: bordered,
        style: style,
        animation: WovenRingAnimation.none,
      ),
    );

    var mismatches = 0;
    for (var y = 0; y < withoutBorders.height; y++) {
      for (var x = 0; x < withoutBorders.width; x++) {
        // Compare occupied alpha support, not coverage strength. Painting an
        // opaque line over an antialiased edge can increase the same edge
        // pixel's alpha, but an inside border may not occupy any new pixel.
        final bool plainInside = withoutBorders.at(x, y).alpha > 0;
        final bool borderedInside = withBorders.at(x, y).alpha > 0;
        if (plainInside != borderedInside) mismatches++;
      }
    }
    expect(
      mismatches,
      0,
      reason: 'the border must be clipped wholly inside the segment silhouette',
    );
  });

  testWidgets(
    'mixed solid gradient bordered and borderless segments preserve one '
    'silhouette',
    (WidgetTester tester) async {
      const Color firstBorder = Color(0xFFFF00FF);
      const Color secondBorder = Color(0xFF00EFFF);
      const List<WovenSegment> styled = <WovenSegment>[
        WovenSegment(value: 31, fill: WovenFill.solid(Color(0xFFE83E66))),
        WovenSegment(
          value: 19,
          fill: WovenFill.gradient(
            head: Color(0xFF74E5AC),
            tail: Color(0xFF087C58),
          ),
          border: WovenBorder(color: firstBorder, widthFraction: 0.05),
        ),
        WovenSegment(
          value: 27,
          fill: WovenFill.solid(Color(0xFF376CDC)),
          border: WovenBorder(color: secondBorder, widthFraction: 0.05),
        ),
        WovenSegment(
          value: 23,
          fill: WovenFill.gradient(
            head: Color(0xFFFFD870),
            tail: Color(0xFFD36E08),
          ),
        ),
      ];
      final List<WovenSegment> borderless = <WovenSegment>[
        for (final WovenSegment segment in styled)
          segment.copyWith(removeBorder: true),
      ];

      for (final bool clockwise in <bool>[true, false]) {
        final WovenRingStyle style = WovenRingStyle(
          startAngle: 0.437,
          clockwise: clockwise,
        );
        final WovenRingGeometry geometry = WovenRingGeometry.forSize(
          const Size.square(_side),
          style,
        );
        final List<WovenSegmentExtent> extents = geometry.extents(
          wovenSegmentFractions(
            const <double>[31, 19, 27, 23],
            minimumFraction: geometry.minimumFraction,
            policy: style.smallValuePolicy,
          ),
          style.resolvedStartAngle,
          clockwise: clockwise,
        );
        final _Raster plainRaster = await _render(
          tester,
          WovenRingChart(
            segments: borderless,
            style: style,
            animation: WovenRingAnimation.none,
          ),
        );
        final _Raster styledRaster = await _render(
          tester,
          WovenRingChart(
            segments: styled,
            style: style,
            animation: WovenRingAnimation.none,
          ),
        );

        expect(
          _alphaSupportMismatches(plainRaster, styledRaster),
          0,
          reason:
              '${clockwise ? 'CW' : 'CCW'} mixed borders must stay inside '
              'the common segment silhouette',
        );
        _expectColor(
          styledRaster.atPolar(
            geometry.trackRadius,
            (extents[0].start + extents[0].end) / 2,
          ),
          styled[0].fill.head,
          reason: '${clockwise ? 'CW' : 'CCW'} solid body remains flat',
        );
        final _Rgba gradientEarly = styledRaster.atPolar(
          geometry.trackRadius,
          extents[1].start + (extents[1].end - extents[1].start) * 0.30,
        );
        final _Rgba gradientLate = styledRaster.atPolar(
          geometry.trackRadius,
          extents[1].start + (extents[1].end - extents[1].start) * 0.70,
        );
        expect(
          _opaqueColorDistance(gradientEarly, gradientLate),
          greaterThan(35),
          reason:
              '${clockwise ? 'CW' : 'CCW'} the per-segment gradient must '
              'remain visible beside solid fills',
        );

        final double direction = clockwise ? 1 : -1;
        for (final (int, Color) bordered in <(int, Color)>[
          (1, firstBorder),
          (2, secondBorder),
        ]) {
          final double angle = extents[bordered.$1].start;
          final Offset center = geometry.pointOn(geometry.trackRadius, angle);
          final Offset radial = Offset(math.cos(angle), math.sin(angle));
          final Offset tangent =
              Offset(-math.sin(angle), math.cos(angle)) * direction;
          final Offset target =
              center -
              tangent * geometry.capRadius * 0.62 +
              radial * geometry.capRadius * 0.67;
          expect(
            _hasColorNear(styledRaster, target, bordered.$2),
            isTrue,
            reason:
                '${clockwise ? 'CW' : 'CCW'} mixed border ${bordered.$1} '
                'must follow its rounded head',
          );
        }
      }
    },
  );

  testWidgets('selection adds only an inside border to the selected segment', (
    WidgetTester tester,
  ) async {
    const Color highlightColor = Color(0xFFFF00FF);
    const List<WovenSegment> segments = <WovenSegment>[
      WovenSegment(value: 28, fill: WovenFill.solid(WovenPalette.purple)),
      WovenSegment(value: 22, fill: WovenFill.solid(WovenPalette.rose)),
      WovenSegment(value: 31, fill: WovenFill.solid(WovenPalette.green)),
      WovenSegment(value: 19, fill: WovenFill.solid(WovenPalette.amber)),
    ];
    for (final bool clockwise in <bool>[true, false]) {
      final WovenRingStyle style = WovenRingStyle(
        startAngle: -0.263,
        clockwise: clockwise,
      );
      final WovenRingGeometry geometry = WovenRingGeometry.forSize(
        const Size.square(_side),
        style,
      );
      final List<WovenSegmentExtent> extents = geometry.extents(
        wovenSegmentFractions(
          const <double>[28, 22, 31, 19],
          minimumFraction: geometry.minimumFraction,
          policy: style.smallValuePolicy,
        ),
        style.resolvedStartAngle,
        clockwise: clockwise,
      );
      final _Raster plain = await _render(
        tester,
        WovenRingChart(
          segments: segments,
          style: style,
          animation: WovenRingAnimation.none,
        ),
      );
      final _Raster selected = await _render(
        tester,
        WovenRingChart(
          segments: segments,
          style: style,
          animation: WovenRingAnimation.none,
          highlightedIndex: 2,
          highlightBorder: const WovenBorder(
            color: highlightColor,
            widthFraction: 0.05,
          ),
        ),
      );
      expect(
        _alphaSupportMismatches(plain, selected),
        0,
        reason:
            '${clockwise ? 'CW' : 'CCW'} selection must not enlarge the '
            'ring silhouette',
      );

      final double direction = clockwise ? 1 : -1;
      for (var i = 0; i < extents.length; i++) {
        final double angle = extents[i].start;
        final Offset center = geometry.pointOn(geometry.trackRadius, angle);
        final Offset radial = Offset(math.cos(angle), math.sin(angle));
        final Offset tangent =
            Offset(-math.sin(angle), math.cos(angle)) * direction;
        final Offset target =
            center -
            tangent * geometry.capRadius * 0.62 +
            radial * geometry.capRadius * 0.67;
        expect(
          _hasColorNear(selected, target, highlightColor),
          i == 2,
          reason:
              '${clockwise ? 'CW' : 'CCW'} only selected segment 2 may '
              'carry the highlight border at head $i',
        );
      }
    }
  });

  testWidgets(
    'gradient caps and bodies form one continuous shader in both directions',
    (WidgetTester tester) async {
      const Color head = Color(0xFFFF1010);
      const Color tail = Color(0xFF1010FF);
      final List<String> violations = <String>[];
      for (final bool clockwise in <bool>[true, false]) {
        for (final WovenGradientDirection gradientDirection
            in WovenGradientDirection.values) {
          final WovenRingStyle style = WovenRingStyle(
            startAngle: 0.297,
            clockwise: clockwise,
            gradientDirection: gradientDirection,
          );
          final WovenRingGeometry geometry = WovenRingGeometry.forSize(
            const Size.square(_side),
            style,
          );
          final List<WovenSegmentExtent> extents = geometry.extents(
            wovenSegmentFractions(
              const <double>[55, 26, 19],
              minimumFraction: geometry.minimumFraction,
              policy: style.smallValuePolicy,
            ),
            style.resolvedStartAngle,
            clockwise: clockwise,
          );
          final WovenSegmentExtent extent = extents.first;
          final double direction = clockwise ? 1 : -1;
          final _Raster raster = await _render(
            tester,
            WovenRingChart(
              style: style,
              animation: WovenRingAnimation.none,
              segments: const <WovenSegment>[
                WovenSegment(
                  value: 55,
                  fill: WovenFill.gradient(head: head, tail: tail),
                ),
                WovenSegment(
                  value: 26,
                  fill: WovenFill.solid(WovenPalette.green),
                ),
                WovenSegment(
                  value: 19,
                  fill: WovenFill.solid(WovenPalette.amber),
                ),
              ],
            ),
          );
          final List<double> angles = <double>[
            extent.start - direction * geometry.capAngularExtent * 0.62,
            extent.start,
            extent.start + direction * geometry.capAngularExtent * 0.62,
            extent.start + (extent.end - extent.start) * 0.25,
            extent.start + (extent.end - extent.start) * 0.50,
          ];
          final List<_Rgba> samples = <_Rgba>[
            for (final double angle in angles)
              raster.atPolar(geometry.trackRadius, angle),
          ];
          final List<int> redMinusBlue = <int>[
            for (final _Rgba sample in samples) sample.red - sample.blue,
          ];
          final bool descends =
              gradientDirection == WovenGradientDirection.headToTail;
          for (var i = 1; i < redMinusBlue.length; i++) {
            final bool monotonic = descends
                ? redMinusBlue[i] <= redMinusBlue[i - 1] + 4
                : redMinusBlue[i] >= redMinusBlue[i - 1] - 4;
            if (!monotonic) {
              violations.add(
                '${clockwise ? 'CW' : 'CCW'} ${gradientDirection.name} '
                'shader reverses at sample $i: $redMinusBlue',
              );
              break;
            }
          }
          final _Rgba innerCap = raster.atPolar(
            geometry.trackRadius - geometry.capRadius * 0.62,
            extent.start,
          );
          final _Rgba outerCap = raster.atPolar(
            geometry.trackRadius + geometry.capRadius * 0.62,
            extent.start,
          );
          if (samples.any((_Rgba sample) => sample.alpha != 255) ||
              innerCap.alpha != 255 ||
              outerCap.alpha != 255 ||
              _opaqueColorDistance(innerCap, outerCap) > 4) {
            violations.add(
              '${clockwise ? 'CW' : 'CCW'} ${gradientDirection.name} '
              'cap/body continuity samples=$samples inner=$innerCap '
              'outer=$outerCap',
            );
          }
        }
      }
      expect(
        violations,
        isEmpty,
        reason:
            'the per-segment shader must shade the full rounded cap and continue '
            'monotonically into the body: ${violations.join('; ')}',
      );
    },
  );

  testWidgets(
    'across-thickness gradients preserve silhouette and radial shading',
    (WidgetTester tester) async {
      const List<WovenSegment> solid = <WovenSegment>[
        WovenSegment(value: 43, fill: WovenFill.solid(Color(0xFF7E45D7))),
        WovenSegment(value: 31, fill: WovenFill.solid(WovenPalette.green)),
        WovenSegment(value: 26, fill: WovenFill.solid(WovenPalette.amber)),
      ];
      const List<WovenSegment> gradient = <WovenSegment>[
        WovenSegment(
          value: 43,
          fill: WovenFill.gradient(
            head: Color(0xFFFF1010),
            tail: Color(0xFF1010FF),
          ),
        ),
        WovenSegment(value: 31, fill: WovenFill.solid(WovenPalette.green)),
        WovenSegment(value: 26, fill: WovenFill.solid(WovenPalette.amber)),
      ];
      for (final bool clockwise in <bool>[true, false]) {
        for (final WovenGradientDirection gradientDirection
            in WovenGradientDirection.values) {
          final WovenRingStyle style = WovenRingStyle(
            startAngle: -0.419,
            clockwise: clockwise,
            gradientAxis: WovenGradientAxis.acrossThickness,
            gradientDirection: gradientDirection,
          );
          final WovenRingGeometry geometry = WovenRingGeometry.forSize(
            const Size.square(_side),
            style,
          );
          final WovenSegmentExtent first = geometry
              .extents(
                wovenSegmentFractions(
                  const <double>[43, 31, 26],
                  minimumFraction: geometry.minimumFraction,
                  policy: style.smallValuePolicy,
                ),
                style.resolvedStartAngle,
                clockwise: clockwise,
              )
              .first;
          final _Raster solidRaster = await _render(
            tester,
            WovenRingChart(
              segments: solid,
              style: style,
              animation: WovenRingAnimation.none,
            ),
          );
          final _Raster gradientRaster = await _render(
            tester,
            WovenRingChart(
              segments: gradient,
              style: style,
              animation: WovenRingAnimation.none,
            ),
          );
          expect(
            _alphaSupportMismatches(solidRaster, gradientRaster),
            0,
            reason:
                '${clockwise ? 'CW' : 'CCW'} ${gradientDirection.name} '
                'across-thickness shading must not change the ring outline',
          );
          final double angle = first.start + (first.end - first.start) * 0.45;
          final _Rgba inner = gradientRaster.atPolar(
            geometry.innerRadius + geometry.thickness * 0.20,
            angle,
          );
          final _Rgba outer = gradientRaster.atPolar(
            geometry.innerRadius + geometry.thickness * 0.80,
            angle,
          );
          final bool headFirst =
              gradientDirection == WovenGradientDirection.headToTail;
          expect(
            headFirst ? outer.red - inner.red : inner.red - outer.red,
            greaterThan(80),
            reason:
                '${clockwise ? 'CW' : 'CCW'} ${gradientDirection.name} must '
                'shade consistently across the thickness (inner=$inner outer=$outer)',
          );
        }
      }
    },
  );

  testWidgets('a covered tail border stays hidden under a translucent head', (
    WidgetTester tester,
  ) async {
    const Color borderColor = Color(0xFFFFFFFF);
    const List<WovenSegment> plain = <WovenSegment>[
      WovenSegment(value: 34, fill: WovenFill.solid(WovenPalette.rose)),
      WovenSegment(
        value: 33,
        fill: WovenFill.solid(WovenPalette.green),
        opacity: 0.35,
      ),
      WovenSegment(value: 33, fill: WovenFill.solid(WovenPalette.purple)),
    ];
    const List<WovenSegment> bordered = <WovenSegment>[
      WovenSegment(
        value: 34,
        fill: WovenFill.solid(WovenPalette.rose),
        border: WovenBorder(color: borderColor, widthFraction: 0.05),
      ),
      WovenSegment(
        value: 33,
        fill: WovenFill.solid(WovenPalette.green),
        opacity: 0.35,
      ),
      WovenSegment(value: 33, fill: WovenFill.solid(WovenPalette.purple)),
    ];

    final List<String> violations = <String>[];
    for (final bool clockwise in <bool>[true, false]) {
      final WovenRingStyle style = WovenRingStyle(
        startAngle: 0.417,
        clockwise: clockwise,
      );
      final WovenRingGeometry geometry = WovenRingGeometry.forSize(
        const Size.square(_side),
        style,
      );
      final List<double> fractions = wovenSegmentFractions(
        const <double>[34, 33, 33],
        minimumFraction: geometry.minimumFraction,
        policy: style.smallValuePolicy,
      );
      final List<WovenSegmentExtent> extents = geometry.extents(
        fractions,
        style.resolvedStartAngle,
        clockwise: clockwise,
      );
      final Path predecessor = geometry.segmentPath(
        extents[0].start,
        extents[0].end,
        clockwise: clockwise,
      );
      final Path successor = geometry.segmentPath(
        extents[1].start,
        extents[1].end,
        clockwise: clockwise,
      );
      final _Raster withoutBorder = await _render(
        tester,
        WovenRingChart(
          segments: plain,
          style: style,
          animation: WovenRingAnimation.none,
        ),
      );
      final _Raster withBorder = await _render(
        tester,
        WovenRingChart(
          segments: bordered,
          style: style,
          animation: WovenRingAnimation.none,
        ),
      );

      var mismatches = 0;
      String? firstMismatch;
      for (var y = 0; y < withoutBorder.height; y++) {
        for (var x = 0; x < withoutBorder.width; x++) {
          final Offset center = Offset(x + 0.5, y + 0.5);
          if (!predecessor.contains(center) ||
              !_containsWithMargin(successor, center, 1.35)) {
            continue;
          }
          final _Rgba plainPixel = withoutBorder.at(x, y);
          final _Rgba borderedPixel = withBorder.at(x, y);
          if (_opaqueColorDistance(plainPixel, borderedPixel) <= 3 &&
              (plainPixel.alpha - borderedPixel.alpha).abs() <= 3) {
            continue;
          }
          mismatches++;
          firstMismatch ??=
              'xy=($x,$y) plain=$plainPixel bordered=$borderedPixel';
        }
      }
      if (mismatches > 0) {
        violations.add(
          '${clockwise ? 'CW' : 'CCW'} leaked border through the covered '
          'tail at $mismatches margin-safe successor-interior pixels; '
          'first $firstMismatch',
        );
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'a successor must geometrically suppress the predecessor tail '
          'border even while its opacity is animating: '
          '${violations.join('; ')}',
    );
  });

  testWidgets(
    'an arbitrary data start is preserved clockwise and counter-clockwise',
    (WidgetTester tester) async {
      const double start = 0.371;
      const Color first = Color(0xFFF02D48);
      const Color second = Color(0xFF16A66B);
      const Color third = Color(0xFF285DDA);
      const List<WovenSegment> segments = <WovenSegment>[
        WovenSegment(value: 40, fill: WovenFill.solid(first)),
        WovenSegment(value: 30, fill: WovenFill.solid(second)),
        WovenSegment(value: 30, fill: WovenFill.solid(third)),
      ];

      for (final bool clockwise in <bool>[true, false]) {
        const WovenRingStyle baseStyle = WovenRingStyle(
          thicknessFraction: 0.18,
          startAngle: start,
        );
        final WovenRingStyle style = baseStyle.copyWith(clockwise: clockwise);
        final _Raster raster = await _render(
          tester,
          WovenRingChart(
            segments: segments,
            style: style,
            animation: WovenRingAnimation.none,
          ),
        );
        final WovenRingGeometry geometry = WovenRingGeometry.forSize(
          const Size.square(_side),
          style,
        );
        final double direction = clockwise ? 1 : -1;

        _expectColor(
          raster.atPolar(geometry.trackRadius, start),
          first,
          reason: 'segment zero must own the requested data start',
        );
        _expectColor(
          raster.atPolar(
            geometry.trackRadius,
            start + direction * math.pi * 2 * 0.20,
          ),
          first,
          reason: 'first data interval points in the requested direction',
        );
        _expectColor(
          raster.atPolar(
            geometry.trackRadius,
            start + direction * math.pi * 2 * 0.55,
          ),
          second,
          reason: 'second data interval remains in input order',
        );
        _expectColor(
          raster.atPolar(
            geometry.trackRadius,
            start + direction * math.pi * 2 * 0.82,
          ),
          third,
          reason: 'third data interval remains in input order',
        );
        _expectColor(
          raster.atPolar(
            geometry.trackRadius,
            start - direction * math.pi * 2 * 0.10,
          ),
          third,
          reason: 'counter-clockwise must mirror, rather than rotate, the ring',
        );
      }
    },
  );

  testWidgets('two segments assign each joint to its successor head', (
    WidgetTester tester,
  ) async {
    const List<Color> colors = <Color>[WovenPalette.rose, WovenPalette.green];
    for (final List<double> values in <List<double>>[
      <double>[50, 50],
      <double>[90, 10],
    ]) {
      for (final bool clockwise in <bool>[true, false]) {
        final WovenRingStyle style = WovenRingStyle(
          startAngle: 0.413,
          clockwise: clockwise,
        );
        final WovenRingGeometry geometry = WovenRingGeometry.forSize(
          const Size.square(_side),
          style,
        );
        final List<double> fractions = wovenSegmentFractions(
          values,
          minimumFraction: geometry.minimumFraction,
          policy: style.smallValuePolicy,
        );
        final List<WovenSegmentExtent> extents = geometry.extents(
          fractions,
          style.resolvedStartAngle,
          clockwise: clockwise,
        );
        final List<Path> paths = <Path>[
          for (final WovenSegmentExtent extent in extents)
            geometry.segmentPath(
              extent.start,
              extent.end,
              clockwise: clockwise,
            ),
        ];
        final _Raster raster = await _render(
          tester,
          WovenRingChart(
            animation: WovenRingAnimation.none,
            style: style,
            segments: <WovenSegment>[
              WovenSegment.solid(values[0], colors[0]),
              WovenSegment.solid(values[1], colors[1]),
            ],
          ),
        );
        final double direction = clockwise ? 1 : -1;

        for (var owner = 0; owner < 2; owner++) {
          final (int, int)? sample = _findSharedInteriorPixel(
            paths: paths,
            geometry: geometry,
            targetAngle: extents[owner].start + direction * 0.10,
          );
          expect(
            sample,
            isNotNull,
            reason:
                '$values ${clockwise ? 'CW' : 'CCW'} joint $owner must '
                'contain a margin-safe overlap pixel',
          );
          _expectColor(
            raster.at(sample!.$1, sample.$2),
            colors[owner],
            reason:
                '$values ${clockwise ? 'CW' : 'CCW'} '
                '${owner == 0 ? 'cyclic seam' : 'opposite joint'} must be '
                'owned by segment $owner',
          );
        }
      }
    }
  });

  testWidgets('two-segment borders remain visible on both rounded heads', (
    WidgetTester tester,
  ) async {
    const List<Color> fills = <Color>[WovenPalette.rose, WovenPalette.green];
    const List<Color> borders = <Color>[Color(0xFFFF00FF), Color(0xFF00EFFF)];
    for (final bool clockwise in <bool>[true, false]) {
      final WovenRingStyle style = WovenRingStyle(
        startAngle: 0.271,
        clockwise: clockwise,
      );
      final WovenRingGeometry geometry = WovenRingGeometry.forSize(
        const Size.square(_side),
        style,
      );
      final List<double> fractions = wovenSegmentFractions(
        const <double>[50, 50],
        minimumFraction: geometry.minimumFraction,
        policy: style.smallValuePolicy,
      );
      final List<WovenSegmentExtent> extents = geometry.extents(
        fractions,
        style.resolvedStartAngle,
        clockwise: clockwise,
      );
      final _Raster raster = await _render(
        tester,
        WovenRingChart(
          animation: WovenRingAnimation.none,
          style: style,
          segments: <WovenSegment>[
            for (var i = 0; i < 2; i++)
              WovenSegment(
                value: 50,
                fill: WovenFill.solid(fills[i]),
                border: WovenBorder(color: borders[i], widthFraction: 0.05),
              ),
          ],
        ),
      );
      final double direction = clockwise ? 1 : -1;

      for (var owner = 0; owner < 2; owner++) {
        final double angle = extents[owner].start;
        final Offset center = geometry.pointOn(geometry.trackRadius, angle);
        final Offset radial = Offset(math.cos(angle), math.sin(angle));
        final Offset tangent =
            Offset(-math.sin(angle), math.cos(angle)) * direction;
        const double depthFraction = 0.65;
        final double depth = geometry.capRadius * depthFraction;
        final double chord =
            geometry.capRadius * math.sqrt(1 - depthFraction * depthFraction);
        final double insetScale =
            (geometry.capRadius - geometry.thickness * 0.018) /
            geometry.capRadius;
        for (final double side in <double>[-1, 1]) {
          final Offset target =
              center + (-tangent * depth + radial * chord * side) * insetScale;
          expect(
            _hasColorNear(raster, target, borders[owner]),
            isTrue,
            reason:
                '${clockwise ? 'CW' : 'CCW'} segment $owner must show its '
                'border on side $side of the rounded head',
          );
        }
      }
    }
  });

  testWidgets('two translucent heads fully suppress predecessor color', (
    WidgetTester tester,
  ) async {
    const double opacity = 0.35;
    for (final bool clockwise in <bool>[true, false]) {
      final WovenRingStyle style = WovenRingStyle(
        startAngle: 0.389,
        clockwise: clockwise,
      );
      final WovenRingGeometry geometry = WovenRingGeometry.forSize(
        const Size.square(_side),
        style,
      );
      final List<WovenSegmentExtent> extents = geometry.extents(
        wovenSegmentFractions(
          const <double>[50, 50],
          minimumFraction: geometry.minimumFraction,
          policy: style.smallValuePolicy,
        ),
        style.resolvedStartAngle,
        clockwise: clockwise,
      );
      final List<Path> paths = <Path>[
        for (final WovenSegmentExtent extent in extents)
          geometry.segmentPath(extent.start, extent.end, clockwise: clockwise),
      ];
      final double direction = clockwise ? 1 : -1;

      for (var owner = 0; owner < 2; owner++) {
        final Color topFill = owner == 0
            ? WovenPalette.rose
            : WovenPalette.green;
        final List<Color> firstFills = owner == 0
            ? <Color>[topFill, WovenPalette.purple]
            : <Color>[WovenPalette.rose, topFill];
        final List<Color> secondFills = owner == 0
            ? <Color>[topFill, WovenPalette.amber]
            : <Color>[WovenPalette.blue, topFill];
        List<WovenSegment> segments(List<Color> colors) => <WovenSegment>[
          for (var i = 0; i < 2; i++)
            WovenSegment(
              value: 50,
              fill: WovenFill.solid(colors[i]),
              opacity: i == owner ? opacity : 1,
            ),
        ];
        final _Raster first = await _render(
          tester,
          WovenRingChart(
            segments: segments(firstFills),
            style: style,
            animation: WovenRingAnimation.none,
          ),
        );
        final _Raster second = await _render(
          tester,
          WovenRingChart(
            segments: segments(secondFills),
            style: style,
            animation: WovenRingAnimation.none,
          ),
        );
        final (int, int)? sample = _findSharedInteriorPixel(
          paths: paths,
          geometry: geometry,
          targetAngle: extents[owner].start + direction * 0.10,
        );
        expect(sample, isNotNull);
        final _Rgba firstPixel = first.at(sample!.$1, sample.$2);
        final _Rgba secondPixel = second.at(sample.$1, sample.$2);
        final _Rgba expected = _rgbaOf(
          _blendOver(topFill, opacity, style.surfaceColor),
        );
        expect(
          firstPixel.alpha == 255 &&
              secondPixel.alpha == 255 &&
              _opaqueColorDistance(firstPixel, secondPixel) <= 3 &&
              _opaqueColorDistance(firstPixel, expected) <= 3,
          isTrue,
          reason:
              '${clockwise ? 'CW' : 'CCW'} translucent segment $owner must '
              'paint over the surfaceColor, independent of predecessor color '
              '(first=$firstPixel, second=$secondPixel, expected=$expected)',
        );
      }
    }
  });

  testWidgets(
    'translucent fill colors suppress predecessor color at ordinary and '
    'cyclic joints',
    (WidgetTester tester) async {
      const double startAngle = 0.389;
      const List<double> values = <double>[29, 21, 27, 23];
      const Color hostilePredecessor = Color(0xFF08111F);
      const List<WovenFill> translucentFills = <WovenFill>[
        WovenFill.solid(Color(0x66F04472)),
        WovenFill.gradient(head: Color(0x66FF7AA1), tail: Color(0x666927DB)),
      ];
      final List<String> violations = <String>[];

      for (final bool clockwise in <bool>[true, false]) {
        final WovenRingStyle style = WovenRingStyle(
          startAngle: startAngle,
          clockwise: clockwise,
        );
        final WovenRingGeometry geometry = WovenRingGeometry.forSize(
          const Size.square(_side),
          style,
        );
        final List<WovenSegmentExtent> extents = geometry.extents(
          wovenSegmentFractions(
            values,
            minimumFraction: geometry.minimumFraction,
            policy: style.smallValuePolicy,
          ),
          style.resolvedStartAngle,
          clockwise: clockwise,
        );
        final List<Path> paths = <Path>[
          for (final WovenSegmentExtent extent in extents)
            geometry.segmentPath(
              extent.start,
              extent.end,
              clockwise: clockwise,
            ),
        ];
        final double direction = clockwise ? 1 : -1;

        for (final WovenFill fill in translucentFills) {
          for (final int owner in <int>[0, 2]) {
            final int predecessor = (owner - 1 + values.length) % values.length;
            final _InteriorPixel? sample = _findInteriorPixel(
              paths: paths,
              geometry: geometry,
              targetAngle: extents[owner].start + direction * 0.10,
            );
            expect(
              sample,
              isNotNull,
              reason: 'the joint probe must have stable cyclic ownership',
            );
            expect(sample!.owner, owner);
            expect(sample.covered, contains(predecessor));

            List<WovenSegment> segments(Color predecessorFill) =>
                <WovenSegment>[
                  for (var i = 0; i < values.length; i++)
                    WovenSegment(
                      value: values[i],
                      fill: i == owner
                          ? fill
                          : WovenFill.solid(
                              i == predecessor
                                  ? predecessorFill
                                  : style.surfaceColor,
                            ),
                    ),
                ];

            final _Raster surfaceBaseline = await _render(
              tester,
              WovenRingChart(
                segments: segments(style.surfaceColor),
                style: style,
                animation: WovenRingAnimation.none,
              ),
            );
            final _Raster hostileBackground = await _render(
              tester,
              WovenRingChart(
                segments: segments(hostilePredecessor),
                style: style,
                animation: WovenRingAnimation.none,
              ),
            );
            final _Rgba baselinePixel = surfaceBaseline.at(sample.x, sample.y);
            final _Rgba hostilePixel = hostileBackground.at(sample.x, sample.y);
            final int distance = _rgbaDistance(baselinePixel, hostilePixel);
            if (baselinePixel.alpha != 255 ||
                hostilePixel.alpha != 255 ||
                distance > 3) {
              violations.add(
                '${clockwise ? 'CW' : 'CCW'} '
                '${fill.isSolid ? 'solid' : 'gradient'} '
                '${owner == 0 ? 'cyclic' : 'ordinary'} joint owner=$owner '
                'depends on predecessor: surfaceColor=$baselinePixel '
                'hostile=$hostilePixel distance=$distance',
              );
            }
          }
        }
      }

      expect(
        violations,
        isEmpty,
        reason:
            'fill alpha is part of effective segment translucency even when '
            'segment.opacity is 1. The visible owner must blend once over the '
            'surfaceColor and remain independent of paint order. Failures: '
            '${violations.join('; ')}',
      );
    },
  );

  testWidgets(
    'two-segment shadow appears under both heads and never in the hole',
    (WidgetTester tester) async {
      const WovenShadow visibleShadow = WovenShadow(
        color: Color(0x66000000),
        blurFraction: 0.08,
        offsetFraction: 0.12,
      );
      const WovenShadow transparentShadow = WovenShadow(
        color: Color(0x00000000),
        blurFraction: 0.08,
        offsetFraction: 0.12,
      );
      const List<WovenSegment> segments = <WovenSegment>[
        WovenSegment(value: 50, fill: WovenFill.solid(WovenPalette.rose)),
        WovenSegment(value: 50, fill: WovenFill.solid(WovenPalette.green)),
      ];

      for (final bool clockwise in <bool>[true, false]) {
        final WovenRingStyle visibleStyle = WovenRingStyle(
          startAngle: 0.327,
          clockwise: clockwise,
          shadow: visibleShadow,
        );
        final WovenRingStyle baselineStyle = visibleStyle.copyWith(
          shadow: transparentShadow,
        );
        final WovenRingGeometry geometry = WovenRingGeometry.forSize(
          const Size.square(_side),
          visibleStyle,
        );
        final List<WovenSegmentExtent> extents = geometry.extents(
          wovenSegmentFractions(
            const <double>[50, 50],
            minimumFraction: geometry.minimumFraction,
            policy: visibleStyle.smallValuePolicy,
          ),
          visibleStyle.resolvedStartAngle,
          clockwise: clockwise,
        );
        final List<Path> paths = <Path>[
          for (final WovenSegmentExtent extent in extents)
            geometry.segmentPath(
              extent.start,
              extent.end,
              clockwise: clockwise,
            ),
        ];
        final _Raster baseline = await _render(
          tester,
          WovenRingChart(
            segments: segments,
            style: baselineStyle,
            animation: WovenRingAnimation.none,
          ),
        );
        final _Raster shadowed = await _render(
          tester,
          WovenRingChart(
            segments: segments,
            style: visibleStyle,
            animation: WovenRingAnimation.none,
          ),
        );

        for (var owner = 0; owner < 2; owner++) {
          final Offset head = geometry.pointOn(
            geometry.trackRadius,
            extents[owner].start,
          );
          final Path predecessor = paths[1 - owner];
          final Path current = paths[owner];
          var changedPixels = 0;
          for (var y = 0; y < shadowed.height; y++) {
            for (var x = 0; x < shadowed.width; x++) {
              final Offset point = Offset(x + 0.5, y + 0.5);
              if ((point - head).distance > geometry.capRadius * 1.7 ||
                  !predecessor.contains(point) ||
                  current.contains(point)) {
                continue;
              }
              if (_rgbaDistance(baseline.at(x, y), shadowed.at(x, y)) > 3) {
                changedPixels++;
              }
            }
          }
          expect(
            changedPixels,
            greaterThan(5),
            reason:
                '${clockwise ? 'CW' : 'CCW'} head $owner must cast visible '
                'shadow onto its predecessor (changed=$changedPixels)',
          );
        }

        var holeLeakPixels = 0;
        for (var y = 0; y < shadowed.height; y++) {
          for (var x = 0; x < shadowed.width; x++) {
            final Offset point = Offset(x + 0.5, y + 0.5);
            if ((point - geometry.center).distance < geometry.innerRadius - 3 &&
                shadowed.at(x, y).alpha > 0) {
              holeLeakPixels++;
            }
          }
        }
        expect(
          holeLeakPixels,
          0,
          reason: '${clockwise ? 'CW' : 'CCW'} shadow must not enter the hole',
        );
      }
    },
  );

  testWidgets('the stable data-order seam covers its cyclic predecessor tail', (
    WidgetTester tester,
  ) async {
    final List<_SeamCase> cases = <_SeamCase>[
      const _SeamCase(
        name: 'enforced tiny value',
        values: <double>[0.3, 39.7, 25, 35],
        colors: WovenPalette.quartet,
        style: WovenRingStyle(
          startAngle: 0.413,
          smallValuePolicy: WovenSmallValuePolicy.enforce,
        ),
      ),
      const _SeamCase(
        name: 'highlightedIndex ten-segment non-cardinal CCW',
        values: <double>[10, 9, 11, 8, 12, 10, 9, 11, 8, 12],
        colors: WovenPalette.extended,
        style: WovenRingStyle(
          startAngle: math.pi / 8,
          clockwise: false,
          smallValuePolicy: WovenSmallValuePolicy.enforce,
        ),
      ),
      const _SeamCase(
        name: 'ten equal segments CW',
        values: <double>[10, 10, 10, 10, 10, 10, 10, 10, 10, 10],
        colors: WovenPalette.extended,
        style: WovenRingStyle(startAngle: -0.731),
      ),
      const _SeamCase(
        name: 'ten equal segments CCW',
        values: <double>[10, 10, 10, 10, 10, 10, 10, 10, 10, 10],
        colors: WovenPalette.extended,
        style: WovenRingStyle(startAngle: 0.917, clockwise: false),
      ),
    ];

    for (final _SeamCase seamCase in cases) {
      final List<WovenSegment> segments = <WovenSegment>[
        for (var i = 0; i < seamCase.values.length; i++)
          WovenSegment.solid(seamCase.values[i], seamCase.colors[i]),
      ];
      final WovenRingGeometry geometry = WovenRingGeometry.forSize(
        const Size.square(_side),
        seamCase.style,
      );
      final List<double> fractions = wovenSegmentFractions(
        seamCase.values,
        minimumFraction: geometry.minimumFraction,
        policy: seamCase.style.smallValuePolicy,
      );
      final List<WovenSegmentExtent> extents = geometry.extents(
        fractions,
        seamCase.style.resolvedStartAngle,
        clockwise: seamCase.style.clockwise,
      );
      final int predecessor = seamCase.values.length - 1;
      final _Raster raster = await _render(
        tester,
        WovenRingChart(
          segments: segments,
          style: seamCase.style,
          animation: WovenRingAnimation.none,
        ),
      );

      final double direction = seamCase.style.clockwise ? 1 : -1;
      // Segment 0 owns the simple overlap with the last tail. Dense rings also
      // have a three-way region where segment 1 overlaps both of them; there the
      // normal successor rule wins, so segment 1 must remain above segment 0.
      _expectColor(
        raster.atPolar(
          geometry.trackRadius,
          extents.first.start + direction * 0.10,
        ),
        seamCase.colors.first,
        reason:
            '${seamCase.name}: segment 0 must cover predecessor $predecessor '
            'in the simple cyclic seam overlap',
      );
      _expectColor(
        raster.atPolar(
          geometry.trackRadius,
          extents[1].start - direction * geometry.capAngularExtent * 0.55,
        ),
        seamCase.colors[1],
        reason:
            '${seamCase.name}: segment 1 must stay over segment 0 and predecessor '
            '$predecessor in the three-way overlap',
      );

      final List<Path> paths = <Path>[
        for (final WovenSegmentExtent extent in extents)
          geometry.segmentPath(
            extent.start,
            extent.end,
            clockwise: seamCase.style.clockwise,
          ),
      ];
      final _InteriorPixel? trailingTriple = _findInteriorPixel(
        paths: paths,
        geometry: geometry,
        targetAngle:
            extents.first.start - direction * geometry.capAngularExtent * 0.30,
      );
      expect(
        trailingTriple,
        isNotNull,
        reason:
            '${seamCase.name}: trailing seam probe needs an opaque interior '
            'pixel',
      );
      _expectColor(
        raster.at(trailingTriple!.x, trailingTriple.y),
        seamCase.colors[trailingTriple.owner],
        reason:
            '${seamCase.name}: the furthest cyclic successor must own the '
            'trailing seam overlap ${trailingTriple.covered}',
      );
    }
  });

  testWidgets(
    'a segment gradient is stationary while the sweep head advances',
    (WidgetTester tester) async {
      const double start = -0.83;
      const WovenRingStyle style = WovenRingStyle(
        startAngle: start,
        gradientAxis: WovenGradientAxis.alongSegment,
        gradientDirection: WovenGradientDirection.headToTail,
      );
      final GlobalKey boundaryKey = GlobalKey();
      await _pumpRing(
        tester,
        boundaryKey,
        const WovenRingChart(
          animationDuration: Duration(milliseconds: 1000),
          animation: WovenRingAnimation.sweep,
          style: style,
          segments: <WovenSegment>[
            WovenSegment(
              value: 60,
              fill: WovenFill.gradient(
                head: Color(0xFFFF3B4F),
                tail: Color(0xFF4424DB),
              ),
            ),
            WovenSegment(
              value: 40,
              fill: WovenFill.gradient(
                head: Color(0xFF65D97C),
                tail: Color(0xFF087C58),
              ),
            ),
          ],
        ),
      );
      final WovenRingGeometry geometry = WovenRingGeometry.forSize(
        const Size.square(_side),
        style,
      );
      final double sampleAngle = start + math.pi * 2 * 0.10;

      await tester.pump(const Duration(milliseconds: 400));
      final _Rgba earlier = (await _capture(
        tester,
        boundaryKey,
      )).atPolar(geometry.trackRadius, sampleAngle);
      await tester.pump(const Duration(milliseconds: 200));
      final _Rgba later = (await _capture(
        tester,
        boundaryKey,
      )).atPolar(geometry.trackRadius, sampleAngle);

      expect(earlier.alpha, 255);
      expect(later, earlier);
      expect(
        earlier.red > 20 && earlier.blue > 20,
        isTrue,
        reason: 'the sampled pixel should be inside the per-segment gradient',
      );
    },
  );

  testWidgets(
    'a single gradient traverses the full ring in both directions and modes',
    (WidgetTester tester) async {
      const Color head = Color(0xFFFF0000);
      const Color tail = Color(0xFF0000FF);
      const double start = -0.217;
      final List<String> violations = <String>[];

      for (final WovenSingleSegmentStyle singleStyle
          in WovenSingleSegmentStyle.values) {
        for (final bool clockwise in <bool>[true, false]) {
          for (final WovenGradientDirection gradientDirection
              in WovenGradientDirection.values) {
            final WovenRingStyle style = WovenRingStyle(
              startAngle: start,
              clockwise: clockwise,
              gradientDirection: gradientDirection,
              singleSegmentStyle: singleStyle,
            );
            final _Raster raster = await _render(
              tester,
              WovenRingChart(
                animation: WovenRingAnimation.none,
                style: style,
                segments: const <WovenSegment>[
                  WovenSegment(
                    value: 100,
                    fill: WovenFill.gradient(head: head, tail: tail),
                  ),
                ],
              ),
            );
            final WovenRingGeometry geometry = WovenRingGeometry.forSize(
              const Size.square(_side),
              style,
            );
            final double direction = clockwise ? 1 : -1;
            final _Rgba quarter = raster.atPolar(
              geometry.trackRadius,
              start + direction * math.pi / 2,
            );
            final _Rgba middle = raster.atPolar(
              geometry.trackRadius,
              start + direction * math.pi,
            );
            final _Rgba threeQuarter = raster.atPolar(
              geometry.trackRadius,
              start + direction * math.pi * 3 / 2,
            );
            final bool headFirst =
                gradientDirection == WovenGradientDirection.headToTail;
            final _Rgba early = headFirst ? quarter : threeQuarter;
            final _Rgba late = headFirst ? threeQuarter : quarter;
            final String context =
                '${singleStyle.name} ${clockwise ? 'CW' : 'CCW'} '
                '${gradientDirection.name}';

            if (quarter.alpha != 255 ||
                middle.alpha != 255 ||
                threeQuarter.alpha != 255) {
              violations.add(
                '$context samples are not opaque: quarter=$quarter, '
                'middle=$middle, 3/4=$threeQuarter',
              );
              continue;
            }
            if (early.red - early.blue <= 50) {
              violations.add(
                '$context first quarter is not on the head-color side: '
                'quarter=$quarter, middle=$middle, 3/4=$threeQuarter',
              );
            }
            if (late.blue - late.red <= 50) {
              violations.add(
                '$context third quarter is not on the tail-color side: '
                'quarter=$quarter, middle=$middle, 3/4=$threeQuarter',
              );
            }
            if ((middle.red - middle.blue).abs() >= 35) {
              violations.add(
                '$context halfway point does not contain both endpoint '
                'colors: quarter=$quarter, middle=$middle, '
                '3/4=$threeQuarter',
              );
            }
          }
        }
      }

      expect(
        violations,
        isEmpty,
        reason:
            'single gradients must cover and shade one full turn. Failures: '
            '${violations.join('; ')}',
      );
    },
  );

  testWidgets('a 90 percent gradient does not collapse after crossing zero', (
    WidgetTester tester,
  ) async {
    const Color head = Color(0xFFFF0000);
    const Color tail = Color(0xFF0000FF);
    final List<String> violations = <String>[];

    for (final bool clockwise in <bool>[true, false]) {
      for (final WovenGradientDirection gradientDirection
          in WovenGradientDirection.values) {
        final WovenRingStyle style = WovenRingStyle(
          startAngle: -0.317,
          clockwise: clockwise,
          gradientDirection: gradientDirection,
        );
        final WovenRingGeometry geometry = WovenRingGeometry.forSize(
          const Size.square(_side),
          style,
        );
        final List<double> fractions = wovenSegmentFractions(
          const <double>[90, 10],
          minimumFraction: geometry.minimumFraction,
          policy: style.smallValuePolicy,
        );
        final WovenSegmentExtent extent = geometry
            .extents(fractions, style.resolvedStartAngle, clockwise: clockwise)
            .first;
        final _Raster raster = await _render(
          tester,
          WovenRingChart(
            animation: WovenRingAnimation.none,
            style: style,
            segments: const <WovenSegment>[
              WovenSegment(
                value: 90,
                fill: WovenFill.gradient(head: head, tail: tail),
              ),
              WovenSegment(
                value: 10,
                fill: WovenFill.solid(WovenPalette.green),
              ),
            ],
          ),
        );
        final _Rgba quarter = raster.atPolar(
          geometry.trackRadius,
          extent.start + (extent.end - extent.start) * 0.25,
        );
        final _Rgba middle = raster.atPolar(
          geometry.trackRadius,
          extent.start + (extent.end - extent.start) * 0.50,
        );
        final _Rgba threeQuarter = raster.atPolar(
          geometry.trackRadius,
          extent.start + (extent.end - extent.start) * 0.75,
        );
        final bool headFirst =
            gradientDirection == WovenGradientDirection.headToTail;
        final _Rgba early = headFirst ? quarter : threeQuarter;
        final _Rgba late = headFirst ? threeQuarter : quarter;
        final String context =
            '${clockwise ? 'CW' : 'CCW'} ${gradientDirection.name}';
        if (quarter.alpha != 255 ||
            middle.alpha != 255 ||
            threeQuarter.alpha != 255 ||
            early.red - early.blue <= 50 ||
            late.blue - late.red <= 50 ||
            (middle.red - middle.blue).abs() >= 35) {
          violations.add(
            '$context quarter=$quarter middle=$middle '
            '3/4=$threeQuarter',
          );
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'a large per-segment sweep must preserve the full gradient after '
          'crossing zero: ${violations.join('; ')}',
    );
  });

  for (final _TransitionCase transitionCase in <_TransitionCase>[
    const _TransitionCase(
      name: 'tiny enforced',
      currentValues: <double>[0.3, 39.7, 25, 35],
      alternateValues: <double>[0.3, 30, 42, 27.7],
      colors: WovenPalette.quartet,
      startAngle: -math.pi / 2,
    ),
    const _TransitionCase(
      name: 'extended',
      currentValues: <double>[10, 9, 11, 8, 12, 10, 9, 11, 8, 12],
      alternateValues: <double>[6, 14, 8, 12, 9, 15, 7, 11, 10, 8],
      colors: WovenPalette.extended,
      startAngle: math.pi / 8,
    ),
  ]) {
    for (final bool clockwise in <bool>[true, false]) {
      testWidgets('${transitionCase.name} data transition stays woven '
          '${clockwise ? 'CW' : 'CCW'}', (WidgetTester tester) async {
        const Duration duration = Duration(milliseconds: 480);
        final WovenRingStyle style = WovenRingStyle(
          startAngle: transitionCase.startAngle,
          clockwise: clockwise,
          smallValuePolicy: WovenSmallValuePolicy.enforce,
        );
        final List<WovenSegment> current = transitionCase.segments(
          alternate: false,
        );
        final List<WovenSegment> alternate = transitionCase.segments(
          alternate: true,
        );
        final GlobalKey boundaryKey = GlobalKey();
        await _pumpRing(
          tester,
          boundaryKey,
          WovenRingChart(
            segments: current,
            style: style,
            animation: WovenRingAnimation.none,
            transitionDuration: duration,
          ),
        );

        final _TransitionResult forward = await _scanDataTransition(
          tester: tester,
          boundaryKey: boundaryKey,
          from: current,
          to: alternate,
          style: style,
          duration: duration,
          label: 'current->alternate',
        );
        final _TransitionResult reverse = await _scanDataTransition(
          tester: tester,
          boundaryKey: boundaryKey,
          from: alternate,
          to: current,
          style: style,
          duration: duration,
          label: 'alternate->current',
        );
        final List<String> violations = <String>[
          ...forward.violations,
          ...reverse.violations,
        ];

        expect(
          violations,
          isEmpty,
          reason:
              '${transitionCase.name} ${clockwise ? 'CW' : 'CCW'} '
              'transition must preserve opaque coverage and cyclic joint '
              'ownership. First failures: '
              '${violations.take(12).join('; ')}. '
              'Forward deltas=${forward.frameDeltas}; '
              'reverse deltas=${reverse.frameDeltas}',
        );
      });
    }
  }

  for (final _TopologyTransitionCase transitionCase
      in <_TopologyTransitionCase>[
        _TopologyTransitionCase(
          name: 'enforced 3-to-4 entrant',
          from: <WovenSegment>[
            WovenSegment.solid(40, WovenPalette.purple),
            WovenSegment.solid(35, WovenPalette.rose),
            WovenSegment.solid(25, WovenPalette.green),
          ],
          to: <WovenSegment>[
            WovenSegment.solid(32, WovenPalette.purple),
            WovenSegment.solid(28, WovenPalette.rose),
            WovenSegment.solid(20, WovenPalette.green),
            WovenSegment.solid(20, WovenPalette.amber),
          ],
          smallValuePolicy: WovenSmallValuePolicy.enforce,
          checkCyclicOwnership: true,
        ),
        _TopologyTransitionCase(
          name: 'allowVanish threshold crossing',
          from: <WovenSegment>[
            WovenSegment.solid(1, WovenPalette.amber),
            WovenSegment.solid(33, WovenPalette.purple),
            WovenSegment.solid(33, WovenPalette.rose),
            WovenSegment.solid(33, WovenPalette.green),
          ],
          to: <WovenSegment>[
            WovenSegment.solid(6, WovenPalette.amber),
            WovenSegment.solid(31.34, WovenPalette.purple),
            WovenSegment.solid(31.33, WovenPalette.rose),
            WovenSegment.solid(31.33, WovenPalette.green),
          ],
          smallValuePolicy: WovenSmallValuePolicy.allowVanish,
          checkCyclicOwnership: true,
        ),
        _TopologyTransitionCase(
          name: 'data-to-all-zero',
          from: <WovenSegment>[
            WovenSegment.solid(42, WovenPalette.purple),
            WovenSegment.solid(33, WovenPalette.rose),
            WovenSegment.solid(25, WovenPalette.green),
          ],
          to: <WovenSegment>[
            WovenSegment.solid(0, WovenPalette.purple),
            WovenSegment.solid(0, WovenPalette.rose),
            WovenSegment.solid(0, WovenPalette.green),
          ],
          smallValuePolicy: WovenSmallValuePolicy.enforce,
          minimumAlpha: 128,
          // Dissolving into the neutral empty track means no pixel carries a
          // segment's own colour any more, so owner colours cannot be compared.
          checkCyclicOwnership: false,
        ),
        _TopologyTransitionCase(
          name: 'one-to-three',
          from: <WovenSegment>[WovenSegment.solid(100, WovenPalette.purple)],
          to: <WovenSegment>[
            WovenSegment.solid(34, WovenPalette.purple),
            WovenSegment.solid(33, WovenPalette.rose),
            WovenSegment.solid(33, WovenPalette.green),
          ],
          smallValuePolicy: WovenSmallValuePolicy.enforce,
          checkCyclicOwnership: true,
        ),
        _TopologyTransitionCase(
          name: 'three-to-one',
          from: <WovenSegment>[
            WovenSegment.solid(34, WovenPalette.purple),
            WovenSegment.solid(33, WovenPalette.rose),
            WovenSegment.solid(33, WovenPalette.green),
          ],
          to: <WovenSegment>[WovenSegment.solid(100, WovenPalette.purple)],
          smallValuePolicy: WovenSmallValuePolicy.enforce,
          checkCyclicOwnership: true,
        ),
        const _TopologyTransitionCase(
          name: 'styled one-to-three',
          from: <WovenSegment>[
            WovenSegment(
              value: 100,
              fill: WovenFill.gradient(
                head: Color(0xFFF06A91),
                tail: Color(0xFF7F2FDC),
              ),
              border: WovenBorder(
                color: Color(0xFFFFFFFF),
                widthFraction: 0.05,
              ),
            ),
          ],
          to: <WovenSegment>[
            WovenSegment(
              value: 34,
              fill: WovenFill.gradient(
                head: Color(0xFFF06A91),
                tail: Color(0xFF7F2FDC),
              ),
              border: WovenBorder(
                color: Color(0xFFFFFFFF),
                widthFraction: 0.05,
              ),
            ),
            WovenSegment(
              value: 33,
              fill: WovenFill.gradient(
                head: Color(0xFF6EE7AE),
                tail: Color(0xFF087C58),
              ),
              border: WovenBorder(
                color: Color(0xFFFFF2C7),
                widthFraction: 0.05,
              ),
            ),
            WovenSegment(
              value: 33,
              fill: WovenFill.gradient(
                head: Color(0xFF74B5FF),
                tail: Color(0xFF23385C),
              ),
              border: WovenBorder(
                color: Color(0xFFFFD7E6),
                widthFraction: 0.05,
              ),
            ),
          ],
          smallValuePolicy: WovenSmallValuePolicy.enforce,
          shadow: WovenShadow(
            color: Color(0x33000000),
            blurFraction: 0.08,
            offsetFraction: 0.08,
          ),
          checkCyclicOwnership: false,
        ),
        const _TopologyTransitionCase(
          name: 'styled three-to-one',
          from: <WovenSegment>[
            WovenSegment(
              value: 34,
              fill: WovenFill.gradient(
                head: Color(0xFFF06A91),
                tail: Color(0xFF7F2FDC),
              ),
              border: WovenBorder(
                color: Color(0xFFFFFFFF),
                widthFraction: 0.05,
              ),
            ),
            WovenSegment(
              value: 33,
              fill: WovenFill.gradient(
                head: Color(0xFF6EE7AE),
                tail: Color(0xFF087C58),
              ),
              border: WovenBorder(
                color: Color(0xFFFFF2C7),
                widthFraction: 0.05,
              ),
            ),
            WovenSegment(
              value: 33,
              fill: WovenFill.gradient(
                head: Color(0xFF74B5FF),
                tail: Color(0xFF23385C),
              ),
              border: WovenBorder(
                color: Color(0xFFFFD7E6),
                widthFraction: 0.05,
              ),
            ),
          ],
          to: <WovenSegment>[
            WovenSegment(
              value: 100,
              fill: WovenFill.gradient(
                head: Color(0xFFF06A91),
                tail: Color(0xFF7F2FDC),
              ),
              border: WovenBorder(
                color: Color(0xFFFFFFFF),
                widthFraction: 0.05,
              ),
            ),
          ],
          smallValuePolicy: WovenSmallValuePolicy.enforce,
          shadow: WovenShadow(
            color: Color(0x33000000),
            blurFraction: 0.08,
            offsetFraction: 0.08,
          ),
          checkCyclicOwnership: false,
        ),
      ]) {
    for (final bool clockwise in <bool>[true, false]) {
      testWidgets('${transitionCase.name} has continuous raster topology '
          '${clockwise ? 'CW' : 'CCW'}', (WidgetTester tester) async {
        const Duration duration = Duration(milliseconds: 480);
        final WovenRingStyle style = WovenRingStyle(
          startAngle: 0.287,
          clockwise: clockwise,
          smallValuePolicy: transitionCase.smallValuePolicy,
          shadow: transitionCase.shadow,
        );
        final GlobalKey boundaryKey = GlobalKey();
        final _TransitionResult result = await _scanTopologyTransition(
          tester: tester,
          boundaryKey: boundaryKey,
          from: transitionCase.from,
          to: transitionCase.to,
          style: style,
          duration: duration,
          label: transitionCase.name,
          minimumAlpha: transitionCase.minimumAlpha,
          checkCyclicOwnership: transitionCase.checkCyclicOwnership,
        );

        expect(
          result.violations,
          isEmpty,
          reason:
              '${transitionCase.name} ${clockwise ? 'CW' : 'CCW'} must '
              'remain covered and move continuously from the immediate '
              'update through every animation frame. First failures: '
              '${result.violations.take(12).join('; ')}. '
              'Frame deltas=${result.frameDeltas}',
        );
      });
    }
  }

  testWidgets(
    'topology handoffs scale shadow continuously outside the annulus',
    (WidgetTester tester) async {
      const Duration duration = Duration(milliseconds: 480);
      const WovenShadow diagnosticShadow = WovenShadow(
        color: Color(0xE6000000),
        blurFraction: 0.12,
        offsetFraction: 0.18,
      );
      final List<
        ({
          String name,
          List<WovenSegment> from,
          List<WovenSegment> to,
          bool oneToMany,
        })
      >
      cases =
          <
            ({
              String name,
              List<WovenSegment> from,
              List<WovenSegment> to,
              bool oneToMany,
            })
          >[
            (
              name: 'shadow one-to-three',
              from: <WovenSegment>[
                WovenSegment.solid(100, WovenPalette.purple),
              ],
              to: <WovenSegment>[
                WovenSegment.solid(34, WovenPalette.purple),
                WovenSegment.solid(33, WovenPalette.rose),
                WovenSegment.solid(33, WovenPalette.green),
              ],
              oneToMany: true,
            ),
            (
              name: 'shadow three-to-one',
              from: <WovenSegment>[
                WovenSegment.solid(34, WovenPalette.purple),
                WovenSegment.solid(33, WovenPalette.rose),
                WovenSegment.solid(33, WovenPalette.green),
              ],
              to: <WovenSegment>[WovenSegment.solid(100, WovenPalette.purple)],
              oneToMany: false,
            ),
          ];

      final List<String> violations = <String>[];
      for (final bool clockwise in <bool>[true, false]) {
        final WovenRingStyle style = WovenRingStyle(
          startAngle: 0.287,
          clockwise: clockwise,
          shadow: diagnosticShadow,
        );
        final WovenRingGeometry geometry = WovenRingGeometry.forSize(
          const Size.square(_side),
          style,
        );
        for (final transitionCase in cases) {
          final _ExpectedFrame fromFrame = _resolveExpectedFrame(
            transitionCase.from,
            geometry,
            style,
          );
          final _ExpectedFrame toFrame = _resolveExpectedFrame(
            transitionCase.to,
            geometry,
            style,
          );
          final List<_Raster> rasters = await _captureTopologyFrames(
            tester: tester,
            from: transitionCase.from,
            to: transitionCase.to,
            style: style,
            duration: duration,
          );
          final List<int> signals = <int>[];
          final List<double> scales = <double>[];

          for (var frame = 0; frame <= 30; frame++) {
            final double easedProgress = Curves.easeInOut.transform(frame / 30);
            final double topologyT = Curves.easeInCubic.transform(
              easedProgress,
            );
            final double shadowScale = transitionCase.oneToMany
                ? topologyT
                : 1.0 - topologyT;
            final _ExpectedFrame expectedFrame = _lerpExpectedFrame(
              fromFrame,
              toFrame,
              easedProgress,
            );
            final List<WovenSegmentExtent> extents = geometry.extents(
              expectedFrame.fractions,
              style.resolvedStartAngle,
              clockwise: clockwise,
            );
            signals.add(
              _outsideShadowSignal(
                raster: rasters[frame],
                geometry: geometry,
                headAngle: extents[1].start,
                clockwise: clockwise,
                shadow: diagnosticShadow,
              ),
            );
            scales.add(shadowScale);
          }

          final int fullSignal = transitionCase.oneToMany
              ? signals.last
              : signals.first;
          final String context =
              '${transitionCase.name} ${clockwise ? 'CW' : 'CCW'}';
          if (fullSignal < 12) {
            violations.add(
              '$context has no diagnostic shadow outside the annulus: '
              'fullSignal=$fullSignal signals=$signals',
            );
            continue;
          }

          for (var frame = 0; frame <= 30; frame++) {
            final double expected = fullSignal * scales[frame];
            final double tolerance = math.max(4.0, fullSignal * 0.16);
            if ((signals[frame] - expected).abs() > tolerance) {
              violations.add(
                '$context frame=$frame shadow signal=${signals[frame]} '
                'expected=${expected.toStringAsFixed(2)} '
                'scale=${scales[frame].toStringAsFixed(6)} '
                'tolerance=${tolerance.toStringAsFixed(2)}',
              );
            }
            if (frame > 0) {
              final int step = (signals[frame] - signals[frame - 1]).abs();
              final double expectedStep =
                  fullSignal * (scales[frame] - scales[frame - 1]).abs();
              final double stepLimit = expectedStep + fullSignal * 0.12 + 2;
              if (step > stepLimit) {
                violations.add(
                  '$context frame=$frame discontinuous outside shadow step '
                  '${signals[frame - 1]} -> ${signals[frame]} '
                  'limit=${stepLimit.toStringAsFixed(2)}',
                );
              }
              if (transitionCase.oneToMany &&
                  signals[frame] + 3 < signals[frame - 1]) {
                violations.add(
                  '$context frame=$frame shadow reversed while fading in: '
                  '${signals[frame - 1]} -> ${signals[frame]}',
                );
              }
              if (!transitionCase.oneToMany &&
                  signals[frame] > signals[frame - 1] + 3) {
                violations.add(
                  '$context frame=$frame shadow reversed while fading out: '
                  '${signals[frame - 1]} -> ${signals[frame]}',
                );
              }
            }
          }
          if (transitionCase.oneToMany) {
            if (signals.first > 1 || signals[1] > fullSignal * 0.10 + 2) {
              violations.add(
                '$context exposes shadow at full strength on entry: '
                'frame0=${signals.first} frame1=${signals[1]} '
                'full=$fullSignal',
              );
            }
          } else if (signals.last > 1 || signals[29] > fullSignal * 0.10 + 2) {
            violations.add(
              '$context pops shadow off at completion: '
              'frame29=${signals[29]} frame30=${signals.last} '
              'full=$fullSignal',
            );
          }
        }
      }

      expect(
        violations,
        isEmpty,
        reason:
            'the woven shadow contribution must follow the topology crossfade '
            'outside the annulus, rather than appearing at full strength on '
            'the first multi-segment frame or popping off at the single-segment '
            'endpoint. Failures: ${violations.join('; ')}',
      );
    },
  );

  testWidgets(
    'styled many-to-single retarget preserves the current topology frame',
    (WidgetTester tester) async {
      const Duration duration = Duration(milliseconds: 480);
      const List<WovenSegment> initial = <WovenSegment>[
        WovenSegment(
          value: 34,
          fill: WovenFill.gradient(
            head: Color(0xFFF280B2),
            tail: Color(0xFF6F2ACB),
          ),
          border: WovenBorder(color: Color(0xFFFFFFFF), widthFraction: 0.05),
        ),
        WovenSegment(
          value: 33,
          fill: WovenFill.gradient(
            head: Color(0xFF8AF0BD),
            tail: Color(0xFF087A57),
          ),
          border: WovenBorder(color: Color(0xFFFFE36E), widthFraction: 0.04),
        ),
        WovenSegment(
          value: 33,
          fill: WovenFill.gradient(
            head: Color(0xFF78B8FF),
            tail: Color(0xFF21365D),
          ),
          border: WovenBorder(color: Color(0xFFFF79D1), widthFraction: 0.03),
        ),
      ];
      final List<WovenSegment> soleZero = <WovenSegment>[
        initial[0].copyWith(value: 100),
        initial[1].copyWith(value: 0),
        initial[2].copyWith(value: 0),
      ];
      final List<WovenSegment> soleOne = <WovenSegment>[
        initial[0].copyWith(value: 0),
        initial[1].copyWith(value: 100),
        initial[2].copyWith(value: 0),
      ];
      final List<String> violations = <String>[];

      for (final bool clockwise in <bool>[true, false]) {
        final WovenRingStyle style = WovenRingStyle(
          startAngle: -0.347,
          clockwise: clockwise,
          shadow: const WovenShadow(
            color: Color(0x52000000),
            blurFraction: 0.09,
            offsetFraction: 0.10,
          ),
        );
        final WovenRingGeometry geometry = WovenRingGeometry.forSize(
          const Size.square(_side),
          style,
        );
        final GlobalKey boundaryKey = GlobalKey();
        await tester.pumpWidget(const SizedBox.shrink());
        await _pumpRing(
          tester,
          boundaryKey,
          WovenRingChart(
            segments: initial,
            style: style,
            animation: WovenRingAnimation.none,
            transitionDuration: duration,
          ),
        );
        await _pumpRing(
          tester,
          boundaryKey,
          WovenRingChart(
            segments: soleZero,
            style: style,
            animation: WovenRingAnimation.none,
            transitionDuration: duration,
          ),
        );
        await tester.pump(const Duration(milliseconds: 192));
        final _Raster beforeRetarget = await _capture(tester, boundaryKey);

        await _pumpRing(
          tester,
          boundaryKey,
          WovenRingChart(
            segments: soleOne,
            style: style,
            animation: WovenRingAnimation.none,
            transitionDuration: duration,
          ),
        );
        final _Raster immediate = await _capture(tester, boundaryKey);
        final int immediateMismatches = _pixelMismatchCount(
          beforeRetarget,
          immediate,
        );
        violations.addAll(
          _alphaHoleViolations(
            raster: immediate,
            geometry: geometry,
            context: 'styled retarget ${clockwise ? 'CW' : 'CCW'} frame=0',
            minimumAlpha: 250,
          ),
        );
        if (immediateMismatches != 0) {
          violations.add(
            '${clockwise ? 'CW' : 'CCW'} retarget changed '
            '$immediateMismatches pixels before time advanced',
          );
        }

        _Raster previous = immediate;
        final List<double> frameDeltas = <double>[];
        for (var frame = 1; frame <= 30; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          final _Raster raster = await _capture(tester, boundaryKey);
          violations.addAll(
            _alphaHoleViolations(
              raster: raster,
              geometry: geometry,
              context:
                  'styled retarget ${clockwise ? 'CW' : 'CCW'} frame=$frame',
              minimumAlpha: 250,
            ),
          );
          final _DeltaSample deltaSample = _frameDelta(previous, raster);
          final double delta = deltaSample.mean;
          frameDeltas.add(double.parse(delta.toStringAsFixed(3)));
          if (frame == 1 && delta > 1.5) {
            violations.add(
              '${clockwise ? 'CW' : 'CCW'} retarget frame=1 has a large '
              'first timed delta mean=${delta.toStringAsFixed(3)} '
              'max=${deltaSample.maxChannelDelta} '
              'xy=(${deltaSample.x},${deltaSample.y}) '
              '${deltaSample.before}->${deltaSample.after}',
            );
          }
          if (frame >= 2) {
            final double prior = frameDeltas[frameDeltas.length - 2];
            if ((delta - prior).abs() > 2.5) {
              violations.add(
                '${clockwise ? 'CW' : 'CCW'} retarget frame=$frame has a '
                'discontinuous delta jump ${prior.toStringAsFixed(3)} -> '
                '${delta.toStringAsFixed(3)} '
                'max=${deltaSample.maxChannelDelta} '
                'xy=(${deltaSample.x},${deltaSample.y}) '
                '${deltaSample.before}->${deltaSample.after}',
              );
            }
          }
          if (delta > 20) {
            violations.add(
              '${clockwise ? 'CW' : 'CCW'} retarget frame=$frame has a '
              'discontinuous mean pixel delta ${delta.toStringAsFixed(3)}',
            );
          }
          previous = raster;
        }

        final double finalDelta = frameDeltas.last;
        if (finalDelta > 1.5) {
          violations.add(
            '${clockwise ? 'CW' : 'CCW'} retarget popped on the final frame: '
            'mean=${finalDelta.toStringAsFixed(3)} deltas=$frameDeltas',
          );
        }
        final _Raster staticDestination = await _render(
          tester,
          WovenRingChart(
            segments: soleOne,
            style: style,
            animation: WovenRingAnimation.none,
            transitionDuration: duration,
          ),
        );
        final int finalMismatches = _pixelMismatchCount(
          previous,
          staticDestination,
        );
        if (finalMismatches != 0) {
          violations.add(
            '${clockwise ? 'CW' : 'CCW'} final retarget frame differs from '
            'the sole-index-1 destination at $finalMismatches pixels',
          );
        }
      }

      expect(
        violations,
        isEmpty,
        reason:
            'a mid-flight sole-anchor retarget must preserve the exact current '
            'styled raster, then converge through covered bounded frames to '
            'the new gradient, border, and shadow destination. Failures: '
            '${violations.take(16).join('; ')}',
      );
    },
  );

  testWidgets(
    'the sweep moving head stays semicircular through every color boundary',
    (WidgetTester tester) async {
      const Duration duration = Duration(milliseconds: 960);
      const WovenRingStyle style = WovenRingStyle();
      const List<Color> colors = <Color>[
        WovenPalette.purple,
        WovenPalette.rose,
        WovenPalette.green,
        WovenPalette.amber,
      ];
      const List<WovenSegment> segments = <WovenSegment>[
        WovenSegment(value: 25, fill: WovenFill.solid(WovenPalette.purple)),
        WovenSegment(value: 25, fill: WovenFill.solid(WovenPalette.rose)),
        WovenSegment(value: 25, fill: WovenFill.solid(WovenPalette.green)),
        WovenSegment(value: 25, fill: WovenFill.solid(WovenPalette.amber)),
      ];
      final WovenRingGeometry geometry = WovenRingGeometry.forSize(
        const Size.square(_side),
        style,
      );
      final List<double> fractions = wovenSegmentFractions(
        const <double>[25, 25, 25, 25],
        minimumFraction: geometry.minimumFraction,
        policy: style.smallValuePolicy,
      );
      final List<WovenSegmentExtent> extents = geometry.extents(
        fractions,
        style.resolvedStartAngle,
        clockwise: style.clockwise,
      );
      final GlobalKey boundaryKey = GlobalKey();
      await _pumpRing(
        tester,
        boundaryKey,
        const WovenRingChart(
          segments: segments,
          style: style,
          animation: WovenRingAnimation.sweep,
          animationDuration: duration,
        ),
      );

      final List<String> violations = <String>[];
      final Set<int> observedSegments = <int>{};
      final Map<int, _Rgba> seamOwnership = <int, _Rgba>{};
      for (var frame = 0; frame <= 60; frame++) {
        if (frame > 0) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        final double controllerProgress = frame / 60;
        final double sweepProgress = Curves.easeInOutCubic.transform(
          controllerProgress,
        );
        var segmentIndex = 0;
        for (var i = 1; i < extents.length; i++) {
          final double boundaryProgress =
              (extents[i].start - extents.first.start) / (math.pi * 2);
          if (sweepProgress + 1e-9 >= boundaryProgress) segmentIndex = i;
        }
        observedSegments.add(segmentIndex);
        final double movingCenterAngle =
            extents.first.start + sweepProgress * math.pi * 2;
        final _Raster raster = await _capture(tester, boundaryKey);
        if (sweepProgress < 0.90) {
          violations.addAll(
            _semicircleViolations(
              raster: raster,
              geometry: geometry,
              centerAngle: movingCenterAngle,
              forward: true,
              clockwise: true,
              expected: colors[segmentIndex],
              context:
                  'frame=$frame controller=${controllerProgress.toStringAsFixed(3)} '
                  'sweep=${sweepProgress.toStringAsFixed(5)} segment=$segmentIndex',
            ),
          );
        }

        if (segmentIndex == extents.length - 1) {
          final double lastEnd = frame == 60
              ? extents.last.end
              : movingCenterAngle;
          final Path firstPath = geometry.segmentPath(
            extents.first.start,
            extents.first.end,
            clockwise: true,
          );
          final Path lastPath = geometry.segmentPath(
            extents.last.start,
            lastEnd,
            clockwise: true,
          );
          final Offset seamPoint = geometry.pointOn(
            geometry.trackRadius,
            extents.first.start,
          );
          if (firstPath.contains(seamPoint) && lastPath.contains(seamPoint)) {
            final _Rgba actual = raster.atOffset(seamPoint);
            seamOwnership[frame] = actual;
            final _Rgba expected = _rgbaOf(colors.first);
            if (actual.alpha != 255 ||
                _opaqueColorDistance(actual, expected) > 5) {
              violations.add(
                'frame=$frame controller=${controllerProgress.toStringAsFixed(3)} '
                'sweep=${sweepProgress.toStringAsFixed(5)} seam contact '
                'xy=(${seamPoint.dx.round()},${seamPoint.dy.round()}) '
                'expected segment0=$expected actual=$actual',
              );
            }
          }
        }
      }

      expect(observedSegments, <int>{0, 1, 2, 3});
      expect(seamOwnership.keys, containsAll(<int>[59, 60]));
      expect(
        seamOwnership[59],
        seamOwnership[60],
        reason:
            'cyclic seam ownership must not flip between the last sweep frame '
            'and completion',
      );
      expect(
        violations,
        isEmpty,
        reason:
            'the leading sweep cap must occupy exactly a semicircle; first '
            'violations: ${violations.take(12).join('; ')}',
      );
    },
  );

  test('heads have a true circular profile with radius half the thickness', () {
    const WovenRingStyle style = WovenRingStyle(thicknessFraction: 0.25);
    final WovenRingGeometry geometry = WovenRingGeometry.forSize(
      const Size.square(_side),
      style,
    );
    expect(geometry.capRadius, geometry.thickness / 2);

    const double headAngle = 0.31;
    final Offset radial = Offset(math.cos(headAngle), math.sin(headAngle));
    final Offset clockwiseTangent = Offset(
      -math.sin(headAngle),
      math.cos(headAngle),
    );

    for (final bool clockwise in <bool>[true, false]) {
      final Path segment = geometry.segmentPath(
        headAngle,
        headAngle + (clockwise ? 1 : -1) * 1.7,
        clockwise: clockwise,
      );
      final Offset backwards = clockwise ? -clockwiseTangent : clockwiseTangent;
      final Offset capCenter = geometry.pointOn(
        geometry.trackRadius,
        headAngle,
      );

      for (final double depthFraction in <double>[0.25, 0.60, 0.85]) {
        final double depth = geometry.capRadius * depthFraction;
        final double halfChord = math.sqrt(
          geometry.capRadius * geometry.capRadius - depth * depth,
        );
        for (final double side in <double>[-1, 1]) {
          final Offset onCap =
              capCenter + backwards * depth + radial * halfChord * side * 0.96;
          final Offset beyondCircle =
              capCenter + backwards * depth + radial * halfChord * side * 1.04;
          expect(segment.contains(onCap), isTrue);
          expect(
            segment.contains(beyondCircle),
            isFalse,
            reason: 'the head boundary must follow a circle, not a squircle',
          );
        }
      }
    }
  });
}

Future<_Raster> _render(WidgetTester tester, WovenRingChart ring) async {
  // Independent raster comparisons must not reuse WovenRingState. Reusing the
  // state would capture transition frame zero, which still paints the previous
  // segments and can make a before/after comparison pass without rendering the
  // requested second configuration at all.
  await tester.pumpWidget(const SizedBox.shrink());
  final GlobalKey boundaryKey = GlobalKey();
  await _pumpRing(tester, boundaryKey, ring);
  return _capture(tester, boundaryKey);
}

_ExpectedFrame _resolveExpectedFrame(
  List<WovenSegment> input,
  WovenRingGeometry geometry,
  WovenRingStyle style,
) {
  final List<WovenSegment> segments = <WovenSegment>[
    for (final WovenSegment segment in input)
      segment.copyWith(
        value: segment.value.isFinite && segment.value > 0 ? segment.value : 0,
        opacity: segment.value.isFinite && segment.value > 0
            ? (segment.opacity.isFinite ? segment.opacity.clamp(0.0, 1.0) : 1.0)
            : 0,
      ),
  ];
  return _ExpectedFrame(
    segments,
    wovenSegmentFractions(
      <double>[for (final WovenSegment segment in segments) segment.value],
      minimumFraction: geometry.minimumFraction,
      policy: style.smallValuePolicy,
    ),
  );
}

_ExpectedFrame _lerpExpectedFrame(
  _ExpectedFrame fromFrame,
  _ExpectedFrame toFrame,
  double t,
) {
  final int count = math.max(
    fromFrame.segments.length,
    toFrame.segments.length,
  );
  final _ExpectedFrame from = _padExpectedFrame(fromFrame, count);
  final _ExpectedFrame to = _padExpectedFrame(toFrame, count);
  final List<WovenSegment> segments = <WovenSegment>[];
  final List<double> fractions = <double>[];
  for (var i = 0; i < count; i++) {
    WovenSegment a = from.segments[i];
    WovenSegment b = to.segments[i];
    if (from.fractions[i] <= 1e-12 && to.fractions[i] > 1e-12) {
      a = WovenSegment(value: 0, fill: _expectedNeighborFill(from, i));
    }
    if (to.fractions[i] <= 1e-12 && from.fractions[i] > 1e-12) {
      b = WovenSegment(value: 0, fill: _expectedNeighborFill(to, i));
    }
    segments.add(WovenSegment.lerp(a, b, t));
    fractions.add(
      from.fractions[i] + (to.fractions[i] - from.fractions[i]) * t,
    );
  }
  return _ExpectedFrame(segments, fractions);
}

_ExpectedFrame _padExpectedFrame(_ExpectedFrame frame, int count) {
  if (frame.segments.length >= count) return frame;
  final WovenFill fill = frame.segments.isEmpty
      ? const WovenFill.solid(WovenPalette.neutral)
      : frame.segments.last.fill;
  return _ExpectedFrame(
    <WovenSegment>[
      ...frame.segments,
      for (var i = frame.segments.length; i < count; i++)
        WovenSegment(value: 0, fill: fill),
    ],
    <double>[
      ...frame.fractions,
      for (var i = frame.fractions.length; i < count; i++) 0,
    ],
  );
}

WovenFill _expectedNeighborFill(_ExpectedFrame frame, int index) {
  final int count = frame.segments.length;
  if (count == 0) return const WovenFill.solid(WovenPalette.neutral);
  for (var offset = 1; offset <= count; offset++) {
    final int candidate = (index - offset + count) % count;
    if (frame.fractions[candidate] > 1e-12) {
      return frame.segments[candidate].fill;
    }
  }
  return frame.segments[index.clamp(0, count - 1)].fill;
}

Future<_TransitionResult> _scanTopologyTransition({
  required WidgetTester tester,
  required GlobalKey boundaryKey,
  required List<WovenSegment> from,
  required List<WovenSegment> to,
  required WovenRingStyle style,
  required Duration duration,
  required String label,
  required int minimumAlpha,
  required bool checkCyclicOwnership,
}) async {
  await _pumpRing(
    tester,
    boundaryKey,
    WovenRingChart(
      segments: from,
      style: style,
      animation: WovenRingAnimation.none,
      transitionDuration: duration,
    ),
  );
  _Raster previous = await _capture(tester, boundaryKey);

  await _pumpRing(
    tester,
    boundaryKey,
    WovenRingChart(
      segments: to,
      style: style,
      animation: WovenRingAnimation.none,
      transitionDuration: duration,
    ),
  );

  final WovenRingGeometry geometry = WovenRingGeometry.forSize(
    const Size.square(_side),
    style,
  );
  final List<String> violations = <String>[];
  final List<double> frameDeltas = <double>[];
  final _ExpectedFrame fromFrame = _resolveExpectedFrame(from, geometry, style);
  final _ExpectedFrame toFrame = _resolveExpectedFrame(to, geometry, style);
  final List<int> fromActive = <int>[
    for (var i = 0; i < fromFrame.fractions.length; i++)
      if (fromFrame.fractions[i] > 1e-12) i,
  ];
  final List<int> toActive = <int>[
    for (var i = 0; i < toFrame.fractions.length; i++)
      if (toFrame.fractions[i] > 1e-12) i,
  ];
  final bool oneToMany = fromActive.length == 1 && toActive.length > 1;
  final bool manyToOne = fromActive.length > 1 && toActive.length == 1;
  final int? topologyAnchor = oneToMany
      ? fromActive.single
      : manyToOne
      ? toActive.single
      : null;
  final Set<int> observedOwners = <int>{};
  final Set<int> requiredOwners = <int>{
    for (
      var i = 0;
      i < math.max(fromFrame.fractions.length, toFrame.fractions.length);
      i++
    )
      if ((i < fromFrame.fractions.length && fromFrame.fractions[i] > 0) ||
          (i < toFrame.fractions.length && toFrame.fractions[i] > 0))
        i,
  };

  // Frame 0 is the immediate didUpdateWidget paint. Frames 1 through 30 are
  // the complete 480 ms transition at a 60 Hz cadence.
  for (var frame = 0; frame <= 30; frame++) {
    if (frame > 0) await tester.pump(const Duration(milliseconds: 16));
    final double rawProgress = frame / 30;
    final double easedProgress = Curves.easeInOut.transform(rawProgress);
    final _ExpectedFrame expectedFrame = _lerpExpectedFrame(
      fromFrame,
      toFrame,
      easedProgress,
    );
    final double topologyT = Curves.easeInCubic.transform(easedProgress);
    final double topologyMerge = oneToMany
        ? 1.0 - topologyT
        : manyToOne
        ? topologyT
        : 0.0;
    final _Raster raster = await _capture(tester, boundaryKey);
    violations.addAll(
      _alphaHoleViolations(
        raster: raster,
        geometry: geometry,
        context: '$label frame=$frame',
        minimumAlpha: minimumAlpha,
      ),
    );

    if (checkCyclicOwnership) {
      final List<int> active = <int>[
        for (var i = 0; i < expectedFrame.fractions.length; i++)
          if (expectedFrame.fractions[i] > 1e-12) i,
      ];
      if (active.length >= 2) {
        final List<WovenSegmentExtent> extents = geometry.extents(
          expectedFrame.fractions,
          style.resolvedStartAngle,
          clockwise: style.clockwise,
        );
        final List<Path> paths = <Path>[
          for (final int index in active)
            geometry.segmentPath(
              extents[index].start,
              extents[index].end,
              clockwise: style.clockwise,
            ),
        ];
        final double direction = style.clockwise ? 1 : -1;
        for (final int joint in active) {
          for (final double targetAngle in <double>[
            extents[joint].start - direction * geometry.capAngularExtent * 0.30,
            extents[joint].start + direction * geometry.jointLag * 0.50,
          ]) {
            final _InteriorPixel? sample = _findInteriorPixel(
              paths: paths,
              geometry: geometry,
              targetAngle: targetAngle,
            );
            // Transient sub-minimum spans can make every active path cover the
            // same point. There is no geometric cyclic owner at that exact
            // point; continuity assertions still catch a linear-order flash.
            if (sample == null) continue;
            final int owner = active[sample.owner];
            observedOwners.add(owner);
            final _Rgba expected = _expectedTopologyComposite(
              frame: expectedFrame,
              owner: owner,
              anchor: topologyAnchor,
              topologyMerge: topologyMerge,
            );
            final _Rgba actual = raster.at(sample.x, sample.y);
            if (actual.alpha != 255 ||
                _opaqueColorDistance(actual, expected) > 5) {
              violations.add(
                '$label frame=$frame raw=${rawProgress.toStringAsFixed(3)} '
                'cyclic owner=$owner covered=${sample.covered} '
                'topologyMerge=${topologyMerge.toStringAsFixed(6)} '
                'xy=(${sample.x},${sample.y}) expected=$expected '
                'actual=$actual',
              );
            }
          }
        }
      }
    }

    final _DeltaSample deltaSample = _frameDelta(previous, raster);
    final double delta = deltaSample.mean;
    frameDeltas.add(double.parse(delta.toStringAsFixed(3)));
    if (frame == 0 && delta > 1.5) {
      violations.add(
        '$label frame=0 changed before animation time advanced: '
        'mean=${delta.toStringAsFixed(3)} max=${deltaSample.maxChannelDelta} '
        'xy=(${deltaSample.x},${deltaSample.y}) '
        '${deltaSample.before}->${deltaSample.after}',
      );
    }
    if (frame == 1 && delta > 1.5) {
      violations.add(
        '$label frame=1 has a large first timed-frame jump: '
        'mean=${delta.toStringAsFixed(3)} max=${deltaSample.maxChannelDelta} '
        'xy=(${deltaSample.x},${deltaSample.y}) '
        '${deltaSample.before}->${deltaSample.after}',
      );
    }
    if (frame >= 2) {
      final double prior = frameDeltas[frameDeltas.length - 2];
      if ((delta - prior).abs() > 2.5) {
        violations.add(
          '$label frame=$frame has a discontinuous delta jump '
          '${prior.toStringAsFixed(3)} -> ${delta.toStringAsFixed(3)} '
          'max=${deltaSample.maxChannelDelta} '
          'xy=(${deltaSample.x},${deltaSample.y}) '
          '${deltaSample.before}->${deltaSample.after}',
        );
      }
    }
    if (delta > 20) {
      violations.add(
        '$label frame=$frame has a discontinuous mean pixel delta '
        '${delta.toStringAsFixed(3)} max=${deltaSample.maxChannelDelta} '
        'xy=(${deltaSample.x},${deltaSample.y}) '
        '${deltaSample.before}->${deltaSample.after}',
      );
    }
    previous = raster;
  }

  if (checkCyclicOwnership && !observedOwners.containsAll(requiredOwners)) {
    violations.add(
      '$label did not obtain margin-safe cyclic ownership samples for '
      '${requiredOwners.difference(observedOwners)}',
    );
  }

  return _TransitionResult(violations, frameDeltas);
}

_Rgba _expectedTopologyComposite({
  required _ExpectedFrame frame,
  required int owner,
  required int? anchor,
  required double topologyMerge,
}) {
  final Color ownerColor = frame.segments[owner].fill.head;
  if (anchor == null || topologyMerge <= 0.0) return _rgbaOf(ownerColor);

  // The topology painter draws the woven owner first, then overlays the
  // canonical single-segment anchor at topologyMerge. At a margin-safe owner
  // pixel both layers are opaque, so the equivalent source-over composite is
  // owner at 1 - topologyMerge over anchor. Comparing with the raw woven owner
  // would incorrectly reject the intentional topology handoff.
  final Color anchorColor = frame.segments[anchor].fill.head;
  return _rgbaOf(_blendOver(ownerColor, 1.0 - topologyMerge, anchorColor));
}

Future<List<_Raster>> _captureTopologyFrames({
  required WidgetTester tester,
  required List<WovenSegment> from,
  required List<WovenSegment> to,
  required WovenRingStyle style,
  required Duration duration,
}) async {
  await tester.pumpWidget(const SizedBox.shrink());
  final GlobalKey boundaryKey = GlobalKey();
  await _pumpRing(
    tester,
    boundaryKey,
    WovenRingChart(
      segments: from,
      style: style,
      animation: WovenRingAnimation.none,
      transitionDuration: duration,
    ),
  );
  await _pumpRing(
    tester,
    boundaryKey,
    WovenRingChart(
      segments: to,
      style: style,
      animation: WovenRingAnimation.none,
      transitionDuration: duration,
    ),
  );

  final List<_Raster> frames = <_Raster>[];
  for (var frame = 0; frame <= 30; frame++) {
    if (frame > 0) await tester.pump(const Duration(milliseconds: 16));
    frames.add(await _capture(tester, boundaryKey));
  }
  return frames;
}

int _outsideShadowSignal({
  required _Raster raster,
  required WovenRingGeometry geometry,
  required double headAngle,
  required bool clockwise,
  required WovenShadow shadow,
}) {
  final double offset = shadow.resolvedOffsetFraction * geometry.thickness;
  final Offset back =
      Offset(math.sin(headAngle), -math.cos(headAngle)) *
      (clockwise ? 1.0 : -1.0) *
      offset;
  final Offset shadowCenter =
      geometry.pointOn(geometry.trackRadius, headAngle) + back;
  final double searchRadius = geometry.capRadius * 1.8;
  var maximumAlpha = 0;

  for (var y = 0; y < raster.height; y++) {
    for (var x = 0; x < raster.width; x++) {
      final Offset point = Offset(x + 0.5, y + 0.5);
      final double radius = (point - geometry.center).distance;
      if (radius <= geometry.outerRadius + 1.5 ||
          (point - shadowCenter).distance > searchRadius) {
        continue;
      }
      maximumAlpha = math.max(maximumAlpha, raster.at(x, y).alpha);
    }
  }
  return maximumAlpha;
}

List<String> _alphaHoleViolations({
  required _Raster raster,
  required WovenRingGeometry geometry,
  required String context,
  int minimumAlpha = 250,
}) {
  final List<String> violations = <String>[];
  for (var radialIndex = -1; radialIndex <= 1; radialIndex++) {
    final double radius =
        geometry.trackRadius + radialIndex * geometry.thickness * 0.32;
    for (var sample = 0; sample < 720; sample++) {
      final double angle = sample * math.pi * 2 / 720;
      final _Rgba pixel = raster.atPolar(radius, angle);
      if (pixel.alpha < minimumAlpha) {
        final Offset point = geometry.pointOn(radius, angle);
        violations.add(
          '$context background flash radiusIndex=$radialIndex '
          'angle=${angle.toStringAsFixed(5)} '
          'xy=(${point.dx.round()},${point.dy.round()}) pixel=$pixel',
        );
        break;
      }
    }
  }
  return violations;
}

Future<_TransitionResult> _scanDataTransition({
  required WidgetTester tester,
  required GlobalKey boundaryKey,
  required List<WovenSegment> from,
  required List<WovenSegment> to,
  required WovenRingStyle style,
  required Duration duration,
  required String label,
}) async {
  await _pumpRing(
    tester,
    boundaryKey,
    WovenRingChart(
      segments: to,
      style: style,
      animation: WovenRingAnimation.none,
      transitionDuration: duration,
    ),
  );

  final WovenRingGeometry geometry = WovenRingGeometry.forSize(
    const Size.square(_side),
    style,
  );
  final List<String> violations = <String>[];
  final List<double> frameDeltas = <double>[];
  final List<double> fromFractions = wovenSegmentFractions(
    <double>[for (final WovenSegment segment in from) segment.value],
    minimumFraction: geometry.minimumFraction,
    policy: style.smallValuePolicy,
  );
  final List<double> toFractions = wovenSegmentFractions(
    <double>[for (final WovenSegment segment in to) segment.value],
    minimumFraction: geometry.minimumFraction,
    policy: style.smallValuePolicy,
  );
  _Raster? previous;

  for (var frame = 0; frame <= 30; frame++) {
    if (frame > 0) await tester.pump(const Duration(milliseconds: 16));
    final double rawProgress = frame / 30;
    final double easedProgress = Curves.easeInOut.transform(rawProgress);
    final List<WovenSegment> current = <WovenSegment>[
      for (var i = 0; i < from.length; i++)
        WovenSegment.lerp(from[i], to[i], easedProgress),
    ];
    final List<double> fractions = <double>[
      for (var i = 0; i < fromFractions.length; i++)
        fromFractions[i] + (toFractions[i] - fromFractions[i]) * easedProgress,
    ];
    final List<WovenSegmentExtent> extents = geometry.extents(
      fractions,
      style.resolvedStartAngle,
      clockwise: style.clockwise,
    );
    final List<Path> paths = <Path>[
      for (final WovenSegmentExtent extent in extents)
        geometry.segmentPath(
          extent.start,
          extent.end,
          clockwise: style.clockwise,
        ),
    ];
    final _Raster raster = await _capture(tester, boundaryKey);

    final double direction = style.clockwise ? 1 : -1;
    for (var radialIndex = -1; radialIndex <= 1; radialIndex++) {
      final double radius =
          geometry.trackRadius + radialIndex * geometry.thickness * 0.32;
      for (var sample = 0; sample < 720; sample++) {
        final double angle = sample * math.pi * 2 / 720;
        final _Rgba pixel = raster.atPolar(radius, angle);
        if (pixel.alpha < 250) {
          final Offset point = geometry.pointOn(radius, angle);
          violations.add(
            '$label frame=$frame raw=${rawProgress.toStringAsFixed(3)} '
            'hole radiusIndex=$radialIndex angle=${angle.toStringAsFixed(5)} '
            'xy=(${point.dx.round()},${point.dy.round()}) pixel=$pixel',
          );
          break;
        }
      }
    }

    for (var joint = 0; joint < current.length; joint++) {
      final WovenSegmentExtent extent = extents[joint];
      final List<(String, double)> samples = <(String, double)>[
        (
          'backward-cap',
          extent.start - direction * geometry.capAngularExtent * 0.30,
        ),
        ('head-center', extent.start),
        ('overlap-body', extent.start + direction * geometry.jointLag * 0.50),
        (
          'after-boundary',
          extent.boundaryStart + direction * geometry.capAngularExtent * 0.25,
        ),
      ];
      for (final (String sampleName, double angle) in samples) {
        final _InteriorPixel? sample = _findInteriorPixel(
          paths: paths,
          geometry: geometry,
          targetAngle: angle,
        );
        if (sample == null) {
          final Offset point = geometry.pointOn(geometry.trackRadius, angle);
          violations.add(
            '$label frame=$frame raw=${rawProgress.toStringAsFixed(3)} '
            'joint=$joint sample=$sampleName has no pixel with a stable '
            'cyclic owner and interior margin '
            'xy=(${point.dx.round()},${point.dy.round()})',
          );
          continue;
        }
        final _Rgba expected = _rgbaOf(current[sample.owner].fill.head);
        final _Rgba actual = raster.at(sample.x, sample.y);
        if (actual.alpha != 255 || _opaqueColorDistance(actual, expected) > 5) {
          violations.add(
            '$label frame=$frame raw=${rawProgress.toStringAsFixed(3)} '
            'joint=$joint sample=$sampleName angle=${angle.toStringAsFixed(5)} '
            'xy=(${sample.x},${sample.y}) expected=$expected '
            'actual=$actual owner=${sample.owner} covered=${sample.covered}',
          );
        }
      }
    }

    if (previous != null) {
      final _DeltaSample deltaSample = _frameDelta(previous, raster);
      final double delta = deltaSample.mean;
      frameDeltas.add(double.parse(delta.toStringAsFixed(3)));
      if (delta > 20) {
        violations.add(
          '$label frame=$frame discontinuous mean pixel delta '
          '${delta.toStringAsFixed(3)} max=${deltaSample.maxChannelDelta} '
          'xy=(${deltaSample.x},${deltaSample.y}) '
          '${deltaSample.before}->${deltaSample.after}',
        );
      }
      if (frameDeltas.length > 3 && frameDeltas.length < 28) {
        final double prior = frameDeltas[frameDeltas.length - 2];
        if ((delta - prior).abs() > 2.5) {
          violations.add(
            '$label frame=$frame discontinuous delta jump '
            '${prior.toStringAsFixed(3)} -> ${delta.toStringAsFixed(3)} '
            'max=${deltaSample.maxChannelDelta} '
            'xy=(${deltaSample.x},${deltaSample.y}) '
            '${deltaSample.before}->${deltaSample.after}',
          );
        }
      }
    }
    previous = raster;
  }

  return _TransitionResult(violations, frameDeltas);
}

(int, List<int>) _topOwnerAt(List<Path> paths, Offset point) {
  final List<int> covered = <int>[
    for (var i = 0; i < paths.length; i++)
      if (paths[i].contains(point)) i,
  ];
  if (covered.isEmpty) return (-1, covered);

  final Set<int> coveredSet = covered.toSet();
  if (coveredSet.length == paths.length) return (-1, covered);

  // Each overlap is cyclic: i + 1 covers i, including last -> 0. Find the
  // beginning of the covered run after a gap, then walk through successors.
  // The furthest successor in that run is the visible owner. This deliberately
  // does not depend on the list's linear beginning, so {last, 0, 1} resolves to
  // 1 while {last, 0} resolves to 0.
  final List<int> runStarts = <int>[
    for (final int index in covered)
      if (!coveredSet.contains((index - 1 + paths.length) % paths.length))
        index,
  ];
  if (runStarts.length != 1) return (-1, covered);

  int owner = runStarts.single;
  while (coveredSet.contains((owner + 1) % paths.length)) {
    owner = (owner + 1) % paths.length;
  }
  return (owner, covered);
}

_InteriorPixel? _findInteriorPixel({
  required List<Path> paths,
  required WovenRingGeometry geometry,
  required double targetAngle,
}) {
  // Nearby candidates keep the semantic probe in the same part of the joint
  // while avoiding accidental selection of a device pixel whose centre lies
  // on a cap tangent. Every accepted pixel has a 1.35 px ownership margin.
  const List<double> angularOffsets = <double>[
    0,
    0.0125,
    -0.0125,
    0.025,
    -0.025,
    0.0375,
    -0.0375,
  ];
  for (final double angularOffset in angularOffsets) {
    final Offset requested = geometry.pointOn(
      geometry.trackRadius,
      targetAngle + angularOffset,
    );
    final int x = (requested.dx - 0.5).round().clamp(0, _side.toInt() - 1);
    final int y = (requested.dy - 0.5).round().clamp(0, _side.toInt() - 1);
    final Offset pixelCenter = Offset(x + 0.5, y + 0.5);
    final (int owner, List<int> covered) = _topOwnerAt(paths, pixelCenter);
    if (owner < 0) continue;

    var stable = true;
    for (var sample = 0; sample < 16; sample++) {
      final double angle = sample * math.pi * 2 / 16;
      final Offset neighbor =
          pixelCenter + Offset(math.cos(angle), math.sin(angle)) * 1.35;
      final (int nearbyOwner, List<int> nearbyCovered) = _topOwnerAt(
        paths,
        neighbor,
      );
      if (nearbyOwner != owner || !_sameIntList(nearbyCovered, covered)) {
        stable = false;
        break;
      }
    }
    if (stable) {
      return _InteriorPixel(x: x, y: y, owner: owner, covered: covered);
    }
  }
  return null;
}

(int, int)? _findSharedInteriorPixel({
  required List<Path> paths,
  required WovenRingGeometry geometry,
  required double targetAngle,
}) {
  const List<double> angularOffsets = <double>[
    0,
    0.0125,
    -0.0125,
    0.025,
    -0.025,
    0.0375,
    -0.0375,
  ];
  for (final double angularOffset in angularOffsets) {
    final Offset requested = geometry.pointOn(
      geometry.trackRadius,
      targetAngle + angularOffset,
    );
    final int x = (requested.dx - 0.5).round().clamp(0, _side.toInt() - 1);
    final int y = (requested.dy - 0.5).round().clamp(0, _side.toInt() - 1);
    final Offset pixelCenter = Offset(x + 0.5, y + 0.5);
    if (paths.every(
      (Path path) => _containsWithMargin(path, pixelCenter, 1.35),
    )) {
      return (x, y);
    }
  }
  return null;
}

bool _sameIntList(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _containsWithMargin(Path path, Offset point, double margin) {
  if (!path.contains(point)) return false;
  for (var sample = 0; sample < 16; sample++) {
    final double angle = sample * math.pi * 2 / 16;
    if (!path.contains(
      point + Offset(math.cos(angle), math.sin(angle)) * margin,
    )) {
      return false;
    }
  }
  return true;
}

_DeltaSample _frameDelta(_Raster a, _Raster b) {
  var occupied = 0;
  var difference = 0;
  var maxChannelDelta = -1;
  var maxX = 0;
  var maxY = 0;
  var maxBefore = const _Rgba(0, 0, 0, 0);
  var maxAfter = const _Rgba(0, 0, 0, 0);
  for (var y = 0; y < a.height; y++) {
    for (var x = 0; x < a.width; x++) {
      final _Rgba first = a.at(x, y);
      final _Rgba second = b.at(x, y);
      if (first.alpha == 0 && second.alpha == 0) continue;
      occupied++;
      final int red = (first.red - second.red).abs();
      final int green = (first.green - second.green).abs();
      final int blue = (first.blue - second.blue).abs();
      difference += red + green + blue;
      final int localMax = math.max(red, math.max(green, blue));
      if (localMax > maxChannelDelta) {
        maxChannelDelta = localMax;
        maxX = x;
        maxY = y;
        maxBefore = first;
        maxAfter = second;
      }
    }
  }
  return _DeltaSample(
    mean: occupied == 0 ? 0 : difference / (occupied * 3),
    maxChannelDelta: math.max(0, maxChannelDelta),
    x: maxX,
    y: maxY,
    before: maxBefore,
    after: maxAfter,
  );
}

int _opaqueColorDistance(_Rgba actual, _Rgba expected) => math.max(
  (actual.red - expected.red).abs(),
  math.max(
    (actual.green - expected.green).abs(),
    (actual.blue - expected.blue).abs(),
  ),
);

int _rgbaDistance(_Rgba a, _Rgba b) =>
    math.max((a.alpha - b.alpha).abs(), _opaqueColorDistance(a, b));

int _alphaSupportMismatches(_Raster a, _Raster b) {
  var mismatches = 0;
  for (var y = 0; y < a.height; y++) {
    for (var x = 0; x < a.width; x++) {
      if ((a.at(x, y).alpha > 0) != (b.at(x, y).alpha > 0)) mismatches++;
    }
  }
  return mismatches;
}

int _pixelMismatchCount(_Raster a, _Raster b) {
  var mismatches = 0;
  for (var y = 0; y < a.height; y++) {
    for (var x = 0; x < a.width; x++) {
      if (a.at(x, y) != b.at(x, y)) mismatches++;
    }
  }
  return mismatches;
}

bool _hasColorNear(_Raster raster, Offset target, Color color) {
  final _Rgba expected = _rgbaOf(color);
  final int centerX = target.dx.round();
  final int centerY = target.dy.round();
  for (var dy = -3; dy <= 3; dy++) {
    for (var dx = -3; dx <= 3; dx++) {
      final int x = (centerX + dx).clamp(0, raster.width - 1);
      final int y = (centerY + dy).clamp(0, raster.height - 1);
      final _Rgba pixel = raster.at(x, y);
      if (pixel.alpha >= 245 && _opaqueColorDistance(pixel, expected) <= 20) {
        return true;
      }
    }
  }
  return false;
}

Color _blendOver(Color foreground, double opacity, Color background) {
  int channel(double front, double back) =>
      ((front * opacity + back * (1 - opacity)) * 255).round();
  return Color.fromARGB(
    255,
    channel(foreground.r, background.r),
    channel(foreground.g, background.g),
    channel(foreground.b, background.b),
  );
}

Future<void> _pumpRing(
  WidgetTester tester,
  GlobalKey boundaryKey,
  WovenRingChart ring,
) async {
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: RepaintBoundary(
          key: boundaryKey,
          child: SizedBox.square(dimension: _side, child: ring),
        ),
      ),
    ),
  );
}

Future<_Raster> _capture(WidgetTester tester, GlobalKey boundaryKey) async {
  final RenderRepaintBoundary boundary =
      boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final _Raster raster = (await tester.runAsync<_Raster>(() async {
    final ui.Image image = await boundary.toImage(pixelRatio: 1);
    final ByteData data = (await image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!;
    final _Raster result = _Raster(
      image.width,
      image.height,
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
    image.dispose();
    return result;
  }))!;
  expect(raster.width, _side.toInt());
  expect(raster.height, _side.toInt());
  return raster;
}

void _expectColor(_Rgba actual, Color expected, {required String reason}) {
  final _Rgba target = _Rgba(
    (expected.r * 255).round(),
    (expected.g * 255).round(),
    (expected.b * 255).round(),
    (expected.a * 255).round(),
  );
  expect(actual, target, reason: '$reason (actual=$actual, expected=$target)');
}

List<String> _semicircleViolations({
  required _Raster raster,
  required WovenRingGeometry geometry,
  required double centerAngle,
  required bool forward,
  required bool clockwise,
  required Color expected,
  required String context,
}) {
  final Offset center = geometry.pointOn(geometry.trackRadius, centerAngle);
  final Offset radial = Offset(math.cos(centerAngle), math.sin(centerAngle));
  final double direction = clockwise ? 1 : -1;
  final Offset tangent =
      Offset(-math.sin(centerAngle), math.cos(centerAngle)) * direction;
  final Offset longitudinal = forward ? tangent : -tangent;
  final _Rgba target = _rgbaOf(expected);
  final List<String> violations = <String>[];

  for (final double depthFraction in <double>[0.45, 0.70, 0.88]) {
    final double depth = geometry.capRadius * depthFraction;
    final double halfChord = math.sqrt(
      geometry.capRadius * geometry.capRadius - depth * depth,
    );
    for (final double side in <double>[-1, 1]) {
      final Offset inside =
          center + longitudinal * depth + radial * halfChord * side * 0.55;
      final Offset outside =
          center + longitudinal * depth + radial * halfChord * side * 1.45;
      final _Rgba insidePixel = raster.atOffset(inside);
      final _Rgba outsidePixel = raster.atOffset(outside);
      if (!_isColor(insidePixel, target)) {
        violations.add(
          '$context depth=$depthFraction side=$side inside=$insidePixel',
        );
      }
      if (_isColor(outsidePixel, target)) {
        violations.add(
          '$context depth=$depthFraction side=$side outside=$outsidePixel',
        );
      }
    }
  }
  return violations;
}

bool _isColor(_Rgba pixel, _Rgba opaqueTarget) {
  if (pixel.alpha < 128) return false;
  final double coverage = pixel.alpha / 255;
  return (pixel.red - opaqueTarget.red * coverage).abs() <= 3 &&
      (pixel.green - opaqueTarget.green * coverage).abs() <= 3 &&
      (pixel.blue - opaqueTarget.blue * coverage).abs() <= 3;
}

_Rgba _rgbaOf(Color color) => _Rgba(
  (color.r * 255).round(),
  (color.g * 255).round(),
  (color.b * 255).round(),
  (color.a * 255).round(),
);

class _Raster {
  const _Raster(this.width, this.height, this.bytes);

  final int width;
  final int height;
  final Uint8List bytes;

  _Rgba at(int x, int y) {
    final int offset = (y * width + x) * 4;
    return _Rgba(
      bytes[offset],
      bytes[offset + 1],
      bytes[offset + 2],
      bytes[offset + 3],
    );
  }

  _Rgba atPolar(double radius, double angle) => at(
    (_center + radius * math.cos(angle)).round().clamp(0, width - 1),
    (_center + radius * math.sin(angle)).round().clamp(0, height - 1),
  );

  _Rgba atOffset(Offset offset) => at(
    offset.dx.round().clamp(0, width - 1),
    offset.dy.round().clamp(0, height - 1),
  );
}

class _SeamCase {
  const _SeamCase({
    required this.name,
    required this.values,
    required this.colors,
    required this.style,
  });

  final String name;
  final List<double> values;
  final List<Color> colors;
  final WovenRingStyle style;
}

class _TransitionCase {
  const _TransitionCase({
    required this.name,
    required this.currentValues,
    required this.alternateValues,
    required this.colors,
    required this.startAngle,
  });

  final String name;
  final List<double> currentValues;
  final List<double> alternateValues;
  final List<Color> colors;
  final double startAngle;

  List<WovenSegment> segments({required bool alternate}) {
    final List<double> values = alternate ? alternateValues : currentValues;
    final List<Color> orderedColors = alternate
        ? <Color>[...colors.skip(1), colors.first]
        : colors;
    return <WovenSegment>[
      for (var i = 0; i < values.length; i++)
        WovenSegment.solid(values[i], orderedColors[i]),
    ];
  }
}

class _TopologyTransitionCase {
  const _TopologyTransitionCase({
    required this.name,
    required this.from,
    required this.to,
    required this.smallValuePolicy,
    this.minimumAlpha = 250,
    required this.checkCyclicOwnership,
    this.shadow,
  });

  final String name;
  final List<WovenSegment> from;
  final List<WovenSegment> to;
  final WovenSmallValuePolicy smallValuePolicy;
  final int minimumAlpha;

  /// Whether each joint's rendered colour is compared against the expected
  /// cyclic owner. Deliberately required rather than defaulted: a case that
  /// silently inherits "off" verifies only alpha and frame-to-frame smoothness,
  /// which is how a seam regression can pass this file untouched.
  ///
  /// It is off for gradient-filled cases only because [_expectedOwnerColor]
  /// models a segment as its single head colour. Ownership through those
  /// transitions is verified instead by catalog_test.dart section F16, whose
  /// oracle accepts any colour along a fill's head-to-tail range.
  final bool checkCyclicOwnership;
  final WovenShadow? shadow;
}

class _TransitionResult {
  const _TransitionResult(this.violations, this.frameDeltas);

  final List<String> violations;
  final List<double> frameDeltas;
}

class _ExpectedFrame {
  const _ExpectedFrame(this.segments, this.fractions);

  final List<WovenSegment> segments;
  final List<double> fractions;
}

class _DeltaSample {
  const _DeltaSample({
    required this.mean,
    required this.maxChannelDelta,
    required this.x,
    required this.y,
    required this.before,
    required this.after,
  });

  final double mean;
  final int maxChannelDelta;
  final int x;
  final int y;
  final _Rgba before;
  final _Rgba after;
}

class _InteriorPixel {
  const _InteriorPixel({
    required this.x,
    required this.y,
    required this.owner,
    required this.covered,
  });

  final int x;
  final int y;
  final int owner;
  final List<int> covered;
}

class _Rgba {
  const _Rgba(this.red, this.green, this.blue, this.alpha);

  final int red;
  final int green;
  final int blue;
  final int alpha;

  @override
  bool operator ==(Object other) =>
      other is _Rgba &&
      other.red == red &&
      other.green == green &&
      other.blue == blue &&
      other.alpha == alpha;

  @override
  int get hashCode => Object.hash(red, green, blue, alpha);

  @override
  String toString() => 'rgba($red, $green, $blue, $alpha)';
}
