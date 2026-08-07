// The resolved geometry of a woven ring: proportions, the signed extents each
// segment is drawn between, how much of a segment its successor really covers,
// and the silhouette path itself.
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woven_ring_chart/woven_ring_chart.dart';

import '../support/numeric_matchers.dart';

void main() {
  group('WovenRingGeometry proportions', () {
    test('derives every default dimension from the shortest side', () {
      final geometry = WovenRingGeometry.forSize(
        const Size(200, 300),
        const WovenRingStyle(),
      );

      expect(geometry.center, const Offset(100, 150));
      expectClose(geometry.outerRadius, 100);
      expectClose(geometry.thickness, 40);
      expectClose(geometry.trackRadius, 80);
      expectClose(geometry.capRadius, 20);
      expectClose(geometry.innerRadius, 60);
      expectClose(geometry.holeDiameter, 120);
      expectClose(geometry.holeDiameter / (geometry.outerRadius * 2), 0.60);
      expectClose(geometry.capAngle, 0.25);
      expectClose(geometry.capAngularExtent, math.asin(0.25));
      expectClose(geometry.minimumFraction, math.asin(0.25) / math.pi);
    });

    test(
      'cap radius remains exactly half the thickness for clamped styles',
      () {
        for (final fraction in <double>[-1, 0.12, 0.20, 0.30, 4]) {
          final geometry = WovenRingGeometry.forSize(
            const Size.square(240),
            WovenRingStyle(thicknessFraction: fraction),
          );

          expectClose(geometry.capRadius * 2, geometry.thickness);
          expectClose(
            geometry.holeDiameter,
            2 * geometry.outerRadius - 2 * geometry.thickness,
          );
        }
      },
    );

    test(
      'shadow reserves breathing room without changing thickness proportions',
      () {
        const style = WovenRingStyle(shadow: WovenShadow());
        final geometry = WovenRingGeometry.forSize(
          const Size.square(200),
          style,
        );

        expectClose(style.shadow!.reach, 0.35);
        expectClose(geometry.outerRadius, 86);
        expectClose(geometry.thickness, geometry.outerRadius * 2 * 0.20);
        expectClose(
          geometry.trackRadius,
          geometry.outerRadius - geometry.thickness / 2,
        );
        expectClose(geometry.capRadius, geometry.thickness / 2);
      },
    );
  });

  group('signed extents', () {
    for (final clockwise in <bool>[true, false]) {
      test(
        '${clockwise ? 'clockwise' : 'counter-clockwise'} preserves an arbitrary start and data order',
        () {
          const start = 7.123;
          const fractions = <double>[0.10, 0.25, 0.65];
          final geometry = WovenRingGeometry.forSize(
            const Size.square(200),
            const WovenRingStyle(overlapFraction: 0.75),
          );
          final extents = geometry.extents(
            fractions,
            start,
            clockwise: clockwise,
          );
          final direction = clockwise ? 1.0 : -1.0;

          expect(extents, hasLength(fractions.length));
          expectClose(extents.first.boundaryStart, start);

          var cursor = start;
          for (var i = 0; i < extents.length; i++) {
            final extent = extents[i];
            final expectedEnd = cursor + direction * fractions[i] * math.pi * 2;

            expectClose(extent.boundaryStart, cursor);
            expectClose(extent.boundaryEnd, expectedEnd);
            expectClose(extent.start, cursor - direction * geometry.jointLag);
            expectClose(extent.end, expectedEnd);
            expectClose(
              extent.boundaryEnd - extent.boundaryStart,
              direction * fractions[i] * math.pi * 2,
            );
            expectClose(
              extent.headApex(geometry.capAngle, clockwise: clockwise),
              extent.start - direction * geometry.capAngle,
            );
            expectClose(
              extent.tailApex(geometry.capAngle, clockwise: clockwise),
              extent.end + direction * geometry.capAngle,
            );
            cursor = expectedEnd;
          }

          expectClose(
            extents.last.boundaryEnd,
            start + direction * math.pi * 2,
          );
        },
      );
    }
  });

  group('real overlap', () {
    for (final clockwise in <bool>[true, false]) {
      test(
        '${clockwise ? 'clockwise' : 'counter-clockwise'} neighbors share the requested arc depth, including the seam',
        () {
          const style = WovenRingStyle(overlapFraction: 0.75);
          final geometry = WovenRingGeometry.forSize(
            const Size.square(240),
            style,
          );
          final extents = geometry.extents(
            const <double>[0.20, 0.30, 0.50],
            0.37,
            clockwise: clockwise,
          );
          final direction = clockwise ? 1.0 : -1.0;

          for (var i = 0; i < extents.length; i++) {
            final previous = extents[i];
            final next = extents[(i + 1) % extents.length];
            final nextStart = i == extents.length - 1
                ? next.start + direction * math.pi * 2
                : next.start;
            final angularOverlap = direction * (previous.end - nextStart);

            expectClose(angularOverlap, geometry.jointLag);
            expectClose(
              angularOverlap * geometry.trackRadius,
              style.overlapFraction * geometry.thickness,
            );
          }
        },
      );

      test(
        '${clockwise ? 'clockwise' : 'counter-clockwise'} adjacent silhouettes truly overlap on the track',
        () {
          final geometry = WovenRingGeometry.forSize(
            const Size.square(200),
            const WovenRingStyle(overlapFraction: 0.50),
          );
          final extents = geometry.extents(
            const <double>[0.50, 0.50],
            -0.61,
            clockwise: clockwise,
          );
          final direction = clockwise ? 1.0 : -1.0;
          final jointMiddle =
              extents.first.end - direction * geometry.jointLag / 2;
          final point = geometry.pointOn(geometry.trackRadius, jointMiddle);

          expect(
            geometry
                .segmentPath(
                  extents.first.start,
                  extents.first.end,
                  clockwise: clockwise,
                )
                .contains(point),
            isTrue,
          );
          expect(
            geometry
                .segmentPath(
                  extents.last.start,
                  extents.last.end,
                  clockwise: clockwise,
                )
                .contains(point),
            isTrue,
          );
        },
      );
    }
  });

  group('segment cap paths', () {
    for (final clockwise in <bool>[true, false]) {
      test(
        '${clockwise ? 'clockwise' : 'counter-clockwise'} head is a contained semicircle with an exact radius',
        () {
          final geometry = WovenRingGeometry.forSize(
            const Size.square(200),
            const WovenRingStyle(),
          );
          final direction = clockwise ? 1.0 : -1.0;
          const headAngle = 0.0;
          final tailAngle = direction * math.pi / 2;
          final path = geometry.segmentPath(
            headAngle,
            tailAngle,
            clockwise: clockwise,
          );
          final headCenter = geometry.pointOn(geometry.trackRadius, headAngle);
          final backwardTangent = Offset(0, -direction);
          final justInside =
              headCenter + backwardTangent * (geometry.capRadius * 0.99);
          final justOutside =
              headCenter + backwardTangent * (geometry.capRadius * 1.01);

          expect(path.contains(headCenter), isTrue);
          expect(path.contains(justInside), isTrue);
          expect(path.contains(justOutside), isFalse);
          expect(
            path.contains(
              geometry.pointOn(geometry.trackRadius, direction * math.pi / 4),
            ),
            isTrue,
          );
          expect(
            path.contains(
              geometry.pointOn(
                geometry.outerRadius + 1,
                direction * math.pi / 4,
              ),
            ),
            isFalse,
          );
          expect(
            path.contains(
              geometry.pointOn(
                geometry.innerRadius - 1,
                direction * math.pi / 4,
              ),
            ),
            isFalse,
          );
        },
      );
    }
  });
}
