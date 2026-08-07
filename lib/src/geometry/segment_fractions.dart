import '../model/policy.dart';

/// Turns raw segment values into fractions of the ring, applying [policy].
///
/// The result is parallel to [values] and sums to one, unless every value is
/// unusable, in which case every fraction is zero. Zero, negative, and
/// non-finite values become zero fractions. Order is preserved exactly: this
/// never sorts or rebalances for looks. Normalization runs through the largest
/// value, so a list of huge finite numbers cannot overflow to infinity.
///
/// [minimumFraction] is the smallest share that still draws as a segment,
/// which is `WovenRingGeometry.minimumFraction` for the ring being drawn.
///
/// Under [WovenSmallValuePolicy.enforce] anything below it is raised to it and
/// the rest are rescaled, repeatedly, until no positive value is short; if
/// there is no room for every value at the minimum, they share the ring
/// equally instead. Under [WovenSmallValuePolicy.allowVanish] anything below
/// half the minimum is dropped to zero and the survivors are rescaled; if that
/// leaves no survivors at all, the largest value takes the whole ring.
List<double> wovenSegmentFractions(
  List<double> values, {
  required double minimumFraction,
  required WovenSmallValuePolicy policy,
}) {
  final int n = values.length;
  if (n == 0) return const <double>[];

  double largest = 0.0;
  for (final double v in values) {
    if (v.isFinite && v > largest) largest = v;
  }
  if (largest <= 0.0) return List<double>.filled(n, 0.0);

  // Normalize through the largest value so adding several finite values can
  // never overflow to infinity.
  double scaledTotal = 0.0;
  for (final double v in values) {
    if (v.isFinite && v > 0.0) scaledTotal += v / largest;
  }
  if (!scaledTotal.isFinite || scaledTotal <= 0.0) {
    return List<double>.filled(n, 0.0);
  }

  final List<double> f = <double>[
    for (final double v in values)
      v.isFinite && v > 0 ? (v / largest) / scaledTotal : 0.0,
  ];
  if (policy == WovenSmallValuePolicy.allowVanish) {
    final double vanishBelow = minimumFraction / 2;
    double visibleTotal = 0.0;
    for (var i = 0; i < f.length; i++) {
      if (f[i] < vanishBelow - 1e-12) {
        f[i] = 0.0;
      } else {
        visibleTotal += f[i];
      }
    }
    if (visibleTotal <= 0.0) {
      var largest = 0;
      for (var i = 1; i < values.length; i++) {
        final double candidate = values[i].isFinite ? values[i] : 0.0;
        final double current = values[largest].isFinite ? values[largest] : 0.0;
        if (candidate > current) largest = i;
      }
      return <double>[for (var i = 0; i < n; i++) i == largest ? 1.0 : 0.0];
    }
    return <double>[for (final double value in f) value / visibleTotal];
  }

  final int positives = f.where((double v) => v > 0).length;
  if (positives == 0) return f;
  if (positives * minimumFraction >= 1) {
    // No room for everyone. Share the ring out evenly and be honest about it.
    return <double>[for (final double v in f) v > 0 ? 1 / positives : 0.0];
  }

  final List<bool> locked = List<bool>.filled(n, false);
  for (var pass = 0; pass < positives; pass++) {
    var changed = false;
    for (var i = 0; i < n; i++) {
      if (f[i] > 0 && !locked[i] && f[i] < minimumFraction - 1e-9) {
        locked[i] = true;
        f[i] = minimumFraction;
        changed = true;
      }
    }
    if (!changed) break;
    double lockedSum = 0, freeSum = 0;
    for (var i = 0; i < n; i++) {
      if (f[i] <= 0) continue;
      if (locked[i]) {
        lockedSum += f[i];
      } else {
        freeSum += f[i];
      }
    }
    final double room = 1 - lockedSum;
    if (freeSum <= 0 || room <= 0) break;
    final double scale = room / freeSum;
    for (var i = 0; i < n; i++) {
      if (f[i] > 0 && !locked[i]) f[i] *= scale;
    }
  }
  return f;
}
