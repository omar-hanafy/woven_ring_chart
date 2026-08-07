import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../model/shadow.dart';
import '../model/style.dart';
import 'segment_extent.dart';

/// A `WovenRingStyle`'s fractions resolved against a concrete box.
///
/// This is the whole of a woven ring's shape: two radii, a thickness, and how
/// far a joint lags its data boundary. It carries no colour and no data, which
/// is what lets the specification be checked against it without a canvas.
///
/// Angles run clockwise from three o'clock, in radians.
@immutable
class WovenRingGeometry {
  /// A geometry with every measurement given directly.
  ///
  /// Prefer [WovenRingGeometry.forSize], which derives them from a style.
  const WovenRingGeometry({
    required this.center,
    required this.outerRadius,
    required this.thickness,
    required this.trackRadius,
    required this.jointLag,
  });

  /// The geometry [style] produces inside [size].
  ///
  /// The ring is inscribed in the shorter side and centred in the whole box. A
  /// style carrying a `WovenShadow` insets the ring by the shadow's
  /// [WovenShadow.reach], so the blur has somewhere to go.
  factory WovenRingGeometry.forSize(Size size, WovenRingStyle style) {
    final double side = math.min(size.width, size.height);
    final WovenShadow? shadow = style.shadow;
    final double pad = shadow == null
        ? 0.0
        : side * style.resolvedThicknessFraction * shadow.reach;
    final double outer = math.max(0.0, side / 2 - pad);
    final double thickness = 2 * outer * style.resolvedThicknessFraction;
    final double track = math.max(0.0, outer - thickness / 2);
    return WovenRingGeometry(
      center: Offset(size.width / 2, size.height / 2),
      outerRadius: outer,
      thickness: thickness,
      trackRadius: track,
      jointLag: track > 0.0
          ? style.resolvedOverlapFraction * thickness / track
          : 0.0,
    );
  }

  /// The centre of the ring, in the coordinates of the box it was sized to.
  final Offset center;

  /// The outer edge of the ring.
  ///
  /// A ring with a shadow is smaller than its box, so this is not always half
  /// the shorter side.
  final double outerRadius;

  /// The radial thickness of the ring.
  final double thickness;

  /// Radius of the centreline that segments are bent along.
  final double trackRadius;

  /// How far behind its data boundary a joint sits, in radians.
  final double jointLag;

  /// Half the thickness. A consequence of the segment shape, not a choice.
  double get capRadius => thickness / 2;

  /// The angular extent of one cap. Two of these is one ring-thickness of arc.
  double get capAngle => trackRadius > 0.0 ? capRadius / trackRadius : 0.0;

  /// The exact maximum polar angle a round cap occupies.
  ///
  /// Used by seam clips, where the small-angle approximation in [capAngle] is
  /// not safe on thick rings.
  double get capAngularExtent => trackRadius > 0.0
      ? math.asin((capRadius / trackRadius).clamp(0.0, 1.0))
      : 0.0;

  /// The edge of the hole.
  double get innerRadius => trackRadius - capRadius;

  /// The width of the hole.
  ///
  /// A `WovenRingChart` fits its centre widget into a square inside this
  /// rather than into the whole circle, so the widget clears the ring on every
  /// side.
  double get holeDiameter => 2 * innerRadius;

  /// The smallest share of the ring that still draws as a segment.
  ///
  /// This is the fraction whose two cap centres are exactly one cap diameter
  /// apart. Using the exact polar extent matters on thick rings: the
  /// small-angle approximation lets adjacent round heads overlap slightly.
  double get minimumFraction => capAngularExtent / math.pi;

  /// The point at [radius] and [angle], measured from [center].
  Offset pointOn(double radius, double angle) => Offset(
    center.dx + radius * math.cos(angle),
    center.dy + radius * math.sin(angle),
  );

  /// The silhouette of one segment: a constant-width bar with semicircular
  /// ends, bent along the track between centreline angles [a] and [b].
  ///
  /// Built by hand rather than as a round-capped stroke, so that the caps still
  /// exist when a segment wraps the full circle and so the outline can be
  /// clipped for a border. A sweep of one full turn or more saturates to
  /// [annulus], which is the geometric limit of this shape.
  Path segmentPath(double a, double b, {required bool clockwise}) {
    // Canvas arc primitives are not stable beyond one complete sweep. The
    // geometric limit of a constant-width circular segment at one turn is the
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
      // tail cap: bulges forwards, and is always covered by the next segment
      ..arcTo(capB, b, direction * math.pi, false)
      // inner edge, b -> a
      ..arcTo(inner, b, a - b, false)
      // head cap: the only edge you ever see. Bulges backwards, into the
      // colour behind it.
      ..arcTo(capA, a + math.pi, direction * math.pi, false)
      ..close();
  }

  /// Everything except the hole.
  ///
  /// A shadow is clipped to this, so it can spill softly outside the ring but
  /// never fall inwards.
  Path holeMask() => Path.combine(
    PathOperation.difference,
    Path()..addRect(
      Rect.fromCircle(center: center, radius: outerRadius * 3 + thickness),
    ),
    Path()..addOval(Rect.fromCircle(center: center, radius: innerRadius)),
  );

  /// The full ring, hole excluded.
  ///
  /// This is the exact silhouette of the whole chart, and nothing it paints may
  /// fall outside it.
  Path annulus() => Path()
    ..fillType = PathFillType.evenOdd
    ..addOval(Rect.fromCircle(center: center, radius: trackRadius + capRadius))
    ..addOval(Rect.fromCircle(center: center, radius: innerRadius));

  /// Turns [fractions] into the extents each segment is drawn between,
  /// starting at [startAngle].
  ///
  /// Every segment is pulled back from its data boundary by the same
  /// [jointLag], which is why the seam needs no special case: joint zero is
  /// built exactly like the other n-1.
  List<WovenSegmentExtent> extents(
    List<double> fractions,
    double startAngle, {
    required bool clockwise,
  }) {
    final int n = fractions.length;
    final List<WovenSegmentExtent> out = <WovenSegmentExtent>[];
    final double direction = clockwise ? 1.0 : -1.0;
    double cursor = startAngle;
    for (var i = 0; i < n; i++) {
      final double from = cursor;
      cursor += direction * fractions[i] * math.pi * 2;
      out.add(
        WovenSegmentExtent(
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
