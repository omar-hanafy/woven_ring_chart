/// Independent A-to-Z verification catalog for the woven ring.
///
/// Nothing in this file reuses a helper from the other test files, and the
/// oracle deliberately re-derives geometry and ownership from the written
/// specification rather than from [WovenRingGeometry]. A bug that lives in the
/// production geometry therefore cannot hide inside the checker that is meant
/// to catch it.
///
/// The spec, restated as three testable rules:
///
///   1. A segment is the set of points within `thickness / 2` of the centreline arc it
///      is bent along. That makes every visible edge a true circle of radius
///      `thickness / 2`.
///   2. Segments are laid down in data order, one consistent direction round the
///      ring, each over its predecessor.
///   3. The ordering is cyclic, so segment 0's head laps segment n-1's tail exactly
///      like every other joint.
///
/// Rule 2 and 3 collapse into one predicate used everywhere below: at any
/// covered point, the owner is the covering segment whose head tip is the closest
/// one behind that point in the drawing direction.
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woven_ring_chart/woven_ring_chart.dart';

// ===========================================================================
// Catalog-side geometry, re-derived from the spec
// ===========================================================================

/// Everything the oracle needs, computed from the style alone.
class Ring {
  Ring({
    required this.side,
    required double thicknessFraction,
    required double overlapFraction,
    required this.startAngle,
    required this.clockwise,
    WovenShadow? shadow,
  }) : center = Offset(side / 2, side / 2),
       outer =
           side / 2 -
           (shadow == null
               ? 0.0
               : side *
                     thicknessFraction *
                     (shadow.resolvedBlurFraction * 3 +
                         shadow.resolvedOffsetFraction)) {
    thickness = 2 * outer * thicknessFraction;
    cap = thickness / 2;
    track = outer - cap;
    inner = track - cap;
    jointLag = overlapFraction * thickness / track;
    // Half the angular width of a round cap measured along the centreline
    // circle. Chord length between two centreline points an angle g apart is
    // 2 * track * sin(g / 2); the cap reaches exactly one cap radius.
    capHalf = 2 * math.asin((cap / (2 * track)).clamp(0.0, 1.0));
  }

  final double side;
  final Offset center;
  final double outer;
  final double startAngle;
  final bool clockwise;

  late final double thickness;
  late final double cap;
  late final double track;
  late final double inner;
  late final double jointLag;
  late final double capHalf;

  double get dir => clockwise ? 1.0 : -1.0;

  Offset at(double radius, double angle) => Offset(
    center.dx + radius * math.cos(angle),
    center.dy + radius * math.sin(angle),
  );
}

/// One segment's drawn extent, in centreline angles.
class Extent {
  const Extent(this.start, this.end, this.headTip, this.tailTip);

  final double start;
  final double end;
  final double headTip;
  final double tailTip;
}

List<Extent> extentsFor(Ring r, List<double> fractions) {
  final List<Extent> out = <Extent>[];
  double cursor = r.startAngle;
  for (final double f in fractions) {
    final double boundaryStart = cursor;
    cursor += r.dir * f * 2 * math.pi;
    final double start = boundaryStart - r.dir * r.jointLag;
    final double end = cursor;
    out.add(
      Extent(start, end, start - r.dir * r.capHalf, end + r.dir * r.capHalf),
    );
  }
  return out;
}

/// Signed distance from [p] to segment [e]'s silhouette surfaceColor. Negative inside.
///
/// The silhouette is the capsule of radius `r.cap` around the centreline arc,
/// so this is just `distance(p, arc) - cap`.
double signedDistance(Ring r, Extent e, Offset p) {
  final double dx = p.dx - r.center.dx;
  final double dy = p.dy - r.center.dy;
  final double rho = math.sqrt(dx * dx + dy * dy);
  final double phi = math.atan2(dy, dx);
  // How far along the arc, in the drawing direction, from the arc's start.
  final double along = wrapPositive(r.dir * (phi - e.start));
  final double span = wrapPositive(r.dir * (e.end - e.start));
  // A full turn is the annulus itself.
  final bool fullTurn = span >= 2 * math.pi - 1e-9;
  if (fullTurn || along <= span) {
    return (rho - r.track).abs() - r.cap;
  }
  final Offset head = r.at(r.track, e.start);
  final Offset tail = r.at(r.track, e.end);
  final double toHead = (p - head).distance;
  final double toTail = (p - tail).distance;
  return math.min(toHead, toTail) - r.cap;
}

double wrapPositive(double a) {
  const double tau = 2 * math.pi;
  double v = a % tau;
  if (v < 0) v += tau;
  return v;
}

/// How far along segment [e] the point [p] lies, measured from the segment's head
/// in the drawing direction, or null when [p] is not on that segment at all.
///
/// A polar angle is not enough on its own. A segment whose drawn span plus caps
/// exceeds a full turn passes over the same angle twice, once as its head and
/// once as its tail, and those are different places along its length with
/// different neighbours above them. Where both apply the head is the later
/// layer and wins, which is what makes the position negative there.
double? alongSegment(Ring r, Extent e, Offset p) {
  final double dx = p.dx - r.center.dx;
  final double dy = p.dy - r.center.dy;
  final double rho = math.sqrt(dx * dx + dy * dy);
  final double phi = math.atan2(dy, dx);
  final double along = wrapPositive(r.dir * (phi - e.start));
  final double span = wrapPositive(r.dir * (e.end - e.start));
  final bool fullTurn = span >= 2 * math.pi - 1e-9;
  if (fullTurn || along <= span) {
    return (rho - r.track).abs() <= r.cap ? along : null;
  }
  if ((p - r.at(r.track, e.start)).distance <= r.cap) {
    return along - 2 * math.pi;
  }
  if ((p - r.at(r.track, e.end)).distance <= r.cap) return along;
  return null;
}

/// The spec's ownership rule, and the only one this file uses: of the segments
/// covering [p], the visible one is whichever has travelled least far from its
/// own head to get there.
///
/// Returns the index of the segment that must be visible at [p], or -1 when [p]
/// is on no segment at all.
int ownerAt(Ring r, List<Extent> extents, List<int> active, Offset p) {
  var owner = -1;
  var best = double.infinity;
  for (final int i in active) {
    final double? along = alongSegment(r, extents[i], p);
    if (along == null) continue;
    if (along < best) {
      best = along;
      owner = i;
    }
  }
  return owner;
}

// ===========================================================================
// Catalog-side fraction policy, re-derived from the spec
// ===========================================================================

/// The smallest data fraction whose two cap centres clear one cap diameter.
double minimumFractionOf(Ring r) =>
    math.asin((r.cap / r.track).clamp(0.0, 1.0)) / math.pi;

// ===========================================================================
// Raster
// ===========================================================================

class Rgba {
  const Rgba(this.r, this.g, this.b, this.a);
  final int r;
  final int g;
  final int b;
  final int a;

  @override
  String toString() => 'rgba($r,$g,$b,$a)';
}

class Raster {
  Raster(this.width, this.height, this.bytes);
  final int width;
  final int height;
  final Uint8List bytes;

  Rgba at(int x, int y) {
    if (x < 0 || y < 0 || x >= width || y >= height) {
      return const Rgba(0, 0, 0, 0);
    }
    final int i = (y * width + x) * 4;
    return Rgba(bytes[i], bytes[i + 1], bytes[i + 2], bytes[i + 3]);
  }

  Rgba atPoint(Offset p) => at((p.dx - 0.5).round(), (p.dy - 0.5).round());
}

Rgba rgbaOf(Color c) => Rgba(
  (c.r * 255).round(),
  (c.g * 255).round(),
  (c.b * 255).round(),
  (c.a * 255).round(),
);

int channelDistance(Rgba a, Rgba b) =>
    math.max(math.max((a.r - b.r).abs(), (a.g - b.g).abs()), (a.b - b.b).abs());

/// Distance from [pixel] to the closest colour the fill can legitimately show.
///
/// [shadow] admits the ring-level head shadow, which multiplies the fill by
/// `1 - a` for some `a` between zero and the shadow's own alpha. A darkened red is
/// still red, so this stays sharp enough to catch a wrong owner.
int distanceToFill(Rgba pixel, WovenFill fill, {double shadow = 0.0}) {
  var best = 1 << 30;
  for (var step = 0; step <= 32; step++) {
    final Color c = Color.lerp(fill.head, fill.tail, step / 32)!;
    final Rgba base = rgbaOf(c);
    for (var s = 0; s <= 12; s++) {
      final double a = shadow * s / 12;
      final Rgba dimmed = Rgba(
        (base.r * (1 - a)).round(),
        (base.g * (1 - a)).round(),
        (base.b * (1 - a)).round(),
        base.a,
      );
      best = math.min(best, channelDistance(pixel, dimmed));
      if (shadow == 0.0) break;
    }
  }
  return best;
}

const double side = 480;

/// The alpha of the neutral empty track. It is deliberately translucent so it
/// reads as an absence on whatever surfaceColor the ring sits on, which means a ring
/// in or near the empty state is never fully opaque.
const int emptyTrackAlpha = 0x8C;

Future<Raster> render(
  WidgetTester tester,
  Widget ring, {
  double pixelRatio = 1,
}) async {
  final GlobalKey key = GlobalKey();
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: RepaintBoundary(
          key: key,
          child: SizedBox.square(dimension: side, child: ring),
        ),
      ),
    ),
  );
  return capture(tester, key, pixelRatio: pixelRatio);
}

Future<Raster> capture(
  WidgetTester tester,
  GlobalKey key, {
  double pixelRatio = 1,
}) async {
  final RenderRepaintBoundary boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  return (await tester.runAsync<Raster>(() async {
    final ui.Image image = await boundary.toImage(pixelRatio: pixelRatio);
    final ByteData data = (await image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!;
    final Raster raster = Raster(
      image.width,
      image.height,
      Uint8List.fromList(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      ),
    );
    image.dispose();
    return raster;
  }))!;
}

// ===========================================================================
// The catalog case
// ===========================================================================

class Case {
  const Case({
    required this.name,
    required this.segments,
    required this.style,
    this.margin = 3.0,
    this.tolerance = 4,
    this.expectedFractions,
  });

  final String name;
  final List<WovenSegment> segments;
  final WovenRingStyle style;

  /// How far a sampled pixel must be from any silhouette surfaceColor to count as
  /// unambiguously interior. Must exceed the border width when borders are on.
  final double margin;
  final int tolerance;

  /// Only for cases whose drawn proportions cannot be derived from the policy.
  final List<double>? expectedFractions;

  Ring get ring => Ring(
    side: side,
    thicknessFraction: style.resolvedThicknessFraction,
    overlapFraction: style.resolvedOverlapFraction,
    startAngle: style.resolvedStartAngle,
    clockwise: style.clockwise,
    shadow: style.shadow,
  );

  /// The drawn share of the ring per segment, after the small-value policy.
  List<double> get fractions {
    final List<double>? override = expectedFractions;
    if (override != null) return override;
    final double bf = style.resolvedThicknessFraction;
    return wovenSegmentFractions(
      <double>[for (final WovenSegment s in segments) s.value],
      // cap / track, expressed straight from the thickness fraction.
      minimumFraction: math.asin(bf / (1 - bf)) / math.pi,
      policy: style.smallValuePolicy,
    );
  }
}

// ===========================================================================
// The checks
// ===========================================================================

/// A. Every pixel of the annulus interior is opaque and shows the colour the
/// spec's ownership rule demands.
List<String> checkOwnership(Raster raster, Case c) {
  final Ring r = c.ring;
  final List<double> f = c.fractions;
  final List<Extent> extents = extentsFor(r, f);
  final List<int> active = <int>[
    for (var i = 0; i < f.length; i++)
      if (f[i] > 1e-12) i,
  ];
  final List<String> violations = <String>[];

  const int angleSamples = 1440;
  final List<double> radii = <double>[
    r.track - r.thickness * 0.34,
    r.track - r.thickness * 0.17,
    r.track,
    r.track + r.thickness * 0.17,
    r.track + r.thickness * 0.34,
  ];

  var tested = 0;
  for (var s = 0; s < angleSamples; s++) {
    final double angle = s * 2 * math.pi / angleSamples;
    for (final double radius in radii) {
      final Offset p = r.at(radius, angle);
      // Only judge pixels that are unambiguously interior to exactly one owner
      // and unambiguously clear of every other silhouette surfaceColor.
      final int expected = ownerAt(r, extents, active, p);
      if (expected < 0) continue;
      // Only judge pixels that are clear of every edge where ownership could
      // legitimately change: each silhouette surfaceColor, and each cap circle. A
      // cap circle is an ownership boundary even well inside a silhouette,
      // because a segment that laps its own tail meets itself there.
      var ambiguous = false;
      for (final int i in active) {
        if (signedDistance(r, extents[i], p).abs() < c.margin) {
          ambiguous = true;
          break;
        }
        final double toHead = (p - r.at(r.track, extents[i].start)).distance;
        final double toTail = (p - r.at(r.track, extents[i].end)).distance;
        if ((toHead - r.cap).abs() < c.margin ||
            (toTail - r.cap).abs() < c.margin) {
          ambiguous = true;
          break;
        }
      }
      if (ambiguous) continue;

      tested++;
      final Rgba pixel = raster.atPoint(p);
      if (pixel.a != 255) {
        violations.add(
          '${c.name}: hole at angle=${angle.toStringAsFixed(4)} '
          'r=${radius.toStringAsFixed(1)} pixel=$pixel',
        );
        continue;
      }
      final double shadow = c.style.shadow == null
          ? 0.0
          : c.style.shadow!.color.a;
      final int distance = distanceToFill(
        pixel,
        c.segments[expected].fill,
        shadow: shadow,
      );
      if (distance > c.tolerance) {
        // Name whichever segment it actually looks like: a wrong owner is a far
        // more useful failure message than a colour distance.
        var looksLike = -1;
        for (final int i in active) {
          if (distanceToFill(pixel, c.segments[i].fill, shadow: shadow) <=
              c.tolerance) {
            looksLike = i;
            break;
          }
        }
        violations.add(
          '${c.name}: wrong owner at angle=${angle.toStringAsFixed(4)} '
          'r=${radius.toStringAsFixed(1)} expected=$expected '
          'got=${looksLike < 0 ? 'unknown' : looksLike} '
          'pixel=$pixel distance=$distance',
        );
      }
    }
  }
  if (tested < 500) {
    violations.add('${c.name}: only $tested pixels were testable');
  }
  return violations;
}

/// B. The thickness is continuously covered: no gap anywhere on the centreline.
List<String> checkCoverage(Raster raster, Case c) {
  final Ring r = c.ring;
  final List<String> violations = <String>[];
  for (var s = 0; s < 4320; s++) {
    final double angle = s * 2 * math.pi / 4320;
    for (final double radius in <double>[
      r.inner + 1.5,
      r.track,
      r.outer - 1.5,
    ]) {
      final Rgba pixel = raster.atPoint(r.at(radius, angle));
      if (pixel.a != 255) {
        violations.add(
          '${c.name}: uncovered thickness pixel angle=${angle.toStringAsFixed(4)} '
          'r=${radius.toStringAsFixed(1)} pixel=$pixel',
        );
        return violations;
      }
    }
  }
  return violations;
}

/// C. The silhouette is two perfect circles and the hole is untouched.
List<String> checkSilhouette(Raster raster, Case c) {
  final Ring r = c.ring;
  final List<String> violations = <String>[];
  // A shadow is allowed to breathe past the outer circle; that is exactly what
  // the ring shrank to make room for. Nothing may pass its documented reach.
  final WovenShadow? shadow = c.style.shadow;
  final double outerProbe = shadow == null
      ? r.outer + 2.0
      : r.outer + r.thickness * shadow.reach + 2.0;
  for (var s = 0; s < 1440; s++) {
    final double angle = s * 2 * math.pi / 1440;
    // Just outside the outer circle and just inside the hole must be clear.
    final Rgba out = raster.atPoint(r.at(outerProbe, angle));
    if (out.a != 0) {
      violations.add(
        '${c.name}: paint outside the outer circle at '
        'angle=${angle.toStringAsFixed(4)} pixel=$out',
      );
      return violations;
    }
    final Rgba hole = raster.atPoint(r.at(r.inner - 2.0, angle));
    if (hole.a != 0) {
      violations.add(
        '${c.name}: paint inside the hole at '
        'angle=${angle.toStringAsFixed(4)} pixel=$hole',
      );
      return violations;
    }
  }
  return violations;
}

/// C2. The same silhouette promise, measured sub-pixel.
///
/// [checkSilhouette] samples one ring of points a clear two pixels outside each
/// edge, so it cannot see a spill narrower than a whole pixel - and a stroke
/// centred on the boundary spills exactly half its width, which for every
/// hairline in this chart is well under one pixel at a normal density. This
/// renders several device pixels per logical pixel and scans every one of them,
/// so a half-pixel bleed is a hard failure instead of an invisible one.
///
/// [slack] is the margin the true circles' own antialiasing is allowed. The
/// silhouette is exact, so the only partial coverage belongs to the pixel the
/// boundary passes through; a quarter of a logical pixel clears it with room to
/// spare and still catches every stroke this chart can draw.
List<String> checkSilhouetteSubPixel(
  Raster raster,
  Ring r,
  String name, {
  required double pixelRatio,
  double slack = 0.25,
  double outerReach = 0.0,
}) {
  final double cx = r.center.dx * pixelRatio;
  final double cy = r.center.dy * pixelRatio;
  final double outer = (r.outer + outerReach + slack) * pixelRatio;
  final double inner = (r.inner - slack) * pixelRatio;
  final double outerSq = outer * outer;
  final double innerSq = inner * inner;
  final List<String> violations = <String>[];
  for (var y = 0; y < raster.height; y++) {
    final double dy = y + 0.5 - cy;
    final double dySq = dy * dy;
    for (var x = 0; x < raster.width; x++) {
      if (raster.bytes[(y * raster.width + x) * 4 + 3] <= 8) continue;
      final double dx = x + 0.5 - cx;
      final double d2 = dx * dx + dySq;
      if (d2 <= outerSq && d2 >= innerSq) continue;
      final double logical = math.sqrt(d2) / pixelRatio;
      violations.add(
        d2 > outerSq
            ? '$name: paint ${(logical - r.outer).toStringAsFixed(3)} logical '
                  'px outside the outer circle at device ($x, $y)'
            : '$name: paint ${(r.inner - logical).toStringAsFixed(3)} logical '
                  'px inside the hole at device ($x, $y)',
      );
      if (violations.length >= 8) return violations;
    }
  }
  return violations;
}

/// D. Every visible colour boundary lies on a circle of radius `thickness / 2`
/// centred on the successor head's cap centre. This is the "true semicircle"
/// promise, measured rather than assumed.
List<String> checkCapProfiles(Raster raster, Case c) {
  final Ring r = c.ring;
  final List<double> f = c.fractions;
  final List<Extent> extents = extentsFor(r, f);
  final List<int> active = <int>[
    for (var i = 0; i < f.length; i++)
      if (f[i] > 1e-12) i,
  ];
  if (active.length < 2) return const <String>[];
  final List<String> violations = <String>[];

  for (final int i in active) {
    final Offset capCentre = r.at(r.track, extents[i].start);
    final int predecessor =
        active[(active.indexOf(i) - 1 + active.length) % active.length];
    // Walk radii across the thickness and find where the colour flips from the
    // predecessor to this segment. Every such point must sit on the cap circle.
    // Sample the middle of the thickness. A cap circle is tangent to both thickness
    // edges, so near the edges the boundary runs almost parallel to the sweep
    // and cannot be located to sub-pixel accuracy by any method.
    var samples = 0;
    const int radialSteps = 17;
    for (var step = 0; step <= radialSteps; step++) {
      final double radius =
          r.track -
          r.thickness * 0.35 +
          r.thickness * 0.70 * step / radialSteps;
      // Sweep backwards from the head centre into the predecessor. The edge has
      // an antialiased thickness that matches neither colour, so bracket it: the
      // last pixel that is still this segment and the first that is already the
      // predecessor. The true edge is between them.
      const int sweep = 400;
      const double span = 1.35;
      double? lastSelf;
      double? firstPrev;
      for (var k = 0; k <= sweep; k++) {
        final double t = k / sweep;
        final double angle = extents[i].start - r.dir * (r.capHalf * span) * t;
        final Rgba pixel = raster.atPoint(r.at(radius, angle));
        if (pixel.a != 255) break;
        if (firstPrev == null &&
            distanceToFill(pixel, c.segments[i].fill) <= c.tolerance) {
          lastSelf = t;
          continue;
        }
        if (lastSelf != null &&
            distanceToFill(pixel, c.segments[predecessor].fill) <=
                c.tolerance) {
          firstPrev = t;
          break;
        }
      }
      if (lastSelf == null || firstPrev == null) continue;
      final double gap = (firstPrev - lastSelf) * r.capHalf * span * radius;
      if (gap > 4.0) {
        violations.add(
          '${c.name}: head $i edge at r=${radius.toStringAsFixed(1)} is '
          '${gap.toStringAsFixed(2)}px of neither colour, not a clean edge',
        );
        continue;
      }
      final double t = (lastSelf + firstPrev) / 2;
      final Offset crossing = r.at(
        radius,
        extents[i].start - r.dir * (r.capHalf * span) * t,
      );
      final double radiusFromCap = (crossing - capCentre).distance;
      final double error = (radiusFromCap - r.cap).abs();
      samples++;
      if (error > 2.0) {
        violations.add(
          '${c.name}: head $i boundary is not a cap circle at '
          'r=${radius.toStringAsFixed(1)}: distance from cap centre '
          '${radiusFromCap.toStringAsFixed(2)} vs cap '
          '${r.cap.toStringAsFixed(2)}',
        );
      }
    }
    if (samples <= radialSteps) {
      violations.add(
        '${c.name}: head $i boundary was measurable at only $samples of '
        '${radialSteps + 1} radii, so it is not a full cap edge',
      );
    }
  }
  return violations;
}

/// E. Structural check usable when exact fractions are unknown (animation).
/// Walks the centreline and confirms the colour runs are exactly the expected
/// segments, once each, in data order.
List<String> checkRunStructure(
  Raster raster,
  Ring r,
  List<WovenFill> fills,
  List<int> expectedOrder,
  String label, {
  int tolerance = 6,
  int maxTransitionSamples = 26,
  double shadow = 0.0,
}) {
  const int samples = 2880;
  final List<int> classified = <int>[];
  for (var s = 0; s < samples; s++) {
    // Walk the drawing direction, so the runs come out in data order for both
    // senses of rotation rather than reversed for counter-clockwise.
    final double angle = r.startAngle + r.dir * s * 2 * math.pi / samples;
    final Rgba pixel = raster.atPoint(r.at(r.track, angle));
    if (pixel.a != 255) return <String>['$label: transparent centreline pixel'];
    var best = -1;
    var bestDistance = 1 << 30;
    for (var i = 0; i < fills.length; i++) {
      final int d = distanceToFill(pixel, fills[i], shadow: shadow);
      if (d < bestDistance) {
        bestDistance = d;
        best = i;
      }
    }
    classified.add(bestDistance <= tolerance ? best : -1);
  }

  // Collapse to runs.
  final List<(int, int)> runs = <(int, int)>[];
  for (final int v in classified) {
    if (runs.isNotEmpty && runs.last.$1 == v) {
      runs[runs.length - 1] = (v, runs.last.$2 + 1);
    } else {
      runs.add((v, 1));
    }
  }
  // Rotate so the list starts at a run boundary rather than mid-run.
  if (runs.length > 1 && runs.first.$1 == runs.last.$1) {
    final (int, int) first = runs.removeAt(0);
    runs[runs.length - 1] = (first.$1, runs.last.$2 + first.$2);
  }

  final List<String> violations = <String>[];
  for (final (int value, int count) in runs) {
    if (value == -1 && count > maxTransitionSamples) {
      violations.add(
        '$label: $count consecutive unrecognised centreline samples '
        '(${(count * 360 / samples).toStringAsFixed(1)} degrees of foreign colour)',
      );
    }
  }
  final List<int> order = <int>[
    for (final (int value, int _) in runs)
      if (value != -1) value,
  ];
  // Merge neighbours that became split only by an antialiased transition.
  final List<int> merged = <int>[];
  for (final int v in order) {
    if (merged.isEmpty || merged.last != v) merged.add(v);
  }
  if (merged.length > 1 && merged.first == merged.last) {
    merged.removeLast();
  }

  if (merged.length != expectedOrder.length) {
    violations.add(
      '$label: saw ${merged.length} colour runs $merged, '
      'expected ${expectedOrder.length} $expectedOrder',
    );
    return violations;
  }
  final int offset = merged.indexOf(expectedOrder.first);
  if (offset < 0) {
    violations.add(
      '$label: expected segment ${expectedOrder.first} is missing',
    );
    return violations;
  }
  for (var i = 0; i < expectedOrder.length; i++) {
    if (merged[(offset + i) % merged.length] != expectedOrder[i]) {
      violations.add(
        '$label: colour order $merged does not match data order $expectedOrder',
      );
      break;
    }
  }
  return violations;
}

// ===========================================================================
// Catalog data
// ===========================================================================

const Color cRed = Color(0xFFE0234B);
const Color cGreen = Color(0xFF12A05F);
const Color cBlue = Color(0xFF2563D8);
const Color cAmber = Color(0xFFF0A21B);
const Color cPurple = Color(0xFF7B3FE4);
const Color cTeal = Color(0xFF0FA3A3);
const Color cPink = Color(0xFFE85BB0);
const Color cNavy = Color(0xFF1B2A5B);
const Color cLime = Color(0xFF7DC22B);
const Color cRust = Color(0xFFC1521F);

const List<Color> tenColors = <Color>[
  cRed,
  cGreen,
  cBlue,
  cAmber,
  cPurple,
  cTeal,
  cPink,
  cNavy,
  cLime,
  cRust,
];

List<WovenSegment> solids(
  List<double> values, [
  List<Color> colors = tenColors,
]) => <WovenSegment>[
  for (var i = 0; i < values.length; i++)
    WovenSegment(value: values[i], fill: WovenFill.solid(colors[i])),
];

void main() {
  group('R7 dense cyclic ownership', () {
    const colors = <Color>[
      Color(0xFFFF0000),
      Color(0xFF00FF00),
      Color(0xFF0000FF),
      Color(0xFFFFFF00),
      Color(0xFFFF00FF),
      Color(0xFF00FFFF),
      Color(0xFFFFFFFF),
      Color(0xFF000000),
    ];
    for (final clockwise in <bool>[true, false]) {
      testWidgets(
        'B56 dense heads retain cyclic ownership clockwise=$clockwise',
        (tester) async {
          for (final angle in <double>[0, .37]) {
            for (final alpha in <int>[255, 128]) {
              for (final bordered in <bool>[false, true]) {
                for (final animation in WovenRingAnimation.values) {
                  final style = WovenRingStyle(
                    thicknessFraction: .3,
                    overlapFraction: 1,
                    startAngle: angle,
                    clockwise: clockwise,
                    surfaceColor: const Color(0x00000000),
                  );
                  final r = Ring(
                    side: side,
                    thicknessFraction: .3,
                    overlapFraction: 1,
                    startAngle: angle,
                    clockwise: clockwise,
                  );
                  final complete = extentsFor(r, List<double>.filled(8, .125));
                  final key = GlobalKey();
                  await tester.pumpWidget(const SizedBox.shrink());
                  await pump(
                    tester,
                    key,
                    WovenRingChart(
                      animation: animation,
                      style: style,
                      segments: <WovenSegment>[
                        for (var i = 0; i < 8; i++)
                          WovenSegment.solid(
                            1,
                            colors[i].withAlpha(alpha),
                            border: bordered
                                ? const WovenBorder(
                                    color: Color(0xFFFFFFFF),
                                    widthFraction: .05,
                                  )
                                : null,
                          ),
                      ],
                    ),
                  );
                  var previous = 0;
                  for (final millis
                      in animation == WovenRingAnimation.none
                          ? <int>[1000]
                          : <int>[250, 550, 900, 999, 1000]) {
                    await tester.pump(
                      Duration(milliseconds: millis - previous),
                    );
                    previous = millis;
                    final raster = await capture(tester, key);
                    final progress = animation == WovenRingAnimation.none
                        ? 1.0
                        : Curves.easeInOutCubic.transform(millis / 1000);
                    final visible = <Extent>[];
                    final active = <int>[];
                    for (var i = 0; i < 8; i++) {
                      final full = complete[i];
                      var end = full.end;
                      var present = true;
                      if (progress < 1 &&
                          animation == WovenRingAnimation.sweep) {
                        final distance = math.min(
                          r.dir * (full.end - complete.first.start),
                          progress * 2 * math.pi,
                        );
                        end = complete.first.start + r.dir * distance;
                        present = r.dir * (end - full.start) >= 0;
                      } else if (progress < 1 &&
                          animation == WovenRingAnimation.grow) {
                        final opened =
                            ((progress - .35 / 8 * i) / (1 - .35 / 8 * 7))
                                .clamp(0.0, 1.0);
                        end = full.start + (full.end - full.start) * opened;
                        present = opened > 0;
                      }
                      visible.add(
                        Extent(
                          full.start,
                          end,
                          full.headTip,
                          end + r.dir * r.capHalf,
                        ),
                      );
                      if (present) active.add(i);
                    }
                    var checked = 0;
                    var borderChecked = 0;
                    for (var y = 12; y < 468; y += 4) {
                      for (var x = 12; x < 468; x += 4) {
                        final p = Offset(x + .5, y + .5);
                        if (active.any(
                          (i) => signedDistance(r, visible[i], p).abs() < 2,
                        )) {
                          continue;
                        }
                        // A contiguous run of covering capsules has one winner:
                        // its last cyclic successor. This remains well-defined
                        // when short revealed arcs have overlapping end caps.
                        final covered = <int>{
                          for (final i in active)
                            if (signedDistance(r, visible[i], p) < 0) i,
                        };
                        final winners = <int>[
                          for (final i in covered)
                            if (!covered.contains((i + 1) % 8)) i,
                        ];
                        if (winners.length != 1) continue;
                        final owner = winners.single;
                        final depth = -signedDistance(r, visible[owner], p);
                        final borderWidth = r.thickness * .05;
                        if (bordered && (depth - borderWidth).abs() < 2) {
                          continue;
                        }
                        final isBorder = bordered && depth < borderWidth;
                        final expected = isBorder
                            ? const Color(0xFFFFFFFF)
                            : colors[owner];
                        final a = isBorder ? 255 : alpha;
                        final pixel = raster.at(x, y);
                        final label =
                            '$clockwise angle=$angle alpha=$alpha border=$bordered $animation ms=$millis ($x,$y) owner=$owner progress=$progress actual=$pixel active=$active distances=${[for (final i in active) signedDistance(r, visible[i], p)]} along=${[for (final i in active) alongSegment(r, visible[i], p)]}';
                        expect(pixel.a, a, reason: label);
                        expect(
                          pixel.r,
                          closeTo(expected.r * a, 1),
                          reason: label,
                        );
                        expect(
                          pixel.g,
                          closeTo(expected.g * a, 1),
                          reason: label,
                        );
                        expect(
                          pixel.b,
                          closeTo(expected.b * a, 1),
                          reason: label,
                        );
                        checked++;
                        if (isBorder) borderChecked++;
                      }
                    }
                    expect(
                      checked,
                      greaterThan(100),
                      reason: '$animation $millis',
                    );
                    if (bordered) expect(borderChecked, greaterThan(5));
                  }
                }
              }
            }
          }
        },
      );
    }
    testWidgets(
      'F21 dense ownership persists through data transition boundaries',
      (tester) async {
        const destination = <double>[.2, .08, .12, .1, .15, .1, .125, .125];
        for (final clockwise in <bool>[true, false]) {
          final style = WovenRingStyle(
            thicknessFraction: .3,
            overlapFraction: 1,
            startAngle: -.23,
            clockwise: clockwise,
            smallValuePolicy: WovenSmallValuePolicy.allowVanish,
          );
          final key = GlobalKey();
          WovenRingChart chart(List<double> values) => WovenRingChart(
            animation: WovenRingAnimation.none,
            transitionDuration: const Duration(seconds: 1),
            style: style,
            segments: <WovenSegment>[
              for (var i = 0; i < 8; i++)
                WovenSegment.solid(
                  values[i],
                  colors[i],
                  border: const WovenBorder(
                    color: Color(0xFFFFFFFF),
                    widthFraction: .05,
                  ),
                ),
            ],
          );
          await tester.pumpWidget(const SizedBox.shrink());
          await pump(tester, key, chart(List<double>.filled(8, .125)));
          await pump(tester, key, chart(destination));
          var previous = 0;
          for (final ms in <int>[1, 250, 500, 999, 1000]) {
            await tester.pump(Duration(milliseconds: ms - previous));
            previous = ms;
            final t = Curves.easeInOut.transform(ms / 1000);
            final fractions = <double>[
              for (final end in destination) .125 + (end - .125) * t,
            ];
            final c = Case(
              name: 'dense transition $clockwise $ms',
              style: style,
              segments: chart(fractions).segments,
              margin: 10,
              tolerance: 1,
              expectedFractions: fractions,
            );
            final raster = await capture(tester, key);
            expect(checkOwnership(raster, c), isEmpty);
            expect(checkSilhouette(raster, c), isEmpty);
          }
        }
      },
    );
    testWidgets(
      'C7 shadow entrance excludes the entire independently measured hole',
      (tester) async {
        for (final clockwise in <bool>[true, false]) {
          for (final animation in <WovenRingAnimation>[
            WovenRingAnimation.sweep,
            WovenRingAnimation.grow,
          ]) {
            final key = GlobalKey();
            await tester.pumpWidget(const SizedBox.shrink());
            await pump(
              tester,
              key,
              WovenRingChart(
                animation: animation,
                style: WovenRingStyle(
                  clockwise: clockwise,
                  shadow: const WovenShadow(),
                ),
                segments: <WovenSegment>[
                  WovenSegment.solid(
                    1,
                    const Color(0xFF00FF00),
                    border: const WovenBorder(
                      color: Color(0xFF000000),
                      widthFraction: .05,
                    ),
                  ),
                ],
              ),
            );
            await tester.pump(const Duration(milliseconds: 433));
            final raster = await capture(tester, key);
            const inner = (240 - 480 * .2 * (.1 * 3 + .05)) * (1 - 2 * .2);
            var checked = 0;
            for (var y = 0; y < 480; y++) {
              for (var x = 0; x < 480; x++) {
                if ((Offset(x + .5, y + .5) - const Offset(240, 240)).distance <
                    inner - 2) {
                  expect(
                    raster.at(x, y).a,
                    0,
                    reason: '$clockwise $animation hole ($x,$y)',
                  );
                  checked++;
                }
              }
            }
            expect(checked, greaterThan(40000));
          }
        }
      },
    );
  });

  // =========================================================================
  // Section A - pure geometry and data, no canvas
  // =========================================================================

  group('A. geometry and data', () {
    test(
      'A1 cap radius is exactly half the thickness at every thickness fraction',
      () {
        for (final double bf in <double>[
          0.10,
          0.12,
          0.15,
          0.20,
          0.25,
          0.30,
          0.4,
        ]) {
          final WovenRingStyle style = WovenRingStyle(thicknessFraction: bf);
          final WovenRingGeometry g = WovenRingGeometry.forSize(
            const Size.square(side),
            style,
          );
          expect(
            g.capRadius,
            closeTo(g.thickness / 2, 1e-12),
            reason: 'thicknessFraction=$bf',
          );
          // Silhouette closes exactly on the outer circle.
          expect(
            g.trackRadius + g.capRadius,
            closeTo(g.outerRadius, 1e-9),
            reason: 'thicknessFraction=$bf',
          );
          expect(
            g.innerRadius,
            closeTo(g.trackRadius - g.capRadius, 1e-12),
            reason: 'thicknessFraction=$bf',
          );
          // And matches the independently derived ring.
          final Ring r = Ring(
            side: side,
            thicknessFraction: style.resolvedThicknessFraction,
            overlapFraction: style.resolvedOverlapFraction,
            startAngle: style.resolvedStartAngle,
            clockwise: true,
          );
          expect(
            g.thickness,
            closeTo(r.thickness, 1e-9),
            reason: 'thicknessFraction=$bf',
          );
          expect(
            g.trackRadius,
            closeTo(r.track, 1e-9),
            reason: 'thicknessFraction=$bf',
          );
          expect(
            g.jointLag,
            closeTo(r.jointLag, 1e-9),
            reason: 'thicknessFraction=$bf',
          );
        }
      },
    );

    test('A2 fractions are finite, ordered, and sum to one', () {
      final List<List<double>> inputs = <List<double>>[
        <double>[25, 25, 25, 25],
        <double>[1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
        <double>[0.3, 39.7, 25, 35],
        <double>[100],
        <double>[-5, 10, 0, 20],
        <double>[double.nan, 10, 20],
        <double>[double.infinity, 10, 20],
        <double>[1e308, 1e308, 1e308],
        <double>[1e-300, 1, 1],
        <double>[0, 0, 0],
      ];
      for (final WovenSmallValuePolicy policy in WovenSmallValuePolicy.values) {
        for (final List<double> input in inputs) {
          final List<double> f = wovenSegmentFractions(
            input,
            minimumFraction: 0.0736,
            policy: policy,
          );
          expect(f.length, input.length, reason: '$policy $input');
          for (final double v in f) {
            expect(v.isFinite, isTrue, reason: '$policy $input -> $f');
            expect(
              v,
              greaterThanOrEqualTo(0.0),
              reason: '$policy $input -> $f',
            );
          }
          final double total = f.fold<double>(0, (double a, double b) => a + b);
          if (input.any((double v) => v.isFinite && v > 0)) {
            expect(total, closeTo(1.0, 1e-9), reason: '$policy $input -> $f');
          } else {
            expect(total, closeTo(0.0, 1e-9), reason: '$policy $input -> $f');
          }
        }
      }
    });

    test('A3 empty input yields empty output', () {
      for (final WovenSmallValuePolicy policy in WovenSmallValuePolicy.values) {
        expect(
          wovenSegmentFractions(
            const <double>[],
            minimumFraction: 0.07,
            policy: policy,
          ),
          isEmpty,
        );
      }
    });

    test('A4 enforce raises every positive value to the minimum', () {
      const double minimum = 0.0736;
      final List<double> f = wovenSegmentFractions(
        <double>[0.3, 39.7, 25, 35],
        minimumFraction: minimum,
        policy: WovenSmallValuePolicy.enforce,
      );
      for (var i = 0; i < f.length; i++) {
        expect(
          f[i],
          greaterThanOrEqualTo(minimum - 1e-9),
          reason: 'index $i of $f',
        );
      }
      expect(
        f.fold<double>(0, (double a, double b) => a + b),
        closeTo(1, 1e-9),
      );
    });

    test(
      'A4b enforce retains finite positives across the full double range',
      () {
        const List<double> values = <double>[
          double.minPositive,
          0,
          double.maxFinite,
          1e-300,
          double.infinity,
        ];
        for (final double minimum in <double>[0.1, 0.4]) {
          final List<double> fractions = wovenSegmentFractions(
            values,
            minimumFraction: minimum,
            policy: WovenSmallValuePolicy.enforce,
          );
          for (var index = 0; index < values.length; index++) {
            if (values[index].isFinite && values[index] > 0) {
              expect(
                fractions[index],
                greaterThanOrEqualTo(math.min(minimum, 1 / 3)),
                reason: 'positive input $index vanished at minimum=$minimum',
              );
            } else {
              expect(fractions[index], 0.0);
            }
          }
          expect(
            fractions.fold<double>(0, (double a, double b) => a + b),
            closeTo(1, 1e-9),
          );
        }
      },
    );

    test('A5 enforce is stable either side of the threshold', () {
      const double minimum = 0.0736;
      // Sweep a value through the threshold and confirm the output never jumps.
      List<double>? previous;
      for (var step = 0; step <= 400; step++) {
        final double v = 0.5 + step * 0.05;
        final List<double> f = wovenSegmentFractions(
          <double>[v, 30, 30, 30],
          minimumFraction: minimum,
          policy: WovenSmallValuePolicy.enforce,
        );
        if (previous != null) {
          for (var i = 0; i < f.length; i++) {
            expect(
              (f[i] - previous[i]).abs(),
              lessThan(0.01),
              reason: 'discontinuity at v=$v index=$i: $previous -> $f',
            );
          }
        }
        previous = f;
      }
    });

    test('A6 too many entries falls back to an honest equal share', () {
      final List<double> f = wovenSegmentFractions(
        List<double>.filled(40, 1),
        minimumFraction: 0.0736,
        policy: WovenSmallValuePolicy.enforce,
      );
      for (final double v in f) {
        expect(v, closeTo(1 / 40, 1e-9));
      }
    });

    test(
      'A7 allowVanish only removes values under its documented threshold',
      () {
        const double minimum = 0.0736;
        const double vanishBelow = minimum / 2;
        final List<double> values = <double>[
          vanishBelow * 0.4 * 100,
          vanishBelow * 1.6 * 100,
          40,
          40,
        ];
        final List<double> f = wovenSegmentFractions(
          values,
          minimumFraction: minimum,
          policy: WovenSmallValuePolicy.allowVanish,
        );
        expect(f[0], 0.0, reason: 'below threshold must vanish: $f');
        expect(f[1], greaterThan(0.0), reason: 'above threshold must stay: $f');
        expect(
          f.fold<double>(0, (double a, double b) => a + b),
          closeTo(1, 1e-9),
        );
      },
    );

    test('A8 CW and CCW mirror: same start, same order, opposite sweep', () {
      const WovenRingStyle cw = WovenRingStyle(startAngle: 0.4);
      const WovenRingStyle ccw = WovenRingStyle(
        startAngle: 0.4,
        clockwise: false,
      );
      final WovenRingGeometry gcw = WovenRingGeometry.forSize(
        const Size.square(side),
        cw,
      );
      final WovenRingGeometry gccw = WovenRingGeometry.forSize(
        const Size.square(side),
        ccw,
      );
      const List<double> f = <double>[0.4, 0.35, 0.25];
      final List<WovenSegmentExtent> a = gcw.extents(f, 0.4, clockwise: true);
      final List<WovenSegmentExtent> b = gccw.extents(f, 0.4, clockwise: false);
      expect(a.first.boundaryStart, closeTo(0.4, 1e-12));
      expect(b.first.boundaryStart, closeTo(0.4, 1e-12));
      for (var i = 0; i < f.length; i++) {
        // Mirror about the start angle.
        expect(
          a[i].boundaryEnd - 0.4,
          closeTo(-(b[i].boundaryEnd - 0.4), 1e-12),
          reason: 'index $i',
        );
        expect(
          a[i].start - 0.4,
          closeTo(-(b[i].start - 0.4), 1e-12),
          reason: 'index $i',
        );
      }
      // Each segment's tail lands exactly on the next segment's data boundary.
      for (var i = 0; i < f.length - 1; i++) {
        expect(a[i].end, closeTo(a[i + 1].boundaryStart, 1e-12));
        expect(b[i].end, closeTo(b[i + 1].boundaryStart, 1e-12));
      }
    });

    test('A9 palette cycling never repeats across the seam', () {
      for (var count = 1; count <= 24; count++) {
        final List<Color> colors = WovenPalette.cycle(
          WovenPalette.quartet,
          count,
        );
        expect(colors.length, count);
        for (var i = 0; i < count; i++) {
          if (count < 2) continue;
          expect(
            colors[i],
            isNot(colors[(i + 1) % count]),
            reason: 'count=$count repeated at $i: $colors',
          );
        }
      }
    });
  });

  // =========================================================================
  // Section B - static raster catalog. The heart of the gate.
  // =========================================================================

  final List<Case> catalog = <Case>[
    Case(
      name: 'B01 four equal CW',
      segments: solids(<double>[25, 25, 25, 25], tenColors),
      style: const WovenRingStyle(),
    ),
    Case(
      name: 'B02 four equal CCW',
      segments: solids(<double>[25, 25, 25, 25], tenColors),
      style: const WovenRingStyle(clockwise: false),
    ),
    Case(
      name: 'B03 four unequal CW',
      segments: solids(<double>[37, 19, 29, 15], tenColors),
      style: const WovenRingStyle(),
    ),
    Case(
      name: 'B04 four unequal CCW',
      segments: solids(<double>[37, 19, 29, 15], tenColors),
      style: const WovenRingStyle(clockwise: false),
    ),
    Case(
      name: 'B05 non-cardinal start CW',
      segments: solids(<double>[37, 19, 29, 15], tenColors),
      style: const WovenRingStyle(startAngle: 0.7331),
    ),
    Case(
      name: 'B06 non-cardinal start CCW',
      segments: solids(<double>[37, 19, 29, 15], tenColors),
      style: const WovenRingStyle(startAngle: 2.4312, clockwise: false),
    ),
    Case(
      name: 'B07 three segments',
      segments: solids(<double>[50, 30, 20], tenColors),
      style: const WovenRingStyle(),
    ),
    Case(
      name: 'B08 two segments CW',
      segments: solids(<double>[60, 40], tenColors),
      style: const WovenRingStyle(),
    ),
    Case(
      name: 'B09 two segments CCW',
      segments: solids(<double>[60, 40], tenColors),
      style: const WovenRingStyle(clockwise: false),
    ),
    Case(
      name: 'B10 two equal segments',
      segments: solids(<double>[50, 50], tenColors),
      style: const WovenRingStyle(),
    ),
    Case(
      name: 'B11 ten equal CW',
      segments: solids(List<double>.filled(10, 10), tenColors),
      style: const WovenRingStyle(),
    ),
    Case(
      name: 'B12 ten equal CCW',
      segments: solids(List<double>.filled(10, 10), tenColors),
      style: const WovenRingStyle(clockwise: false),
    ),
    Case(
      name: 'B13 ten unequal',
      segments: solids(<double>[6, 14, 8, 12, 9, 15, 7, 11, 10, 8], tenColors),
      style: const WovenRingStyle(),
    ),
    Case(
      name: 'B14 minimum thickness 0.12',
      segments: solids(<double>[37, 19, 29, 15], tenColors),
      style: const WovenRingStyle(thicknessFraction: 0.12),
      margin: 2.5,
    ),
    Case(
      name: 'B15 maximum thickness 0.30',
      segments: solids(<double>[37, 19, 29, 15], tenColors),
      style: const WovenRingStyle(thicknessFraction: 0.30),
    ),
    Case(
      name: 'B16 thickness clamps below range',
      segments: solids(<double>[37, 19, 29, 15], tenColors),
      style: const WovenRingStyle(thicknessFraction: 0.01),
      margin: 2.5,
    ),
    Case(
      name: 'B17 thickness clamps above range',
      segments: solids(<double>[37, 19, 29, 15], tenColors),
      style: const WovenRingStyle(thicknessFraction: 0.95),
    ),
    Case(
      name: 'B18 overlap 30 percent',
      segments: solids(<double>[37, 19, 29, 15], tenColors),
      style: const WovenRingStyle(overlapFraction: 0.30),
    ),
    Case(
      name: 'B19 overlap 90 percent',
      segments: solids(<double>[37, 19, 29, 15], tenColors),
      style: const WovenRingStyle(overlapFraction: 0.90),
    ),
    Case(
      name: 'B20 overlap 100 percent',
      segments: solids(<double>[37, 19, 29, 15], tenColors),
      style: const WovenRingStyle(overlapFraction: 1.0),
    ),
    Case(
      name: 'B21 overlap 25 percent CCW',
      segments: solids(<double>[37, 19, 29, 15], tenColors),
      style: const WovenRingStyle(overlapFraction: 0.25, clockwise: false),
    ),
    Case(
      name: 'B22 gradient along length',
      segments: <WovenSegment>[
        for (var i = 0; i < 4; i++)
          WovenSegment(
            value: <double>[37, 19, 29, 15][i],
            fill: WovenFill.shaded(tenColors[i], step: 0.08),
          ),
      ],
      style: const WovenRingStyle(),
    ),
    Case(
      name: 'B23 gradient tail to head',
      segments: <WovenSegment>[
        for (var i = 0; i < 4; i++)
          WovenSegment(
            value: <double>[37, 19, 29, 15][i],
            fill: WovenFill.shaded(tenColors[i], step: 0.08),
          ),
      ],
      style: const WovenRingStyle(
        gradientDirection: WovenGradientDirection.tailToHead,
      ),
    ),
    Case(
      name: 'B24 gradient across thickness',
      segments: <WovenSegment>[
        for (var i = 0; i < 4; i++)
          WovenSegment(
            value: <double>[37, 19, 29, 15][i],
            fill: WovenFill.shaded(tenColors[i], step: 0.08),
          ),
      ],
      style: const WovenRingStyle(
        gradientAxis: WovenGradientAxis.acrossThickness,
      ),
    ),
    Case(
      name: 'B25 mixed solid and gradient',
      segments: <WovenSegment>[
        for (var i = 0; i < 4; i++)
          WovenSegment(
            value: <double>[37, 19, 29, 15][i],
            fill: i.isOdd
                ? WovenFill.shaded(tenColors[i], step: 0.08)
                : WovenFill.solid(tenColors[i]),
          ),
      ],
      style: const WovenRingStyle(),
    ),
    Case(
      name: 'B26 all borders',
      segments: <WovenSegment>[
        for (var i = 0; i < 4; i++)
          WovenSegment(
            value: <double>[37, 19, 29, 15][i],
            fill: WovenFill.solid(tenColors[i]),
            border: const WovenBorder(),
          ),
      ],
      style: const WovenRingStyle(),
      margin: 5.0,
    ),
    Case(
      name: 'B27 mixed borders',
      segments: <WovenSegment>[
        for (var i = 0; i < 4; i++)
          WovenSegment(
            value: <double>[37, 19, 29, 15][i],
            fill: WovenFill.solid(tenColors[i]),
            border: i.isOdd ? const WovenBorder() : null,
          ),
      ],
      style: const WovenRingStyle(),
      margin: 5.0,
    ),
    Case(
      name: 'B28 diagnostic wide borders',
      segments: <WovenSegment>[
        for (var i = 0; i < 4; i++)
          WovenSegment(
            value: <double>[37, 19, 29, 15][i],
            fill: WovenFill.solid(tenColors[i]),
            border: const WovenBorder(widthFraction: 0.05),
          ),
      ],
      style: const WovenRingStyle(),
      margin: 9.0,
    ),
    Case(
      name: 'B29 darker-fill borders',
      segments: <WovenSegment>[
        for (var i = 0; i < 4; i++)
          WovenSegment(
            value: <double>[37, 19, 29, 15][i],
            fill: WovenFill.solid(tenColors[i]),
            border: const WovenBorder.darkerFill(),
          ),
      ],
      style: const WovenRingStyle(),
      margin: 5.0,
    ),
    Case(
      name: 'B30 head shadow',
      segments: solids(<double>[37, 19, 29, 15], tenColors),
      style: const WovenRingStyle(shadow: WovenShadow()),
      // The shadow darkens the predecessor under each head, so keep clear of it.
      margin: 6.0,
      tolerance: 6,
    ),
    Case(
      name: 'B31 tiny value enforced',
      segments: solids(<double>[0.3, 39.7, 25, 35], tenColors),
      style: const WovenRingStyle(),
    ),
    Case(
      name: 'B32 tiny value enforced CCW',
      segments: solids(<double>[0.3, 39.7, 25, 35], tenColors),
      style: const WovenRingStyle(clockwise: false),
    ),
    Case(
      name: 'B33 tiny value allowed to vanish',
      segments: solids(<double>[0.3, 39.7, 25, 35], tenColors),
      style: const WovenRingStyle(
        smallValuePolicy: WovenSmallValuePolicy.allowVanish,
      ),
    ),
    Case(
      name: 'B34 zero mixed with data',
      segments: solids(<double>[30, 0, 40, 30], tenColors),
      style: const WovenRingStyle(),
    ),
    Case(
      name: 'B35 dense twelve equal',
      segments: <WovenSegment>[
        for (var i = 0; i < 12; i++)
          WovenSegment(value: 1, fill: WovenFill.solid(tenColors[i % 10])),
      ],
      style: const WovenRingStyle(),
      margin: 2.5,
    ),
    Case(
      name: 'B36 selected border only',
      segments: solids(<double>[37, 19, 29, 15], tenColors),
      style: const WovenRingStyle(),
      margin: 5.0,
    ),
    Case(
      name: 'B37 dark surfaceColor',
      segments: solids(<double>[37, 19, 29, 15], tenColors),
      style: const WovenRingStyle(surfaceColor: Color(0xFF101418)),
    ),
    Case(
      name: 'B38 wide thickness with 90 percent overlap',
      segments: solids(<double>[37, 19, 29, 15], tenColors),
      style: const WovenRingStyle(
        thicknessFraction: 0.30,
        overlapFraction: 0.90,
      ),
    ),
    Case(
      name: 'B39 thin thickness with 90 percent overlap',
      segments: solids(<double>[37, 19, 29, 15], tenColors),
      style: const WovenRingStyle(
        thicknessFraction: 0.12,
        overlapFraction: 0.90,
      ),
      margin: 2.5,
    ),
    // Three segments is the smallest ring where a whole triple of silhouettes can
    // overlap one pixel, and two segments with a very short one is where both
    // joints merge. Both are the cases the generic cyclic mask is least likely
    // to survive.
    Case(
      name: 'B41 three segments with a short one',
      segments: solids(<double>[80, 10, 10], tenColors),
      style: const WovenRingStyle(),
    ),
    Case(
      name: 'B42 three segments short in the middle',
      segments: solids(<double>[10, 80, 10], tenColors),
      style: const WovenRingStyle(),
    ),
    Case(
      name: 'B43 three segments with a short one CCW',
      segments: solids(<double>[80, 10, 10], tenColors),
      style: const WovenRingStyle(clockwise: false),
    ),
    Case(
      name: 'B44 two segments ninety ten',
      segments: solids(<double>[90, 10], tenColors),
      style: const WovenRingStyle(),
    ),
    Case(
      name: 'B45 two segments ten ninety',
      segments: solids(<double>[10, 90], tenColors),
      style: const WovenRingStyle(),
    ),
    Case(
      name: 'B46 two segments ninety ten CCW',
      segments: solids(<double>[90, 10], tenColors),
      style: const WovenRingStyle(clockwise: false),
    ),
    // Just past the point where a segment's own head and tail caps touch, which
    // is where its outline self-intersects: f0 * tau + jointLag + 2 * capHalf
    // reaches a full turn at about 88 percent for the default style.
    Case(
      name: 'B49 two segments at the self-contact threshold',
      segments: solids(<double>[89, 11], tenColors),
      style: const WovenRingStyle(),
    ),
    Case(
      name: 'B50 two segments just past self-contact',
      segments: solids(<double>[91.5, 8.5], tenColors),
      style: const WovenRingStyle(),
    ),
    Case(
      name: 'B51 two segments past self-contact CCW',
      segments: solids(<double>[91.5, 8.5], tenColors),
      style: const WovenRingStyle(clockwise: false),
    ),
    Case(
      name: 'B52 three segments with a self-contacting first',
      segments: solids(<double>[84, 8, 8], tenColors),
      style: const WovenRingStyle(),
    ),
    Case(
      name: 'B47 four segments with a short one',
      segments: solids(<double>[70, 10, 10, 10], tenColors),
      style: const WovenRingStyle(),
    ),
    Case(
      name: 'B48 three segments short one wide overlap',
      segments: solids(<double>[80, 10, 10], tenColors),
      style: const WovenRingStyle(overlapFraction: 1.0),
    ),
    Case(
      name: 'B40 negative start angle wrap',
      segments: solids(<double>[37, 19, 29, 15], tenColors),
      style: const WovenRingStyle(startAngle: -3.9),
    ),
  ];

  group('B. static raster catalog', () {
    for (final bool clockwise in <bool>[true, false]) {
      for (final Color surface in <Color>[
        WovenPalette.surface,
        const Color(0x00000000),
        const Color(0x800000FF),
      ]) {
        testWidgets('B60 identical translucent owners are uniform '
            'clockwise=$clockwise surface=$surface', (
          WidgetTester tester,
        ) async {
          const Color ink = Color(0x80FF0000);
          final Raster reference = await render(
            tester,
            CustomPaint(
              painter: _BorderCompositionReference(
                fill: ink,
                border: const Color(0x00000000),
                surface: surface,
                segmentOpacity: 1,
                lineOpacity: 1,
              ),
            ),
          );
          final Rgba expected = reference.at(240, 240);
          for (final (double, double) proportions in <(double, double)>[
            (0.20, 0.50),
            (0.30, 1),
          ]) {
            for (final double startAngle in <double>[-math.pi / 2, 0.37]) {
              final Ring geometry = Ring(
                side: side,
                thicknessFraction: proportions.$1,
                overlapFraction: proportions.$2,
                startAngle: startAngle,
                clockwise: clockwise,
              );
              Raster? single;
              for (final int count in <int>[1, 2, 4, 8]) {
                final Raster actual = await render(
                  tester,
                  WovenRingChart(
                    animation: WovenRingAnimation.none,
                    style: WovenRingStyle(
                      surfaceColor: surface,
                      thicknessFraction: proportions.$1,
                      overlapFraction: proportions.$2,
                      startAngle: startAngle,
                      clockwise: clockwise,
                    ),
                    segments: <WovenSegment>[
                      for (var i = 0; i < count; i++)
                        const WovenSegment(
                          value: 1,
                          fill: WovenFill.solid(ink),
                        ),
                    ],
                  ),
                );
                if (count == 1) single = actual;
                var samples = 0;
                final List<String> violations = <String>[];
                for (var y = 0; y < actual.height; y++) {
                  for (var x = 0; x < actual.width; x++) {
                    final double radius =
                        (Offset(x + 0.5, y + 0.5) - geometry.center).distance;
                    // Only the actual hole and outer silhouette have AA.
                    // Every internal ownership boundary remains in the scan.
                    if (radius < geometry.inner + 5 ||
                        radius > geometry.outer - 5) {
                      continue;
                    }
                    samples++;
                    final Rgba pixel = actual.at(x, y);
                    final Rgba control = single!.at(x, y);
                    if (channelDistance(pixel, expected) > 1 ||
                        (pixel.a - expected.a).abs() > 1 ||
                        channelDistance(pixel, control) > 1 ||
                        (pixel.a - control.a).abs() > 1) {
                      if (violations.length < 6) {
                        violations.add(
                          '($x,$y)=$pixel reference=$expected single=$control',
                        );
                      }
                    }
                  }
                }
                expect(samples, greaterThan(100000));
                expect(
                  violations,
                  isEmpty,
                  reason:
                      'count=$count thickness=${proportions.$1} '
                      'overlap=${proportions.$2} start=$startAngle: '
                      '${violations.join('; ')}',
                );
              }
            }
          }
        });
      }
    }
    for (final bool clockwise in <bool>[true, false]) {
      testWidgets(
        'B59 mixed color-space owners preserve final laps clockwise=$clockwise',
        (WidgetTester tester) async {
          const Color white = Color(0xFFFFFFFF);
          const Color black = Color(0xFF000000);
          const Color p3Black = Color.from(
            alpha: 1,
            red: 0,
            green: 0,
            blue: 0,
            colorSpace: ui.ColorSpace.displayP3,
          );
          const List<Color> fills = <Color>[
            Color(0xFFFF0000),
            Color(0xFF00FF00),
            Color(0xFF0000FF),
            Color(0xFFFFFF00),
          ];
          for (final int count in <int>[4, 8, 30]) {
            for (final (double thickness, double overlap) proportions
                in <(double, double)>[(0.20, 0.50), (0.30, 1)]) {
              for (final double startAngle in <double>[0, 0.37]) {
                final Ring geometry = Ring(
                  side: side,
                  thicknessFraction: proportions.$1,
                  overlapFraction: proportions.$2,
                  startAngle: startAngle,
                  clockwise: clockwise,
                );
                // Equal values share the ring equally, including the documented
                // no-room-for-minima case. No production fraction helper is used.
                final List<Extent> extents = extentsFor(
                  geometry,
                  List<double>.filled(count, 1 / count),
                );
                final List<int> active = List<int>.generate(
                  count,
                  (int i) => i,
                );
                final double borderWidth = geometry.thickness * 0.05;
                for (final double opacity in <double>[0.25, 0.5]) {
                  Future<Raster> image(int p3Owner) async {
                    await tester.pumpWidget(const SizedBox.shrink());
                    return render(
                      tester,
                      WovenRingChart(
                        animation: WovenRingAnimation.none,
                        style: WovenRingStyle(
                          thicknessFraction: proportions.$1,
                          overlapFraction: proportions.$2,
                          startAngle: startAngle,
                          clockwise: clockwise,
                          surfaceColor: white,
                        ),
                        segments: <WovenSegment>[
                          for (var i = 0; i < count; i++)
                            WovenSegment.solid(
                              1,
                              fills[i % fills.length],
                              opacity: opacity,
                              border: WovenBorder(
                                color: i == p3Owner ? p3Black : black,
                                widthFraction: 0.05,
                              ),
                            ),
                        ],
                      ),
                    );
                  }

                  final Raster srgb = await image(-1);
                  for (final int groupedOwner in <int>[0, count - 1]) {
                    final Raster mixed = await image(groupedOwner);
                    var fillSamples = 0;
                    var borderSamples = 0;
                    var groupedSamples = 0;
                    var nongroupedSamples = 0;
                    var firstOwnerSamples = 0;
                    var lastOwnerSamples = 0;
                    for (var radial = 0; radial < 13; radial++) {
                      final double radius =
                          geometry.inner +
                          3 +
                          (geometry.thickness - 6) * radial / 12;
                      for (var angular = 0; angular < 1440; angular++) {
                        final Offset requested = geometry.at(
                          radius,
                          angular * 2 * math.pi / 1440,
                        );
                        final Offset point = Offset(
                          (requested.dx - 0.5).round() + 0.5,
                          (requested.dy - 0.5).round() + 0.5,
                        );
                        final int owner = ownerAt(
                          geometry,
                          extents,
                          active,
                          point,
                        );
                        if (owner < 0) continue;
                        // Stay clear of every silhouette and cap boundary that
                        // could make a geometric owner or stroke ambiguous.
                        if (extents.any(
                          (Extent extent) =>
                              signedDistance(geometry, extent, point).abs() <
                                  1.5 ||
                              ((point -
                                                  geometry.at(
                                                    geometry.track,
                                                    extent.start,
                                                  ))
                                              .distance -
                                          geometry.cap)
                                      .abs() <
                                  1.5 ||
                              ((point - geometry.at(geometry.track, extent.end))
                                              .distance -
                                          geometry.cap)
                                      .abs() <
                                  1.5,
                        )) {
                          continue;
                        }
                        final double inset = -signedDistance(
                          geometry,
                          extents[owner],
                          point,
                        );
                        final bool fill = inset > borderWidth + 1.5;
                        final bool border =
                            inset > 1.5 && inset < borderWidth - 1.5;
                        if (!fill && !border) continue;
                        final Color source = fill
                            ? fills[owner % fills.length]
                            : black;
                        final double alpha = (opacity * 255).round() / 255;
                        final List<double> expected = <double>[
                          (source.r * alpha + 1 - alpha) * 255,
                          (source.g * alpha + 1 - alpha) * 255,
                          (source.b * alpha + 1 - alpha) * 255,
                          255,
                        ];
                        final Rgba baseline = srgb.atPoint(point);
                        final Rgba actual = mixed.atPoint(point);
                        final String reason =
                            'mixed final owner count=$count '
                            'clockwise=$clockwise proportions=$proportions '
                            'startAngle=$startAngle opacity=$opacity '
                            'grouped=$groupedOwner owner=$owner point=$point '
                            'fill=$fill inset=$inset baseline=$baseline actual=$actual';
                        final List<int> before = <int>[
                          baseline.r,
                          baseline.g,
                          baseline.b,
                          baseline.a,
                        ];
                        final List<int> after = <int>[
                          actual.r,
                          actual.g,
                          actual.b,
                          actual.a,
                        ];
                        for (var channel = 0; channel < 4; channel++) {
                          expect(
                            before[channel],
                            closeTo(expected[channel], 1),
                            reason: '$reason sRGB oracle',
                          );
                          expect(
                            after[channel],
                            closeTo(expected[channel], 1),
                            reason: '$reason mixed oracle',
                          );
                          expect(
                            after[channel],
                            closeTo(before[channel], 1),
                            reason: '$reason equivalent ink',
                          );
                        }
                        if (fill) fillSamples++;
                        if (border) borderSamples++;
                        if (owner == groupedOwner) groupedSamples++;
                        if (owner != groupedOwner) nongroupedSamples++;
                        if (owner == 0) firstOwnerSamples++;
                        if (owner == count - 1) lastOwnerSamples++;
                      }
                    }
                    expect(fillSamples, greaterThan(200));
                    expect(borderSamples, greaterThan(100));
                    expect(groupedSamples, greaterThan(10));
                    expect(nongroupedSamples, greaterThan(200));
                    expect(firstOwnerSamples, greaterThan(10));
                    expect(lastOwnerSamples, greaterThan(10));
                  }
                }
              }
            }
          }
        },
      );
    }

    testWidgets('B58 border groups preserve their renderer color spaces', (
      WidgetTester tester,
    ) async {
      // Paint an independent flat control using the renderer's group
      // compositing. Each source keeps its own color space until drawing;
      // no encoded-channel CPU blend can serve as a wide-gamut oracle.
      const Color p3Green = Color.from(
        alpha: 1,
        red: 0,
        green: 1,
        blue: 0,
        colorSpace: ui.ColorSpace.displayP3,
      );
      const Color p3Blue = Color.from(
        alpha: 0.5,
        red: 0.1,
        green: 0.2,
        blue: 1,
        colorSpace: ui.ColorSpace.displayP3,
      );
      const Color p3Red = Color.from(
        alpha: 1,
        red: 1,
        green: 0,
        blue: 0,
        colorSpace: ui.ColorSpace.displayP3,
      );
      const Color blue = Color(0xFF0000FF);
      const List<(Color, Color, double)> sources = <(Color, Color, double)>[
        (p3Green, Color(0xFFFF0000), 1),
        (p3Green, Color(0x80FF0000), 1),
        (p3Green, Color(0x00000000), 1),
        (p3Blue, Color(0xFFFF0000), 0.5),
        (Color(0x800000FF), p3Red, 0.5),
        (p3Green, p3Red, 1),
      ];
      for (final bool clockwise in <bool>[true, false]) {
        for (final (Color ink, Color surface, double lineOpacity) in sources) {
          for (final double opacity in <double>[0.25, 0.5]) {
            await tester.pumpWidget(const SizedBox.shrink());
            final Raster reference = await render(
              tester,
              CustomPaint(
                painter: _BorderCompositionReference(
                  fill: blue,
                  border: ink,
                  surface: surface,
                  segmentOpacity: opacity,
                  lineOpacity: lineOpacity,
                ),
              ),
            );
            Rgba? singlePixel;
            for (final int count in <int>[1, 4]) {
              await tester.pumpWidget(const SizedBox.shrink());
              final Raster actual = await render(
                tester,
                WovenRingChart(
                  animation: WovenRingAnimation.none,
                  style: WovenRingStyle(
                    clockwise: clockwise,
                    surfaceColor: surface,
                  ),
                  segments: <WovenSegment>[
                    for (var i = 0; i < count; i++)
                      WovenSegment(
                        value: 1,
                        opacity: opacity,
                        fill: const WovenFill.solid(blue),
                        border: WovenBorder(
                          color: ink,
                          opacity: lineOpacity,
                          widthFraction: 0.05,
                        ),
                      ),
                  ],
                ),
              );
              // This pixel is 3.5px inside the circular outer edge and fully
              // inside its 4.8px border. Geometry and antialiasing cannot
              // justify a color change when identical owners are added.
              final Rgba pixel = actual.at(476, 240);
              final Rgba expected = reference.at(476, 240);
              final String reason =
                  'renderer group count=$count '
                  'clockwise=$clockwise opacity=$opacity border=$ink '
                  'lineOpacity=$lineOpacity surface=$surface pixel=$pixel '
                  'reference=$expected';
              for (final (int actual, int expected) channel in <(int, int)>[
                (pixel.r, expected.r),
                (pixel.g, expected.g),
                (pixel.b, expected.b),
                (pixel.a, expected.a),
              ]) {
                expect(channel.$1, closeTo(channel.$2, 1), reason: reason);
              }
              if (singlePixel != null) {
                expect(
                  channelDistance(pixel, singlePixel),
                  lessThanOrEqualTo(1),
                  reason: reason,
                );
                expect(pixel.a, closeTo(singlePixel.a, 1), reason: reason);
              }
              singlePixel = pixel;
            }
          }
        }
      }
    });

    testWidgets('B57 whole segment opacity combines fill and border once', (
      WidgetTester tester,
    ) async {
      // These are premultiplied source-over equations, independently derived
      // from the public whole-segment opacity contract. The raster reference
      // verifies the unattenuated fill/border first; it cannot silently bless
      // a border with the wrong alpha or an incorrect highlight override.
      List<double> premultiplied(Color color, {double opacity = 1}) {
        final double alpha = (color.a * opacity * 255).round() / 255;
        return <double>[
          color.r * alpha,
          color.g * alpha,
          color.b * alpha,
          alpha,
        ];
      }

      List<double> over(List<double> foreground, List<double> background) =>
          <double>[
            for (var c = 0; c < 4; c++)
              foreground[c] + background[c] * (1 - foreground[3]),
          ];

      void expectPremultiplied(
        Rgba pixel,
        List<double> expected,
        String reason,
      ) {
        final List<int> channels = <int>[pixel.r, pixel.g, pixel.b, pixel.a];
        for (var c = 0; c < 4; c++) {
          expect(channels[c], closeTo(expected[c] * 255, 1), reason: reason);
        }
      }

      const Color transparent = Color(0x00000000);
      const Color red = Color(0xFFFF0000);
      const Color black = Color(0xFF000000);
      const List<(Color, Color, Color, double, Color)> combinations =
          <(Color, Color, Color, double, Color)>[
            (red, black, transparent, 1, transparent),
            (red, black, Color(0xFFFFFFFF), 1, transparent),
            (red, black, Color(0x800000FF), 1, transparent),
            (
              Color(0x80FF0000),
              Color(0x80000000),
              Color(0x800000FF),
              0.5,
              transparent,
            ),
            (
              Color(0x80FF0000),
              Color(0x80000000),
              transparent,
              0.5,
              Color(0xFF00FF00),
            ),
          ];
      for (final int count in <int>[1, 4]) {
        for (final bool clockwise in <bool>[true, false]) {
          for (final bool highlighted in <bool>[false, true]) {
            for (final (
                  Color fill,
                  Color ink,
                  Color surface,
                  double lineOpacity,
                  Color ancestor,
                )
                in combinations) {
              final WovenBorder border = WovenBorder(
                color: ink,
                widthFraction: 0.05,
                opacity: lineOpacity,
              );
              final Ring geometry = Ring(
                side: side,
                thicknessFraction: 0.20,
                overlapFraction: 0.50,
                startAngle: 0,
                clockwise: clockwise,
              );
              final List<Offset> points = <Offset>[
                // Radial edge, well inside the 4.8px inside-only border.
                const Offset(476.5, 240.5),
                if (count > 1)
                  for (final Extent extent in extentsFor(
                    geometry,
                    List<double>.filled(count, 1 / count),
                  ).take(highlighted ? 1 : count))
                    geometry.at(geometry.track, extent.start) +
                        Offset(
                              math.sin(extent.start),
                              -math.cos(extent.start),
                            ) *
                            geometry.dir *
                            (geometry.cap - 2.4),
              ];
              Future<Raster> image(
                double opacity,
                Color chartSurface,
                Color backdrop,
              ) async {
                await tester.pumpWidget(const SizedBox.shrink());
                return render(
                  tester,
                  ColoredBox(
                    color: backdrop,
                    child: WovenRingChart(
                      style: WovenRingStyle(
                        startAngle: 0,
                        clockwise: clockwise,
                        surfaceColor: chartSurface,
                      ),
                      animation: WovenRingAnimation.none,
                      highlightedIndex: highlighted ? 0 : null,
                      highlightBorder: border,
                      segments: <WovenSegment>[
                        for (var i = 0; i < count; i++)
                          WovenSegment(
                            value: 1,
                            fill: WovenFill.solid(fill),
                            opacity: opacity,
                            border: highlighted
                                ? const WovenBorder(
                                    color: Color(0xFFFFFFFF),
                                    widthFraction: 0.05,
                                  )
                                : border,
                          ),
                      ],
                    ),
                  ),
                );
              }

              final Raster full = await image(1, transparent, transparent);
              final List<double> combined = over(
                premultiplied(ink, opacity: lineOpacity),
                premultiplied(fill),
              );
              for (final double opacity in <double>[0.25, 0.5]) {
                final Raster actual = await image(opacity, surface, ancestor);
                final double groupAlpha = (opacity * 255).round() / 255;
                for (final Offset point in points) {
                  final String reason =
                      'whole-segment composition count=$count '
                      'clockwise=$clockwise highlighted=$highlighted fill=$fill '
                      'border=$ink lineOpacity=$lineOpacity surface=$surface '
                      'ancestor=$ancestor opacity=$opacity point=$point';
                  final Rgba reference = full.atPoint(point);
                  expectPremultiplied(reference, combined, '$reason reference');
                  // Scale the complete independently verified raster exactly
                  // once, then place it over the configured surface/backdrop.
                  final List<double> attenuated = <double>[
                    reference.r / 255 * groupAlpha,
                    reference.g / 255 * groupAlpha,
                    reference.b / 255 * groupAlpha,
                    reference.a / 255 * groupAlpha,
                  ];
                  expectPremultiplied(
                    actual.atPoint(point),
                    over(
                      over(attenuated, premultiplied(surface)),
                      premultiplied(ancestor),
                    ),
                    reason,
                  );
                }
              }
            }
          }
        }
      }
    });

    testWidgets('B55 zero opacity keeps its surface and woven ownership', (
      WidgetTester tester,
    ) async {
      for (final Color surface in <Color>[
        const Color(0xFF000000),
        const Color(0x00000000),
      ]) {
        for (final WovenFill fill in <WovenFill>[
          const WovenFill.solid(Color(0xFFFF0000)),
          const WovenFill.gradient(
            head: Color(0xFFFF0000),
            tail: Color(0xFF0000FF),
          ),
        ]) {
          for (final bool clockwise in <bool>[true, false]) {
            final WovenRingStyle style = WovenRingStyle(
              startAngle: 0,
              clockwise: clockwise,
              surfaceColor: surface,
            );
            final Ring r = Ring(
              side: side,
              thicknessFraction: 0.20,
              overlapFraction: 0.50,
              startAngle: 0,
              clockwise: clockwise,
            );
            for (final int count in <int>[1, 4]) {
              // Render a fresh public widget, not the previous chart's first
              // transition frame. Odd owners are hostile opaque predecessors.
              await tester.pumpWidget(const SizedBox.shrink());
              final Raster raster = await render(
                tester,
                WovenRingChart(
                  style: style,
                  animation: WovenRingAnimation.none,
                  segments: <WovenSegment>[
                    for (var i = 0; i < count; i++)
                      WovenSegment(
                        value: 1,
                        fill: i.isEven
                            ? fill
                            : const WovenFill.solid(Color(0xFF00FF00)),
                        opacity: i.isEven ? 0 : 1,
                      ),
                  ],
                ),
              );
              final List<Extent> extents = extentsFor(
                r,
                List<double>.filled(count, 1 / count),
              );
              final List<int> active = List<int>.generate(count, (int i) => i);
              var zeroOwnerSamples = 0;
              var coveredPredecessorSamples = 0;
              for (final double radius in <double>[
                r.track - r.cap / 2,
                r.track,
                r.track + r.cap / 2,
              ]) {
                for (var sample = 0; sample < 360; sample++) {
                  final Offset requested = r.at(
                    radius,
                    sample * 2 * math.pi / 360,
                  );
                  final Offset p = Offset(
                    (requested.dx - 0.5).round() + 0.5,
                    (requested.dy - 0.5).round() + 0.5,
                  );
                  if (count > 1 &&
                      extents.any(
                        (Extent e) => signedDistance(r, e, p).abs() <= 1.25,
                      )) {
                    continue;
                  }
                  final int owner = count == 1
                      ? 0
                      : ownerAt(r, extents, active, p);
                  expect(owner, greaterThanOrEqualTo(0));
                  final Rgba expected = rgbaOf(
                    owner.isEven ? surface : const Color(0xFF00FF00),
                  );
                  final Rgba pixel = raster.atPoint(p);
                  expect(
                    (pixel.r, pixel.g, pixel.b, pixel.a),
                    (expected.r, expected.g, expected.b, expected.a),
                    reason:
                        'zero opacity changed its surface: count=$count '
                        'clockwise=$clockwise surface=$surface owner=$owner '
                        'point=$p pixel=$pixel',
                  );
                  if (owner.isEven) {
                    zeroOwnerSamples++;
                    if (count > 1 &&
                        signedDistance(
                              r,
                              extents[(owner - 1 + count) % count],
                              p,
                            ) <
                            -1.25) {
                      coveredPredecessorSamples++;
                    }
                  }
                }
              }
              expect(zeroOwnerSamples, greaterThan(400));
              if (count > 1) {
                expect(coveredPredecessorSamples, greaterThan(30));
              }
            }
          }
        }
      }
    });

    testWidgets('B54 partial border opacity blends once at every visible head', (
      WidgetTester tester,
    ) async {
      for (final bool clockwise in <bool>[true, false]) {
        for (final (double lineOpacity, double segmentOpacity, Color ink)
            in <(double, double, Color)>[
              (0.5, 1, const Color(0xFF000000)),
              (0.25, 1, const Color(0xFF000000)),
              (0.5, 0.5, const Color(0xFF000000)),
              (0.5, 1, const Color(0x80000000)),
            ]) {
          final WovenRingStyle style = WovenRingStyle(
            startAngle: 0,
            clockwise: clockwise,
            surfaceColor: const Color(0xFFFFFFFF),
          );
          final Ring r = Ring(
            side: side,
            thicknessFraction: 0.20,
            overlapFraction: 0.50,
            startAngle: 0,
            clockwise: clockwise,
          );
          final List<Extent> extents = extentsFor(r, const <double>[
            0.25,
            0.25,
            0.25,
            0.25,
          ]);
          final Raster raster = await render(
            tester,
            WovenRingChart(
              style: style,
              animation: WovenRingAnimation.none,
              segments: <WovenSegment>[
                for (var i = 0; i < 4; i++)
                  WovenSegment(
                    value: 1,
                    fill: const WovenFill.solid(Color(0xFFFFFFFF)),
                    opacity: segmentOpacity,
                    border: WovenBorder(
                      color: ink,
                      widthFraction: 0.05,
                      opacity: lineOpacity,
                    ),
                  ),
              ],
            ),
          );
          // The isolated layer stores requested line alpha as one RGBA byte;
          // blending that byte once over white gives this exact interior gray.
          final int gray =
              255 - (ink.a * lineOpacity * segmentOpacity * 255).round();
          for (var i = 0; i < extents.length; i++) {
            final double head = extents[i].start;
            final Offset capCenter = r.at(r.track, head);
            final Offset backward =
                Offset(math.sin(head), -math.cos(head)) * r.dir;
            final double width = r.thickness * 0.05;
            final Offset requested = capCenter + backward * (r.cap - width / 2);
            final Offset pixelCenter = Offset(
              (requested.dx - 0.5).round() + 0.5,
              (requested.dy - 0.5).round() + 0.5,
            );
            final double inset = r.cap - (pixelCenter - capCenter).distance;
            expect(inset, greaterThan(1.25));
            expect(width - inset, greaterThan(1.25));
            expect(signedDistance(r, extents[i], pixelCenter), lessThan(-1.25));
            expect(
              signedDistance(r, extents[(i + 1) % 4], pixelCenter),
              greaterThan(1.25),
            );
            expect(
              ownerAt(r, extents, const <int>[0, 1, 2, 3], pixelCenter),
              i,
            );
            final Rgba pixel = raster.atPoint(pixelCenter);
            expect(
              (pixel.r, pixel.g, pixel.b, pixel.a),
              (gray, gray, gray, 255),
              reason:
                  'border opacity compounded at head=$i clockwise=$clockwise '
                  'lineOpacity=$lineOpacity segmentOpacity=$segmentOpacity '
                  'ink=$ink pixel=$pixel',
            );
          }
        }
      }
    });

    testWidgets('B53 large finite start angles retain their circular phase', (
      WidgetTester tester,
    ) async {
      final List<WovenSegment> segments = <WovenSegment>[
        for (final Color color in tenColors.take(4))
          WovenSegment(value: 1, fill: WovenFill.shaded(color)),
      ];
      for (final bool clockwise in <bool>[true, false]) {
        for (final double angle in <double>[
          1e20,
          -1e20,
          double.maxFinite,
          -double.maxFinite,
        ]) {
          final WovenRingStyle style = WovenRingStyle(
            startAngle: angle,
            clockwise: clockwise,
          );
          final WovenRingStyle wrapped = style.copyWith(
            startAngle: math.atan2(math.sin(angle), math.cos(angle)),
          );
          for (final int count in <int>[1, 4]) {
            final Raster actual = await render(
              tester,
              WovenRingChart(
                segments: segments.take(count).toList(),
                style: style,
                animation: WovenRingAnimation.none,
              ),
            );
            final Raster expected = await render(
              tester,
              WovenRingChart(
                segments: segments.take(count).toList(),
                style: wrapped,
                animation: WovenRingAnimation.none,
              ),
            );
            expect(
              pixelDifference(actual, expected),
              0,
              reason: 'angle=$angle clockwise=$clockwise count=$count',
            );
            if (count == 4) {
              // Probe segment bodies by rotating the original sin/cos vector,
              // independently of either angle-normalization implementation.
              // A remainder against a rounded tau cannot pass this contract.
              for (var i = 0; i < count; i++) {
                final double offset =
                    (clockwise ? 1 : -1) * (i + 0.5) * 2 * math.pi / count;
                final double x =
                    math.cos(angle) * math.cos(offset) -
                    math.sin(angle) * math.sin(offset);
                final double y =
                    math.sin(angle) * math.cos(offset) +
                    math.cos(angle) * math.sin(offset);
                final Rgba pixel = actual.atPoint(
                  const Offset(side / 2, side / 2) +
                      Offset(x, y) * (side * 0.4),
                );
                expect(
                  distanceToFill(pixel, segments[i].fill),
                  lessThanOrEqualTo(4),
                  reason:
                      'raw sin/cos phase angle=$angle clockwise=$clockwise '
                      'segment=$i pixel=$pixel',
                );
              }
            }
          }
          final Raster loading = await render(
            tester,
            WovenRingChart.loading(style: style),
          );
          final Raster wrappedLoading = await render(
            tester,
            WovenRingChart.loading(style: wrapped),
          );
          expect(
            pixelDifference(loading, wrappedLoading),
            0,
            reason: 'loading angle=$angle clockwise=$clockwise',
          );
        }
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });

    for (final Case c in catalog) {
      testWidgets(c.name, (WidgetTester tester) async {
        final Raster raster = await render(
          tester,
          WovenRingChart(
            segments: c.segments,
            style: c.style,
            animation: WovenRingAnimation.none,
            highlightedIndex: c.name.contains('selected') ? 2 : null,
          ),
        );
        final List<String> violations = <String>[
          ...checkCoverage(raster, c),
          ...checkSilhouette(raster, c),
          ...checkOwnership(raster, c),
        ];
        expect(violations, isEmpty, reason: violations.take(12).join('\n'));
      });
    }
  });

  group('C. cap profiles are true circles', () {
    for (final Case c in catalog.where(
      (Case c) =>
          !c.name.contains('border') &&
          !c.name.contains('shadow') &&
          !c.name.contains('gradient'),
    )) {
      testWidgets(c.name, (WidgetTester tester) async {
        final Raster raster = await render(
          tester,
          WovenRingChart(
            segments: c.segments,
            style: c.style,
            animation: WovenRingAnimation.none,
          ),
        );
        final List<String> violations = checkCapProfiles(raster, c);
        expect(violations, isEmpty, reason: violations.take(12).join('\n'));
      });
    }
  });

  // =========================================================================
  // Section C2 - the silhouette, measured below the pixel
  //
  // Every hairline this chart draws sits on a curve, and two of those
  // curves - the traced outline and the single segment's self-joint cap - run
  // right up to the edge of the thickness. A stroke centred on the boundary spills
  // half its width past it. At one device pixel per logical pixel that spill is
  // invisible; on a retina display it is a visible whisker poking out of the
  // ring. Render dense and scan every pixel.
  // =========================================================================

  group('C2. nothing paints outside the silhouette, sub-pixel', () {
    const double density = 4;
    final List<
      ({String name, WovenRingStyle style, List<WovenSegment> segments})
    >
    cases = <({String name, WovenRingStyle style, List<WovenSegment> segments})>[
      for (final bool cw in <bool>[true, false])
        for (final WovenSingleSegmentStyle single
            in WovenSingleSegmentStyle.values)
          (
            name: 'single 100 percent ${single.name} ${cw ? 'cw' : 'ccw'}',
            style: WovenRingStyle(clockwise: cw, singleSegmentStyle: single),
            segments: solids(<double>[100], <Color>[cBlue]),
          ),
      // The self-joint is the one stroke whose two ends land exactly on the
      // silhouette, so it is named explicitly rather than inherited: the
      // default is smooth, and a case that quietly stopped drawing the joint
      // would still pass while covering nothing.
      (
        name: 'single 100 percent jointed, thin thickness',
        style: const WovenRingStyle(
          thicknessFraction: 0.12,
          singleSegmentStyle: WovenSingleSegmentStyle.jointed,
        ),
        segments: solids(<double>[100], <Color>[cBlue]),
      ),
      (
        name: 'single 100 percent jointed, wide thickness',
        style: const WovenRingStyle(
          thicknessFraction: 0.30,
          singleSegmentStyle: WovenSingleSegmentStyle.jointed,
        ),
        segments: solids(<double>[100], <Color>[cBlue]),
      ),
      (
        name: 'single 100 percent jointed, off-axis start',
        style: const WovenRingStyle(
          startAngle: 0.7,
          singleSegmentStyle: WovenSingleSegmentStyle.jointed,
        ),
        segments: solids(<double>[100], <Color>[cBlue]),
      ),
      (
        name: 'single 100 percent jointed and bordered',
        style: const WovenRingStyle(
          singleSegmentStyle: WovenSingleSegmentStyle.jointed,
        ),
        segments: <WovenSegment>[
          const WovenSegment(
            value: 100,
            fill: WovenFill.solid(cBlue),
            border: WovenBorder(),
          ),
        ],
      ),
      (
        name: 'single 100 percent jointed, wide diagnostic border',
        style: const WovenRingStyle(
          singleSegmentStyle: WovenSingleSegmentStyle.jointed,
        ),
        segments: <WovenSegment>[
          const WovenSegment(
            value: 100,
            fill: WovenFill.solid(cBlue),
            border: WovenBorder(widthFraction: 0.05),
          ),
        ],
      ),
      (
        name: 'four bordered segments',
        style: const WovenRingStyle(),
        segments: <WovenSegment>[
          for (var i = 0; i < 4; i++)
            WovenSegment(
              value: 25,
              fill: WovenFill.solid(tenColors[i]),
              border: const WovenBorder(),
            ),
        ],
      ),
      (
        name: 'four plain segments',
        style: const WovenRingStyle(),
        segments: solids(<double>[25, 25, 25, 25]),
      ),
      (
        name: 'ninety percent self-lapping segment',
        style: const WovenRingStyle(),
        segments: solids(<double>[90, 10]),
      ),
    ];

    for (final ({
          String name,
          WovenRingStyle style,
          List<WovenSegment> segments,
        })
        c
        in cases) {
      testWidgets('C2 ${c.name}', (WidgetTester tester) async {
        final Raster raster = await render(
          tester,
          WovenRingChart(
            segments: c.segments,
            style: c.style,
            animation: WovenRingAnimation.none,
          ),
          pixelRatio: density,
        );
        final Ring r = Ring(
          side: side,
          thicknessFraction: c.style.resolvedThicknessFraction,
          overlapFraction: c.style.resolvedOverlapFraction,
          startAngle: c.style.resolvedStartAngle,
          clockwise: c.style.clockwise,
        );
        final List<String> violations = checkSilhouetteSubPixel(
          raster,
          r,
          c.name,
          pixelRatio: density,
        );
        expect(violations, isEmpty, reason: violations.take(8).join('\n'));
      });
    }

    testWidgets('C2 through a four-to-one merge', (WidgetTester tester) async {
      final GlobalKey key = GlobalKey();
      // Jointed on purpose: the merge path draws the self-joint from its own
      // call site, so the default style would leave that branch uncovered.
      const WovenRingStyle style = WovenRingStyle(
        singleSegmentStyle: WovenSingleSegmentStyle.jointed,
      );
      final Ring r = Ring(
        side: side,
        thicknessFraction: style.resolvedThicknessFraction,
        overlapFraction: style.resolvedOverlapFraction,
        startAngle: style.resolvedStartAngle,
        clockwise: true,
      );
      Widget ringOf(List<double> values) => Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: RepaintBoundary(
            key: key,
            child: SizedBox.square(
              dimension: side,
              child: WovenRingChart(
                segments: solids(values),
                style: style,
                animation: WovenRingAnimation.none,
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(ringOf(<double>[25, 25, 25, 25]));
      await tester.pumpWidget(ringOf(<double>[100]));
      final List<String> violations = <String>[];
      for (var frame = 0; frame <= 12; frame++) {
        if (frame > 0) await tester.pump(const Duration(milliseconds: 60));
        violations.addAll(
          checkSilhouetteSubPixel(
            await capture(tester, key, pixelRatio: 4),
            r,
            'merge frame $frame',
            pixelRatio: 4,
          ),
        );
        if (violations.isNotEmpty) break;
      }
      expect(violations, isEmpty, reason: violations.take(8).join('\n'));
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  // =========================================================================
  // Section D - the non-data states
  // =========================================================================

  group('D. states', () {
    testWidgets('D1 empty is one flat neutral annulus with no joints', (
      WidgetTester tester,
    ) async {
      const WovenRingStyle style = WovenRingStyle();
      final Raster raster = await render(
        tester,
        const WovenRingChart.empty(style: style),
      );
      final Ring r = Ring(
        side: side,
        thicknessFraction: style.resolvedThicknessFraction,
        overlapFraction: style.resolvedOverlapFraction,
        startAngle: style.resolvedStartAngle,
        clockwise: true,
      );
      // Same colour the whole way round: a joint anywhere would show up here.
      final Rgba reference = raster.atPoint(r.at(r.track, 0));
      // Pins the constant the transition checks lean on.
      expect(
        reference.a,
        emptyTrackAlpha,
        reason: 'the empty track is no longer $emptyTrackAlpha alpha',
      );
      for (var s = 0; s < 2880; s++) {
        final double angle = s * 2 * math.pi / 2880;
        final Rgba pixel = raster.atPoint(r.at(r.track, angle));
        expect(
          channelDistance(pixel, reference),
          lessThanOrEqualTo(2),
          reason: 'empty ring is not uniform at angle $angle: $pixel',
        );
      }
      // And it still respects the silhouette.
      for (var s = 0; s < 720; s++) {
        final double angle = s * 2 * math.pi / 720;
        expect(raster.atPoint(r.at(r.outer + 2, angle)).a, 0);
        expect(raster.atPoint(r.at(r.inner - 2, angle)).a, 0);
      }
    });

    testWidgets('D2 loading spins one segment and stops when replaced', (
      WidgetTester tester,
    ) async {
      final GlobalKey key = GlobalKey();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: RepaintBoundary(
              key: key,
              child: const SizedBox.square(
                dimension: side,
                child: WovenRingChart.loading(),
              ),
            ),
          ),
        ),
      );
      final Raster first = await capture(tester, key);
      await tester.pump(const Duration(milliseconds: 350));
      final Raster later = await capture(tester, key);
      expect(
        pixelDifference(first, later),
        greaterThan(200),
        reason: 'loading ring is not animating',
      );
      // Swapping to a data ring must stop the spin ticker.
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: RepaintBoundary(
              key: key,
              child: SizedBox.square(
                dimension: side,
                child: WovenRingChart(
                  segments: solids(<double>[50, 50], tenColors),
                  animation: WovenRingAnimation.none,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 16));
      final Raster settledA = await capture(tester, key);
      await tester.pump(const Duration(milliseconds: 400));
      final Raster settledB = await capture(tester, key);
      expect(
        pixelDifference(settledA, settledB),
        0,
        reason: 'the spin ticker is still running after leaving loading',
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('D3 a single 100 percent segment fills the whole annulus', (
      WidgetTester tester,
    ) async {
      for (final WovenSingleSegmentStyle single
          in WovenSingleSegmentStyle.values) {
        final WovenRingStyle style = WovenRingStyle(singleSegmentStyle: single);
        final Raster raster = await render(
          tester,
          WovenRingChart(
            segments: solids(<double>[100], <Color>[cBlue]),
            style: style,
            animation: WovenRingAnimation.none,
          ),
        );
        final Ring r = Ring(
          side: side,
          thicknessFraction: style.resolvedThicknessFraction,
          overlapFraction: style.resolvedOverlapFraction,
          startAngle: style.resolvedStartAngle,
          clockwise: true,
        );
        var offColour = 0;
        for (var s = 0; s < 2880; s++) {
          final double angle = s * 2 * math.pi / 2880;
          final Rgba pixel = raster.atPoint(r.at(r.track, angle));
          expect(pixel.a, 255, reason: '$single gap at angle $angle');
          if (channelDistance(pixel, rgbaOf(cBlue)) > 6) offColour++;
        }
        // Jointed draws one thin surfaceColor-coloured seam mark; smooth draws none.
        if (single == WovenSingleSegmentStyle.smooth) {
          expect(offColour, 0, reason: 'smooth single must be one flat ring');
        } else {
          expect(
            offColour,
            greaterThan(0),
            reason: 'jointed single must keep a visible self-joint',
          );
          expect(
            offColour,
            lessThan(120),
            reason: 'the self-joint must be a hairline, not a thickness',
          );
        }
      }
    });

    testWidgets('D3b the default single-value ring carries no seam mark', (
      WidgetTester tester,
    ) async {
      // One value has no boundary to show, so the default shows none. The
      // self-joint is the only edge in this chart that no fill produced,
      // and a surfaceColor-coloured line on a ring the caller asked to be
      // borderless reads as damage rather than as a lap; jointed is opt-in.
      expect(
        const WovenRingStyle().singleSegmentStyle,
        WovenSingleSegmentStyle.smooth,
      );
      const WovenRingStyle style = WovenRingStyle();
      final Raster raster = await render(
        tester,
        WovenRingChart(
          segments: solids(<double>[100], <Color>[cBlue]),
          style: style,
          animation: WovenRingAnimation.none,
        ),
      );
      final Ring r = Ring(
        side: side,
        thicknessFraction: style.resolvedThicknessFraction,
        overlapFraction: style.resolvedOverlapFraction,
        startAngle: style.resolvedStartAngle,
        clockwise: true,
      );
      // Every radius across the thickness, all the way round: no mark anywhere,
      // not just on the centreline the jointed check walks.
      for (var s = 0; s < 1440; s++) {
        final double angle = s * 2 * math.pi / 1440;
        for (var k = 1; k < 8; k++) {
          final double radius = r.inner + r.thickness * k / 8;
          final Rgba pixel = raster.atPoint(r.at(radius, angle));
          expect(
            channelDistance(pixel, rgbaOf(cBlue)),
            lessThanOrEqualTo(6),
            reason:
                'default single value must be one flat ring: '
                'angle=${angle.toStringAsFixed(4)} '
                'r=${radius.toStringAsFixed(1)} pixel=$pixel',
          );
        }
      }
    });

    testWidgets('D4 all-zero data falls back to the empty track', (
      WidgetTester tester,
    ) async {
      final Raster raster = await render(
        tester,
        WovenRingChart(
          segments: solids(<double>[0, 0, 0], tenColors),
          animation: WovenRingAnimation.none,
        ),
      );
      const WovenRingStyle style = WovenRingStyle();
      final Ring r = Ring(
        side: side,
        thicknessFraction: style.resolvedThicknessFraction,
        overlapFraction: style.resolvedOverlapFraction,
        startAngle: style.resolvedStartAngle,
        clockwise: true,
      );
      for (var s = 0; s < 1440; s++) {
        final double angle = s * 2 * math.pi / 1440;
        final Rgba pixel = raster.atPoint(r.at(r.track, angle));
        expect(pixel.a, greaterThan(0), reason: 'nothing drawn at $angle');
        for (final Color c in tenColors.take(3)) {
          expect(
            channelDistance(pixel, rgbaOf(c)),
            greaterThan(20),
            reason: 'zero-valued segment still painted at $angle',
          );
        }
      }
    });
  });

  // =========================================================================
  // Section E - animation. The endpoint identity check is the one that
  // catches a seam that swaps on the final frame.
  // =========================================================================

  group('E. animation', () {
    for (final WovenRingAnimation animation in <WovenRingAnimation>[
      WovenRingAnimation.none,
      WovenRingAnimation.sweep,
      WovenRingAnimation.grow,
    ]) {
      for (final (String label, List<double> dropped)
          in <(String, List<double>)>[
            ('zero', <double>[0]),
            ('negative', <double>[-3]),
            ('NaN', <double>[double.nan]),
            ('infinity', <double>[double.infinity]),
            ('negative infinity', <double>[double.negativeInfinity]),
            (
              'mixed',
              <double>[
                0,
                -3,
                double.nan,
                double.infinity,
                double.negativeInfinity,
              ],
            ),
          ]) {
        testWidgets(
          'E8 dropped $label values preserve ${animation.name} frames',
          (WidgetTester tester) async {
            for (final int count in <int>[1, 4]) {
              for (final bool clockwise in <bool>[true, false]) {
                for (final Color surface in <Color>[
                  const Color(0x00000000),
                  const Color(0x800000FF),
                  const Color(0xFFFFFFFF),
                ]) {
                  final List<WovenSegment> valid = <WovenSegment>[
                    for (var i = 0; i < count; i++)
                      WovenSegment(
                        value: 1,
                        fill: WovenFill.shaded(tenColors[i]),
                        border: const WovenBorder(
                          color: Color(0x80000000),
                          widthFraction: 0.05,
                          opacity: 0.5,
                        ),
                      ),
                  ];
                  final List<WovenSegment> ignored = <WovenSegment>[
                    for (final double value in dropped)
                      WovenSegment(
                        value: value,
                        fill: const WovenFill.solid(Color(0xFFFF00FF)),
                        border: const WovenBorder(color: Color(0xFF00FFFF)),
                      ),
                  ];
                  // Leading, interior and trailing invalid slots must all be
                  // absent from the visible frame. Keep the highlighted owner
                  // identical after its caller-visible index shifts.
                  final List<WovenSegment> withIgnored = <WovenSegment>[
                    ...ignored,
                    valid.first,
                    ...ignored,
                    ...valid.skip(1),
                    ...ignored,
                  ];
                  Future<List<Raster>> frames(
                    List<WovenSegment> segments,
                    int highlight,
                  ) async {
                    await tester.pumpWidget(const SizedBox.shrink());
                    final GlobalKey key = GlobalKey();
                    await pump(
                      tester,
                      key,
                      WovenRingChart(
                        segments: segments,
                        highlightedIndex: highlight,
                        highlightBorder: const WovenBorder(
                          color: Color(0xFF000000),
                          widthFraction: 0.05,
                        ),
                        style: WovenRingStyle(
                          clockwise: clockwise,
                          surfaceColor: surface,
                        ),
                        animation: animation,
                        animationDuration: const Duration(seconds: 1),
                      ),
                    );
                    if (animation == WovenRingAnimation.none) {
                      return <Raster>[await capture(tester, key)];
                    }
                    await tester.pump(const Duration(milliseconds: 250));
                    final Raster entrance = await capture(tester, key);
                    await tester.pump(const Duration(milliseconds: 750));
                    return <Raster>[entrance, await capture(tester, key)];
                  }

                  final List<Raster> expected = await frames(valid, 0);
                  final List<Raster> actual = await frames(
                    withIgnored,
                    ignored.length,
                  );
                  expect(actual.length, expected.length);
                  for (var frame = 0; frame < expected.length; frame++) {
                    // Exact bytes, including antialiasing and transparent pixels.
                    // A dropped category has no permission to alter any pixel.
                    expect(
                      actual[frame].bytes,
                      orderedEquals(expected[frame].bytes),
                      reason:
                          '$label changed ${animation.name} count=$count '
                          'clockwise=$clockwise surface=$surface frame=$frame',
                    );
                  }
                }
              }
            }
          },
        );
      }
    }

    testWidgets(
      'E7 single reveals keep round bordered ends and close shadows',
      (WidgetTester tester) async {
        for (final bool clockwise in <bool>[true, false]) {
          for (final WovenRingAnimation animation in <WovenRingAnimation>[
            WovenRingAnimation.sweep,
            WovenRingAnimation.grow,
          ]) {
            for (final WovenShadow? shadow in <WovenShadow?>[
              null,
              const WovenShadow(color: Color(0xCC000000)),
            ]) {
              await tester.pumpWidget(const SizedBox.shrink());
              final WovenRingStyle style = WovenRingStyle(
                clockwise: clockwise,
                shadow: shadow,
              );
              final Ring r = Ring(
                side: side,
                thicknessFraction: style.resolvedThicknessFraction,
                overlapFraction: style.resolvedOverlapFraction,
                startAngle: style.resolvedStartAngle,
                clockwise: clockwise,
                shadow: shadow,
              );
              final GlobalKey key = GlobalKey();
              await pump(
                tester,
                key,
                WovenRingChart(
                  animation: animation,
                  animationDuration: const Duration(seconds: 1),
                  style: style,
                  segments: const <WovenSegment>[
                    WovenSegment(
                      value: 1,
                      fill: WovenFill.gradient(head: cRed, tail: cBlue),
                      border: WovenBorder(
                        color: Color(0xFF000000),
                        widthFraction: 0.05,
                      ),
                    ),
                  ],
                ),
              );
              await tester.pump(const Duration(milliseconds: 500));
              final Raster half = await capture(tester, key);
              expect(
                leadingEdgeViolations(half, r, '$clockwise $animation'),
                isEmpty,
              );
              final double end =
                  r.startAngle -
                  r.dir * r.jointLag +
                  r.dir * 2 * math.pi * Curves.easeInOutCubic.transform(0.5);
              final Offset tangent =
                  Offset(-math.sin(end), math.cos(end)) * r.dir;
              final Rgba edge = half.atPoint(
                r.at(r.track, end) + tangent * (r.cap - 2.5),
              );
              expect(
                (edge.r, edge.g, edge.b, edge.a),
                (0, 0, 0, 255),
                reason: 'the moving free cap must retain its border',
              );
              var exteriorAlpha = 0;
              for (var y = 0; y < side; y++) {
                for (var x = 0; x < side; x++) {
                  final double radius =
                      (Offset(x + 0.5, y + 0.5) - r.center).distance;
                  if (radius < r.inner - 2) expect(half.at(x, y).a, 0);
                  if (radius > r.outer + 2) {
                    exteriorAlpha = math.max(exteriorAlpha, half.at(x, y).a);
                  }
                }
              }
              expect(exteriorAlpha, shadow == null ? 0 : greaterThan(0));
              await tester.pump(const Duration(milliseconds: 499));
              final Raster near = await capture(tester, key);
              await tester.pump(const Duration(milliseconds: 1));
              final Raster settled = await capture(tester, key);
              for (var y = 0; y < side; y++) {
                for (var x = 0; x < side; x++) {
                  final double radius =
                      (Offset(x + 0.5, y + 0.5) - r.center).distance;
                  if (radius > r.outer + 2 || radius < r.inner - 2) {
                    expect(
                      near.at(x, y).a,
                      lessThanOrEqualTo(1),
                      reason: '$clockwise $animation $shadow ($x,$y)',
                    );
                    expect(settled.at(x, y).a, 0);
                  }
                }
              }
            }
          }
        }
      },
    );

    testWidgets('E6 single gradients retain phase throughout the reveal', (
      WidgetTester tester,
    ) async {
      for (final bool clockwise in <bool>[true, false]) {
        for (final WovenRingAnimation animation in <WovenRingAnimation>[
          WovenRingAnimation.sweep,
          WovenRingAnimation.grow,
        ]) {
          for (final WovenGradientAxis axis in WovenGradientAxis.values) {
            await tester.pumpWidget(const SizedBox.shrink());
            final GlobalKey key = GlobalKey();
            await pump(
              tester,
              key,
              WovenRingChart(
                animation: animation,
                animationDuration: const Duration(seconds: 1),
                style: WovenRingStyle(clockwise: clockwise, gradientAxis: axis),
                segments: const <WovenSegment>[
                  WovenSegment(
                    value: 1,
                    fill: WovenFill.gradient(
                      head: Color(0x80FF0000),
                      tail: Color(0x800000FF),
                    ),
                  ),
                ],
              ),
            );
            await tester.pump(const Duration(milliseconds: 500));
            final Raster half = await capture(tester, key);
            await tester.pump(const Duration(milliseconds: 499));
            final Raster penultimate = await capture(tester, key);
            await tester.pump(const Duration(milliseconds: 1));
            final Raster complete = await capture(tester, key);
            // The first quarter is already exposed halfway through either
            // reveal. Its paint must stay stationary as the free cap moves.
            final double direction = clockwise ? 1 : -1;
            for (var sample = 0; sample < 90; sample++) {
              final double angle =
                  -math.pi / 2 + direction * sample * math.pi / 180;
              final Offset point =
                  const Offset(side / 2, side / 2) +
                  Offset(math.cos(angle), math.sin(angle)) * side * 0.4;
              expect(
                channelDistance(half.atPoint(point), complete.atPoint(point)),
                lessThanOrEqualTo(1),
                reason: '$clockwise $animation $axis $sample',
              );
            }
            // Stay two pixels clear of either circle, independent of painter
            // geometry. No interior color boundary may relocate at completion.
            for (var y = 0; y < side; y++) {
              for (var x = 0; x < side; x++) {
                final double radius =
                    (Offset(x + 0.5, y + 0.5) -
                            const Offset(side / 2, side / 2))
                        .distance;
                if (radius < side * 0.3 + 2 || radius > side * 0.5 - 2) {
                  continue;
                }
                expect(
                  channelDistance(penultimate.at(x, y), complete.at(x, y)),
                  lessThanOrEqualTo(1),
                  reason: '$clockwise $animation $axis ($x,$y)',
                );
                expect(penultimate.at(x, y).a, closeTo(complete.at(x, y).a, 1));
              }
            }
          }
        }
      }
    });

    for (final bool clockwise in <bool>[true, false]) {
      for (final WovenRingAnimation animation in <WovenRingAnimation>[
        WovenRingAnimation.sweep,
        WovenRingAnimation.grow,
      ]) {
        final String label = '${animation.name} ${clockwise ? 'CW' : 'CCW'}';

        testWidgets('E1 $label settles onto the exact static frame', (
          WidgetTester tester,
        ) async {
          final WovenRingStyle style = WovenRingStyle(clockwise: clockwise);
          final List<WovenSegment> segments = solids(<double>[
            37,
            19,
            29,
            15,
          ], tenColors);
          final GlobalKey key = GlobalKey();
          await pump(
            tester,
            key,
            WovenRingChart(
              segments: segments,
              style: style,
              animation: animation,
            ),
          );
          await tester.pump(const Duration(milliseconds: 2500));
          final Raster settled = await capture(tester, key);

          await tester.pumpWidget(const SizedBox.shrink());
          await pump(
            tester,
            key,
            WovenRingChart(
              segments: segments,
              style: style,
              animation: WovenRingAnimation.none,
            ),
          );
          final Raster reference = await capture(tester, key);
          expect(
            pixelDifference(settled, reference),
            0,
            reason:
                '$label does not land on the static rendering; the final '
                'frame changes ownership',
          );
        });

        testWidgets('E2 $label never paints outside the silhouette', (
          WidgetTester tester,
        ) async {
          final WovenRingStyle style = WovenRingStyle(clockwise: clockwise);
          final Ring r = Ring(
            side: side,
            thicknessFraction: style.resolvedThicknessFraction,
            overlapFraction: style.resolvedOverlapFraction,
            startAngle: style.resolvedStartAngle,
            clockwise: clockwise,
          );
          final GlobalKey key = GlobalKey();
          await pump(
            tester,
            key,
            WovenRingChart(
              segments: solids(<double>[37, 19, 29, 15], tenColors),
              style: style,
              animation: animation,
            ),
          );
          for (var frame = 0; frame < 40; frame++) {
            await tester.pump(const Duration(milliseconds: 25));
            final Raster raster = await capture(tester, key);
            for (var s = 0; s < 480; s++) {
              final double angle = s * 2 * math.pi / 480;
              expect(
                raster.atPoint(r.at(r.outer + 2, angle)).a,
                0,
                reason: '$label frame $frame painted outside the ring',
              );
              expect(
                raster.atPoint(r.at(r.inner - 2, angle)).a,
                0,
                reason: '$label frame $frame painted into the hole',
              );
            }
          }
        });
      }
    }

    // Sampled densely and right through completion, in both directions. The
    // approach to the seam is the hardest part of the whole chart, so it is
    // deliberately not excluded.
    for (final bool clockwise in <bool>[true, false]) {
      for (final WovenRingAnimation animation in <WovenRingAnimation>[
        WovenRingAnimation.sweep,
        WovenRingAnimation.grow,
      ]) {
        final String label = '${animation.name} ${clockwise ? 'CW' : 'CCW'}';
        testWidgets('E3 the growing head is a true circular cap ($label)', (
          WidgetTester tester,
        ) async {
          final WovenRingStyle style = WovenRingStyle(clockwise: clockwise);
          final Ring r = Ring(
            side: side,
            thicknessFraction: style.resolvedThicknessFraction,
            overlapFraction: style.resolvedOverlapFraction,
            startAngle: style.resolvedStartAngle,
            clockwise: clockwise,
          );
          final GlobalKey key = GlobalKey();
          await pump(
            tester,
            key,
            WovenRingChart(
              segments: solids(<double>[37, 19, 29, 15], tenColors),
              style: style,
              animation: animation,
            ),
          );
          final List<String> violations = <String>[];
          for (var frame = 1; frame <= 60; frame++) {
            await tester.pump(const Duration(milliseconds: 17));
            final Raster raster = await capture(tester, key);
            violations.addAll(
              leadingEdgeViolations(raster, r, '$label f$frame'),
            );
          }
          expect(violations, isEmpty, reason: violations.take(10).join('\n'));
        });
      }
    }

    testWidgets('E4 replay restarts and settles on the same static frame', (
      WidgetTester tester,
    ) async {
      final WovenRingChartController controller = WovenRingChartController();
      addTearDown(controller.dispose);
      final GlobalKey key = GlobalKey();
      final List<WovenSegment> segments = solids(<double>[37, 19, 29, 15]);
      await pump(
        tester,
        key,
        WovenRingChart(
          segments: segments,
          animation: WovenRingAnimation.sweep,
          controller: controller,
        ),
      );
      await tester.pump(const Duration(milliseconds: 2000));
      final Raster settled = await capture(tester, key);
      for (var replay = 0; replay < 5; replay++) {
        controller.replay();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 120));
        final Raster mid = await capture(tester, key);
        expect(
          pixelDifference(mid, settled),
          greaterThan(0),
          reason: 'replay $replay did not restart the animation',
        );
        await tester.pump(const Duration(milliseconds: 2000));
        expect(
          pixelDifference(await capture(tester, key), settled),
          0,
          reason: 'replay $replay settled on a different frame',
        );
      }
    });
  });

  group('E5 borders never get buried', () {
    for (final WovenRingAnimation animation in <WovenRingAnimation>[
      WovenRingAnimation.sweep,
      WovenRingAnimation.grow,
    ]) {
      for (final bool clockwise in <bool>[true, false]) {
        for (final WovenSingleSegmentStyle single
            in WovenSingleSegmentStyle.values) {
          final String label =
              '${animation.name} ${clockwise ? 'CW' : 'CCW'} ${single.name}';
          testWidgets('a self-lapping segment buries no border ($label)', (
            WidgetTester tester,
          ) async {
            final WovenRingStyle style = WovenRingStyle(
              thicknessFraction: 0.15,
              overlapFraction: 0.30,
              clockwise: clockwise,
              singleSegmentStyle: single,
            );
            // An explicit border colour that no fill and no joint mark uses, so
            // anything found is unambiguously a border stroke.
            const Color ink = Color(0xFF000000);
            final Ring r = Ring(
              side: side,
              thicknessFraction: style.resolvedThicknessFraction,
              overlapFraction: style.resolvedOverlapFraction,
              startAngle: style.resolvedStartAngle,
              clockwise: clockwise,
            );
            final GlobalKey key = GlobalKey();
            await pump(
              tester,
              key,
              WovenRingChart(
                segments: <WovenSegment>[
                  WovenSegment(
                    value: 100,
                    fill: WovenFill.shaded(cPurple, step: 0.04),
                    border: const WovenBorder(color: ink),
                  ),
                ],
                style: style,
                animation: animation,
              ),
            );
            final List<String> violations = <String>[];
            for (var frame = 0; frame <= 26; frame++) {
              if (frame > 0) {
                await tester.pump(const Duration(milliseconds: 40));
              }
              violations.addAll(
                buriedBorderViolations(
                  await capture(tester, key),
                  r,
                  ink,
                  '$label f$frame',
                ),
              );
              if (violations.isNotEmpty) break;
            }
            expect(violations, isEmpty, reason: violations.take(6).join('\n'));
          });
        }
      }
    }
  });

  // =========================================================================
  // Section F - data transitions
  // =========================================================================

  group('F. data transitions', () {
    for (final bool clockwise in <bool>[true, false]) {
      for (final int? selected in <int?>[null, 0, 1, 2]) {
        testWidgets('F23 highlight replaces its logical border contribution '
            'clockwise=$clockwise selected=$selected', (
          WidgetTester tester,
        ) async {
          const List<Color> normal = <Color>[
            Color(0xFFFF0000),
            Color(0xFF0000FF),
            Color(0xFFFFFF00),
          ];
          for (final int? previous in <int?>[null, 0]) {
            for (final Color highlight in <Color>[
              const Color(0xFF00FF00),
              const Color(0xFFFF00FF),
            ]) {
              Future<Raster> run({required bool selectionFirst}) async {
                await tester.pumpWidget(const SizedBox.shrink());
                final GlobalKey boundary = GlobalKey();
                WovenRingChart chart(int active, int? selection, Color line) =>
                    WovenRingChart(
                      animation: WovenRingAnimation.none,
                      transitionDuration: const Duration(seconds: 1),
                      highlightedIndex: selection,
                      highlightBorder: WovenBorder(
                        color: line,
                        widthFraction: 0.05,
                      ),
                      style: WovenRingStyle(clockwise: clockwise),
                      segments: <WovenSegment>[
                        for (var i = 0; i < normal.length; i++)
                          WovenSegment(
                            value: i == active ? 1 : 0,
                            fill: const WovenFill.solid(Color(0xFFFFFFFF)),
                            border: WovenBorder(
                              color: normal[i],
                              widthFraction: 0.05,
                            ),
                          ),
                      ],
                    );
                const Color oldHighlight = Color(0xFF00FF00);
                await pump(tester, boundary, chart(0, previous, oldHighlight));
                await pump(tester, boundary, chart(1, previous, oldHighlight));
                await tester.pump(const Duration(milliseconds: 500));
                if (selectionFirst) {
                  await pump(tester, boundary, chart(1, selected, highlight));
                  await pump(tester, boundary, chart(2, selected, highlight));
                } else {
                  await pump(
                    tester,
                    boundary,
                    chart(2, previous, oldHighlight),
                  );
                  await pump(tester, boundary, chart(2, selected, highlight));
                }
                return capture(tester, boundary);
              }

              final Raster beforeRetarget = await run(selectionFirst: true);
              final Raster afterRetarget = await run(selectionFirst: false);
              // At the halfway frame, the old red and blue logical sources
              // contribute equally. Highlight replaces only its own source;
              // the new yellow target contributes nothing until time advances.
              final Color first = selected == 0 ? highlight : normal[0];
              final Color second = selected == 1 ? highlight : normal[1];
              final Rgba expected = Rgba(
                ((first.r + second.r) * 255 / 2).round(),
                ((first.g + second.g) * 255 / 2).round(),
                ((first.b + second.b) * 255 / 2).round(),
                255,
              );
              for (final Raster raster in <Raster>[
                beforeRetarget,
                afterRetarget,
              ]) {
                for (final (int, int) point in <(int, int)>[
                  (240, 3),
                  (476, 240),
                  (240, 476),
                  (3, 240),
                ]) {
                  final Rgba pixel = raster.at(point.$1, point.$2);
                  expect(
                    channelDistance(pixel, expected),
                    lessThanOrEqualTo(1),
                    reason:
                        'previous=$previous highlight=$highlight '
                        'point=$point pixel=$pixel expected=$expected',
                  );
                  expect(pixel.a, 255);
                }
              }
              expect(
                afterRetarget.bytes,
                orderedEquals(beforeRetarget.bytes),
                reason:
                    'no time elapsed: selection and retarget order must '
                    'preserve the same frame; previous=$previous '
                    'highlight=$highlight',
              );
            }
          }
        });
      }
    }
    for (final int destinationCount in <int>[2, 1, 0]) {
      for (final bool retarget in <bool>[false, true]) {
        testWidgets('F22 invalid current-list highlight is absent during '
            'shrink to $destinationCount retarget=$retarget', (
          WidgetTester tester,
        ) async {
          for (final bool clockwise in <bool>[true, false]) {
            for (final bool oldSelection in <bool>[false, true]) {
              for (final int requested in <int>{-1, destinationCount, 3, 8}) {
                Future<List<Raster>> run(int? index) async {
                  await tester.pumpWidget(const SizedBox.shrink());
                  final GlobalKey boundary = GlobalKey();
                  WovenRingChart chart(int count, int? selection) =>
                      WovenRingChart(
                        animation: WovenRingAnimation.none,
                        transitionDuration: const Duration(seconds: 1),
                        style: WovenRingStyle(clockwise: clockwise),
                        highlightedIndex: selection,
                        highlightBorder: const WovenBorder(
                          color: Color(0xFF000000),
                          widthFraction: 0.05,
                        ),
                        segments: <WovenSegment>[
                          for (var i = 0; i < count; i++)
                            WovenSegment(
                              value: 1,
                              fill: WovenFill.solid(tenColors[i]),
                            ),
                        ],
                      );
                  await pump(
                    tester,
                    boundary,
                    chart(4, oldSelection ? 3 : null),
                  );
                  if (retarget) {
                    // Start a many-to-sole topology handoff, then retarget
                    // its retained styles before the first motion settles.
                    await pump(tester, boundary, chart(1, index));
                    await tester.pump(const Duration(milliseconds: 300));
                  }
                  await pump(tester, boundary, chart(destinationCount, index));
                  await tester.pump(const Duration(milliseconds: 100));
                  final Raster early = await capture(tester, boundary);
                  await tester.pump(const Duration(milliseconds: 200));
                  final Raster middle = await capture(tester, boundary);
                  await tester.pump(const Duration(milliseconds: 700));
                  return <Raster>[
                    early,
                    middle,
                    await capture(tester, boundary),
                  ];
                }

                final List<Raster> unselected = await run(null);
                final List<Raster> invalid = await run(requested);
                for (var frame = 0; frame < unselected.length; frame++) {
                  expect(
                    invalid[frame].bytes,
                    orderedEquals(unselected[frame].bytes),
                    reason:
                        'current list length=$destinationCount '
                        'invalid index=$requested clockwise=$clockwise '
                        'oldSelection=$oldSelection retarget=$retarget frame=$frame',
                  );
                }
                if (destinationCount > 0 && requested == 3) {
                  final List<Raster> valid = await run(0);
                  expect(
                    pixelDifference(valid[1], unselected[1]),
                    greaterThan(0),
                    reason: 'a valid current-list index must still highlight',
                  );
                  final Rgba settledBorder = valid.last.at(240, 3);
                  expect(
                    (
                      settledBorder.r,
                      settledBorder.g,
                      settledBorder.b,
                      settledBorder.a,
                    ),
                    (0, 0, 0, 255),
                    reason:
                        'valid selected border must be visible after shrink',
                  );
                }
              }
            }
          }
        });
      }
    }

    testWidgets('F18 topology preserves premultiplied color over a backdrop', (
      WidgetTester tester,
    ) async {
      for (final bool clockwise in <bool>[true, false]) {
        for (final bool toMany in <bool>[true, false]) {
          for (final Color surface in <Color>[
            const Color(0x00000000),
            const Color(0x800000FF),
          ]) {
            for (final bool backdrop in <bool>[false, true]) {
              await tester.pumpWidget(const SizedBox.shrink());
              final GlobalKey key = GlobalKey();
              Widget chart(int count) {
                final Widget ring = WovenRingChart(
                  animation: WovenRingAnimation.none,
                  transitionDuration: const Duration(seconds: 1),
                  style: WovenRingStyle(
                    clockwise: clockwise,
                    surfaceColor: surface,
                  ),
                  segments: <WovenSegment>[
                    for (var i = 0; i < count; i++)
                      const WovenSegment(
                        value: 1,
                        fill: WovenFill.solid(Color(0x80FF0000)),
                      ),
                  ],
                );
                return backdrop
                    ? ColoredBox(color: const Color(0xFF00FF00), child: ring)
                    : ring;
              }

              await pump(tester, key, chart(toMany ? 1 : 3));
              final Raster before = await capture(tester, key);
              await pump(tester, key, chart(toMany ? 3 : 1));
              expect(
                (await capture(tester, key)).bytes,
                orderedEquals(before.bytes),
              );
              var elapsed = 0;
              for (final int time in <int>[1, 250, 500, 750, 999, 1000]) {
                await tester.pump(Duration(milliseconds: time - elapsed));
                elapsed = time;
                final Raster frame = await capture(tester, key);
                final Rgba pixel = frame.at(
                  (side * 0.1).toInt(),
                  (side / 2).toInt(),
                );
                final int blue = surface.a == 0 ? 0 : 64;
                final int alpha = surface.a == 0 ? 128 : 192;
                expect(pixel.r, closeTo(128, 1));
                expect(pixel.b, closeTo(blue, 1));
                expect(pixel.g, closeTo(backdrop ? 255 - alpha : 0, 1));
                expect(
                  pixel.a,
                  closeTo(backdrop ? 255 : alpha, 1),
                  reason:
                      '$clockwise $toMany $surface backdrop=$backdrop time=$time',
                );
                // The result layer must leave the hole/background untouched.
                expect(frame.at(240, 240).a, backdrop ? 255 : 0);
              }
            }
          }
        }
      }
    });

    testWidgets('F19 a newly visible sole destination carries its highlight', (
      WidgetTester tester,
    ) async {
      for (final bool clockwise in <bool>[true, false]) {
        await tester.pumpWidget(const SizedBox.shrink());
        final GlobalKey key = GlobalKey();
        WovenRingChart chart(bool single) => WovenRingChart(
          animation: WovenRingAnimation.none,
          transitionDuration: const Duration(seconds: 1),
          highlightedIndex: 2,
          highlightBorder: const WovenBorder(
            color: Color(0xFF000000),
            widthFraction: 0.05,
          ),
          style: WovenRingStyle(clockwise: clockwise),
          segments: <WovenSegment>[
            WovenSegment.solid(single ? 0 : 50, const Color(0xFFFF0000)),
            WovenSegment.solid(single ? 0 : 50, const Color(0xFF00FF00)),
            WovenSegment.solid(single ? 100 : 0, const Color(0xFF0000FF)),
          ],
        );
        await pump(tester, key, chart(false));
        await pump(tester, key, chart(true));
        await tester.pump(const Duration(milliseconds: 999));
        final Raster before = await capture(tester, key);
        await tester.pump(const Duration(milliseconds: 1));
        final Raster after = await capture(tester, key);
        final Rgba edge = before.at(240, 2);
        expect((edge.r, edge.g, edge.b, edge.a), (0, 0, 0, 255));
        for (final double radius in <double>[side * 0.3 + 3, side * 0.5 - 3]) {
          for (var sample = 0; sample < 720; sample++) {
            final double angle = sample * 2 * math.pi / 720;
            final Offset point =
                const Offset(side / 2, side / 2) +
                Offset(math.cos(angle), math.sin(angle)) * radius;
            final Rgba pending = before.atPoint(point);
            final Rgba settled = after.atPoint(point);
            expect(
              (pending.r, pending.g, pending.b, pending.a),
              (0, 0, 0, 255),
              reason: 'destination highlight at $point',
            );
            expect(channelDistance(pending, settled), lessThanOrEqualTo(1));
          }
        }
      }
    });

    testWidgets('F17 a sole-index handoff keeps its phase while colors morph', (
      WidgetTester tester,
    ) async {
      const List<WovenFill> fills = <WovenFill>[
        WovenFill.gradient(head: Color(0xFFFF0000), tail: Color(0xFF0000FF)),
        WovenFill.gradient(head: Color(0xFF00FF00), tail: Color(0xFF000000)),
      ];
      const List<int> times = <int>[1, 120, 240, 360, 479, 480];
      for (final bool clockwise in <bool>[true, false]) {
        for (final int source in <int>[0, 1]) {
          final WovenRingStyle style = WovenRingStyle(
            clockwise: clockwise,
            startAngle: 0.287,
          );
          final Ring r = Ring(
            side: side,
            thicknessFraction: 0.20,
            overlapFraction: 0.50,
            startAngle: 0.287,
            clockwise: clockwise,
          );
          final GlobalKey key = GlobalKey();
          WovenRingChart chart(int active) => WovenRingChart(
            style: style,
            animation: WovenRingAnimation.none,
            transitionDuration: const Duration(milliseconds: 480),
            segments: <WovenSegment>[
              for (var i = 0; i < 2; i++)
                WovenSegment(value: i == active ? 100 : 0, fill: fills[i]),
            ],
          );
          await tester.pumpWidget(const SizedBox.shrink());
          await pump(tester, key, chart(source));
          final Raster before = await capture(tester, key);
          await pump(tester, key, chart(1 - source));
          expect(pixelDifference(before, await capture(tester, key)), 0);
          var elapsed = 0;
          for (final int time in times) {
            await tester.pump(Duration(milliseconds: time - elapsed));
            elapsed = time;
            final Raster raster = await capture(tester, key);
            final double t = Curves.easeInOut.transform(time / 480);
            // The sole ring keeps the same head and one-turn gradient phase.
            // Derive pixel-center phase and RGB directly, without the package's
            // geometry, segment interpolation, painter, or shader helpers.
            final double head = r.startAngle - r.dir * r.jointLag;
            final Color fromHead = fills[source].head;
            final Color fromTail = fills[source].tail;
            final Color toHead = fills[1 - source].head;
            final Color toTail = fills[1 - source].tail;
            for (final double radius in <double>[
              r.track - r.cap / 2,
              r.track,
              r.track + r.cap / 2,
            ]) {
              for (final double phase in <double>[
                0.125,
                0.25,
                0.5,
                0.75,
                0.875,
              ]) {
                final Offset requested = r.at(
                  radius,
                  head + r.dir * phase * 2 * math.pi,
                );
                final Offset p = Offset(
                  (requested.dx - 0.5).round() + 0.5,
                  (requested.dy - 0.5).round() + 0.5,
                );
                final double angle = math.atan2(
                  p.dy - r.center.dy,
                  p.dx - r.center.dx,
                );
                final double along =
                    wrapPositive(r.dir * (angle - head)) / (2 * math.pi);
                int channel(
                  double aHead,
                  double aTail,
                  double bHead,
                  double bTail,
                ) =>
                    (((aHead + (bHead - aHead) * t) * (1 - along) +
                                (aTail + (bTail - aTail) * t) * along) *
                            255)
                        .round();
                final Rgba expected = Rgba(
                  channel(fromHead.r, fromTail.r, toHead.r, toTail.r),
                  channel(fromHead.g, fromTail.g, toHead.g, toTail.g),
                  channel(fromHead.b, fromTail.b, toHead.b, toTail.b),
                  255,
                );
                final Rgba pixel = raster.atPoint(p);
                expect(pixel.a, 255);
                expect(
                  channelDistance(pixel, expected),
                  lessThanOrEqualTo(2),
                  reason:
                      'sole-index phase changed: clockwise=$clockwise '
                      'source=$source time=$time point=$p pixel=$pixel '
                      'expected=$expected',
                );
              }
            }
          }
        }
      }
    });

    final List<(String, List<double>, List<double>)>
    moves = <(String, List<double>, List<double>)>[
      (
        'F01 four values change',
        <double>[25, 25, 25, 25],
        <double>[18, 31, 23, 28],
      ),
      ('F02 four reversed', <double>[18, 31, 23, 28], <double>[28, 23, 31, 18]),
      (
        'F03 tiny value crossing',
        <double>[0.3, 39.7, 25, 35],
        <double>[0.3, 30, 42, 27.7],
      ),
      (
        'F04 four to ten',
        <double>[25, 25, 25, 25],
        <double>[10, 9, 11, 8, 12, 10, 9, 11, 8, 12],
      ),
      (
        'F05 ten to four',
        <double>[10, 9, 11, 8, 12, 10, 9, 11, 8, 12],
        <double>[25, 25, 25, 25],
      ),
      ('F06 four to one', <double>[25, 25, 25, 25], <double>[100, 0, 0, 0]),
      ('F07 one to four', <double>[100, 0, 0, 0], <double>[25, 25, 25, 25]),
      ('F08 four to two', <double>[25, 25, 25, 25], <double>[60, 40, 0, 0]),
      ('F09 two to four', <double>[60, 40, 0, 0], <double>[25, 25, 25, 25]),
      ('F10 two to one', <double>[60, 40], <double>[100, 0]),
      ('F11 one to two', <double>[100, 0], <double>[60, 40]),
      ('F12 three to two', <double>[40, 35, 25], <double>[55, 45, 0]),
      ('F13 data to all zero', <double>[25, 25, 25, 25], <double>[0, 0, 0, 0]),
      ('F14 all zero to data', <double>[0, 0, 0, 0], <double>[25, 25, 25, 25]),
    ];

    for (final (String name, List<double> from, List<double> to) in moves) {
      for (final bool clockwise in <bool>[true, false]) {
        testWidgets('$name ${clockwise ? 'CW' : 'CCW'}', (
          WidgetTester tester,
        ) async {
          final WovenRingStyle style = WovenRingStyle(clockwise: clockwise);
          final Ring r = Ring(
            side: side,
            thicknessFraction: style.resolvedThicknessFraction,
            overlapFraction: style.resolvedOverlapFraction,
            startAngle: style.resolvedStartAngle,
            clockwise: clockwise,
          );
          final GlobalKey key = GlobalKey();
          await pump(
            tester,
            key,
            WovenRingChart(
              segments: solids(from, tenColors),
              style: style,
              animation: WovenRingAnimation.none,
            ),
          );
          await pump(
            tester,
            key,
            WovenRingChart(
              segments: solids(to, tenColors),
              style: style,
              animation: WovenRingAnimation.none,
            ),
          );

          // Every frame keeps the thickness covered: no background flash and no
          // hole opening up while the geometry rearranges. A ring that is
          // fading to or from the empty state is only ever as opaque as the
          // neutral empty track itself, which is translucent by design.
          final bool touchesEmpty =
              from.every((double v) => v <= 0) ||
              to.every((double v) => v <= 0);
          final int minimumAlpha = touchesEmpty ? emptyTrackAlpha : 255;
          for (var frame = 0; frame <= 32; frame++) {
            if (frame > 0) await tester.pump(const Duration(milliseconds: 16));
            final Raster raster = await capture(tester, key);
            for (var s = 0; s < 720; s++) {
              final double angle = s * 2 * math.pi / 720;
              for (final double radius in <double>[
                r.inner + 2,
                r.track,
                r.outer - 2,
              ]) {
                expect(
                  raster.atPoint(r.at(radius, angle)).a,
                  greaterThanOrEqualTo(minimumAlpha),
                  reason:
                      '$name frame $frame has a see-through thickness pixel at '
                      'angle ${angle.toStringAsFixed(4)} r=$radius',
                );
              }
            }
          }

          // And it lands exactly on the static rendering of the destination.
          await tester.pump(const Duration(milliseconds: 900));
          final Raster settled = await capture(tester, key);
          await tester.pumpWidget(const SizedBox.shrink());
          await pump(
            tester,
            key,
            WovenRingChart(
              segments: solids(to, tenColors),
              style: style,
              animation: WovenRingAnimation.none,
            ),
          );
          expect(
            pixelDifference(settled, await capture(tester, key)),
            0,
            reason: '$name did not land on the static destination frame',
          );
        });
      }
    }

    // The colour runs round the centreline are the data order, once each, at
    // every frame. This needs no knowledge of the interpolated fractions, so it
    // holds through a transition, and it fails the moment a tail peeks past a
    // successor head or the seam changes owner.
    final List<
      (String, WovenRingStyle, List<WovenSegment> Function(List<double>))
    >
    styles =
        <(String, WovenRingStyle, List<WovenSegment> Function(List<double>))>[
          (
            'flat',
            const WovenRingStyle(),
            (List<double> v) => solids(v, tenColors),
          ),
          (
            'gradient',
            const WovenRingStyle(),
            (List<double> v) => <WovenSegment>[
              for (var i = 0; i < v.length; i++)
                WovenSegment(
                  value: v[i],
                  fill: WovenFill.shaded(tenColors[i], step: 0.16),
                ),
            ],
          ),
          (
            'bordered',
            const WovenRingStyle(),
            (List<double> v) => <WovenSegment>[
              for (var i = 0; i < v.length; i++)
                WovenSegment(
                  value: v[i],
                  fill: WovenFill.solid(tenColors[i]),
                  border: const WovenBorder(),
                ),
            ],
          ),
          (
            'shadow',
            const WovenRingStyle(shadow: WovenShadow()),
            (List<double> v) => solids(v, tenColors),
          ),
        ];

    for (final (
          String styleName,
          WovenRingStyle style,
          List<WovenSegment> Function(List<double>) build,
        )
        in styles) {
      for (final bool clockwise in <bool>[true, false]) {
        testWidgets(
          'F16 $styleName keeps every joint owner through the transition '
          '${clockwise ? 'CW' : 'CCW'}',
          (WidgetTester tester) async {
            final WovenRingStyle resolved = style.copyWith(
              clockwise: clockwise,
            );
            final Ring r = Ring(
              side: side,
              thicknessFraction: resolved.resolvedThicknessFraction,
              overlapFraction: resolved.resolvedOverlapFraction,
              startAngle: resolved.resolvedStartAngle,
              clockwise: clockwise,
              shadow: resolved.shadow,
            );
            final double shadow = resolved.shadow == null
                ? 0.0
                : resolved.shadow!.color.a;
            final List<WovenFill> fills = <WovenFill>[
              for (final WovenSegment s in build(<double>[1, 1, 1, 1])) s.fill,
            ];
            final GlobalKey key = GlobalKey();
            await pump(
              tester,
              key,
              WovenRingChart(
                segments: build(<double>[25, 25, 25, 25]),
                style: resolved,
                animation: WovenRingAnimation.none,
              ),
            );
            await pump(
              tester,
              key,
              WovenRingChart(
                segments: build(<double>[9, 44, 12, 35]),
                style: resolved,
                animation: WovenRingAnimation.none,
              ),
            );
            final List<String> violations = <String>[];
            for (var frame = 0; frame <= 30; frame++) {
              if (frame > 0) {
                await tester.pump(const Duration(milliseconds: 16));
              }
              violations.addAll(
                checkRunStructure(
                  await capture(tester, key),
                  r,
                  fills,
                  <int>[0, 1, 2, 3],
                  '$styleName ${clockwise ? 'CW' : 'CCW'} f$frame',
                  tolerance: 10,
                  shadow: shadow,
                ),
              );
              if (violations.isNotEmpty) break;
            }
            expect(violations, isEmpty, reason: violations.take(6).join('\n'));
          },
        );
      }
    }

    testWidgets('F20 surface borders repaint immediately after retargets', (
      WidgetTester tester,
    ) async {
      const Color black = Color(0xFF000000);
      const Color white = Color(0xFFFFFFFF);
      const List<List<List<double>>> sequences = <List<List<double>>>[
        <List<double>>[
          <double>[1, 1],
          <double>[3, 1],
          <double>[1, 3],
        ],
        <List<double>>[
          <double>[1, 0],
          <double>[0, 1],
          <double>[1, 0],
        ],
        <List<double>>[
          <double>[1, 1, 1],
          <double>[1, 0, 0],
          <double>[0, 0, 1],
        ],
        <List<double>>[
          <double>[1, 0, 0],
          <double>[1, 1, 1],
          <double>[1, 2, 3],
        ],
      ];
      for (final bool clockwise in <bool>[true, false]) {
        for (final List<List<double>> sequence in sequences) {
          Future<Raster> run(Color initialSurface) async {
            await tester.pumpWidget(const SizedBox.shrink());
            final GlobalKey key = GlobalKey();
            WovenRingChart chart(List<double> values, Color surface) =>
                WovenRingChart(
                  animation: WovenRingAnimation.none,
                  transitionDuration: const Duration(seconds: 1),
                  style: WovenRingStyle(
                    clockwise: clockwise,
                    surfaceColor: surface,
                  ),
                  segments: <WovenSegment>[
                    for (final double value in values)
                      WovenSegment(
                        value: value,
                        fill: const WovenFill.solid(Color(0xFF0000FF)),
                        border: const WovenBorder(widthFraction: .05),
                      ),
                  ],
                );
            await pump(tester, key, chart(sequence[0], initialSurface));
            await pump(tester, key, chart(sequence[1], initialSurface));
            await tester.pump(const Duration(milliseconds: 400));
            await pump(tester, key, chart(sequence[2], initialSurface));
            await tester.pump(const Duration(milliseconds: 100));
            await pump(tester, key, chart(sequence[2], black));
            return capture(tester, key);
          }

          // Changing only the surface must immediately match the same motion
          // rendered on that surface all along. Inputs have no explicit border
          // colors, so no old surface color belongs in the new frame.
          final Raster expected = await run(black);
          final Raster changed = await run(white);
          expect(
            changed.bytes,
            orderedEquals(expected.bytes),
            reason: 'surface repaint clockwise=$clockwise sequence=$sequence',
          );
        }
      }
    });

    testWidgets('F15 mid-transition retargeting never rewinds', (
      WidgetTester tester,
    ) async {
      final GlobalKey key = GlobalKey();
      final List<List<double>> sequence = <List<double>>[
        <double>[25, 25, 25, 25],
        <double>[40, 20, 20, 20],
        <double>[10, 10, 10, 70],
        <double>[100, 0, 0, 0],
        <double>[25, 25, 25, 25],
        <double>[60, 40, 0, 0],
        <double>[5, 5, 45, 45],
      ];
      await pump(
        tester,
        key,
        WovenRingChart(
          segments: solids(sequence.first, tenColors),
          animation: WovenRingAnimation.none,
        ),
      );
      const WovenRingStyle style = WovenRingStyle();
      final Ring r = Ring(
        side: side,
        thicknessFraction: style.resolvedThicknessFraction,
        overlapFraction: style.resolvedOverlapFraction,
        startAngle: style.resolvedStartAngle,
        clockwise: true,
      );
      for (var step = 1; step < sequence.length; step++) {
        final Raster before = await capture(tester, key);
        await pump(
          tester,
          key,
          WovenRingChart(
            segments: solids(sequence[step], tenColors),
            animation: WovenRingAnimation.none,
          ),
        );
        // The very first frame after a retarget must be the frame that was
        // already on screen: a rewind would show as a large jump here.
        final Raster immediate = await capture(tester, key);
        expect(
          pixelDifference(before, immediate),
          0,
          reason: 'step $step jumped on the update frame',
        );
        // Interrupt part way through, every time.
        await tester.pump(const Duration(milliseconds: 130));
        final Raster raster = await capture(tester, key);
        for (var s = 0; s < 720; s++) {
          final double angle = s * 2 * math.pi / 720;
          expect(
            raster.atPoint(r.at(r.track, angle)).a,
            255,
            reason: 'step $step opened a gap mid-flight at angle $angle',
          );
        }
      }
    });
  });

  // =========================================================================
  // Section G - layout, lifecycle and accessibility
  // =========================================================================

  // =========================================================================
  // Section H - gradients. A gradient is the only fill that makes the joint
  // edge visible on a single self-lapping segment, so it is also the only one
  // that can expose a seam that is not a cap.
  // =========================================================================

  group('H. gradients', () {
    testWidgets('H5 long and saturated heads retain their cap-to-cap phase', (
      WidgetTester tester,
    ) async {
      for (final (double fraction, double width, double overlap) shape
          in <(double, double, double)>[
            (0.18, 0.20, 0.5),
            (0.55, 0.20, 0.5),
            (0.90, 0.20, 0.5),
            (0.95, 0.20, 0.5),
            (0.975, 0.12, 0.9),
            (0.93, 0.28, 0.8),
          ]) {
        for (final bool clockwise in <bool>[true, false]) {
          for (final WovenGradientDirection direction
              in WovenGradientDirection.values) {
            for (final double rotation in <double>[0, 0.739, -2.27]) {
              final WovenRingStyle style = WovenRingStyle(
                thicknessFraction: shape.$2,
                overlapFraction: shape.$3,
                clockwise: clockwise,
                startAngle: rotation,
                gradientDirection: direction,
                smallValuePolicy: WovenSmallValuePolicy.allowVanish,
              );
              final Ring r = Ring(
                side: side,
                thicknessFraction: shape.$2,
                overlapFraction: shape.$3,
                startAngle: rotation,
                clockwise: clockwise,
              );
              // Tangency from the ring centre to the cap disc gives its maximum
              // polar reach. This is not the centreline chord reach capHalf.
              final double reach = math.asin(r.cap / r.track);
              expect(
                1 - shape.$1,
                greaterThan(reach / (2 * math.pi)),
                reason:
                    'both values must survive the stated allowVanish policy',
              );
              final double head = rotation - r.dir * r.jointLag;
              final double origin = head - r.dir * reach;
              final double span =
                  shape.$1 * 2 * math.pi + r.jointLag + 2 * reach;
              await tester.pumpWidget(const SizedBox.shrink());
              final Raster raster = await render(
                tester,
                WovenRingChart(
                  animation: WovenRingAnimation.none,
                  style: style,
                  segments: <WovenSegment>[
                    WovenSegment(
                      value: shape.$1,
                      fill: const WovenFill.gradient(
                        head: Color(0xFFFF0000),
                        tail: Color(0xFF0000FF),
                      ),
                    ),
                    WovenSegment.solid(1 - shape.$1, const Color(0xFF00FF00)),
                  ],
                ),
              );
              for (final double along in <double>[
                -reach * .65,
                0,
                (shape.$1 * 2 * math.pi - reach) * .25,
                (shape.$1 * 2 * math.pi - reach) * .5,
                (shape.$1 * 2 * math.pi - reach) * .70,
              ]) {
                final Offset point = r.at(r.track, head + r.dir * along);
                final int x = point.dx.floor();
                final int y = point.dy.floor();
                final double polar = math.atan2(
                  y + .5 - r.center.dy,
                  x + .5 - r.center.dx,
                );
                final double phase =
                    wrapPositive(r.dir * (polar - origin)) / span;
                final double t = direction == WovenGradientDirection.headToTail
                    ? phase
                    : 1 - phase;
                final Rgba actual = raster.at(x, y);
                final String label =
                    '$shape $clockwise $direction rotation=$rotation '
                    'along=$along pixel=($x,$y)';
                expect(actual.r, closeTo(255 * (1 - t), 1), reason: label);
                expect(actual.b, closeTo(255 * t, 1), reason: label);
                expect((actual.g, actual.a), (0, 255), reason: label);
              }
            }
          }
        }
      }
    });

    testWidgets('H4 a translucent self lap composites once over its surface', (
      WidgetTester tester,
    ) async {
      for (final bool clockwise in <bool>[true, false]) {
        for (final double opacity in <double>[1, 0.5]) {
          final WovenRingStyle style = WovenRingStyle(
            startAngle: 0,
            clockwise: clockwise,
            surfaceColor: const Color(0xFFFFFFFF),
          );
          final Raster raster = await render(
            tester,
            WovenRingChart(
              style: style,
              animation: WovenRingAnimation.none,
              segments: <WovenSegment>[
                WovenSegment(
                  value: 100,
                  fill: const WovenFill.gradient(
                    head: Color(0x80FF0000),
                    tail: Color(0x800000FF),
                  ),
                  opacity: opacity,
                ),
              ],
            ),
          );
          // Both gradient ends have zero green and alpha 128. Blending once
          // over white gives this channel everywhere inside the annulus,
          // including its self lap and both antialiased lap boundaries.
          final int expectedGreen = 255 - (128 * opacity).round();
          for (final double radius in <double>[
            side * 0.32,
            side * 0.40,
            side * 0.48,
          ]) {
            for (var sample = 0; sample < 1440; sample++) {
              final double angle = sample * 2 * math.pi / 1440;
              final Rgba pixel = raster.atPoint(
                const Offset(side / 2, side / 2) +
                    Offset(math.cos(angle), math.sin(angle)) * radius,
              );
              expect(pixel.a, 255);
              expect(
                pixel.g,
                expectedGreen,
                reason:
                    'single alpha compounded: clockwise=$clockwise '
                    'opacity=$opacity radius=$radius angle=$angle pixel=$pixel',
              );
            }
          }
        }
      }
    });

    for (final bool clockwise in <bool>[true, false]) {
      for (final WovenSingleSegmentStyle single
          in WovenSingleSegmentStyle.values) {
        final String label = '${single.name} ${clockwise ? 'CW' : 'CCW'}';
        testWidgets(
          'H1 a self-lapping segment joins with a cap, not a radial seam ($label)',
          (WidgetTester tester) async {
            final WovenRingStyle style = WovenRingStyle(
              thicknessFraction: 0.15,
              overlapFraction: 0.45,
              startAngle: 45 * math.pi / 180,
              clockwise: clockwise,
              singleSegmentStyle: single,
            );
            final WovenFill fill = WovenFill.shaded(cPurple, step: 0.20);
            final Raster raster = await render(
              tester,
              WovenRingChart(
                segments: <WovenSegment>[WovenSegment(value: 100, fill: fill)],
                style: style,
                animation: WovenRingAnimation.none,
              ),
            );
            final Ring r = Ring(
              side: side,
              thicknessFraction: style.resolvedThicknessFraction,
              overlapFraction: style.resolvedOverlapFraction,
              startAngle: style.resolvedStartAngle,
              clockwise: clockwise,
            );
            // The single segment's head sits one overlap depth behind the data
            // boundary, exactly like every other segment's head.
            final double head = r.startAngle - r.dir * r.jointLag;
            final List<String> violations = selfJointEdgeViolations(
              raster,
              r,
              head,
              label,
            );
            expect(violations, isEmpty, reason: violations.join('\n'));
          },
        );
      }
    }

    for (final bool clockwise in <bool>[true, false]) {
      for (final WovenGradientDirection direction
          in WovenGradientDirection.values) {
        testWidgets('H2 along-length gradients run the right way '
            '(${direction.name} ${clockwise ? 'CW' : 'CCW'})', (
          WidgetTester tester,
        ) async {
          final WovenRingStyle style = WovenRingStyle(
            clockwise: clockwise,
            gradientDirection: direction,
          );
          final List<WovenFill> fills = <WovenFill>[
            for (var i = 0; i < 4; i++)
              WovenFill.shaded(tenColors[i], step: 0.18),
          ];
          final Raster raster = await render(
            tester,
            WovenRingChart(
              segments: <WovenSegment>[
                for (var i = 0; i < 4; i++)
                  WovenSegment(value: 25, fill: fills[i]),
              ],
              style: style,
              animation: WovenRingAnimation.none,
            ),
          );
          final Ring r = Ring(
            side: side,
            thicknessFraction: style.resolvedThicknessFraction,
            overlapFraction: style.resolvedOverlapFraction,
            startAngle: style.resolvedStartAngle,
            clockwise: clockwise,
          );
          final List<Extent> extents = extentsFor(
            r,
            List<double>.filled(4, 0.25),
          );
          for (var i = 0; i < 4; i++) {
            // Just inside the head, and the last strip still visible before
            // the successor's head buries the tail.
            final Rgba atHead = raster.atPoint(
              r.at(r.track, extents[i].start + r.dir * r.capHalf * 0.4),
            );
            final Rgba atTail = raster.atPoint(
              r.at(
                r.track,
                extents[i].end - r.dir * (r.jointLag + r.capHalf * 1.4),
              ),
            );
            final bool headFirst =
                direction == WovenGradientDirection.headToTail;
            final Rgba near = rgbaOf(headFirst ? fills[i].head : fills[i].tail);
            final Rgba far = rgbaOf(headFirst ? fills[i].tail : fills[i].head);
            expect(
              channelDistance(atHead, near),
              lessThan(channelDistance(atHead, far)),
              reason:
                  'segment $i shows the wrong end of its gradient at the head '
                  '(pixel $atHead, expected nearer $near than $far)',
            );
            expect(
              channelDistance(atTail, far),
              lessThan(channelDistance(atTail, near)),
              reason:
                  'segment $i shows the wrong end of its gradient at the tail '
                  '(pixel $atTail, expected nearer $far than $near)',
            );
          }
        });
      }
    }

    testWidgets('H3 across-thickness gradients shade radially, not angularly', (
      WidgetTester tester,
    ) async {
      // Smooth, so the jointed style's surfaceColor-coloured hairline does not
      // count as angular variation. H1 covers the joint itself.
      const WovenRingStyle style = WovenRingStyle(
        gradientAxis: WovenGradientAxis.acrossThickness,
        singleSegmentStyle: WovenSingleSegmentStyle.smooth,
      );
      final WovenFill fill = WovenFill.shaded(cPurple, step: 0.20);
      final Raster raster = await render(
        tester,
        WovenRingChart(
          segments: <WovenSegment>[WovenSegment(value: 100, fill: fill)],
          style: style,
          animation: WovenRingAnimation.none,
        ),
      );
      final Ring r = Ring(
        side: side,
        thicknessFraction: style.resolvedThicknessFraction,
        overlapFraction: style.resolvedOverlapFraction,
        startAngle: style.resolvedStartAngle,
        clockwise: true,
      );
      // A tube has no angular variation at all: the same radius is the same
      // colour the whole way round.
      for (final double radius in <double>[
        r.track - r.thickness * 0.3,
        r.track,
        r.track + r.thickness * 0.3,
      ]) {
        final Rgba reference = raster.atPoint(r.at(radius, 0));
        for (var s = 0; s < 720; s++) {
          final double angle = s * 2 * math.pi / 720;
          expect(
            channelDistance(raster.atPoint(r.at(radius, angle)), reference),
            lessThanOrEqualTo(3),
            reason:
                'across-thickness shading varies with angle at r=$radius '
                'angle=$angle',
          );
        }
      }
      // And it does vary across the thickness.
      expect(
        channelDistance(
          raster.atPoint(r.at(r.inner + 3, 0)),
          raster.atPoint(r.at(r.outer - 3, 0)),
        ),
        greaterThan(20),
        reason: 'across-thickness shading is flat',
      );
    });
  });

  group('G. widget contract', () {
    testWidgets('G1 every layout constraint is safe', (
      WidgetTester tester,
    ) async {
      final Widget ring = WovenRingChart(
        segments: solids(<double>[37, 19, 29, 15], tenColors),
        animation: WovenRingAnimation.none,
        center: const Text('x'),
      );
      // Each entry hands the ring a genuinely different constraint shape.
      final List<(String, Widget)> layouts = <(String, Widget)>[
        ('bounded', SizedBox.square(dimension: 300, child: ring)),
        ('very wide', SizedBox(width: 900, height: 120, child: ring)),
        ('very tall', SizedBox(width: 120, height: 900, child: ring)),
        // A Row leaves its child's width unbounded, a Column its height.
        (
          'unbounded width',
          Row(children: <Widget>[SizedBox(height: 200, child: ring)]),
        ),
        (
          'unbounded height',
          Column(children: <Widget>[SizedBox(width: 200, child: ring)]),
        ),
        ('both unbounded', UnconstrainedBox(child: ring)),
        ('zero', SizedBox.square(dimension: 0, child: ring)),
        ('one pixel', SizedBox.square(dimension: 1, child: ring)),
        ('huge', SizedBox.square(dimension: 4000, child: ring)),
      ];
      for (final (String name, Widget layout) in layouts) {
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: OverflowBox(
                minWidth: 0,
                minHeight: 0,
                maxWidth: double.infinity,
                maxHeight: double.infinity,
                child: layout,
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull, reason: '$name layout threw');
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('G2 reduced motion completes immediately', (
      WidgetTester tester,
    ) async {
      final GlobalKey key = GlobalKey();
      Future<void> pumpReduced(List<double> values) async {
        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Center(
                child: RepaintBoundary(
                  key: key,
                  child: SizedBox.square(
                    dimension: side,
                    child: WovenRingChart(
                      segments: solids(values, tenColors),
                      animation: WovenRingAnimation.sweep,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }

      await pumpReduced(<double>[37, 19, 29, 15]);
      await tester.pump();
      final Raster immediate = await capture(tester, key);
      await tester.pump(const Duration(seconds: 2));
      expect(
        pixelDifference(immediate, await capture(tester, key)),
        0,
        reason: 'reduced motion still animated the animation',
      );

      await pumpReduced(<double>[10, 10, 40, 40]);
      await tester.pump();
      final Raster afterChange = await capture(tester, key);
      await tester.pump(const Duration(seconds: 2));
      expect(
        pixelDifference(afterChange, await capture(tester, key)),
        0,
        reason: 'reduced motion still animated the data change',
      );
    });

    testWidgets('G3 disposal leaves no live ticker', (
      WidgetTester tester,
    ) async {
      for (final Widget ring in <Widget>[
        const WovenRingChart.loading(),
        const WovenRingChart.empty(),
        WovenRingChart(segments: solids(<double>[1, 2, 3], tenColors)),
      ]) {
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: SizedBox.square(dimension: side, child: ring),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 120));
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 1));
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('G3b all-invalid data and replay schedule no animation', (
      WidgetTester tester,
    ) async {
      final WovenRingChartController controller = WovenRingChartController();
      final GlobalKey key = GlobalKey();
      await pump(
        tester,
        key,
        WovenRingChart(
          segments: solids(<double>[0, -1, double.nan, double.infinity]),
          controller: controller,
        ),
      );
      expect(tester.binding.transientCallbackCount, 0);
      final Raster empty = await capture(tester, key);
      controller.replay();
      await tester.pump();
      expect(tester.binding.transientCallbackCount, 0);
      expect(pixelDifference(empty, await capture(tester, key)), 0);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    });

    testWidgets(
      'G3c disabling an active entrance ends its ticker immediately',
      (WidgetTester tester) async {
        final GlobalKey key = GlobalKey();
        final List<WovenSegment> segments = solids(<double>[25, 25, 25, 25]);
        await pump(tester, key, WovenRingChart(segments: segments));
        await tester.pump(const Duration(milliseconds: 250));
        expect(tester.binding.transientCallbackCount, greaterThan(0));
        await pump(
          tester,
          key,
          WovenRingChart(
            segments: segments,
            animation: WovenRingAnimation.none,
          ),
        );
        expect(tester.binding.transientCallbackCount, 0);
        final Raster completed = await capture(tester, key);
        await tester.pump(const Duration(seconds: 1));
        expect(pixelDifference(completed, await capture(tester, key)), 0);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      'G3d empty-to-invalid changes do not animate the neutral ring',
      (WidgetTester tester) async {
        final GlobalKey key = GlobalKey();
        await pump(
          tester,
          key,
          const WovenRingChart(segments: <WovenSegment>[]),
        );
        expect(tester.binding.transientCallbackCount, 0);
        final Raster empty = await capture(tester, key);
        for (final List<double> values in <List<double>>[
          <double>[0, double.nan],
          <double>[-1, double.infinity, double.negativeInfinity],
          <double>[],
        ]) {
          await pump(tester, key, WovenRingChart(segments: solids(values)));
          expect(
            tester.binding.transientCallbackCount,
            0,
            reason:
                'no transition should be scheduled for invalid values $values',
          );
          expect(pixelDifference(empty, await capture(tester, key)), 0);
        }
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      'G3e clearing an active entrance finishes the fade then idles',
      (WidgetTester tester) async {
        final Raster expectedEmpty = await render(
          tester,
          const WovenRingChart.empty(),
        );
        for (final WovenRingAnimation animation in <WovenRingAnimation>[
          WovenRingAnimation.sweep,
          WovenRingAnimation.grow,
        ]) {
          for (final List<double> values in <List<double>>[
            <double>[],
            <double>[0, 0],
          ]) {
            await tester.pumpWidget(const SizedBox.shrink());
            final GlobalKey key = GlobalKey();
            await pump(
              tester,
              key,
              WovenRingChart(
                segments: solids(<double>[1, 1]),
                animation: animation,
                animationDuration: const Duration(seconds: 10),
              ),
            );
            await tester.pump(const Duration(milliseconds: 100));
            final Raster before = await capture(tester, key);
            await pump(
              tester,
              key,
              WovenRingChart(
                segments: solids(values),
                animation: animation,
                animationDuration: const Duration(seconds: 10),
              ),
            );
            expect(pixelDifference(before, await capture(tester, key)), 0);
            await tester.pump(const Duration(milliseconds: 450));
            expect(tester.binding.transientCallbackCount, 0);
            expect(
              pixelDifference(expectedEmpty, await capture(tester, key)),
              0,
            );
          }
        }
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets('G4 semantics expose the aggregate and the entries', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox.square(
              dimension: side,
              child: WovenRingChart(
                segments: <WovenSegment>[
                  WovenSegment(
                    value: 60,
                    fill: WovenFill.solid(cRed),
                    semanticLabel: 'Red sixty',
                  ),
                  WovenSegment(
                    value: 40,
                    fill: WovenFill.solid(cGreen),
                    semanticLabel: 'Green forty',
                  ),
                ],
                animation: WovenRingAnimation.none,
                semanticValue: '2 entries',
              ),
            ),
          ),
        ),
      );
      expect(find.bySemanticsLabel('Red sixty, Green forty'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('G4b per-segment labels do not silence the centre', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      Future<void> pumpRing({required bool labelSegments}) async {
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: SizedBox.square(
                dimension: side,
                child: WovenRingChart(
                  segments: <WovenSegment>[
                    WovenSegment(
                      value: 60,
                      fill: const WovenFill.solid(cRed),
                      semanticLabel: labelSegments ? 'Red sixty' : null,
                    ),
                    WovenSegment(
                      value: 40,
                      fill: const WovenFill.solid(cGreen),
                      semanticLabel: labelSegments ? 'Green forty' : null,
                    ),
                  ],
                  animation: WovenRingAnimation.none,
                  center: const Text('60 percent'),
                ),
              ),
            ),
          ),
        );
      }

      // Baseline: with no labels at all the centre is readable.
      await pumpRing(labelSegments: false);
      expect(find.bySemanticsLabel('60 percent'), findsOneWidget);

      // Describing the segments must not take the total away. The ring's own
      // annotation merges with the centre, so the total arrives as part of that
      // node's label rather than as a node of its own.
      await pumpRing(labelSegments: true);
      expect(
        find.bySemanticsLabel(RegExp('60 percent')),
        findsOneWidget,
        reason: 'adding per-segment labels hid the centre from assistive tech',
      );
      expect(
        find.bySemanticsLabel(RegExp('Red sixty, Green forty')),
        findsOneWidget,
      );

      // An explicit ring description does stand for the whole chart, so there
      // the centre stays excluded and is not announced twice.
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox.square(
              dimension: side,
              child: WovenRingChart(
                segments: solids(<double>[60, 40], tenColors),
                animation: WovenRingAnimation.none,
                semanticLabel: 'Allocation',
                center: const Text('60 percent'),
              ),
            ),
          ),
        ),
      );
      expect(find.bySemanticsLabel('60 percent'), findsNothing);
      expect(find.bySemanticsLabel('Allocation'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('G5 a reused mutable list still animates', (
      WidgetTester tester,
    ) async {
      final GlobalKey key = GlobalKey();
      final List<WovenSegment> shared = <WovenSegment>[
        ...solids(<double>[25, 25, 25, 25], tenColors),
      ];
      await pump(
        tester,
        key,
        WovenRingChart(segments: shared, animation: WovenRingAnimation.none),
      );
      final Raster before = await capture(tester, key);
      shared[0] = const WovenSegment(value: 70, fill: WovenFill.solid(cRed));
      await pump(
        tester,
        key,
        WovenRingChart(segments: shared, animation: WovenRingAnimation.none),
      );
      await tester.pump(const Duration(milliseconds: 900));
      expect(
        pixelDifference(before, await capture(tester, key)),
        greaterThan(0),
        reason: 'mutating the same list instance was not picked up',
      );
    });
  });
}

// ===========================================================================
// Shared test plumbing
// ===========================================================================

// Independent whole-segment control: ask the renderer to compose each source
// before applying the group's opacity, preserving the supplied color spaces.
class _BorderCompositionReference extends CustomPainter {
  const _BorderCompositionReference({
    required this.fill,
    required this.border,
    required this.surface,
    required this.segmentOpacity,
    required this.lineOpacity,
  });

  final Color fill;
  final Color border;
  final Color surface;
  final double segmentOpacity;
  final double lineOpacity;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect bounds = Offset.zero & size;
    canvas.drawRect(bounds, Paint()..color = surface);
    canvas.saveLayer(
      bounds,
      Paint()
        ..color = const Color(0xFFFFFFFF).withValues(alpha: segmentOpacity),
    );
    canvas.drawRect(bounds, Paint()..color = fill);
    canvas.drawRect(
      bounds,
      Paint()..color = border.withValues(alpha: border.a * lineOpacity),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BorderCompositionReference oldDelegate) =>
      fill != oldDelegate.fill ||
      border != oldDelegate.border ||
      surface != oldDelegate.surface ||
      segmentOpacity != oldDelegate.segmentOpacity ||
      lineOpacity != oldDelegate.lineOpacity;
}

Future<void> pump(WidgetTester tester, GlobalKey key, Widget ring) async {
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: RepaintBoundary(
          key: key,
          child: SizedBox.square(dimension: side, child: ring),
        ),
      ),
    ),
  );
}

/// Number of pixels that differ by more than one unit in any channel.
int pixelDifference(Raster a, Raster b) {
  if (a.width != b.width || a.height != b.height) return 1 << 30;
  var count = 0;
  for (var i = 0; i < a.bytes.length; i += 4) {
    for (var c = 0; c < 4; c++) {
      if ((a.bytes[i + c] - b.bytes[i + c]).abs() > 1) {
        count++;
        break;
      }
    }
  }
  return count;
}

/// Every edge of a growing ring is a cap: a circle of radius `cap` centred one
/// cap back along the centreline. This checks *both* ends of *every* covered
/// run, so it holds for the sweep's single travelling head and for grow's
/// several simultaneous ones, in either direction.
List<String> leadingEdgeViolations(Raster raster, Ring r, String label) {
  const int samples = 2880;
  final List<bool> raw = <bool>[
    for (var s = 0; s < samples; s++)
      raster.atPoint(r.at(r.track, s * 2 * math.pi / samples)).a == 255,
  ];
  // A cap tip is a single sub-pixel point on the centreline, so the last
  // sample or two there can flip either way. Runs shorter than this are
  // measurement noise, not geometry.
  const int noise = 3;
  final List<bool> covered = List<bool>.of(raw);
  for (var s = 0; s < samples; s++) {
    var run = 0;
    while (run < noise && covered[(s + run) % samples] == covered[s]) {
      run++;
    }
    if (run < noise) {
      for (var k = 0; k < run; k++) {
        covered[(s + k) % samples] = !covered[s];
      }
    }
  }

  final int count = covered.where((bool v) => v).length;
  // Nothing meaningful to measure before the first head exists, or once the
  // ring has closed and there are no free ends left.
  if (count < 200 || count > samples - 200) return const <String>[];

  // Every index where coverage changes is a free end of some segment.
  final List<(int, bool)> edges = <(int, bool)>[
    for (var s = 0; s < samples; s++)
      if (covered[s] != covered[(s - 1 + samples) % samples]) (s, covered[s]),
  ];
  final List<String> violations = <String>[];
  for (final (int index, bool startsCover) in edges) {
    // Skip an end that is about to merge with the next one: the two caps
    // overlap there and no single circle describes the boundary.
    final int gapToNeighbour = edges
        .map(((int, bool) e) => ((e.$1 - index).abs() % samples))
        .where((int d) => d > 0)
        .fold(samples, math.min);
    if (gapToNeighbour < 40) continue;

    final double edgeAngle = index * 2 * math.pi / samples;
    // The covered side lies at increasing angle when the run starts here.
    final double into = startsCover ? 1.0 : -1.0;
    final Offset capCentre = r.at(r.track, edgeAngle + into * r.capHalf);

    var measured = 0;
    for (var step = 0; step <= 12; step++) {
      final double radius =
          r.track - r.thickness * 0.3 + r.thickness * 0.6 * step / 12;
      for (var k = 0; k <= 260; k++) {
        final double angle = edgeAngle + into * (r.capHalf * 1.4) * (k / 260);
        final Offset p = r.at(radius, angle);
        if (raster.atPoint(p).a == 255) {
          final double d = (p - capCentre).distance;
          measured++;
          if ((d - r.cap).abs() > 3.0) {
            violations.add(
              '$label: edge at r=${radius.toStringAsFixed(1)} is '
              '${d.toStringAsFixed(2)} from its cap centre, not '
              '${r.cap.toStringAsFixed(2)}',
            );
          }
          break;
        }
      }
    }
    if (measured < 10) {
      violations.add('$label: an edge was measurable at only $measured radii');
    }
  }
  return violations;
}

/// The one visible edge on a segment that laps its own tail must be the head's
/// cap circle, and there must be no other. A sweep gradient that simply wraps
/// puts a straight radial line here instead, which is the shape this chart
/// promises never to show; checking only that *an* edge sits on the cap circle
/// is not enough, because a joint hairline sits there too and would mask it.
List<String> selfJointEdgeViolations(
  Raster raster,
  Ring r,
  double head,
  String label,
) {
  final List<String> violations = <String>[];
  const int radialSteps = 16;
  var measured = 0;
  var worstStray = 0;
  for (var step = 0; step <= radialSteps; step++) {
    final double radius =
        r.track - r.thickness * 0.35 + r.thickness * 0.70 * step / radialSteps;
    // Where the cap circle crosses this radius, from the cosine rule.
    final double cosDelta =
        (radius * radius + r.track * r.track - r.cap * r.cap) /
        (2 * radius * r.track);
    if (cosDelta.abs() > 1) continue;
    final double edgeAngle = head - r.dir * math.acos(cosDelta);

    // Sweep the whole joint, from behind the cap tip to past the lap's far end.
    const int n = 700;
    final double from = head - r.dir * r.capHalf * 1.8;
    final double span = r.capHalf * 1.8 + r.jointLag + r.capHalf * 1.8;
    var edgeJump = 0;
    var strayJump = 0;
    double strayAt = 0;
    Rgba? previous;
    for (var k = 0; k <= n; k++) {
      final double angle = from + r.dir * span * k / n;
      final Rgba pixel = raster.atPoint(r.at(radius, angle));
      if (pixel.a != 255) {
        previous = null;
        continue;
      }
      if (previous != null) {
        final int jump = channelDistance(previous, pixel);
        final double at = angle - r.dir * span / (2 * n);
        // Everything within a couple of pixels of the cap circle counts as the
        // joint edge itself; anything else is a second, unwanted edge.
        final bool onEdge = (at - edgeAngle).abs() * radius <= 3.0;
        if (onEdge) {
          edgeJump = math.max(edgeJump, jump);
        } else if (jump > strayJump) {
          strayJump = jump;
          strayAt = at;
        }
      }
      previous = pixel;
    }
    measured++;
    worstStray = math.max(worstStray, strayJump);
    if (edgeJump < 10) {
      violations.add(
        '$label: no edge on the cap circle at r=${radius.toStringAsFixed(1)} '
        '(largest step there $edgeJump)',
      );
    }
    if (strayJump > 12) {
      violations.add(
        '$label: a second edge away from the cap circle at '
        'r=${radius.toStringAsFixed(1)}, step $strayJump at angle '
        '${strayAt.toStringAsFixed(4)} (cap edge is at '
        '${edgeAngle.toStringAsFixed(4)}): this is a radial seam',
      );
    }
  }
  if (measured <= radialSteps) {
    violations.add(
      '$label: joint measurable at only $measured of ${radialSteps + 1} radii',
    );
  }
  return violations;
}

/// A border is a hairline on the silhouette. Every border pixel must therefore
/// have background within a stroke width or two of it. One that is walled in by
/// fill on all sides is a stroke drawn along a buried edge, which is what a
/// self-overlapping segment produces if its traced outline is stroked as traced.
List<String> buriedBorderViolations(
  Raster raster,
  Ring r,
  Color borderColor,
  String label,
) {
  final Rgba target = rgbaOf(borderColor);
  // The stroke is drawn at double width and clipped to the silhouette, so the
  // visible line is one width thick and hugs the edge from the inside.
  final double reach = r.thickness * 0.015 + 3.0;
  final List<String> violations = <String>[];
  for (var s = 0; s < 720; s++) {
    final double angle = s * 2 * math.pi / 720;
    for (var step = 0; step <= 30; step++) {
      final double radius = r.inner + r.thickness * step / 30;
      final Offset p = r.at(radius, angle);
      final Rgba pixel = raster.atPoint(p);
      if (pixel.a != 255) continue;
      if (channelDistance(pixel, target) > 40) continue;
      var seesBackground = false;
      for (var k = 0; k < 24 && !seesBackground; k++) {
        final double around = k * 2 * math.pi / 24;
        final Offset neighbour =
            p + Offset(math.cos(around), math.sin(around)) * reach;
        if (raster.atPoint(neighbour).a < 200) seesBackground = true;
      }
      if (!seesBackground) {
        violations.add(
          '$label: border pixel walled in by fill at '
          'angle=${angle.toStringAsFixed(4)} r=${radius.toStringAsFixed(1)} '
          '(a buried edge is being stroked)',
        );
        return violations;
      }
    }
  }
  return violations;
}
