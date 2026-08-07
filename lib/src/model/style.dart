import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'gradient.dart';
import 'palette.dart';
import 'policy.dart';
import 'shadow.dart';

/// Everything about a woven ring that is not its data.
///
/// Every measurement here is a fraction, never a pixel count, so one style
/// renders correctly at any size: a style that looks right at 120 logical
/// pixels still looks right at 600.
///
/// ```dart
/// const WovenRingStyle(
///   thicknessFraction: 0.20,
///   overlapFraction: 0.5,
///   clockwise: true,
/// )
/// ```
///
/// Fields with a `resolved` counterpart are clamped to the range that still
/// draws a woven ring. The raw value is kept exactly as written, so a style
/// survives a round trip through [copyWith].
@immutable
class WovenRingStyle {
  /// A ring at the reference proportions: a fifth of the diameter thick,
  /// joints half a ring-thickness behind their boundaries, starting at 12 o'clock
  /// and running clockwise.
  const WovenRingStyle({
    this.thicknessFraction = 0.20,
    this.overlapFraction = 0.5,
    this.startAngle = -math.pi / 2,
    this.clockwise = true,
    this.gradientAxis = WovenGradientAxis.alongSegment,
    this.gradientDirection = WovenGradientDirection.headToTail,
    this.shadow,
    this.surfaceColor = WovenPalette.surface,
    this.smallValuePolicy = WovenSmallValuePolicy.enforce,
    this.singleSegmentStyle = WovenSingleSegmentStyle.smooth,
  });

  /// Ring thickness as a fraction of the outer diameter. 20% by default.
  ///
  /// See [resolvedThicknessFraction] for the range actually drawn. Below about
  /// 15% the caps stop reading as caps, and above about 25% the hole gets too
  /// small for a centre widget, so those are the values worth reaching for even
  /// though the clamp is wider.
  final double thicknessFraction;

  /// How far a joint sits behind its data boundary, in multiples of the ring's
  /// thickness.
  ///
  /// Half a ring-thickness by default, which puts each head's cap centre exactly
  /// half a ring-thickness behind the boundary it belongs to. This changes how much
  /// of a segment its successor really covers; it never changes the cap shape,
  /// which is always a half circle of radius half the thickness.
  ///
  /// See [resolvedOverlapFraction] for the range actually drawn.
  final double overlapFraction;

  /// Where the first segment begins, in radians clockwise from three o'clock.
  ///
  /// The default, negative one quarter turn, is 12 o'clock. See
  /// [resolvedStartAngle].
  final double startAngle;

  /// Whether segments are laid down clockwise. True by default.
  ///
  /// Counter-clockwise is a mirror image rather than a rotation, so the heads
  /// flip too.
  final bool clockwise;

  /// Whether gradients run along each segment or radially across the ring.
  ///
  /// One axis for the whole chart.
  final WovenGradientAxis gradientAxis;

  /// Which end of a `WovenFill` lands on the visible rounded cap.
  final WovenGradientDirection gradientDirection;

  /// An optional shadow under every segment head, or null for none.
  ///
  /// A shadow needs breathing room outside the outer circle, and the ring
  /// shrinks within its box to make it.
  final WovenShadow? shadow;

  /// The colour of the surface the chart sits on. Also the best border colour.
  ///
  /// The chart paints this behind translucent segments and resolves uncoloured
  /// borders to it, so a ring on a dark background needs this set even though
  /// the chart never fills its own background.
  final Color surfaceColor;

  /// What happens to a value too small to draw as a segment.
  final WovenSmallValuePolicy smallValuePolicy;

  /// Whether a lone value covering the whole ring keeps a visible self-joint.
  final WovenSingleSegmentStyle singleSegmentStyle;

  /// [thicknessFraction] clamped to the 12 to 30 percent that still leaves a
  /// hole and still reads as a ring, with a non-finite value falling back to
  /// 0.20.
  double get resolvedThicknessFraction =>
      thicknessFraction.isFinite ? thicknessFraction.clamp(0.12, 0.30) : 0.20;

  /// [overlapFraction] clamped to 25 to 100 percent of the ring's thickness,
  /// with a non-finite value falling back to 0.5.
  double get resolvedOverlapFraction =>
      overlapFraction.isFinite ? overlapFraction.clamp(0.25, 1.0) : 0.50;

  /// [startAngle] with a non-finite value replaced by 12 o'clock.
  ///
  /// Angles are not wrapped, so any winding the caller wrote is preserved.
  double get resolvedStartAngle =>
      startAngle.isFinite ? startAngle : -math.pi / 2;

  /// A copy with the given fields replaced.
  ///
  /// Pass `removeShadow` to drop the shadow, since passing null means "keep
  /// what is there".
  WovenRingStyle copyWith({
    double? thicknessFraction,
    double? overlapFraction,
    double? startAngle,
    bool? clockwise,
    WovenGradientAxis? gradientAxis,
    WovenGradientDirection? gradientDirection,
    WovenShadow? shadow,
    bool removeShadow = false,
    Color? surfaceColor,
    WovenSmallValuePolicy? smallValuePolicy,
    WovenSingleSegmentStyle? singleSegmentStyle,
  }) {
    return WovenRingStyle(
      thicknessFraction: thicknessFraction ?? this.thicknessFraction,
      overlapFraction: overlapFraction ?? this.overlapFraction,
      startAngle: startAngle ?? this.startAngle,
      clockwise: clockwise ?? this.clockwise,
      gradientAxis: gradientAxis ?? this.gradientAxis,
      gradientDirection: gradientDirection ?? this.gradientDirection,
      shadow: removeShadow ? null : (shadow ?? this.shadow),
      surfaceColor: surfaceColor ?? this.surfaceColor,
      smallValuePolicy: smallValuePolicy ?? this.smallValuePolicy,
      singleSegmentStyle: singleSegmentStyle ?? this.singleSegmentStyle,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is WovenRingStyle &&
      other.thicknessFraction == thicknessFraction &&
      other.overlapFraction == overlapFraction &&
      other.startAngle == startAngle &&
      other.clockwise == clockwise &&
      other.gradientAxis == gradientAxis &&
      other.gradientDirection == gradientDirection &&
      other.shadow == shadow &&
      other.surfaceColor == surfaceColor &&
      other.smallValuePolicy == smallValuePolicy &&
      other.singleSegmentStyle == singleSegmentStyle;

  @override
  int get hashCode => Object.hash(
    thicknessFraction,
    overlapFraction,
    startAngle,
    clockwise,
    gradientAxis,
    gradientDirection,
    shadow,
    surfaceColor,
    smallValuePolicy,
    singleSegmentStyle,
  );
}
