// The immutable value types: equality, copyWith, interpolation, and the
// clamping every `resolved` getter applies.
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woven_ring_chart/woven_ring_chart.dart';

import '../support/numeric_matchers.dart';

void main() {
  group('immutable models', () {
    test('fill, border, shadow, segment, and style use value equality', () {
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
      const shadowA = WovenShadow();
      const shadowB = WovenShadow();
      const segmentA = WovenSegment(
        value: 4,
        fill: fillA,
        border: borderA,
        semanticLabel: 'four',
        opacity: 0.8,
      );
      const segmentB = WovenSegment(
        value: 4,
        fill: fillB,
        border: borderB,
        semanticLabel: 'four',
        opacity: 0.8,
      );
      const styleA = WovenRingStyle(shadow: shadowA);
      const styleB = WovenRingStyle(shadow: shadowB);

      expect(fillA, fillB);
      expect(fillA.hashCode, fillB.hashCode);
      expect(borderA, borderB);
      expect(borderA.hashCode, borderB.hashCode);
      expect(shadowA, shadowB);
      expect(shadowA.hashCode, shadowB.hashCode);
      expect(segmentA, segmentB);
      expect(segmentA.hashCode, segmentB.hashCode);
      expect(styleA, styleB);
      expect(styleA.hashCode, styleB.hashCode);
    });

    test(
      'segment copyWith updates fields and can explicitly remove a border',
      () {
        final original = WovenSegment.solid(
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

    test(
      'style copyWith preserves values and can explicitly remove shadow',
      () {
        const original = WovenRingStyle(
          thicknessFraction: 0.18,
          overlapFraction: 0.70,
          startAngle: 0.4,
          clockwise: false,
          shadow: WovenShadow(),
        );

        expect(original.copyWith(), original);
        final withoutShadow = original.copyWith(
          thicknessFraction: 0.22,
          removeShadow: true,
        );
        expect(withoutShadow.thicknessFraction, 0.22);
        expect(withoutShadow.clockwise, isFalse);
        expect(withoutShadow.shadow, isNull);
      },
    );
  });

  group('style and decoration clamping', () {
    test('ring style clamps finite extremes and defaults nonfinite values', () {
      expect(
        const WovenRingStyle(thicknessFraction: -2).resolvedThicknessFraction,
        0.12,
      );
      expect(
        const WovenRingStyle(thicknessFraction: 2).resolvedThicknessFraction,
        0.30,
      );
      expect(
        const WovenRingStyle(
          thicknessFraction: double.nan,
        ).resolvedThicknessFraction,
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

    test('border and shadow fractions are safely bounded', () {
      expect(const WovenBorder(widthFraction: -1).resolvedWidthFraction, 0.005);
      expect(const WovenBorder(widthFraction: 1).resolvedWidthFraction, 0.05);
      expect(
        const WovenBorder(widthFraction: double.nan).resolvedWidthFraction,
        0.015,
      );

      const lowShadow = WovenShadow(blurFraction: -1, offsetFraction: -1);
      const highShadow = WovenShadow(blurFraction: 1, offsetFraction: 1);
      const invalidShadow = WovenShadow(
        blurFraction: double.nan,
        offsetFraction: double.infinity,
      );
      expect(lowShadow.resolvedBlurFraction, 0);
      expect(lowShadow.resolvedOffsetFraction, 0);
      expect(highShadow.resolvedBlurFraction, 0.30);
      expect(highShadow.resolvedOffsetFraction, 0.20);
      expect(invalidShadow.resolvedBlurFraction, 0.10);
      expect(invalidShadow.resolvedOffsetFraction, 0.05);
      expectClose(highShadow.reach, 1.10);
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

    test('borders resolve explicit, surfaceColor, and darker-fill colors', () {
      const fill = WovenFill.solid(Color(0xFF80A0C0));
      const surfaceColor = Color(0xFFF8F7F4);
      const explicit = Color(0xFF112233);

      expect(
        const WovenBorder(color: explicit).resolve(fill, surfaceColor),
        explicit,
      );
      expect(const WovenBorder().resolve(fill, surfaceColor), surfaceColor);
      final darker = const WovenBorder.darkerFill().resolve(fill, surfaceColor);
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
        const surfaceColor = Color(0xFFF8F7F4);
        const samples = <double>[0.499, 0.5, 0.501];
        final fromColor = from.resolve(fill, surfaceColor);
        final toColor = to.resolve(fill, surfaceColor);
        final fromSegment = WovenSegment(value: 1, fill: fill, border: from);
        final toSegment = WovenSegment(value: 1, fill: fill, border: to);
        final directColors = <Color>[];
        final segmentColors = <Color>[];

        for (final t in samples) {
          final expected = Color.lerp(fromColor, toColor, t)!;
          final direct = WovenBorder.lerp(
            from,
            to,
            t,
            fill: fill,
            surfaceColor: surfaceColor,
          )!;
          final segment = WovenSegment.lerp(
            fromSegment,
            toSegment,
            t,
            surfaceColor: surfaceColor,
          );
          final directColor = direct.resolve(fill, surfaceColor);
          final segmentColor = segment.border!.resolve(
            segment.fill,
            surfaceColor,
          );
          directColors.add(directColor);
          segmentColors.add(segmentColor);

          expectColorNear(
            directColor,
            expected,
            reason: '$name direct lerp at $t',
          );
          expectColorNear(
            segmentColor,
            expected,
            reason: '$name segment lerp at $t',
          );
        }

        for (var i = 1; i < samples.length; i++) {
          expect(
            colorDistance(directColors[i - 1], directColors[i]),
            lessThan(0.03),
            reason: '$name direct midpoint step $i',
          );
          expect(
            colorDistance(segmentColors[i - 1], segmentColors[i]),
            lessThan(0.03),
            reason: '$name segment midpoint step $i',
          );
        }
      });
    }

    testBorderTransition(
      name: 'surfaceColor-to-explicit',
      from: const WovenBorder(),
      to: const WovenBorder(color: Color(0xFF17324D)),
    );
    testBorderTransition(
      name: 'darkerFill-to-surfaceColor',
      from: const WovenBorder.darkerFill(),
      to: const WovenBorder(),
    );
    testBorderTransition(
      name: 'darkerFill-to-explicit',
      from: const WovenBorder.darkerFill(),
      to: const WovenBorder(color: Color(0xFF17324D)),
    );
  });
}
