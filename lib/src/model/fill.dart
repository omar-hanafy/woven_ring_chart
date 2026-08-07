import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// The interior of one segment: a flat colour, or a gradient between two.
///
/// A fill only names the two colours involved. Where those colours land on
/// screen is a chart-level decision: `WovenRingStyle.gradientAxis` chooses
/// whether the gradient runs along each segment or radially across the ring,
/// and `WovenRingStyle.gradientDirection` chooses which end of the fill sits on
/// the visible cap.
@immutable
class WovenFill {
  /// One flat colour from cap to cap.
  const WovenFill.solid(Color color) : head = color, tail = color;

  /// A gradient from [head], the end that stays visible, to [tail], the end
  /// that the next segment laps over.
  const WovenFill.gradient({required this.head, required this.tail});

  /// A restrained gradient derived from a single colour: the same hue, one
  /// step of HSL lightness either side of `base`.
  ///
  /// [step] is how far each end moves from `base`. It is clamped to the 0 to
  /// 0.2 that still reads as one colour rather than as two, and a non-finite
  /// step falls back to 0.05. If the result reads as a gradient instead of as
  /// shading, lower it.
  factory WovenFill.shaded(Color base, {double step = 0.05}) {
    final HSLColor hsl = HSLColor.fromColor(base);
    final double safeStep = step.isFinite ? step.abs().clamp(0.0, 0.20) : 0.05;
    return WovenFill.gradient(
      head: hsl
          .withLightness((hsl.lightness + safeStep).clamp(0.0, 1.0))
          .toColor(),
      tail: hsl
          .withLightness((hsl.lightness - safeStep).clamp(0.0, 1.0))
          .toColor(),
    );
  }

  /// The colour at the head cap: the rounded end that laps over the segment
  /// before it, and the end a reader's eye lands on.
  final Color head;

  /// The colour at the tail cap, which the following segment covers.
  final Color tail;

  /// Whether both ends carry the same colour, so no shader is needed.
  bool get isSolid => head == tail;

  /// The colour halfway between [head] and [tail].
  ///
  /// A solid segment placed next to a gradient one should match this rather
  /// than either end.
  Color get midtone => Color.lerp(head, tail, 0.5)!;

  /// Interpolates [a] and [b] at [t], blending both ends independently.
  ///
  /// A solid fill can therefore become a gradient one without a flash.
  static WovenFill lerp(WovenFill a, WovenFill b, double t) =>
      WovenFill.gradient(
        head: Color.lerp(a.head, b.head, t)!,
        tail: Color.lerp(a.tail, b.tail, t)!,
      );

  @override
  bool operator ==(Object other) =>
      other is WovenFill && other.head == head && other.tail == tail;

  @override
  int get hashCode => Object.hash(head, tail);
}
