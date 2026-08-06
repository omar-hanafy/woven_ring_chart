import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'palette.dart';

/// A snake's interior. Solid, or a gradient that runs head to tail.
///
/// Which way "head to tail" points on screen, and whether the gradient runs
/// along the snake or across the band, are ring-level choices on
/// `WovenRingStyle`. A fill only says which two colours are involved.
@immutable
class WovenFill {
  /// One flat colour from cap to cap.
  const WovenFill.solid(Color color) : head = color, tail = color;

  /// A gradient from [head], the end you see, to [tail], the end that ends up
  /// under the next snake.
  const WovenFill.gradient({required this.head, required this.tail});

  /// A subtle gradient derived from one colour: same hue, one step apart in
  /// lightness. If it reads as a gradient rather than as shading, turn it down.
  ///
  /// [step] is how far the two ends move from `base`, in HSL lightness. It is
  /// clamped to the 0 to 0.2 that still reads as one colour, and a non-finite
  /// step falls back to the default.
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

  /// The colour at the head cap, the rounded end that laps over the snake
  /// before it. This is the end a reader's eye lands on.
  final Color head;

  /// The colour at the tail cap, which the next snake covers.
  final Color tail;

  /// Whether both ends carry the same colour, so no shader is needed.
  bool get isSolid => head == tail;

  /// A solid snake next to a gradient one should match this, not either end.
  Color get midtone => Color.lerp(head, tail, 0.5)!;

  /// Interpolates both ends independently, so a solid fill can become a
  /// gradient one without a flash.
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

/// A hairline around a snake's silhouette. It sits *inside* the snake, so a
/// bordered snake is never fatter than an unbordered one.
///
/// The line is stroked at double width and clipped to the silhouette, which
/// keeps the ring's outer edge a perfect circle no matter how wide the border
/// gets. Borders belong to the visible owner of a pixel: a tail buried under
/// its successor does not draw one.
@immutable
class WovenBorder {
  /// Leave [color] null for the surface colour, the one that turns
  /// "overlapping" into "cut out" and makes the weave pop on busy or coloured
  /// surfaces. Never a neutral dark line: it makes the ring look like a
  /// colouring book.
  const WovenBorder({
    this.color,
    this.widthFraction = 0.015,
    this.opacity = 1.0,
  }) : _fromFill = false;

  /// The other option that works: a darker shade of the snake's own fill.
  ///
  /// [resolve] takes the fill's [WovenFill.midtone] and drops its lightness by
  /// 0.14, so a gradient snake gets one border colour rather than two.
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
  /// Null means the ring's surface colour, unless this border came from
  /// [WovenBorder.darkerFill].
  final Color? color;

  /// Fraction of the band width. 1 to 2%.
  final double widthFraction;

  /// Used internally to crossfade border changes without a one-frame pop.
  final double opacity;

  final bool _fromFill;

  /// The colour this border actually paints on a snake filled with [fill],
  /// sitting on [surface].
  Color resolve(WovenFill fill, Color surface) {
    final Color? explicit = color;
    if (explicit != null) return explicit;
    if (!_fromFill) return surface;
    final HSLColor hsl = HSLColor.fromColor(fill.midtone);
    return hsl.withLightness((hsl.lightness - 0.14).clamp(0.0, 1.0)).toColor();
  }

  /// [widthFraction] clamped to the 0.5 to 5 percent of the band that reads as
  /// a line, with a non-finite value falling back to the default.
  double get resolvedWidthFraction =>
      widthFraction.isFinite ? widthFraction.clamp(0.005, 0.05) : 0.015;

  /// [opacity] clamped to 0 to 1, with a non-finite value treated as opaque.
  double get resolvedOpacity =>
      opacity.isFinite ? opacity.clamp(0.0, 1.0) : 1.0;

  /// Interpolates two borders, either of which may be null.
  ///
  /// A border appearing fades up from transparent and one disappearing fades
  /// down, so adding or removing a border never pops. Both ends are resolved
  /// against [fill] and [surface] first, so a colour derived from the fill and
  /// an explicit colour can be crossfaded against each other.
  static WovenBorder? lerp(
    WovenBorder? a,
    WovenBorder? b,
    double t, {
    WovenFill? fill,
    Color surface = WovenPalette.surface,
  }) {
    if (a == null && b == null) return null;
    if (a == null) {
      return b!._withOpacity(b.resolvedOpacity * t);
    }
    if (b == null) {
      return a._withOpacity(a.resolvedOpacity * (1 - t));
    }
    final WovenFill resolvedFill = fill ?? WovenFill.solid(surface);
    return WovenBorder._(
      color: Color.lerp(
        a.resolve(resolvedFill, surface),
        b.resolve(resolvedFill, surface),
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

/// A very soft, very tight shadow under each head. Ring-level, never per
/// snake. If you notice it as a shadow it is twice too strong.
///
/// The shadow falls backwards along the track from each head cap, so it lands
/// on the snake underneath. It is clipped out of the hole, and the ring shrinks
/// by [reach] to give the blur room outside the outer circle.
@immutable
class WovenLift {
  /// A lift at the default strength: a 12 percent black at a tenth of a band
  /// of blur, offset a twentieth of a band.
  const WovenLift({
    this.color = const Color(0x1F000000),
    this.blurFraction = 0.10,
    this.offsetFraction = 0.05,
  });

  /// The shadow colour, alpha included.
  final Color color;

  /// Blur radius, as a fraction of the band width.
  final double blurFraction;

  /// How far the shadow is pushed back along the track, as a fraction of the
  /// band width.
  final double offsetFraction;

  /// [blurFraction] clamped to 0 to 0.3, with a non-finite value falling back
  /// to the default.
  double get resolvedBlurFraction =>
      blurFraction.isFinite ? blurFraction.clamp(0.0, 0.30) : 0.10;

  /// [offsetFraction] clamped to 0 to 0.2, with a non-finite value falling back
  /// to the default.
  double get resolvedOffsetFraction =>
      offsetFraction.isFinite ? offsetFraction.clamp(0.0, 0.20) : 0.05;

  /// How far outside the outer circle the ring now needs to breathe, in band
  /// widths. The ring is inset by this much so a lifted ring still fits its
  /// box.
  double get reach => resolvedBlurFraction * 3 + resolvedOffsetFraction;

  @override
  bool operator ==(Object other) =>
      other is WovenLift &&
      other.color == color &&
      other.blurFraction == blurFraction &&
      other.offsetFraction == offsetFraction;

  @override
  int get hashCode => Object.hash(color, blurFraction, offsetFraction);
}

/// One coloured segment.
@immutable
class WovenSnake {
  /// A segment worth [value], painted with [fill].
  const WovenSnake({
    required this.value,
    required this.fill,
    this.border,
    this.semanticLabel,
    this.opacity = 1.0,
  });

  /// A segment worth [value] in one flat colour.
  WovenSnake.solid(
    this.value,
    Color color, {
    this.border,
    this.semanticLabel,
    this.opacity = 1.0,
  }) : fill = WovenFill.solid(color);

  /// This segment's share of the ring, in whatever unit the caller likes.
  ///
  /// Values are normalized against the others, so percentages, counts, and
  /// currency all work. Zero, negative, and non-finite values are dropped, and
  /// a value too small to read as a snake is handled by
  /// `WovenRingStyle.minimumPolicy`.
  final double value;

  /// The segment's interior.
  final WovenFill fill;

  /// Null means no border, the default and what both references show.
  final WovenBorder? border;

  /// Optional per-snake accessibility text.
  ///
  /// Without a ring-level label, the labels of every visible snake are joined
  /// to describe the chart. Setting these does not hide the ring's centre from
  /// assistive technology.
  final String? semanticLabel;

  /// Primarily used while snakes enter or leave during a data transition.
  final double opacity;

  /// A copy with the given fields replaced.
  ///
  /// Pass `removeBorder` or `removeSemanticLabel` to clear a field, since
  /// passing null means "keep what is there".
  WovenSnake copyWith({
    double? value,
    WovenFill? fill,
    WovenBorder? border,
    bool removeBorder = false,
    String? semanticLabel,
    bool removeSemanticLabel = false,
    double? opacity,
  }) => WovenSnake(
    value: value ?? this.value,
    fill: fill ?? this.fill,
    border: removeBorder ? null : (border ?? this.border),
    semanticLabel: removeSemanticLabel
        ? null
        : (semanticLabel ?? this.semanticLabel),
    opacity: opacity ?? this.opacity,
  );

  /// Interpolates value, fill, border, and opacity together.
  ///
  /// [surface] is needed because a border with no colour of its own resolves
  /// against it. The semantic label switches at the halfway point rather than
  /// blending.
  static WovenSnake lerp(
    WovenSnake a,
    WovenSnake b,
    double t, {
    Color surface = WovenPalette.surface,
  }) {
    final WovenFill fill = WovenFill.lerp(a.fill, b.fill, t);
    return WovenSnake(
      value: a.value + (b.value - a.value) * t,
      fill: fill,
      border: WovenBorder.lerp(
        a.border,
        b.border,
        t,
        fill: fill,
        surface: surface,
      ),
      semanticLabel: t < 0.5 ? a.semanticLabel : b.semanticLabel,
      opacity: a.opacity + (b.opacity - a.opacity) * t,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is WovenSnake &&
      other.value == value &&
      other.fill == fill &&
      other.border == border &&
      other.semanticLabel == semanticLabel &&
      other.opacity == opacity;

  @override
  int get hashCode => Object.hash(value, fill, border, semanticLabel, opacity);
}
