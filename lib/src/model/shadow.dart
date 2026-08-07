import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// A soft, tight shadow cast by each segment head onto the segment beneath it.
///
/// This is a chart-level setting on `WovenRingStyle`, never a per-segment one,
/// so every head is lit the same way. If you notice it as a shadow it is twice
/// too strong.
///
/// The shadow falls backwards along the track from each head cap, is clipped
/// out of the ring's hole, and the ring shrinks by [reach] so the blur has room
/// outside the outer circle.
@immutable
class WovenShadow {
  /// A shadow at the reference strength: 12 percent black, blurred by a tenth
  /// of the ring's thickness and offset by a twentieth of it.
  const WovenShadow({
    this.color = const Color(0x1F000000),
    this.blurFraction = 0.10,
    this.offsetFraction = 0.05,
  });

  /// The shadow colour, alpha included.
  final Color color;

  /// Blur radius as a fraction of the ring's thickness.
  ///
  /// See [resolvedBlurFraction] for the range actually drawn.
  final double blurFraction;

  /// How far the shadow is pushed back along the track, as a fraction of the
  /// ring's thickness.
  ///
  /// See [resolvedOffsetFraction] for the range actually drawn.
  final double offsetFraction;

  /// [blurFraction] clamped to 0 to 0.3, with a non-finite value falling back
  /// to 0.10.
  double get resolvedBlurFraction =>
      blurFraction.isFinite ? blurFraction.clamp(0.0, 0.30) : 0.10;

  /// [offsetFraction] clamped to 0 to 0.2, with a non-finite value falling back
  /// to 0.05.
  double get resolvedOffsetFraction =>
      offsetFraction.isFinite ? offsetFraction.clamp(0.0, 0.20) : 0.05;

  /// How far outside the outer circle the blur needs to spread, in multiples
  /// of the ring's thickness.
  ///
  /// `WovenRingGeometry` insets the ring by this much, so a chart with a
  /// shadow still fits the box it was given.
  double get reach => resolvedBlurFraction * 3 + resolvedOffsetFraction;

  @override
  bool operator ==(Object other) =>
      other is WovenShadow &&
      other.color == color &&
      other.blurFraction == blurFraction &&
      other.offsetFraction == offsetFraction;

  @override
  int get hashCode => Object.hash(color, blurFraction, offsetFraction);
}
