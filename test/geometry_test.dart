import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woven_ring_chart/woven_ring_chart.dart';

const double _epsilon = 1e-10;

void _expectClose(double actual, double expected) {
  expect(actual, closeTo(expected, _epsilon));
}

void _expectFractions(List<double> actual, List<double> expected) {
  expect(actual, hasLength(expected.length));
  for (var i = 0; i < expected.length; i++) {
    _expectClose(actual[i], expected[i]);
  }
}

void _expectColorNear(Color actual, Color expected, {required String reason}) {
  const tolerance = 1 / 255 + 1e-6;
  expect(actual.a, closeTo(expected.a, tolerance), reason: reason);
  expect(actual.r, closeTo(expected.r, tolerance), reason: reason);
  expect(actual.g, closeTo(expected.g, tolerance), reason: reason);
  expect(actual.b, closeTo(expected.b, tolerance), reason: reason);
}

double _colorDistance(Color a, Color b) =>
    (a.a - b.a).abs() +
    (a.r - b.r).abs() +
    (a.g - b.g).abs() +
    (a.b - b.b).abs();

void main() {
  group('WovenRingGeometry proportions', () {
    test('derives every default dimension from the shortest side', () {
      final geometry = WovenRingGeometry.forSize(
        const Size(200, 300),
        const WovenRingStyle(),
      );

      expect(geometry.center, const Offset(100, 150));
      _expectClose(geometry.outerRadius, 100);
      _expectClose(geometry.band, 40);
      _expectClose(geometry.trackRadius, 80);
      _expectClose(geometry.capRadius, 20);
      _expectClose(geometry.innerRadius, 60);
      _expectClose(geometry.holeDiameter, 120);
      _expectClose(geometry.holeDiameter / (geometry.outerRadius * 2), 0.60);
      _expectClose(geometry.capAngle, 0.25);
      _expectClose(geometry.capAngularExtent, math.asin(0.25));
      _expectClose(geometry.minimumFraction, math.asin(0.25) / math.pi);
    });

    test('cap radius remains exactly half the band for clamped styles', () {
      for (final fraction in <double>[-1, 0.12, 0.20, 0.30, 4]) {
        final geometry = WovenRingGeometry.forSize(
          const Size.square(240),
          WovenRingStyle(bandFraction: fraction),
        );

        _expectClose(geometry.capRadius * 2, geometry.band);
        _expectClose(
          geometry.holeDiameter,
          2 * geometry.outerRadius - 2 * geometry.band,
        );
      }
    });

    test('lift reserves breathing room without changing band proportions', () {
      const style = WovenRingStyle(lift: WovenLift());
      final geometry = WovenRingGeometry.forSize(const Size.square(200), style);

      _expectClose(style.lift!.reach, 0.35);
      _expectClose(geometry.outerRadius, 86);
      _expectClose(geometry.band, geometry.outerRadius * 2 * 0.20);
      _expectClose(
        geometry.trackRadius,
        geometry.outerRadius - geometry.band / 2,
      );
      _expectClose(geometry.capRadius, geometry.band / 2);
    });
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
          _expectClose(extents.first.boundaryStart, start);

          var cursor = start;
          for (var i = 0; i < extents.length; i++) {
            final extent = extents[i];
            final expectedEnd = cursor + direction * fractions[i] * math.pi * 2;

            _expectClose(extent.boundaryStart, cursor);
            _expectClose(extent.boundaryEnd, expectedEnd);
            _expectClose(extent.start, cursor - direction * geometry.jointLag);
            _expectClose(extent.end, expectedEnd);
            _expectClose(
              extent.boundaryEnd - extent.boundaryStart,
              direction * fractions[i] * math.pi * 2,
            );
            _expectClose(
              extent.headApex(geometry.capAngle, clockwise: clockwise),
              extent.start - direction * geometry.capAngle,
            );
            _expectClose(
              extent.tailApex(geometry.capAngle, clockwise: clockwise),
              extent.end + direction * geometry.capAngle,
            );
            cursor = expectedEnd;
          }

          _expectClose(
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

            _expectClose(angularOverlap, geometry.jointLag);
            _expectClose(
              angularOverlap * geometry.trackRadius,
              style.overlapFraction * geometry.band,
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
                .snakePath(
                  extents.first.start,
                  extents.first.end,
                  clockwise: clockwise,
                )
                .contains(point),
            isTrue,
          );
          expect(
            geometry
                .snakePath(
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

  group('wovenFractions', () {
    test('empty and wholly invalid inputs preserve shape without NaNs', () {
      expect(
        wovenFractions(
          const <double>[],
          minimumFraction: 0.1,
          policy: WovenMinimumPolicy.enforce,
        ),
        isEmpty,
      );

      final fractions = wovenFractions(
        <double>[double.nan, double.infinity, double.negativeInfinity, -4, 0],
        minimumFraction: 0.1,
        policy: WovenMinimumPolicy.enforce,
      );

      expect(fractions, everyElement(0.0));
      expect(fractions, hasLength(5));
      expect(fractions, everyElement(isNot(isNaN)));
    });

    test('ignores nonfinite and nonpositive values while retaining order', () {
      final fractions = wovenFractions(
        <double>[
          double.nan,
          2,
          double.infinity,
          -1,
          0,
          6,
          double.negativeInfinity,
        ],
        minimumFraction: 0.01,
        policy: WovenMinimumPolicy.enforce,
      );

      _expectFractions(fractions, const <double>[0, 0.25, 0, 0, 0, 0.75, 0]);
      _expectClose(fractions.fold(0.0, (sum, value) => sum + value), 1);
    });

    test('normalizes very large finite values without overflowing', () {
      final fractions = wovenFractions(
        const <double>[double.maxFinite, double.maxFinite],
        minimumFraction: 0.01,
        policy: WovenMinimumPolicy.enforce,
      );

      _expectFractions(fractions, const <double>[0.5, 0.5]);
    });

    test('enforce inflates short snakes and rescales remaining data', () {
      final fractions = wovenFractions(
        const <double>[1, 2, 97],
        minimumFraction: 0.10,
        policy: WovenMinimumPolicy.enforce,
      );

      _expectFractions(fractions, const <double>[0.10, 0.10, 0.80]);
      _expectClose(fractions.fold(0.0, (sum, value) => sum + value), 1);
    });

    test('enforce shares equally when all minimums cannot fit', () {
      final fractions = wovenFractions(
        const <double>[1, 0, 2, -1, 3],
        minimumFraction: 0.34,
        policy: WovenMinimumPolicy.enforce,
      );

      _expectFractions(fractions, const <double>[1 / 3, 0, 1 / 3, 0, 1 / 3]);
    });

    test('allowVanish removes sub-half-band snakes and renormalizes', () {
      final fractions = wovenFractions(
        const <double>[1, 2, 97],
        minimumFraction: 0.10,
        policy: WovenMinimumPolicy.allowVanish,
      );

      _expectFractions(fractions, const <double>[0, 0, 1]);
    });

    test('allowVanish retains a snake exactly at the vanish threshold', () {
      final fractions = wovenFractions(
        const <double>[1, 9],
        minimumFraction: 0.20,
        policy: WovenMinimumPolicy.allowVanish,
      );

      _expectFractions(fractions, const <double>[0.10, 0.90]);
    });

    test(
      'allowVanish keeps the largest when an extreme threshold hides all',
      () {
        final fractions = wovenFractions(
          const <double>[1, 3, 2],
          minimumFraction: 3,
          policy: WovenMinimumPolicy.allowVanish,
        );

        _expectFractions(fractions, const <double>[0, 1, 0]);
      },
    );
  });

  group('WovenPalette.cycle', () {
    const red = Color(0xFFFF0000);
    const green = Color(0xFF00FF00);
    const blue = Color(0xFF0000FF);

    test('handles empty requests and permits one snake', () {
      expect(WovenPalette.cycle(const <Color>[], 4), isEmpty);
      expect(WovenPalette.cycle(const <Color>[red], 0), isEmpty);
      expect(WovenPalette.cycle(const <Color>[red], -1), isEmpty);
      expect(WovenPalette.cycle(const <Color>[red], 1), const <Color>[red]);
    });

    test('deduplicates colors, cycles them, and protects the seam', () {
      final colors = WovenPalette.cycle(const <Color>[
        red,
        red,
        green,
        blue,
        green,
      ], 7);

      expect(colors, hasLength(7));
      expect(colors.take(6), const <Color>[red, green, blue, red, green, blue]);
      for (var i = 0; i < colors.length; i++) {
        expect(colors[i], isNot(colors[(i + 1) % colors.length]));
      }
    });

    test('two colors form a valid even closed cycle', () {
      expect(WovenPalette.cycle(const <Color>[red, green], 6), const <Color>[
        red,
        green,
        red,
        green,
        red,
        green,
      ]);
    });

    test('rejects multiple snakes when only one distinct color exists', () {
      expect(
        () => WovenPalette.cycle(const <Color>[red, red], 2),
        throwsArgumentError,
      );
    });

    test('rejects an odd closed cycle with only two distinct colors', () {
      expect(
        () => WovenPalette.cycle(const <Color>[red, green, red], 5),
        throwsArgumentError,
      );
    });
  });

  group('immutable models', () {
    test('fill, border, lift, snake, and style use value equality', () {
      const fillA = WovenFill.gradient(
        head: Color(0xFF123456),
        tail: Color(0xFF654321),
      );
      const fillB = WovenFill.gradient(
        head: Color(0xFF123456),
        tail: Color(0xFF654321),
      );
      const borderA = WovenBorder(
        color: Color(0xFFFFFFFF),
        widthFraction: 0.02,
      );
      const borderB = WovenBorder(
        color: Color(0xFFFFFFFF),
        widthFraction: 0.02,
      );
      const liftA = WovenLift();
      const liftB = WovenLift();
      const snakeA = WovenSnake(
        value: 4,
        fill: fillA,
        border: borderA,
        semanticLabel: 'four',
        opacity: 0.8,
      );
      const snakeB = WovenSnake(
        value: 4,
        fill: fillB,
        border: borderB,
        semanticLabel: 'four',
        opacity: 0.8,
      );
      const styleA = WovenRingStyle(lift: liftA);
      const styleB = WovenRingStyle(lift: liftB);

      expect(fillA, fillB);
      expect(fillA.hashCode, fillB.hashCode);
      expect(borderA, borderB);
      expect(borderA.hashCode, borderB.hashCode);
      expect(liftA, liftB);
      expect(liftA.hashCode, liftB.hashCode);
      expect(snakeA, snakeB);
      expect(snakeA.hashCode, snakeB.hashCode);
      expect(styleA, styleB);
      expect(styleA.hashCode, styleB.hashCode);
    });

    test(
      'snake copyWith updates fields and can explicitly remove a border',
      () {
        final original = WovenSnake.solid(
          4,
          const Color(0xFF123456),
          border: const WovenBorder(color: Color(0xFFFFFFFF)),
          semanticLabel: 'four',
          opacity: 0.8,
        );

        expect(original.copyWith(), original);
        final updated = original.copyWith(
          value: 8,
          fill: const WovenFill.solid(Color(0xFFABCDEF)),
          opacity: 0.4,
        );
        expect(updated.value, 8);
        expect(updated.fill, const WovenFill.solid(Color(0xFFABCDEF)));
        expect(updated.opacity, 0.4);
        expect(updated.border, original.border);
        expect(updated.semanticLabel, 'four');

        final borderless = original.copyWith(
          border: const WovenBorder(color: Color(0xFF000000)),
          removeBorder: true,
        );
        expect(borderless.border, isNull);
        expect(borderless.value, original.value);
        expect(borderless.fill, original.fill);
      },
    );

    test('style copyWith preserves values and can explicitly remove lift', () {
      const original = WovenRingStyle(
        bandFraction: 0.18,
        overlapFraction: 0.70,
        startAngle: 0.4,
        clockwise: false,
        lift: WovenLift(),
      );

      expect(original.copyWith(), original);
      final withoutLift = original.copyWith(
        bandFraction: 0.22,
        removeLift: true,
      );
      expect(withoutLift.bandFraction, 0.22);
      expect(withoutLift.clockwise, isFalse);
      expect(withoutLift.lift, isNull);
    });
  });

  group('style and decoration clamping', () {
    test('ring style clamps finite extremes and defaults nonfinite values', () {
      expect(const WovenRingStyle(bandFraction: -2).resolvedBandFraction, 0.12);
      expect(const WovenRingStyle(bandFraction: 2).resolvedBandFraction, 0.30);
      expect(
        const WovenRingStyle(bandFraction: double.nan).resolvedBandFraction,
        0.20,
      );
      expect(
        const WovenRingStyle(overlapFraction: -2).resolvedOverlapFraction,
        0.25,
      );
      expect(
        const WovenRingStyle(overlapFraction: 2).resolvedOverlapFraction,
        1.0,
      );
      expect(
        const WovenRingStyle(
          overlapFraction: double.infinity,
        ).resolvedOverlapFraction,
        0.50,
      );
      expect(
        const WovenRingStyle(startAngle: double.nan).resolvedStartAngle,
        -math.pi / 2,
      );
      expect(const WovenRingStyle(startAngle: 9).resolvedStartAngle, 9);
    });

    test('border and lift fractions are safely bounded', () {
      expect(const WovenBorder(widthFraction: -1).resolvedWidthFraction, 0.005);
      expect(const WovenBorder(widthFraction: 1).resolvedWidthFraction, 0.05);
      expect(
        const WovenBorder(widthFraction: double.nan).resolvedWidthFraction,
        0.015,
      );

      const lowLift = WovenLift(blurFraction: -1, offsetFraction: -1);
      const highLift = WovenLift(blurFraction: 1, offsetFraction: 1);
      const invalidLift = WovenLift(
        blurFraction: double.nan,
        offsetFraction: double.infinity,
      );
      expect(lowLift.resolvedBlurFraction, 0);
      expect(lowLift.resolvedOffsetFraction, 0);
      expect(highLift.resolvedBlurFraction, 0.30);
      expect(highLift.resolvedOffsetFraction, 0.20);
      expect(invalidLift.resolvedBlurFraction, 0.10);
      expect(invalidLift.resolvedOffsetFraction, 0.05);
      _expectClose(highLift.reach, 1.10);
    });

    test('fill shading bounds and sanitizes its lightness step', () {
      const base = Color(0xFF4080C0);
      expect(WovenFill.shaded(base, step: -0.05), WovenFill.shaded(base));
      expect(WovenFill.shaded(base, step: double.nan), WovenFill.shaded(base));
      expect(
        WovenFill.shaded(base, step: 4),
        WovenFill.shaded(base, step: 0.20),
      );
      expect(const WovenFill.solid(base).isSolid, isTrue);
      expect(WovenFill.shaded(base).isSolid, isFalse);
    });

    test('borders resolve explicit, surface, and darker-fill colors', () {
      const fill = WovenFill.solid(Color(0xFF80A0C0));
      const surface = Color(0xFFF8F7F4);
      const explicit = Color(0xFF112233);

      expect(
        const WovenBorder(color: explicit).resolve(fill, surface),
        explicit,
      );
      expect(const WovenBorder().resolve(fill, surface), surface);
      final darker = const WovenBorder.darkerFill().resolve(fill, surface);
      expect(
        HSLColor.fromColor(darker).lightness,
        lessThan(HSLColor.fromColor(fill.midtone).lightness),
      );
    });

    void testBorderTransition({
      required String name,
      required WovenBorder from,
      required WovenBorder to,
    }) {
      test('$name border color is continuous at midpoint', () {
        const fill = WovenFill.gradient(
          head: Color(0xFF73A6D8),
          tail: Color(0xFF315B84),
        );
        const surface = Color(0xFFF8F7F4);
        const samples = <double>[0.499, 0.5, 0.501];
        final fromColor = from.resolve(fill, surface);
        final toColor = to.resolve(fill, surface);
        final fromSnake = WovenSnake(value: 1, fill: fill, border: from);
        final toSnake = WovenSnake(value: 1, fill: fill, border: to);
        final directColors = <Color>[];
        final snakeColors = <Color>[];

        for (final t in samples) {
          final expected = Color.lerp(fromColor, toColor, t)!;
          final direct = WovenBorder.lerp(
            from,
            to,
            t,
            fill: fill,
            surface: surface,
          )!;
          final snake = WovenSnake.lerp(
            fromSnake,
            toSnake,
            t,
            surface: surface,
          );
          final directColor = direct.resolve(fill, surface);
          final snakeColor = snake.border!.resolve(snake.fill, surface);
          directColors.add(directColor);
          snakeColors.add(snakeColor);

          _expectColorNear(
            directColor,
            expected,
            reason: '$name direct lerp at $t',
          );
          _expectColorNear(
            snakeColor,
            expected,
            reason: '$name snake lerp at $t',
          );
        }

        for (var i = 1; i < samples.length; i++) {
          expect(
            _colorDistance(directColors[i - 1], directColors[i]),
            lessThan(0.03),
            reason: '$name direct midpoint step $i',
          );
          expect(
            _colorDistance(snakeColors[i - 1], snakeColors[i]),
            lessThan(0.03),
            reason: '$name snake midpoint step $i',
          );
        }
      });
    }

    testBorderTransition(
      name: 'surface-to-explicit',
      from: const WovenBorder(),
      to: const WovenBorder(color: Color(0xFF17324D)),
    );
    testBorderTransition(
      name: 'darkerFill-to-surface',
      from: const WovenBorder.darkerFill(),
      to: const WovenBorder(),
    );
    testBorderTransition(
      name: 'darkerFill-to-explicit',
      from: const WovenBorder.darkerFill(),
      to: const WovenBorder(color: Color(0xFF17324D)),
    );
  });

  group('snake cap paths', () {
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
          final path = geometry.snakePath(
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
