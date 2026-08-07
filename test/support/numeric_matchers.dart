/// Shared numeric and colour matchers for the unit-level suites.
///
/// The specification catalog under `test/spec/` deliberately shares nothing
/// with this file: it re-derives everything it checks from the written spec so
/// that a bug in production geometry cannot hide inside its own checker.
library;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

/// The tolerance used for exact geometric identities.
const double kEpsilon = 1e-10;

/// Expects [actual] to equal [expected] within [kEpsilon].
void expectClose(double actual, double expected) {
  expect(actual, closeTo(expected, kEpsilon));
}

/// Expects two fraction lists to match element for element within [kEpsilon].
void expectFractions(List<double> actual, List<double> expected) {
  expect(actual, hasLength(expected.length));
  for (var i = 0; i < expected.length; i++) {
    expectClose(actual[i], expected[i]);
  }
}

/// Expects two colours to agree on every channel within one 8-bit step.
void expectColorNear(Color actual, Color expected, {required String reason}) {
  const tolerance = 1 / 255 + 1e-6;
  expect(actual.a, closeTo(expected.a, tolerance), reason: reason);
  expect(actual.r, closeTo(expected.r, tolerance), reason: reason);
  expect(actual.g, closeTo(expected.g, tolerance), reason: reason);
  expect(actual.b, closeTo(expected.b, tolerance), reason: reason);
}

/// The sum of the per-channel differences between [a] and [b].
double colorDistance(Color a, Color b) =>
    (a.a - b.a).abs() +
    (a.r - b.r).abs() +
    (a.g - b.g).abs() +
    (a.b - b.b).abs();
