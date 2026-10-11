import 'dart:ui' show ColorSpace;

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
  }) : _fromFill = false,
       _derivation = null;

  /// A border in a darker shade of the segment's own fill.
  ///
  /// [resolve] takes the fill's [WovenFill.midtone] and drops its lightness by
  /// 0.14, so a gradient segment gets one border colour rather than two.
  const WovenBorder.darkerFill({this.widthFraction = 0.015, this.opacity = 1.0})
    : color = null,
      _fromFill = true,
      _derivation = null;

  const WovenBorder._({
    required this.color,
    required this.widthFraction,
    required this.opacity,
    required this._fromFill,
    this._derivation,
  });

  /// An explicit border colour, or null to derive one.
  ///
  /// Null resolves to the chart's `WovenRingStyle.surfaceColor`, unless this
  /// border came from [WovenBorder.darkerFill]. For an interpolated border this
  /// is the sampled colour; [resolve] also applies any live derived colours.
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
  final _BorderDerivation? _derivation;

  double get _surfaceShare =>
      _derivation?.surfaceShare ?? (color == null && !_fromFill ? 1.0 : 0.0);

  double get _fillShare => _derivation?.fillShare ?? (_fromFill ? 1.0 : 0.0);

  _BorderSource? get _source {
    if (_derivation != null) return _derivation.source;
    if (color != null) return null;
    return _fromFill ? _BorderSource.fill : _BorderSource.surface;
  }

  /// The colour this border paints on a segment filled with [fill], on a chart
  /// whose surface is [surfaceColor].
  Color resolve(WovenFill fill, Color surfaceColor) {
    final Color? explicit = color;
    if (explicit != null) {
      return _derivation?.resolve(explicit, fill, surfaceColor) ?? explicit;
    }
    if (!_fromFill) return surfaceColor;
    return _darkerFill(fill);
  }

  static Color _darkerFill(WovenFill fill) {
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
  /// The result retains its derived contributions, so [resolve] follows later
  /// surface or fill changes even when this interpolation is interrupted.
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
    final double surfaceShare =
        a._surfaceShare + (b._surfaceShare - a._surfaceShare) * t;
    final double fillShare = a._fillShare + (b._fillShare - a._fillShare) * t;
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
      derivation: surfaceShare == 0 && fillShare == 0
          ? null
          : _BorderDerivation(
              surfaceShare: surfaceShare,
              fillShare: fillShare,
              surface: surfaceShare == 0 ? null : surfaceColor,
              fill: fillShare == 0 ? null : _darkerFill(resolvedFill),
              source: a._source == b._source ? a._source : null,
            ),
    );
  }

  WovenBorder _withOpacity(double nextOpacity) => WovenBorder._(
    color: color,
    widthFraction: widthFraction,
    opacity: nextOpacity,
    fromFill: _fromFill,
    derivation: _derivation,
  );

  @override
  bool operator ==(Object other) =>
      other is WovenBorder &&
      other.color == color &&
      other.widthFraction == widthFraction &&
      other.opacity == opacity &&
      other._fromFill == _fromFill &&
      other._derivation == _derivation;

  @override
  int get hashCode =>
      Object.hash(color, widthFraction, opacity, _fromFill, _derivation);
}

enum _BorderSource { surface, fill }

// Each interpolation stores its exact Color.lerp sample and at most two live
// contributions. Their reference colours are sampled in the same context.
// Resolving in that context returns the sample unchanged; elsewhere it adds
// the weighted source deltas in the sample's (or a wider) colour space. Pure
// derived borders resolve directly. A subsequent lerp samples and reanchors
// this fixed-size state: it never retains either endpoint or a history tree.
//
// This deliberately preserves sampled mixed-gamut interpolation, rather than
// reassociating its nonlinear colour conversions into a global weighted sum.
// Live deltas use the current snapshot's space, not a replay of old lerps.
@immutable
class _BorderDerivation {
  const _BorderDerivation({
    required this.surfaceShare,
    required this.fillShare,
    required this.surface,
    required this.fill,
    required this.source,
  });

  final double surfaceShare;
  final double fillShare;
  final Color? surface;
  final Color? fill;
  // Only a shared source at both endpoints is pure. A weight of one alone is
  // insufficient: extrapolation can cancel weights of different colours.
  final _BorderSource? source;

  Color resolve(Color sample, WovenFill currentFill, Color currentSurface) {
    final Color? nextFill = fillShare == 0
        ? null
        : WovenBorder._darkerFill(currentFill);
    final Color? nextSurface = surfaceShare == 0 ? null : currentSurface;
    if (nextSurface == surface && nextFill == fill) return sample;
    if (source == _BorderSource.surface) return currentSurface;
    if (source == _BorderSource.fill) return nextFill!;

    final ColorSpace space =
        sample.colorSpace == ColorSpace.displayP3 ||
            nextSurface?.colorSpace == ColorSpace.displayP3 ||
            nextFill?.colorSpace == ColorSpace.displayP3
        ? ColorSpace.displayP3
        : sample.colorSpace;
    final Color base = sample.withValues(colorSpace: space);
    double alpha = base.a;
    double red = base.r;
    double green = base.g;
    double blue = base.b;
    void addDelta(Color? before, Color? after, double share) {
      if (before == null || after == null || before == after) return;
      final Color a = before.withValues(colorSpace: space);
      final Color b = after.withValues(colorSpace: space);
      alpha += share * (b.a - a.a);
      red += share * (b.r - a.r);
      green += share * (b.g - a.g);
      blue += share * (b.b - a.b);
    }

    addDelta(surface, nextSurface, surfaceShare);
    addDelta(fill, nextFill, fillShare);
    return Color.from(
      alpha: alpha.clamp(0.0, 1.0),
      red: red.clamp(0.0, 1.0),
      green: green.clamp(0.0, 1.0),
      blue: blue.clamp(0.0, 1.0),
      colorSpace: space,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is _BorderDerivation &&
      other.surfaceShare == surfaceShare &&
      other.fillShare == fillShare &&
      other.surface == surface &&
      other.fill == fill &&
      other.source == source;

  @override
  int get hashCode =>
      Object.hash(surfaceShare, fillShare, surface, fill, source);
}
