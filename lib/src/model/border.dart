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

/// A bounded border interpolation with one logical border left replaceable.
///
/// This is internal widget state, not part of the package's public exports.
/// Each update appends a concrete endpoint or the replacement itself.
@internal
@immutable
class WovenBorderSubstitution {
  /// A captured border belonging to an unselected logical index.
  WovenBorderSubstitution.border(
    WovenBorder? border,
    WovenFill fill,
    Color surface,
  ) : _present = border != null,
      _width = border?.resolvedWidthFraction ?? 0,
      _widthShare = 0,
      _opacity = border?.resolvedOpacity ?? 0,
      _opacityShare = 0,
      _colorShare = 0,
      _surfaceBorder = border,
      _fillBorder = border,
      _surfaceShare = border?._surfaceShare ?? 0,
      _fillShare = border?._fillShare ?? 0,
      _referenceSurface = surface,
      _referenceFill = WovenBorder._darkerFill(fill),
      _srgb = _SubstitutionColor.constant(
        border?.resolve(fill, surface) ?? const Color(0x00000000),
      ),
      _p3 = _SubstitutionColor.constant(
        border?.resolve(fill, surface) ?? const Color(0x00000000),
      );

  /// The border supplied later for the selected logical index.
  WovenBorderSubstitution.highlight(WovenFill fill, Color surface)
    : _present = true,
      _width = 0,
      _widthShare = 1,
      _opacity = 0,
      _opacityShare = 1,
      _colorShare = 1,
      _surfaceBorder = const WovenBorder(),
      _fillBorder = const WovenBorder.darkerFill(),
      _surfaceShare = 0,
      _fillShare = 0,
      _referenceSurface = surface,
      _referenceFill = WovenBorder._darkerFill(fill),
      _srgb = _SubstitutionColor.highlight(ColorSpace.sRGB),
      _p3 = _SubstitutionColor.highlight(ColorSpace.displayP3);

  const WovenBorderSubstitution._({
    required this._present,
    required this._width,
    required this._widthShare,
    required this._opacity,
    required this._opacityShare,
    required this._colorShare,
    required this._surfaceBorder,
    required this._fillBorder,
    required this._surfaceShare,
    required this._fillShare,
    required this._referenceSurface,
    required this._referenceFill,
    required this._srgb,
    required this._p3,
  });

  // Absent endpoints fade opacity, but do not dilute colour or line width.
  // Keep those coefficients separate instead of using the logical weight for
  // every border property.
  final bool _present;
  final double _width;
  final double _widthShare;
  final double _opacity;
  final double _opacityShare;
  final double _colorShare;
  // Pure derived replacements follow the same sampled derivation as a normal
  // border, including fill changes between retargets. These are fixed-size
  // WovenBorder values, not references to earlier substitutions.
  final WovenBorder? _surfaceBorder;
  final WovenBorder? _fillBorder;
  final double _surfaceShare;
  final double _fillShare;
  final Color _referenceSurface;
  final Color _referenceFill;
  // A P3 replacement can widen an earlier blend sooner than an sRGB one.
  // Retain both responses so changing the highlight does not reassociate
  // nonlinear colour conversions or alter the unselected contributions.
  final _SubstitutionColor _srgb;
  final _SubstitutionColor _p3;

  /// Appends the next logical endpoint without retaining previous states.
  WovenBorderSubstitution lerpTo(
    WovenBorder? border,
    double t, {
    required bool replace,
    required WovenFill fill,
    required Color surface,
  }) {
    final b = replace
        ? WovenBorderSubstitution.highlight(fill, surface)
        : WovenBorderSubstitution.border(border, fill, surface);
    final nextFill = WovenBorder._darkerFill(fill);
    _SubstitutionColor reanchor(_SubstitutionColor color) => color
        .addDelta(_referenceSurface, surface, _surfaceShare)
        .addDelta(_referenceFill, nextFill, _fillShare);
    final double aColorWeight = b._present ? 1 - t : 1;
    final double bColorWeight = _present ? t : 1;
    final _SubstitutionColor aSrgb = reanchor(_srgb);
    final _SubstitutionColor aP3 = reanchor(_p3);
    return WovenBorderSubstitution._(
      present: _present || b._present,
      width: _width * aColorWeight + b._width * bColorWeight,
      widthShare: _widthShare * aColorWeight + b._widthShare * bColorWeight,
      opacity: _opacity * (1 - t) + b._opacity * t,
      opacityShare: _opacityShare * (1 - t) + b._opacityShare * t,
      colorShare: _colorShare * aColorWeight + b._colorShare * bColorWeight,
      surfaceBorder: WovenBorder.lerp(
        _surfaceBorder,
        b._surfaceBorder,
        t,
        fill: fill,
        surfaceColor: surface,
      ),
      fillBorder: WovenBorder.lerp(
        _fillBorder,
        b._fillBorder,
        t,
        fill: fill,
        surfaceColor: surface,
      ),
      surfaceShare:
          _surfaceShare * aColorWeight + b._surfaceShare * bColorWeight,
      fillShare: _fillShare * aColorWeight + b._fillShare * bColorWeight,
      referenceSurface: surface,
      referenceFill: nextFill,
      srgb: !_present
          ? b._srgb
          : !b._present
          ? aSrgb
          : aSrgb.lerp(b._srgb, t),
      p3: !_present
          ? b._p3
          : !b._present
          ? aP3
          : aP3.lerp(b._p3, t),
    );
  }

  /// Replaces only the selected logical contribution in the captured border.
  WovenBorder? resolve(WovenBorder highlight, WovenFill fill, Color surface) {
    if (!_present) return null;
    final double nextWidth =
        _width + _widthShare * highlight.resolvedWidthFraction;
    final double nextOpacity =
        _opacity + _opacityShare * highlight.resolvedOpacity;
    if (highlight._source case final _BorderSource source) {
      final WovenBorder derived = source == _BorderSource.surface
          ? _surfaceBorder!
          : _fillBorder!;
      return WovenBorder._(
        color: derived.color,
        widthFraction: nextWidth,
        opacity: nextOpacity,
        fromFill: derived._fromFill,
        derivation: derived._derivation,
      );
    }
    // A replacement with no other border must retain its colour space,
    // including a border that only fades against absent endpoints.
    if (_colorShare == 1 &&
        _surfaceShare == 0 &&
        _fillShare == 0 &&
        _srgb.hasOnlyHighlight &&
        _p3.hasOnlyHighlight) {
      return WovenBorder._(
        color: highlight.color,
        widthFraction: nextWidth,
        opacity: nextOpacity,
        fromFill: highlight._fromFill,
        derivation: highlight._derivation,
      );
    }
    final Color replacement = highlight.resolve(fill, surface);
    final Color nextFill = WovenBorder._darkerFill(fill);
    final _SubstitutionColor response =
        (replacement.colorSpace == ColorSpace.displayP3 ? _p3 : _srgb)
            .addDelta(_referenceSurface, surface, _surfaceShare)
            .addDelta(_referenceFill, nextFill, _fillShare);
    final double nextSurfaceShare =
        _surfaceShare + _colorShare * highlight._surfaceShare;
    final double nextFillShare =
        _fillShare + _colorShare * highlight._fillShare;
    return WovenBorder._(
      color: response.resolve(replacement),
      widthFraction: nextWidth,
      opacity: nextOpacity,
      fromFill: false,
      derivation: nextSurfaceShare == 0 && nextFillShare == 0
          ? null
          : _BorderDerivation(
              surfaceShare: nextSurfaceShare,
              fillShare: nextFillShare,
              surface: nextSurfaceShare == 0 ? null : surface,
              fill: nextFillShare == 0 ? null : nextFill,
              source: null,
            ),
    );
  }
}

// A replaceable colour has a linear remainder and at most one sRGB blend
// converted to P3. Retargets append a leaf, and gamut only widens, so the
// nonlinear conversion is retained once rather than retaining a lerp tree.
@immutable
class _SubstitutionColor {
  const _SubstitutionColor._(
    this.constant,
    this.share, {
    this.promotedConstant,
    this.promotedInputShare = 0,
    this.promotedShare = 0,
  });

  const _SubstitutionColor.constant(Color color) : this._(color, 0);

  _SubstitutionColor.highlight(ColorSpace space)
    : this._(
        Color.from(alpha: 0, red: 0, green: 0, blue: 0, colorSpace: space),
        1,
      );

  final Color constant;
  final double share;
  final Color? promotedConstant;
  final double promotedInputShare;
  final double promotedShare;

  bool get hasOnlyHighlight =>
      promotedConstant == null &&
      share == 1 &&
      constant.a == 0 &&
      constant.r == 0 &&
      constant.g == 0 &&
      constant.b == 0;

  _SubstitutionColor _inP3() {
    if (constant.colorSpace == ColorSpace.displayP3) return this;
    if (share == 0) {
      return _SubstitutionColor.constant(
        constant.withValues(colorSpace: ColorSpace.displayP3),
      );
    }
    if (hasOnlyHighlight) {
      return _SubstitutionColor.highlight(ColorSpace.displayP3);
    }
    return _SubstitutionColor._(
      const Color.from(
        alpha: 0,
        red: 0,
        green: 0,
        blue: 0,
        colorSpace: ColorSpace.displayP3,
      ),
      0,
      promotedConstant: constant,
      promotedInputShare: share,
      promotedShare: 1,
    );
  }

  _SubstitutionColor lerp(_SubstitutionColor b, double t) {
    final bool wide =
        constant.colorSpace == ColorSpace.displayP3 ||
        b.constant.colorSpace == ColorSpace.displayP3;
    final a = wide ? _inP3() : this;
    final next = wide ? b._inP3() : b;
    assert(next.promotedConstant == null);
    return _SubstitutionColor._(
      _combine(a.constant, next.constant, 1 - t, t),
      a.share * (1 - t) + next.share * t,
      promotedConstant: a.promotedConstant,
      promotedInputShare: a.promotedInputShare,
      promotedShare: a.promotedShare * (1 - t),
    );
  }

  _SubstitutionColor addDelta(Color before, Color after, double weight) {
    if (weight == 0 || before == after) return this;
    final response = after.colorSpace == ColorSpace.displayP3 ? _inP3() : this;
    final space = response.constant.colorSpace;
    final delta = _combine(
      before.withValues(colorSpace: space),
      after.withValues(colorSpace: space),
      -weight,
      weight,
    );
    return _SubstitutionColor._(
      _combine(response.constant, delta, 1, 1),
      response.share,
      promotedConstant: response.promotedConstant,
      promotedInputShare: response.promotedInputShare,
      promotedShare: response.promotedShare,
    );
  }

  Color resolve(Color highlight) {
    final space = constant.colorSpace;
    Color result = _combine(
      constant,
      highlight.withValues(colorSpace: space),
      1,
      share,
    );
    if (promotedConstant != null) {
      final beforePromotion = _clamp(
        _combine(
          promotedConstant!,
          highlight.withValues(colorSpace: ColorSpace.sRGB),
          1,
          promotedInputShare,
        ),
      );
      result = _combine(
        result,
        beforePromotion.withValues(colorSpace: space),
        1,
        promotedShare,
      );
    }
    return _clamp(result);
  }

  static Color _clamp(Color color) => color.withValues(
    alpha: color.a.clamp(0.0, 1.0),
    red: color.r.clamp(0.0, 1.0),
    green: color.g.clamp(0.0, 1.0),
    blue: color.b.clamp(0.0, 1.0),
  );

  static Color _combine(Color a, Color b, double aShare, double bShare) =>
      Color.from(
        alpha: a.a * aShare + b.a * bShare,
        red: a.r * aShare + b.r * bShare,
        green: a.g * aShare + b.g * bShare,
        blue: a.b * aShare + b.b * bShare,
        colorSpace: a.colorSpace,
      );
}
