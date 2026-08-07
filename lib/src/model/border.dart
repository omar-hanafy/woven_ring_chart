import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'fill.dart';
import 'palette.dart';

/// A hairline around a segment's silhouette.
///
/// The line sits *inside* the segment: it is stroked at double width and
/// clipped to the silhouette, so a bordered segment is never fatter than an
/// unbordered one and the ring's outer edge stays a perfect circle however wide
/// the border gets.
///
/// A border belongs to whichever segment owns a pixel, so a tail buried under
/// its successor does not draw one.
@immutable
class WovenBorder {
  /// A border in [color], or in the chart's surface colour when [color] is
  /// null.
  ///
  /// The surface colour is the one that turns "overlapping" into "cut out" and
  /// makes the weave read on busy or coloured backgrounds. A flat dark outline
  /// is the option to avoid: it makes the ring look like a colouring book.
  const WovenBorder({
    this.color,
    this.widthFraction = 0.015,
    this.opacity = 1.0,
  }) : _fromFill = false;

  /// A border in a darker shade of the segment's own fill.
  ///
  /// [resolve] takes the fill's [WovenFill.midtone] and drops its lightness by
  /// 0.14, so a gradient segment gets one border colour rather than two.
  const WovenBorder.darkerFill({this.widthFraction = 0.015, this.opacity = 1.0})
    : color = null,
      _fromFill = true;

  const WovenBorder._({
    required this.color,
    required this.widthFraction,
    required this.opacity,
    required this._fromFill,
  });

  /// An explicit border colour, or null to derive one.
  ///
  /// Null resolves to the chart's `WovenRingStyle.surfaceColor`, unless this
  /// border came from [WovenBorder.darkerFill].
  final Color? color;

  /// Line width as a fraction of the ring's thickness. 1 to 2% reads as a
  /// hairline.
  ///
  /// See [resolvedWidthFraction] for the range actually drawn.
  final double widthFraction;

  /// Opacity of the line, used to crossfade border changes without a
  /// one-frame pop.
  final double opacity;

  final bool _fromFill;

  /// The colour this border paints on a segment filled with [fill], on a chart
  /// whose surface is [surfaceColor].
  Color resolve(WovenFill fill, Color surfaceColor) {
    final Color? explicit = color;
    if (explicit != null) return explicit;
    if (!_fromFill) return surfaceColor;
    final HSLColor hsl = HSLColor.fromColor(fill.midtone);
    return hsl.withLightness((hsl.lightness - 0.14).clamp(0.0, 1.0)).toColor();
  }

  /// [widthFraction] clamped to the 0.5 to 5 percent of the ring's thickness
  /// that still reads as a line, with a non-finite value falling back to 0.015.
  double get resolvedWidthFraction =>
      widthFraction.isFinite ? widthFraction.clamp(0.005, 0.05) : 0.015;

  /// [opacity] clamped to 0 to 1, with a non-finite value treated as opaque.
  double get resolvedOpacity =>
      opacity.isFinite ? opacity.clamp(0.0, 1.0) : 1.0;

  /// Interpolates [a] and [b] at [t]. Either may be null.
  ///
  /// A border that is appearing fades up from transparent and one that is
  /// disappearing fades down, so adding or removing a border never pops. Both
  /// ends are resolved against [fill] and [surfaceColor] first, which is what
  /// lets a colour derived from the fill crossfade against an explicit one.
  static WovenBorder? lerp(
    WovenBorder? a,
    WovenBorder? b,
    double t, {
    WovenFill? fill,
    Color surfaceColor = WovenPalette.surface,
  }) {
    if (a == null && b == null) return null;
    if (a == null) {
      return b!._withOpacity(b.resolvedOpacity * t);
    }
    if (b == null) {
      return a._withOpacity(a.resolvedOpacity * (1 - t));
    }
    final WovenFill resolvedFill = fill ?? WovenFill.solid(surfaceColor);
    return WovenBorder._(
      color: Color.lerp(
        a.resolve(resolvedFill, surfaceColor),
        b.resolve(resolvedFill, surfaceColor),
        t,
      ),
      widthFraction:
          a.resolvedWidthFraction +
          (b.resolvedWidthFraction - a.resolvedWidthFraction) * t,
      opacity: a.resolvedOpacity + (b.resolvedOpacity - a.resolvedOpacity) * t,
      fromFill: false,
    );
  }

  WovenBorder _withOpacity(double nextOpacity) => WovenBorder._(
    color: color,
    widthFraction: widthFraction,
    opacity: nextOpacity,
    fromFill: _fromFill,
  );

  @override
  bool operator ==(Object other) =>
      other is WovenBorder &&
      other.color == color &&
      other.widthFraction == widthFraction &&
      other.opacity == opacity &&
      other._fromFill == _fromFill;

  @override
  int get hashCode => Object.hash(color, widthFraction, opacity, _fromFill);
}
