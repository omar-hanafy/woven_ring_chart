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
