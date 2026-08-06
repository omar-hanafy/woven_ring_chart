import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'enums.dart';
import 'snake.dart';
import 'style.dart';

/// Every ratio in one place, resolved against a concrete box.
///
/// This is the whole of the ring's shape: two radii, a band width, and how far
/// a joint lags its data boundary. It holds no colour and no data, which is
/// what lets the specification be checked against it without a canvas.
@immutable
class WovenRingGeometry {
  /// A geometry with every measurement given directly. Prefer
  /// [WovenRingGeometry.forSize], which derives them from a style.
  const WovenRingGeometry({
    required this.center,
    required this.outerRadius,
    required this.band,
    required this.trackRadius,
    required this.jointLag,
  });

  /// The geometry [style] produces inside [size].
  ///
  /// The ring is inscribed in the shorter side and centred in the whole box. A
  /// style carrying a [WovenLift] insets the ring by the lift's
  /// [WovenLift.reach] so the blur has somewhere to go.
  factory WovenRingGeometry.forSize(Size size, WovenRingStyle style) {
    final double side = math.min(size.width, size.height);
    final WovenLift? lift = style.lift;
    final double pad = lift == null
        ? 0.0
        : side * style.resolvedBandFraction * lift.reach;
    final double outer = math.max(0.0, side / 2 - pad);
    final double band = 2 * outer * style.resolvedBandFraction;
    final double track = math.max(0.0, outer - band / 2);
    return WovenRingGeometry(
      center: Offset(size.width / 2, size.height / 2),
      outerRadius: outer,
      band: band,
      trackRadius: track,
      jointLag: track > 0.0
          ? style.resolvedOverlapFraction * band / track
          : 0.0,
    );
  }

  /// The centre of the ring, in the coordinates of the box it was sized to.
  final Offset center;

  /// The outer edge of the band. A lifted ring is smaller than its box, so
  /// this is not always half the shorter side.
  final double outerRadius;

  /// The thickness of the ring.
  final double band;

  /// Radius of the centreline the snakes are bent along.
  final double trackRadius;

  /// How far behind its data boundary a joint sits, in radians.
  final double jointLag;

  /// Half the band. A consequence, not a choice.
  double get capRadius => band / 2;

  /// The angular extent of one cap. Two of these is one band width of arc.
  double get capAngle => trackRadius > 0.0 ? capRadius / trackRadius : 0.0;

  /// Exact maximum polar angle occupied by a round cap. This is used by seam
  /// clips, where the small-angle approximation is not safe on thick bands.
  double get capAngularExtent => trackRadius > 0.0
      ? math.asin((capRadius / trackRadius).clamp(0.0, 1.0))
      : 0.0;

  /// The edge of the hole.
  double get innerRadius => trackRadius - capRadius;

  /// The width of the hole, which is what a centre widget has to fit inside.
  double get holeDiameter => 2 * innerRadius;

  /// Minimum snake, as a fraction of the ring: one band width of visible arc.
  /// Minimum data fraction whose two cap centres are at least one full cap
  /// diameter apart. Using the exact polar extent matters on thick bands: the
  /// small-angle approximation lets adjacent round heads overlap slightly.
  double get minimumFraction => capAngularExtent / math.pi;

  /// The point at [radius] and [angle], measured from [center] with angles
  /// running clockwise from three o'clock.
  Offset pointOn(double radius, double angle) => Offset(
    center.dx + radius * math.cos(angle),
    center.dy + radius * math.sin(angle),
  );

  /// The silhouette of one snake: a constant-width bar with semicircular ends,
  /// bent along the track. [a] and [b] are centreline angles.
  ///
  /// Built by hand rather than as a round-capped stroke so that the caps still
  /// exist when a snake wraps the full circle, and so the outline can be
  /// clipped for the border.
  Path snakePath(double a, double b, {required bool clockwise}) {
    // Canvas arc primitives are not stable beyond one complete sweep. The
    // geometric limit of a constant-width circular snake at one turn is the
    // annulus itself, so saturate there during single-to-many transitions.
    if ((b - a).abs() >= math.pi * 2 - 1e-9) return annulus();

    final double direction = clockwise ? 1.0 : -1.0;
    final double ro = trackRadius + capRadius;
    final double ri = trackRadius - capRadius;
    final Rect outer = Rect.fromCircle(center: center, radius: ro);
    final Rect inner = Rect.fromCircle(center: center, radius: ri);
    final Rect capA = Rect.fromCircle(
      center: pointOn(trackRadius, a),
      radius: capRadius,
    );
    final Rect capB = Rect.fromCircle(
      center: pointOn(trackRadius, b),
      radius: capRadius,
    );

    final Offset start = pointOn(ro, a);
    return Path()
      ..moveTo(start.dx, start.dy)
      // outer edge, a -> b
      ..arcTo(outer, a, b - a, false)
      // tail cap: bulges forwards, and is always covered by the next snake
      ..arcTo(capB, b, direction * math.pi, false)
      // inner edge, b -> a
      ..arcTo(inner, b, a - b, false)
      // head cap: the only edge you ever see. Bulges backwards, into the
      // colour behind it.
      ..arcTo(capA, a + math.pi, direction * math.pi, false)
      ..close();
  }

  /// Everything except the hole. The lift is clipped to this so it can spill
  /// softly outside the ring but never fall inwards.
  Path holeMask() => Path.combine(
    PathOperation.difference,
    Path()..addRect(
      Rect.fromCircle(center: center, radius: outerRadius * 3 + band),
    ),
    Path()..addOval(Rect.fromCircle(center: center, radius: innerRadius)),
  );

  /// The full band, hole excluded. This is the exact silhouette of the whole
  /// ring, and nothing the component paints may fall outside it.
  Path annulus() => Path()
    ..fillType = PathFillType.evenOdd
    ..addOval(Rect.fromCircle(center: center, radius: trackRadius + capRadius))
    ..addOval(Rect.fromCircle(center: center, radius: innerRadius));

  /// Turns fractions into drawn extents.
  ///
  /// Every snake is pulled back from its data boundary by the same [jointLag],
  /// which is the whole reason the seam needs no special case: joint zero is
  /// built exactly like the other N-1.
  List<WovenSnakeExtent> extents(
    List<double> fractions,
    double startAngle, {
    required bool clockwise,
  }) {
    final int n = fractions.length;
    final List<WovenSnakeExtent> out = <WovenSnakeExtent>[];
    final double direction = clockwise ? 1.0 : -1.0;
    double cursor = startAngle;
    for (var i = 0; i < n; i++) {
      final double from = cursor;
      cursor += direction * fractions[i] * math.pi * 2;
      out.add(
        WovenSnakeExtent(
          boundaryStart: from,
          boundaryEnd: cursor,
          start: from - direction * jointLag,
          // The tail reaches the next data boundary. The successor starts one
          // overlap depth before that boundary, so its body fully buries this
          // rounded tail instead of merely rotating the joint.
          end: cursor,
        ),
      );
    }
    return out;
  }
}

/// Where one snake is actually drawn, in centreline angles, alongside the data
/// boundaries it came from.
@immutable
class WovenSnakeExtent {
  /// An extent with both its data boundaries and its drawn endpoints given.
  const WovenSnakeExtent({
    required this.boundaryStart,
    required this.boundaryEnd,
    required this.start,
    required this.end,
  });

  /// The invisible data line this snake starts on, before any overlap.
  final double boundaryStart;

  /// The invisible data line this snake ends on, which is also where the next
  /// snake's boundary begins.
  final double boundaryEnd;

  /// Centreline angle where the drawn bar starts, one joint lag behind
  /// [boundaryStart]. The head cap sits one [WovenRingGeometry.capAngle]
  /// outside it.
  final double start;

  /// Centreline angle where the drawn bar ends, on [boundaryEnd]. The tail cap
  /// sits one [WovenRingGeometry.capAngle] outside it, under the next snake.
  final double end;

  /// The tip of the head, the only edge of this snake anybody ever sees.
  double headApex(double capAngle, {required bool clockwise}) =>
      start - (clockwise ? 1.0 : -1.0) * capAngle;

  /// The tip of the tail, always underneath the next snake.
  double tailApex(double capAngle, {required bool clockwise}) =>
      end + (clockwise ? 1.0 : -1.0) * capAngle;
}

/// Turns raw values into fractions of the ring, applying the minimum-length
/// policy. Never sorts or rebalances for looks. Data order is kept.
///
/// The result is parallel to [values] and sums to one, unless every value is
/// unusable, in which case every fraction is zero. Zero, negative, and
/// non-finite values become zero fractions. Normalization runs through the
/// largest value, so a list of huge finite numbers cannot overflow to
/// infinity.
///
/// [minimumFraction] is the smallest share that still draws as a snake, which
/// is [WovenRingGeometry.minimumFraction] for the ring being drawn. Under
/// [WovenMinimumPolicy.enforce] anything below it is lifted to it and the rest
/// are rescaled, repeatedly, until no positive value is short; if there is no
/// room for every value at the minimum, they share the ring equally instead.
/// Under [WovenMinimumPolicy.allowVanish] anything below half the minimum is
/// dropped to zero and the survivors are rescaled.
List<double> wovenFractions(
  List<double> values, {
  required double minimumFraction,
  required WovenMinimumPolicy policy,
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
  if (policy == WovenMinimumPolicy.allowVanish) {
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
