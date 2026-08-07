// Normalization and the two small-value policies.
import 'package:flutter_test/flutter_test.dart';
import 'package:woven_ring_chart/woven_ring_chart.dart';

import '../support/numeric_matchers.dart';

void main() {
  group('wovenSegmentFractions', () {
    test('empty and wholly invalid inputs preserve shape without NaNs', () {
      expect(
        wovenSegmentFractions(
          const <double>[],
          minimumFraction: 0.1,
          policy: WovenSmallValuePolicy.enforce,
        ),
        isEmpty,
      );

      final fractions = wovenSegmentFractions(
        <double>[double.nan, double.infinity, double.negativeInfinity, -4, 0],
        minimumFraction: 0.1,
        policy: WovenSmallValuePolicy.enforce,
      );

      expect(fractions, everyElement(0.0));
      expect(fractions, hasLength(5));
      expect(fractions, everyElement(isNot(isNaN)));
    });

    test('ignores nonfinite and nonpositive values while retaining order', () {
      final fractions = wovenSegmentFractions(
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
        policy: WovenSmallValuePolicy.enforce,
      );

      expectFractions(fractions, const <double>[0, 0.25, 0, 0, 0, 0.75, 0]);
      expectClose(fractions.fold(0.0, (sum, value) => sum + value), 1);
    });

    test('normalizes very large finite values without overflowing', () {
      final fractions = wovenSegmentFractions(
        const <double>[double.maxFinite, double.maxFinite],
        minimumFraction: 0.01,
        policy: WovenSmallValuePolicy.enforce,
      );

      expectFractions(fractions, const <double>[0.5, 0.5]);
    });

    test('enforce inflates short segments and rescales remaining data', () {
      final fractions = wovenSegmentFractions(
        const <double>[1, 2, 97],
        minimumFraction: 0.10,
        policy: WovenSmallValuePolicy.enforce,
      );

      expectFractions(fractions, const <double>[0.10, 0.10, 0.80]);
      expectClose(fractions.fold(0.0, (sum, value) => sum + value), 1);
    });

    test('enforce shares equally when all minimums cannot fit', () {
      final fractions = wovenSegmentFractions(
        const <double>[1, 0, 2, -1, 3],
        minimumFraction: 0.34,
        policy: WovenSmallValuePolicy.enforce,
      );

      expectFractions(fractions, const <double>[1 / 3, 0, 1 / 3, 0, 1 / 3]);
    });

    test(
      'allowVanish removes sub-half-thickness segments and renormalizes',
      () {
        final fractions = wovenSegmentFractions(
          const <double>[1, 2, 97],
          minimumFraction: 0.10,
          policy: WovenSmallValuePolicy.allowVanish,
        );

        expectFractions(fractions, const <double>[0, 0, 1]);
      },
    );

    test('allowVanish retains a segment exactly at the vanish threshold', () {
      final fractions = wovenSegmentFractions(
        const <double>[1, 9],
        minimumFraction: 0.20,
        policy: WovenSmallValuePolicy.allowVanish,
      );

      expectFractions(fractions, const <double>[0.10, 0.90]);
    });

    test(
      'allowVanish keeps the largest when an extreme threshold hides all',
      () {
        final fractions = wovenSegmentFractions(
          const <double>[1, 3, 2],
          minimumFraction: 3,
          policy: WovenSmallValuePolicy.allowVanish,
        );

        expectFractions(fractions, const <double>[0, 1, 0]);
      },
    );
  });
}
