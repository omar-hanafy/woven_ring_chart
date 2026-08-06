import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'enums.dart';
import 'palette.dart';
import 'snake.dart';

/// Everything about a ring that is not its data.
///
/// Every measurement here is a ratio, never a pixel count, so one style renders
/// correctly at any size. Fields with a `resolved` counterpart are clamped to
/// the range that still draws a woven ring; the raw value is kept as written so
/// a style survives a round trip through [copyWith].
@immutable
class WovenRingStyle {
  /// A ring at the reference proportions: a fifth of the diameter thick,
  /// joints half a band behind their boundaries, starting at 12 o'clock and
  /// running clockwise.
  const WovenRingStyle({
    this.bandFraction = 0.20,
    this.overlapFraction = 0.5,
    this.startAngle = -math.pi / 2,
    this.clockwise = true,
    this.gradientAxis = WovenGradientAxis.alongLength,
    this.gradientDirection = WovenGradientDirection.headToTail,
    this.lift,
    this.surface = WovenPalette.surface,
    this.minimumPolicy = WovenMinimumPolicy.enforce,
    this.singleSnakeStyle = WovenSingleSnakeStyle.smooth,
  });

  /// Band width as a fraction of the outer diameter. 20% by default.
  ///
  /// See [resolvedBandFraction] for the range actually used: below about 15%
  /// the caps stop reading as caps, and above about 25% the hole gets too
  /// small for a centre widget, so those are the values worth reaching for
  /// even though the clamp is wider.
  final double bandFraction;

  /// How far the joint sits behind its data boundary, in band widths.
  ///
  /// Half a band by default, which is where the reference puts it: the head's
  /// cap centre lands exactly half a band behind the boundary it belongs to.
  ///
  /// This changes the real head-over-tail coverage. It does not change the cap
  /// shape, which is always a half circle with radius half the band.
  final double overlapFraction;

  /// Where the first snake begins, in radians clockwise from three o'clock.
  /// The default, negative one quarter turn, is 12 o'clock.
  final double startAngle;

  /// Counter-clockwise is a mirror image, not a rotation. The heads flip too.
  final bool clockwise;

  /// Whether gradients run along each snake or across the band. One axis for
  /// the whole ring.
  final WovenGradientAxis gradientAxis;

  /// Which end of a [WovenFill] lands on the visible rounded end.
  final WovenGradientDirection gradientDirection;

  /// Optional, ring-level. Needs breathing room; the ring shrinks to make it.
  final WovenLift? lift;

  /// The surface the ring sits on. Also the best border colour.
  ///
  /// The component paints this colour behind translucent snakes and resolves
  /// uncoloured borders to it, so a ring on a dark background needs this set
  /// even though the ring never fills its own background.
  final Color surface;

  /// What happens to a value too small to draw as a snake.
  final WovenMinimumPolicy minimumPolicy;

  /// Whether a lone 100 percent value keeps a visible self-joint.
  final WovenSingleSnakeStyle singleSnakeStyle;

  /// [bandFraction] clamped to the 12 to 30 percent that still leaves a hole
  /// and still reads as a band, with a non-finite value falling back to 20
  /// percent.
  double get resolvedBandFraction =>
      bandFraction.isFinite ? bandFraction.clamp(0.12, 0.30) : 0.20;

  /// [overlapFraction] clamped to 25 to 100 percent of a band, with a
  /// non-finite value falling back to a half.
  double get resolvedOverlapFraction =>
      overlapFraction.isFinite ? overlapFraction.clamp(0.25, 1.0) : 0.50;

  /// [startAngle] with a non-finite value replaced by 12 o'clock. Angles are
  /// not wrapped, so any winding is preserved.
  double get resolvedStartAngle =>
      startAngle.isFinite ? startAngle : -math.pi / 2;

  /// A copy with the given fields replaced. Pass `removeLift` to drop the
  /// lift, since passing null means "keep what is there".
  WovenRingStyle copyWith({
    double? bandFraction,
    double? overlapFraction,
    double? startAngle,
    bool? clockwise,
    WovenGradientAxis? gradientAxis,
    WovenGradientDirection? gradientDirection,
    WovenLift? lift,
    bool removeLift = false,
    Color? surface,
    WovenMinimumPolicy? minimumPolicy,
    WovenSingleSnakeStyle? singleSnakeStyle,
  }) {
    return WovenRingStyle(
      bandFraction: bandFraction ?? this.bandFraction,
      overlapFraction: overlapFraction ?? this.overlapFraction,
      startAngle: startAngle ?? this.startAngle,
      clockwise: clockwise ?? this.clockwise,
      gradientAxis: gradientAxis ?? this.gradientAxis,
      gradientDirection: gradientDirection ?? this.gradientDirection,
      lift: removeLift ? null : (lift ?? this.lift),
      surface: surface ?? this.surface,
      minimumPolicy: minimumPolicy ?? this.minimumPolicy,
      singleSnakeStyle: singleSnakeStyle ?? this.singleSnakeStyle,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is WovenRingStyle &&
      other.bandFraction == bandFraction &&
      other.overlapFraction == overlapFraction &&
      other.startAngle == startAngle &&
      other.clockwise == clockwise &&
      other.gradientAxis == gradientAxis &&
      other.gradientDirection == gradientDirection &&
      other.lift == lift &&
      other.surface == surface &&
      other.minimumPolicy == minimumPolicy &&
      other.singleSnakeStyle == singleSnakeStyle;

  @override
  int get hashCode => Object.hash(
    bandFraction,
    overlapFraction,
    startAngle,
    clockwise,
    gradientAxis,
    gradientDirection,
    lift,
    surface,
    minimumPolicy,
    singleSnakeStyle,
  );
}
