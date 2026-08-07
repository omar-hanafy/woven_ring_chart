import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'border.dart';
import 'fill.dart';
import 'palette.dart';

/// One coloured piece of a woven ring.
///
/// A segment is a constant-width bar with semicircular ends, bent along the
/// ring, drawn over the segment before it. Segments are laid out in the order
/// they are given: the chart never sorts or rebalances them.
@immutable
class WovenSegment {
  /// A segment worth [value], painted with [fill].
  const WovenSegment({
    required this.value,
    required this.fill,
    this.border,
    this.semanticLabel,
    this.opacity = 1.0,
  });

  /// A segment worth [value] in one flat colour.
  ///
  /// Not a `const` constructor, because it builds its [fill] from [color]. Use
  /// the primary constructor with `WovenFill.solid` for a `const` list.
  WovenSegment.solid(
    this.value,
    Color color, {
    this.border,
    this.semanticLabel,
    this.opacity = 1.0,
  }) : fill = WovenFill.solid(color);

  /// This segment's share of the ring, in whatever unit the caller likes.
  ///
  /// Values are normalized against each other, so percentages, counts, and
  /// currency all work. Zero, negative, and non-finite values are dropped. A
  /// value too small to draw as a segment is handled by
  /// `WovenRingStyle.smallValuePolicy`.
  final double value;

  /// The segment's interior.
  final WovenFill fill;

  /// A hairline around this segment, or null for none.
  ///
  /// Null is the default. `WovenRingChart.highlightedIndex` overrides this for
  /// one segment at a time.
  final WovenBorder? border;

  /// Optional accessibility text describing this segment.
  ///
  /// When the chart has no `WovenRingChart.semanticLabel` of its own, the
  /// labels of every segment carrying a positive value are joined to describe
  /// it, in order. Setting these does not hide the chart's centre widget from
  /// assistive technology.
  final String? semanticLabel;

  /// Opacity of the whole segment, fill and border together.
  ///
  /// Used mainly while segments enter or leave during a data transition.
  /// Clamped to 0 to 1, with a non-finite value treated as opaque.
  final double opacity;

  /// A copy with the given fields replaced.
  ///
  /// Pass `removeBorder` or `removeSemanticLabel` to clear a field, since
  /// passing null means "keep what is there".
  WovenSegment copyWith({
    double? value,
    WovenFill? fill,
    WovenBorder? border,
    bool removeBorder = false,
    String? semanticLabel,
    bool removeSemanticLabel = false,
    double? opacity,
  }) => WovenSegment(
    value: value ?? this.value,
    fill: fill ?? this.fill,
    border: removeBorder ? null : (border ?? this.border),
    semanticLabel: removeSemanticLabel
        ? null
        : (semanticLabel ?? this.semanticLabel),
    opacity: opacity ?? this.opacity,
  );

  /// Interpolates [a] and [b] at [t], blending value, fill, border, and
  /// opacity together.
  ///
  /// [surfaceColor] is needed because a border with no colour of its own
  /// resolves against it. The semantic label switches at the halfway point
  /// rather than blending.
  static WovenSegment lerp(
    WovenSegment a,
    WovenSegment b,
    double t, {
    Color surfaceColor = WovenPalette.surface,
  }) {
    final WovenFill fill = WovenFill.lerp(a.fill, b.fill, t);
    return WovenSegment(
      value: a.value + (b.value - a.value) * t,
      fill: fill,
      border: WovenBorder.lerp(
        a.border,
        b.border,
        t,
        fill: fill,
        surfaceColor: surfaceColor,
      ),
      semanticLabel: t < 0.5 ? a.semanticLabel : b.semanticLabel,
      opacity: a.opacity + (b.opacity - a.opacity) * t,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is WovenSegment &&
      other.value == value &&
      other.fill == fill &&
      other.border == border &&
      other.semanticLabel == semanticLabel &&
      other.opacity == opacity;

  @override
  int get hashCode => Object.hash(value, fill, border, semanticLabel, opacity);
}
