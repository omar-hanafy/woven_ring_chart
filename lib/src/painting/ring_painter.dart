import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../geometry/ring_geometry.dart';
import '../geometry/segment_extent.dart';
import '../model/animation.dart';
import '../model/border.dart';
import '../model/chart_mode.dart';
import '../model/fill.dart';
import '../model/gradient.dart';
import '../model/palette.dart';
import '../model/policy.dart';
import '../model/segment.dart';
import '../model/shadow.dart';
import '../model/style.dart';

/// Draws one frame of a woven ring.
///
/// The painter is told exactly what to draw. It does not normalize data, run
/// the minimum policy, or own any animation: it is handed a segment list, the
/// fractions those segments occupy, and the progress values for the frame. That
/// is what lets a transition interpolate fractions directly instead of
/// re-running a nonlinear policy on every tick.
class WovenRingChartPainter extends CustomPainter {
  /// Creates a painter for one frame. The segment and fraction lists are copied,
  /// so a caller can keep mutating its own.
  WovenRingChartPainter({
    required List<WovenSegment> segments,
    required List<double> fractions,
    required this.style,
    required this.mode,
    required this.animation,
    required this.animationProgress,
    required this.spin,
    required this.highlightedIndex,
    required this.highlightBorder,
    required this.topologyMerge,
    required this.topologyAnchor,
  }) : segments = List<WovenSegment>.unmodifiable(segments),
       fractions = List<double>.unmodifiable(fractions);

  /// The segments to draw, in data order.
  final List<WovenSegment> segments;

  /// Each segment's share of the ring, parallel to [segments] and already through
  /// the minimum policy.
  final List<double> fractions;

  /// The ring's proportions and colours.
  final WovenRingStyle style;

  /// Which of the three renderings to produce.
  final WovenRingChartMode mode;

  /// Which animation [animationProgress] is driving.
  final WovenRingAnimation animation;

  /// Animation completion from 0 to 1, already eased.
  final double animationProgress;

  /// Phase of the loading sweep, from 0 to 1. Ignored outside
  /// [WovenRingChartMode.loading].
  final double spin;

  /// Index of the segment that takes [highlightBorder] instead of its own, or
  /// null.
  final int? highlightedIndex;

  /// The border given to the [highlightedIndex] segment.
  final WovenBorder highlightBorder;

  /// The canonical single ring's weight in the woven-to-single crossfade, from
  /// 0 to 1. Non-zero only while a one-to-many or many-to-one change is in
  /// flight.
  final double topologyMerge;

  /// The segment that owns the whole ring at either end of that handoff.
  final int? topologyAnchor;

  static const double _tau = math.pi * 2;

  // Keep painter arithmetic within one turn. At large finite angles, adding a
  // sweep or subtracting a joint lag can lose the entire shape. Reducing by a
  // rounded tau also loses the actual circular phase at those magnitudes:
  // sin/cos perform the precise argument reduction pointOn already relies on.
  // Ordinary angles keep their exact value; the public style keeps its winding.
  double get _startAngle {
    final double angle = style.resolvedStartAngle;
    return angle.abs() <= _tau
        ? angle
        : math.atan2(math.sin(angle), math.cos(angle));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final WovenRingGeometry g = WovenRingGeometry.forSize(size, style);
    if (g.outerRadius <= 0.0 || g.trackRadius <= 0.0) return;

    switch (mode) {
      case WovenRingChartMode.empty:
        canvas.drawPath(g.annulus(), Paint()..color = _emptyTrack);
        break;
      case WovenRingChartMode.loading:
        _paintLoading(canvas, g);
        break;
      case WovenRingChartMode.data:
        // Surface replacement owns the chart's pixels, not its ancestor's
        // canvas. A RepaintBoundary records drawing but does not isolate src
        // blending; keep transparent surfaces from erasing a parent backdrop.
        final bool replacesSurface = segments.any(_isTranslucent);
        if (replacesSurface) {
          canvas.saveLayer(Offset.zero & size, Paint());
        }
        _paintRing(canvas, g);
        if (replacesSurface) canvas.restore();
        break;
    }
  }

  // -- states ---------------------------------------------------------------

  /// The neutral at low opacity, premultiplied so the package does not depend
  /// on which Flutter version's colour API is available.
  static const Color _emptyTrack = Color(0x8CDBD8D1);
  static const Color _loadingTrack = Color(0x4DDBD8D1);

  void _paintLoading(Canvas canvas, WovenRingGeometry g) {
    canvas.drawPath(g.annulus(), Paint()..color = _loadingTrack);
    final double direction = style.clockwise ? 1.0 : -1.0;
    final double from = _startAngle + direction * spin * _tau;
    canvas.drawPath(
      g.segmentPath(
        from,
        from + direction * _tau * 0.20,
        clockwise: style.clockwise,
      ),
      Paint()..color = WovenPalette.neutral,
    );
  }

  void _paintRing(
    Canvas canvas,
    WovenRingGeometry g, {
    bool allowTopology = true,
    int? canonicalIndex,
  }) {
    final int n = segments.length;
    if (n == 0) {
      canvas.drawPath(g.annulus(), Paint()..color = _emptyTrack);
      return;
    }

    assert(fractions.length == n);
    final List<int> active = canonicalIndex == null
        ? <int>[
            for (var i = 0; i < n; i++)
              if (fractions[i] > 0) i,
          ]
        : <int>[canonicalIndex];
    if (active.isEmpty) {
      canvas.drawPath(g.annulus(), Paint()..color = _emptyTrack);
      return;
    }

    final double merge = topologyMerge.isFinite
        ? topologyMerge.clamp(0.0, 1.0)
        : 0.0;
    if (allowTopology &&
        active.length > 1 &&
        active.contains(topologyAnchor) &&
        merge > 0) {
      final Rect bounds = Rect.fromLTWH(0, 0, g.center.dx * 2, g.center.dy * 2);
      // Complementary byte weights sum to exactly one after raster
      // quantization, including partial borders shared by both results.
      final int canonicalAlpha = (merge * 255).round();
      // Crossfade complete premultiplied results, including the neutral track
      // and any empty-state fade. SrcOver or a shared underlay would count
      // translucent pixels twice. Surface replacement stays within each
      // render; the outer layer receives only the two weighted results.
      canvas.saveLayer(bounds, Paint());
      canvas.saveLayer(
        bounds,
        Paint()..color = Color.fromARGB(255 - canonicalAlpha, 255, 255, 255),
      );
      _paintRing(canvas, g, allowTopology: false);
      canvas.restore();
      canvas.saveLayer(
        bounds,
        Paint()
          ..blendMode = BlendMode.plus
          ..color = Color.fromARGB(canonicalAlpha, 255, 255, 255),
      );
      _paintRing(
        canvas,
        g,
        allowTopology: false,
        canonicalIndex: topologyAnchor,
      );
      canvas.restore();
      canvas.restore();
      return;
    }

    final double fractionTotal = fractions.fold<double>(
      0.0,
      (double total, double fraction) => total + fraction,
    );
    final bool fadesToEmpty = fractionTotal < 0.999;
    if (fadesToEmpty ||
        segments.any((WovenSegment segment) => segment.opacity < 0.999)) {
      canvas.drawPath(g.annulus(), Paint()..color = _emptyTrack);
    }
    if (fadesToEmpty) {
      // A shrinking segment still has a full round cap at an arbitrarily small
      // fraction. Fade the complete woven layer with its remaining coverage so
      // those final subpixel caps dissolve into the neutral empty track rather
      // than popping away on the last frame.
      canvas.saveLayer(
        Rect.fromLTWH(0, 0, g.center.dx * 2, g.center.dy * 2),
        Paint()
          ..color = _withOpacity(
            const Color(0xFFFFFFFF),
            fractionTotal.clamp(0.0, 1.0),
          ),
      );
    }

    final List<WovenSegmentExtent> extents = g.extents(
      fractions,
      _startAngle,
      clockwise: style.clockwise,
    );
    final double direction = style.clockwise ? 1.0 : -1.0;

    // The sweep: one head, one turn, colours handing over at each boundary.
    double tip = 0.0;
    if (animation == WovenRingAnimation.sweep) {
      tip =
          extents.first.start +
          direction * (g.capAngle + animationProgress * _tau);
    }

    if (active.length == 1) {
      final int index = active.single;
      final double head = extents[index].start;
      final double fullEnd = head + direction * _tau;
      final double visibleEnd = _visibleEnd(
        g,
        head,
        fullEnd,
        0,
        1,
        tip,
        clockwise: style.clockwise,
      );
      if (!visibleEnd.isNaN) {
        _paintSmoothSingle(canvas, g, index, head, visibleEnd: visibleEnd);
        if (style.singleSegmentStyle == WovenSingleSegmentStyle.jointed) {
          canvas.save();
          if ((visibleEnd - head).abs() < _tau - 1e-9) {
            canvas.clipPath(
              g.segmentPath(head, visibleEnd, clockwise: style.clockwise),
            );
          }
          _paintSingleJoint(canvas, g, head, segments[index].opacity);
          canvas.restore();
        }
      }
      if (fadesToEmpty) canvas.restore();
      return;
    }

    // A direct one-to-many interpolation briefly leaves the surviving segment
    // at or above one full turn while the new heads are being born. Crossfade
    // that topological handoff from the exact one-segment rendering to the woven
    // rendering across the overlap-depth interval. This keeps gradients,
    // borders, shadow, and the single self-joint continuous without changing the
    // logical fractions or their endpoint proportions.
    final int anchorPosition = topologyAnchor == null
        ? -1
        : active.indexOf(topologyAnchor!);
    final int? cycleAnchorPosition = anchorPosition < 0 ? null : anchorPosition;
    // Keep one stable data-order sequence through the entire animation and every
    // transition. A base fill guarantees antialiased coverage. Exact cyclic
    // owner masks then repaint each visible segment everywhere its successor is
    // absent. In any contiguous overlap run that leaves only the furthest
    // successor visible, so both possible three-way seam overlaps obey the
    // same successor > current > predecessor rule.
    final List<int> paintOrder = active;
    final List<double> visibleEnds = <double>[
      for (var position = 0; position < paintOrder.length; position++)
        _visibleEnd(
          g,
          extents[paintOrder[position]].start,
          extents[paintOrder[position]].end,
          position,
          paintOrder.length,
          tip,
          clockwise: style.clockwise,
        ),
    ];
    final List<Path?> visiblePaths = <Path?>[
      for (var position = 0; position < paintOrder.length; position++)
        visibleEnds[position].isNaN
            ? null
            : g.segmentPath(
                extents[paintOrder[position]].start,
                visibleEnds[position],
                clockwise: style.clockwise,
              ),
    ];
    final List<Path?> outsidePaths = <Path?>[
      for (var position = 0; position < paintOrder.length; position++)
        if (visiblePaths[position] == null)
          null
        else
          _outsidePath(
            g,
            _simplified(
              g,
              visiblePaths[position]!,
              extents[paintOrder[position]].start,
              visibleEnds[position],
            ),
          ),
    ];
    // One overlap depth of each segment's own body, measured from its head. This
    // is the ground a head takes from its predecessor, and it is the part of
    // the weave the successor mask cannot state on its own. That mask says
    // "paint me where my successor is absent", which has no answer when a pixel
    // is covered by the whole cycle at once: three segments closing around a
    // short one, or two whose joints have merged. Every segment is then excluded
    // by its own successor, nothing is painted, and whatever the underlay left
    // there shows through.
    final List<double> lapSpans = <double>[
      for (var position = 0; position < paintOrder.length; position++)
        math.min(
          g.jointLag,
          direction *
              (visibleEnds[position] - extents[paintOrder[position]].start),
        ),
    ];
    final List<Path?> laps = <Path?>[
      for (var position = 0; position < paintOrder.length; position++)
        visiblePaths[position] == null
            ? null
            : g.segmentPath(
                extents[paintOrder[position]].start,
                extents[paintOrder[position]].start +
                    direction * lapSpans[position],
                clockwise: style.clockwise,
              ),
    ];

    final List<Path?> outsideLaps = <Path?>[
      for (final Path? lap in laps) lap == null ? null : _outsidePath(g, lap),
    ];

    // Coverage underlay. Borders and shadow are deliberately omitted: covered
    // tails have neither, even while their successor is translucent.
    for (var position = 0; position < paintOrder.length; position++) {
      final int i = paintOrder[position];
      final double end = visibleEnds[position];
      if (end.isNaN) continue;
      _paintSegment(
        canvas,
        g,
        i,
        extents[i].start,
        end,
        shaderEnd: extents[i].end,
        paintShadow: false,
        paintBorder: false,
      );
    }

    // Paint each top owner. The masks are independent of paint order, so sweep
    // completion and data transitions cannot swap the seam on the final frame.
    for (var position = 0; position < paintOrder.length; position++) {
      final Path? path = visiblePaths[position];
      if (path == null) continue;
      final int i = paintOrder[position];
      final int successorPosition = (position + 1) % paintOrder.length;
      final Path? outsideSuccessor = outsidePaths[successorPosition];
      canvas.save();
      canvas.clipPath(path, doAntiAlias: false);
      if (outsideSuccessor != null) {
        canvas.clipPath(outsideSuccessor, doAntiAlias: false);
      }
      if (_isTranslucent(segments[i])) {
        _paintSurface(canvas, path);
      }
      _paintSegment(
        canvas,
        g,
        i,
        extents[i].start,
        visibleEnds[position],
        shaderEnd: extents[i].end,
        paintShadow: false,
        paintBorder: false,
      );
      canvas.restore();
    }

    // When every active path covers the same pixel, cyclic pairwise ordering
    // has no mathematical winner. This occurs only during the saturated
    // one-to-many handoff. Keep the surviving full-turn segment as an explicit
    // cycle anchor instead of exposing whichever underlay index painted last.
    final bool anchorIsSaturated =
        cycleAnchorPosition != null &&
        (extents[paintOrder[cycleAnchorPosition]].end -
                    extents[paintOrder[cycleAnchorPosition]].start)
                .abs() >=
            _tau - 1e-9;
    if (anchorIsSaturated &&
        paintOrder.length >= 3 &&
        visiblePaths.every((Path? path) => path != null)) {
      final int anchorPosition = cycleAnchorPosition;
      final int anchor = paintOrder[anchorPosition];
      final Path anchorPath = visiblePaths[anchorPosition]!;
      canvas.save();
      for (final Path? path in visiblePaths) {
        canvas.clipPath(path!, doAntiAlias: false);
      }
      if (_isTranslucent(segments[anchor])) {
        _paintSurface(canvas, anchorPath);
      }
      _paintSegment(
        canvas,
        g,
        anchor,
        extents[anchor].start,
        visibleEnds[anchorPosition],
        shaderEnd: extents[anchor].end,
        paintShadow: false,
        paintBorder: false,
      );
      canvas.restore();
    }

    // Every head takes its visible lap, except where a later cyclic head
    // already owns that ground. Apply the same rule to every index: a linear
    // paint order plus a first-head repair cannot resolve dense overlap runs
    // that cross the seam and continue beyond the first head.
    // Only the revealed part participates, so an emerging head cannot mask
    // another segment with the portion of its lap that has not appeared yet.
    final double lapReach = g.jointLag + 2 * g.capAngularExtent;
    final List<List<int>> lapMasks = <List<int>>[
      for (var position = 0; position < paintOrder.length; position++) <int>[],
    ];
    for (var position = 0; position < paintOrder.length; position++) {
      if (laps[position] == null) continue;
      final List<int> masks = lapMasks[position];
      double coveredEnd = double.negativeInfinity;
      for (var step = 1; step < paintOrder.length; step++) {
        final int other = (position + step) % paintOrder.length;
        final double ahead = _forward(
          extents[paintOrder[other]].boundaryStart -
              extents[paintOrder[position]].boundaryStart,
          direction,
        );
        if (ahead >= lapReach) break;
        if (ahead <= 0 || outsideLaps[other] == null) continue;
        final double end = ahead + lapSpans[other];
        // Successive starts increase. A lap ending inside a retained arc is
        // contained in that arc's constant-radius capsule as well.
        if (end <= coveredEnd) continue;
        masks.add(other);
        coveredEnd = end;
        // Any point shared by this lap and a farther one must also cross the
        // intervening arc once that arc reaches this lap's endpoint. The
        // allowed widths keep the whole candidate interval below one turn.
        if (coveredEnd >= lapSpans[position]) break;
      }
      // Preserve the original order among retained clips, including the seam.
      masks.sort();
    }
    void paintLaps({required bool fill}) {
      for (var position = 0; position < paintOrder.length; position++) {
        final Path? path = visiblePaths[position];
        final Path? lap = laps[position];
        if (path == null || lap == null) continue;
        final int i = paintOrder[position];
        canvas.save();
        canvas.clipPath(path, doAntiAlias: false);
        canvas.clipPath(lap, doAntiAlias: false);
        for (final int other in lapMasks[position]) {
          canvas.clipPath(outsideLaps[other]!, doAntiAlias: false);
        }
        if (!fill) canvas.drawPaint(Paint()..blendMode = BlendMode.clear);
        if (fill && _isTranslucent(segments[i])) _paintSurface(canvas, path);
        _paintSegment(
          canvas,
          g,
          i,
          extents[i].start,
          visibleEnds[position],
          shaderEnd: extents[i].end,
          paintShadow: false,
          paintFill: fill,
          paintBorder: !fill,
        );
        canvas.restore();
      }
    }

    paintLaps(fill: true);

    // A shadow is visible only on the predecessor and only where neither the
    // segment casting it nor its successor covers it. This keeps shadows out of
    // the hole and prevents a covered head from leaking through a later one.
    if (style.shadow != null) {
      final Path outsideRing = _outsidePath(g, g.annulus());
      for (var position = 0; position < paintOrder.length; position++) {
        final Path? path = visiblePaths[position];
        final Path? predecessor =
            visiblePaths[(position - 1 + paintOrder.length) %
                paintOrder.length];
        if (path == null || predecessor == null) continue;
        final Path? outsideCurrent = outsidePaths[position];
        final Path? outsideSuccessor =
            outsidePaths[(position + 1) % paintOrder.length];
        final int i = paintOrder[position];
        final double opacity = segments[i].opacity.isFinite
            ? segments[i].opacity.clamp(0.0, 1.0)
            : 1.0;
        final Path receiver = Path.combine(
          PathOperation.union,
          predecessor,
          outsideRing,
        );
        canvas.save();
        // The tight shadow lands on the predecessor inside the ring and may
        // breathe just beyond the outer circle. _paintShadow applies the hole
        // mask afterwards, so the exterior allowance can never leak inward.
        canvas.clipPath(receiver, doAntiAlias: false);
        if (outsideCurrent != null) {
          canvas.clipPath(outsideCurrent, doAntiAlias: false);
        }
        if (paintOrder.length != 2 && outsideSuccessor != null) {
          canvas.clipPath(outsideSuccessor, doAntiAlias: false);
        }
        _paintShadow(canvas, g, extents[i].start, opacity);
        canvas.restore();
      }
    }

    // Borders are a property of the visible owner, never of a covered tail.
    // Resolve all ownership passes on a transparent border layer, replacing
    // each owned region before drawing its line. A head can belong to both a
    // body mask and a lap, but its requested
    // opacity must blend over the fill only once. Clearing the whole region
    // also removes a predecessor's line when a borderless head takes it.
    if (active.any((int i) => _borderFor(i) != null)) {
      canvas.saveLayer(
        Rect.fromLTWH(0, 0, g.center.dx * 2, g.center.dy * 2),
        Paint(),
      );
      for (var position = 0; position < paintOrder.length; position++) {
        final Path? path = visiblePaths[position];
        if (path == null) continue;
        final int i = paintOrder[position];
        final Path? outsideSuccessor =
            outsidePaths[(position + 1) % paintOrder.length];
        canvas.save();
        canvas.clipPath(path, doAntiAlias: false);
        if (outsideSuccessor != null) {
          canvas.clipPath(outsideSuccessor, doAntiAlias: false);
        }
        canvas.drawPaint(Paint()..blendMode = BlendMode.clear);
        _paintSegment(
          canvas,
          g,
          i,
          extents[i].start,
          visibleEnds[position],
          shaderEnd: extents[i].end,
          paintShadow: false,
          paintFill: false,
        );
        canvas.restore();
      }

      paintLaps(fill: false);
      canvas.restore();
    }

    if (fadesToEmpty) canvas.restore();
  }

  Path _outsidePath(WovenRingGeometry g, Path path) => Path()
    ..fillType = PathFillType.evenOdd
    ..addRect(Rect.fromLTWH(0, 0, g.center.dx * 2, g.center.dy * 2))
    ..addPath(path, Offset.zero);

  /// Where segment [i] currently ends, or NaN while it is not yet born.
  double _visibleEnd(
    WovenRingGeometry g,
    double a,
    double b,
    int i,
    int n,
    double tip, {
    required bool clockwise,
  }) {
    if (animation == WovenRingAnimation.none || animationProgress >= 1) {
      return b;
    }
    if (animation == WovenRingAnimation.sweep) {
      // The tip is the leading edge of the growing segment. A new segment is born
      // the instant the tip arrives, as a full round head lying on top of the
      // one before it. This is why the head never looks cut off.
      final double direction = clockwise ? 1.0 : -1.0;
      final double endAlong = math.min(
        direction * b,
        direction * tip - g.capAngle,
      );
      return endAlong < direction * a ? double.nan : direction * endAlong;
    }
    // Grow: each segment opens from its own start, staggered by index.
    final double stagger = n <= 1 ? 0.0 : 0.35 / n;
    final double span = 1 - stagger * (n - 1);
    final double p =
        ((animationProgress - stagger * i) / (span <= 0 ? 1 : span)).clamp(
          0.0,
          1.0,
        );
    if (p <= 0) return double.nan;
    return a + (b - a) * p;
  }

  // -- one segment ------------------------------------------------------------

  /// A segment that owns the whole ring. [head] is its drawn start, the same
  /// angle every other segment's head cap is centred on.
  void _paintSmoothSingle(
    Canvas canvas,
    WovenRingGeometry g,
    int index,
    double head, {
    double? visibleEnd,
  }) {
    final WovenSegment segment = segments[index];
    final double opacity = segment.opacity.isFinite
        ? segment.opacity.clamp(0.0, 1.0)
        : 1.0;
    final double direction = style.clockwise ? 1.0 : -1.0;
    final double end = visibleEnd ?? head + direction * _tau;
    final Path ring = g.segmentPath(head, end, clockwise: style.clockwise);
    if (opacity <= 0.0) {
      // A positive-value segment still owns its surface when its fill reaches
      // zero alpha, exactly as it does throughout the opacity transition.
      _paintSurface(canvas, ring);
      return;
    }
    if (style.shadow != null && (end - head).abs() < _tau - 1e-9) {
      // The returning tail buries the head's exposed caster as the ring
      // closes. Subtract that actual geometry before blurring, so its shadow
      // disappears continuously instead of switching off on the final frame.
      final double contact = 2 * g.capAngularExtent;
      _paintShadow(
        canvas,
        g,
        head,
        opacity,
        occluder: _tau - (end - head).abs() < contact
            ? (Path()..addOval(
                Rect.fromCircle(
                  center: g.pointOn(g.trackRadius, end),
                  radius: g.capRadius,
                ),
              ))
            : null,
      );
    }
    final Paint fill = Paint()..isAntiAlias = true;
    // A sweep that has to close on itself wraps somewhere, and the wrap is a
    // straight radial line: the one edge shape this chart promises never to
    // show. Put the wrap exactly on the head's cap centre so the head's own lap
    // can bury it, the same way a successor's head buries its predecessor's
    // tail at every other joint.
    final Shader? shader = _closedShaderFor(g, segment.fill, head, opacity);
    if (shader == null) {
      fill.color = _withOpacity(segment.fill.head, opacity);
    } else {
      fill.shader = shader;
    }
    final bool translucent = _isTranslucent(segment);
    final bool composeLap =
        translucent &&
        !segment.fill.isSolid &&
        style.gradientAxis == WovenGradientAxis.alongSegment;
    if (translucent) _paintSurface(canvas, ring);
    if (composeLap) {
      // Compose the wrap and its lap as one translucent fill, then blend that
      // fill once over the surface. Replacing the lap inside this layer also
      // keeps its antialiased interior edge at the same effective opacity.
      canvas.saveLayer(
        Rect.fromLTWH(0, 0, g.center.dx * 2, g.center.dy * 2),
        Paint(),
      );
    }
    canvas.drawPath(ring, fill);

    // The lap: one overlap depth of the segment's own body, carrying the head end
    // of its gradient. Its backward cap is the true semicircle the joint reads
    // as, and it covers the wrap entirely because the wrap sits at its centre.
    if (!segment.fill.isSolid &&
        style.gradientAxis == WovenGradientAxis.alongSegment) {
      // Anchored one cap back, so the lap carries the head end of the gradient
      // right out to the cap tip. A sweep wider than a full turn cannot be
      // anchored at all here: past one turn its angles alias, which silently
      // hands the counter-clockwise lap the tail colour instead of the head.
      final Shader? lap = _closedShaderFor(
        g,
        segment.fill,
        head - direction * g.capAngularExtent,
        opacity,
      );
      if (lap != null) {
        canvas.save();
        if ((end - head).abs() < _tau - 1e-9) {
          canvas.clipPath(ring, doAntiAlias: false);
        }
        canvas.drawPath(
          g.segmentPath(
            head,
            head + direction * g.jointLag,
            clockwise: style.clockwise,
          ),
          Paint()
            ..shader = lap
            ..blendMode = composeLap ? BlendMode.src : BlendMode.srcOver
            ..isAntiAlias = true,
        );
        canvas.restore();
      }
    }
    if (composeLap) canvas.restore();

    final WovenBorder? border = _borderFor(index);
    if (border == null) return;
    canvas.save();
    canvas.clipPath(ring);
    canvas.drawPath(
      _simplified(g, ring, head, end),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = border.resolvedWidthFraction * g.thickness * 2
        ..color = _withOpacity(
          border.resolve(segment.fill, style.surfaceColor),
          opacity * border.resolvedOpacity,
        )
        ..isAntiAlias = true,
    );
    canvas.restore();
  }

  void _paintSingleJoint(
    Canvas canvas,
    WovenRingGeometry g,
    double headAngle,
    double requestedOpacity,
  ) {
    final double opacity = requestedOpacity.isFinite
        ? requestedOpacity.clamp(0.0, 1.0)
        : 1.0;
    if (opacity <= 0.0) return;
    final double direction = style.clockwise ? 1.0 : -1.0;
    final Rect cap = Rect.fromCircle(
      center: g.pointOn(g.trackRadius, headAngle),
      radius: g.capRadius,
    );
    // The joint runs cap tip to cap tip, so both its ends land exactly on the
    // silhouette. A stroke is centred on its path, which puts half its width
    // past the ring's edge at each end: clip it, the same way a border is
    // clipped, so the mark reads as an edge belonging to the ring instead of a
    // whisker laid over it. Butt ends for the same reason - a round cap would
    // bulge along the ring's edge where the clip cannot reach it.
    canvas.save();
    canvas.clipPath(g.annulus());
    canvas.drawArc(
      cap,
      headAngle + math.pi,
      direction * math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.5, g.thickness * 0.012)
        ..color = _withOpacity(style.surfaceColor, opacity * 0.85)
        ..isAntiAlias = true,
    );
    canvas.restore();
  }

  void _paintSegment(
    Canvas canvas,
    WovenRingGeometry g,
    int i,
    double a,
    double b, {
    required double shaderEnd,
    bool paintShadow = true,
    bool paintFill = true,
    bool paintBorder = true,
    bool composeSurface = false,
  }) {
    final WovenSegment segment = segments[i];
    final double opacity = segment.opacity.isFinite
        ? segment.opacity.clamp(0.0, 1.0)
        : 1.0;
    if (opacity <= 0.0) {
      if (paintFill && composeSurface) {
        _paintSurface(canvas, g.segmentPath(a, b, clockwise: style.clockwise));
      }
      return;
    }
    final Path path = g.segmentPath(a, b, clockwise: style.clockwise);

    if (paintShadow && style.shadow != null) {
      _paintShadow(canvas, g, a, opacity);
    }

    if (paintFill) {
      if (composeSurface && _isTranslucent(segment)) {
        _paintSurface(canvas, path);
      }
      final Paint fill = Paint()..isAntiAlias = true;
      // Saturating the silhouette to an annulus must not relocate its head
      // or change the cap-to-cap gradient slope.
      final Shader? shader = _shaderFor(g, segment.fill, a, shaderEnd, opacity);
      if (shader != null) {
        fill.shader = shader;
      } else {
        fill.color = _withOpacity(segment.fill.head, opacity);
      }
      canvas.drawPath(path, fill);
    }

    final WovenBorder? border = paintBorder ? _borderFor(i) : null;
    if (border == null) return;

    // Stroked at double width and clipped to the silhouette, so the line lands
    // entirely inside the segment. A bordered segment is never fatter than its
    // neighbours, and the ring's outer edge stays a perfect circle.
    final double width = border.resolvedWidthFraction * g.thickness;
    canvas.save();
    canvas.clipPath(path);
    canvas.drawPath(
      _simplified(g, path, a, b),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width * 2
        ..color = _withOpacity(
          border.resolve(segment.fill, style.surfaceColor),
          opacity * border.resolvedOpacity,
        )
        ..isAntiAlias = true,
    );
    canvas.restore();
  }

  /// A segment path with any self-intersection resolved into a plain boundary.
  ///
  /// A segment long enough to catch its own tail overlaps itself, and the path is
  /// still *traced* through both caps even though only their outer halves are
  /// on the silhouette. That costs twice:
  ///
  ///   * stroking it as traced draws the two buried halves as a circle
  ///     floating inside the ring, which pops away the moment the ring closes;
  ///   * the doubly wound lens has an even crossing count, so an even-odd
  ///     complement reads it as *outside* the segment and punches a hole in the
  ///     exclusion mask, letting a neighbour paint over this segment's head.
  ///     That second one is defensive: no case in the catalog can currently
  ///     see it, because the lens sits inside the segment's own head lap and the
  ///     lap pass repaints it either way. It is kept because relying on one
  ///     pass to cover another pass's wrong mask is how the two-segment seam
  ///     stayed broken for so long.
  ///
  /// Unioning with nothing collapses the winding, so what remains is the
  /// boundary of the filled region and nothing else.
  ///
  /// The caps first touch when their centres are one cap diameter apart, and
  /// the centres are a chord `2 * track * sin(gap / 2)` apart, so contact
  /// begins at a gap of exactly `2 * asin(cap / track)`. Short of that a segment
  /// cannot overlap itself and the path is returned untouched.
  Path _simplified(WovenRingGeometry g, Path path, double a, double b) {
    final double gap = _tau - (b - a).abs();
    if (gap <= 0 || gap >= 2 * g.capAngularExtent) return path;
    return Path.combine(PathOperation.union, path, Path());
  }

  bool _isTranslucent(WovenSegment segment) {
    final double opacity = segment.opacity.isFinite
        ? segment.opacity.clamp(0.0, 1.0)
        : 1.0;
    return opacity < 0.999 ||
        segment.fill.head.a < 0.999 ||
        segment.fill.tail.a < 0.999;
  }

  void _paintSurface(Canvas canvas, Path path) {
    canvas.drawPath(
      path,
      Paint()
        ..color = style.surfaceColor
        ..blendMode = BlendMode.src
        ..isAntiAlias = true,
    );
  }

  void _paintShadow(
    Canvas canvas,
    WovenRingGeometry g,
    double headAngle,
    double opacity, {
    Path? occluder,
  }) {
    final WovenShadow shadow = style.shadow!;
    final double blur = shadow.resolvedBlurFraction * g.thickness;
    final double offset = shadow.resolvedOffsetFraction * g.thickness;
    // Backwards along the tangent at the head, so the shadow falls behind the
    // cap and onto the segment underneath it.
    final Offset back =
        Offset(math.sin(headAngle), -math.cos(headAngle)) *
        (style.clockwise ? 1.0 : -1.0) *
        offset;
    final Path head = Path()
      ..addOval(
        Rect.fromCircle(
          center: g.pointOn(g.trackRadius, headAngle),
          radius: g.capRadius,
        ),
      );
    canvas.save();
    canvas.clipPath(g.holeMask());
    canvas.drawPath(
      (occluder == null
              ? head
              : Path.combine(PathOperation.difference, head, occluder))
          .shift(back),
      Paint()
        ..color = _withOpacity(shadow.color, opacity)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur),
    );
    canvas.restore();
  }

  WovenBorder? _borderFor(int i) {
    if (i == highlightedIndex) return highlightBorder;
    return segments[i].border;
  }

  /// The along-segment gradient for a segment that closes on itself, wrapping
  /// exactly at [head] so the head's lap can hide the seam. Across-thickness
  /// gradients are radial and have no seam, so they are returned unchanged.
  Shader? _closedShaderFor(
    WovenRingGeometry g,
    WovenFill fill,
    double head,
    double opacity,
  ) {
    if (fill.isSolid) return null;
    if (style.gradientAxis == WovenGradientAxis.acrossThickness) {
      final double direction = style.clockwise ? 1.0 : -1.0;
      return _shaderFor(g, fill, head, head + direction * _tau, opacity);
    }
    final bool headFirst =
        style.gradientDirection == WovenGradientDirection.headToTail;
    List<Color> colors = headFirst
        ? <Color>[fill.head, fill.tail]
        : <Color>[fill.tail, fill.head];
    colors = <Color>[
      for (final Color color in colors) _withOpacity(color, opacity),
    ];
    // Counter-clockwise runs against increasing polar angle, so the stops are
    // laid down in the opposite order and the wrap still lands on [head].
    if (!style.clockwise) colors = colors.reversed.toList(growable: false);
    return SweepGradient(
      startAngle: 0,
      endAngle: _tau,
      colors: colors,
      tileMode: TileMode.clamp,
      transform: GradientRotation(head),
    ).createShader(Rect.fromCircle(center: g.center, radius: g.outerRadius));
  }

  Shader? _shaderFor(
    WovenRingGeometry g,
    WovenFill fill,
    double a,
    double b,
    double opacity,
  ) {
    if (fill.isSolid) return null;
    final Rect box = Rect.fromCircle(center: g.center, radius: g.outerRadius);
    final bool headFirst =
        style.gradientDirection == WovenGradientDirection.headToTail;
    List<Color> colors = headFirst
        ? <Color>[fill.head, fill.tail]
        : <Color>[fill.tail, fill.head];
    colors = <Color>[
      for (final Color color in colors) _withOpacity(color, opacity),
    ];

    if (style.gradientAxis == WovenGradientAxis.acrossThickness) {
      // A tube: lighter on the outer edge. Ring-wide by nature, which is why
      // the axis is a ring-level choice and never mixed between segments.
      final List<Color> acrossColors = headFirst
          ? <Color>[fill.tail, fill.head]
          : <Color>[fill.head, fill.tail];
      return RadialGradient(
        radius: 0.5,
        colors: <Color>[
          for (final Color color in acrossColors) _withOpacity(color, opacity),
        ],
        stops: <double>[g.innerRadius / g.outerRadius, 1.0],
        tileMode: TileMode.clamp,
      ).createShader(box);
    }
    // Along the length, cap tip to cap tip, so the rounded ends are shaded too
    // because a flat cap on a gradient segment reads as a chip in the paint. The
    // gradient belongs to the segment: it restarts at every one of them.
    final double direction = style.clockwise ? 1.0 : -1.0;
    final double head = a - direction * g.capAngularExtent;
    final double tail = b + direction * g.capAngularExtent;
    return SweepGradient(
      startAngle: 0,
      endAngle: math.max(direction * (tail - head), 1e-4),
      colors: colors,
      tileMode: TileMode.clamp,
      // Both directions start at the head. Anchoring a reversed CCW sweep
      // at the tail aliases the head to the tail color when overlap plus caps
      // exceeds one turn. Reflecting the shader preserves the full span and
      // slope while keeping the visible head interval before the polar wrap.
      transform: style.clockwise
          ? GradientRotation(head)
          : _CounterClockwiseSweep(head),
    ).createShader(box);
  }

  /// How far [delta] is ahead in the drawing direction, in [0, tau).
  static double _forward(double delta, double direction) {
    final double ahead = (direction * delta) % _tau;
    return ahead < 0 ? ahead + _tau : ahead;
  }

  static Color _withOpacity(Color color, double opacity) =>
      color.withValues(alpha: color.a * opacity);

  @override
  bool shouldRepaint(WovenRingChartPainter old) =>
      old.mode != mode ||
      old.animation != animation ||
      old.animationProgress != animationProgress ||
      old.spin != spin ||
      old.highlightedIndex != highlightedIndex ||
      old.highlightBorder != highlightBorder ||
      old.topologyMerge != topologyMerge ||
      old.topologyAnchor != topologyAnchor ||
      old.style != style ||
      !listEquals(old.fractions, fractions) ||
      !listEquals(old.segments, segments);
}

/// Maps the shader's increasing angle to a counter-clockwise angle from [head].
/// Only the shader is reflected; the segment silhouette and ownership stay put.
class _CounterClockwiseSweep extends GradientTransform {
  const _CounterClockwiseSweep(this.head);

  final double head;

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) {
    final double cosine = math.cos(head);
    final double sine = math.sin(head);
    final Offset center = bounds.center;
    // Translate to the center, reflect y, rotate to the head, then translate
    // back. The explicit matrix keeps the reflection centered on this ring.
    return Matrix4.identity()
      ..setEntry(0, 0, cosine)
      ..setEntry(0, 1, sine)
      ..setEntry(1, 0, sine)
      ..setEntry(1, 1, -cosine)
      ..setEntry(0, 3, center.dx - cosine * center.dx - sine * center.dy)
      ..setEntry(1, 3, center.dy - sine * center.dx + cosine * center.dy);
  }
}
