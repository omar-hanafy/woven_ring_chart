import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'package:woven_ring_chart/woven_ring_chart.dart';

/// Which set of numbers the playground is drawing.
enum DemoData {
  quartet('Four segments'),
  extended('Ten segments'),
  tiny('One value too small to draw'),
  single('A single value at 100%');

  const DemoData(this.label);

  final String label;
}

/// How the playground fills its segments.
enum DemoFill {
  solid('Solid'),
  shaded('Shaded from one colour'),
  gradient('Gradient between two colours');

  const DemoFill(this.label);

  final String label;
}

/// Whether the playground's segments carry a hairline, and which kind.
enum DemoBorder {
  none('None'),
  surface('Surface colour'),
  darkerFill('Darker shade of the fill');

  const DemoBorder(this.label);

  final String label;
}

/// Everything the playground can be set to, and the only thing that describes
/// it.
///
/// This is the reason the code panel on the page can be trusted. The chart is
/// built from [buildSegments], [buildStyle], [animation] and
/// [highlightedIndex]; the panel is built from [toDartSource]; and both read
/// the same fields off the same object. There is no second copy of the
/// configuration to fall out of step with the first.
///
/// [toDartSource] leaves out anything sitting at its default, so the snippet
/// grows only as far as a visitor has actually moved away from the defaults.
@immutable
class PlaygroundConfig {
  const PlaygroundConfig({
    this.data = DemoData.quartet,
    this.fill = DemoFill.solid,
    this.border = DemoBorder.none,
    this.animation = WovenRingAnimation.sweep,
    this.gradientAxis = WovenGradientAxis.alongSegment,
    this.gradientDirection = WovenGradientDirection.headToTail,
    this.smallValuePolicy = WovenSmallValuePolicy.enforce,
    this.singleSegmentStyle = WovenSingleSegmentStyle.smooth,
    this.thicknessFraction = 0.20,
    this.overlapFraction = 0.5,
    this.startDegrees = -90,
    this.clockwise = true,
    this.shadow = false,
    this.highlightedIndex,
  });

  final DemoData data;
  final DemoFill fill;
  final DemoBorder border;
  final WovenRingAnimation animation;
  final WovenGradientAxis gradientAxis;
  final WovenGradientDirection gradientDirection;
  final WovenSmallValuePolicy smallValuePolicy;
  final WovenSingleSegmentStyle singleSegmentStyle;
  final double thicknessFraction;
  final double overlapFraction;
  final double startDegrees;
  final bool clockwise;
  final bool shadow;
  final int? highlightedIndex;

  PlaygroundConfig copyWith({
    DemoData? data,
    DemoFill? fill,
    DemoBorder? border,
    WovenRingAnimation? animation,
    WovenGradientAxis? gradientAxis,
    WovenGradientDirection? gradientDirection,
    WovenSmallValuePolicy? smallValuePolicy,
    WovenSingleSegmentStyle? singleSegmentStyle,
    double? thicknessFraction,
    double? overlapFraction,
    double? startDegrees,
    bool? clockwise,
    bool? shadow,
    int? highlightedIndex,
    bool clearHighlight = false,
  }) {
    return PlaygroundConfig(
      data: data ?? this.data,
      fill: fill ?? this.fill,
      border: border ?? this.border,
      animation: animation ?? this.animation,
      gradientAxis: gradientAxis ?? this.gradientAxis,
      gradientDirection: gradientDirection ?? this.gradientDirection,
      smallValuePolicy: smallValuePolicy ?? this.smallValuePolicy,
      singleSegmentStyle: singleSegmentStyle ?? this.singleSegmentStyle,
      thicknessFraction: thicknessFraction ?? this.thicknessFraction,
      overlapFraction: overlapFraction ?? this.overlapFraction,
      startDegrees: startDegrees ?? this.startDegrees,
      clockwise: clockwise ?? this.clockwise,
      shadow: shadow ?? this.shadow,
      highlightedIndex: clearHighlight
          ? null
          : highlightedIndex ?? this.highlightedIndex,
    );
  }

  /// The numbers being charted.
  List<double> get values => switch (data) {
    DemoData.quartet => const <double>[37, 19, 29, 15],
    DemoData.extended => const <double>[12, 9, 14, 8, 11, 7, 13, 10, 9, 7],
    DemoData.tiny => const <double>[0.4, 39.6, 25, 35],
    DemoData.single => const <double>[100],
  };

  /// One colour per value, in order.
  List<Color> get colors => switch (data) {
    DemoData.extended => WovenPalette.extended,
    DemoData.single => const <Color>[WovenPalette.purple],
    _ => WovenPalette.quartet,
  };

  /// The data, as the widget takes it.
  ///
  /// Nothing is set here that [toDartSource] does not also write out. In
  /// particular there are no per-segment semantic labels: the preview's own
  /// accessibility is handled by the section around it, so that the snippet
  /// stays an exact description of the chart rather than an approximation of
  /// it. Labelling segments has its own section further down the page.
  List<WovenSegment> buildSegments() {
    final List<double> v = values;
    return <WovenSegment>[
      for (int i = 0; i < v.length; i++)
        WovenSegment(value: v[i], fill: _fillFor(i), border: _border),
    ];
  }

  /// Everything that is not the data, as the widget takes it.
  ///
  /// `surfaceColor` is deliberately left alone. Every chart on this page sits
  /// on a card painted `WovenPalette.surface`, which is what the field already
  /// defaults to, so no snippet has to carry it.
  WovenRingStyle buildStyle() {
    return WovenRingStyle(
      thicknessFraction: thicknessFraction,
      overlapFraction: overlapFraction,
      startAngle: _radians,
      clockwise: clockwise,
      gradientAxis: gradientAxis,
      gradientDirection: gradientDirection,
      shadow: shadow ? const WovenShadow() : null,
      smallValuePolicy: smallValuePolicy,
      singleSegmentStyle: singleSegmentStyle,
    );
  }

  /// The index the chart highlights, or null when the index is out of range.
  int? get resolvedHighlightedIndex {
    final int? index = highlightedIndex;
    if (index == null || index < 0 || index >= values.length) return null;
    return index;
  }

  /// The Dart that builds exactly the chart currently on screen.
  ///
  /// Paste it into a widget tree that already has the package imported and it
  /// compiles. Fields at their default are omitted, so a visitor who has
  /// changed nothing sees the shortest thing that works.
  String toDartSource() {
    final List<String> styleArgs = _styleArguments();
    final List<String> chartArgs = <String>[
      'segments: <WovenSegment>[\n${_segmentLines()}\n  ],',
      if (styleArgs.isNotEmpty)
        'style: const WovenRingStyle(\n'
            '${styleArgs.map((String a) => '    $a').join('\n')}\n'
            '  ),',
      if (animation != WovenRingAnimation.sweep)
        'animation: WovenRingAnimation.${animation.name},',
      if (resolvedHighlightedIndex != null)
        'highlightedIndex: $resolvedHighlightedIndex,',
    ];

    final String needsMath = startDegrees == -90
        ? ''
        : "// needs: import 'dart:math' as math;\n";

    return '$needsMath'
        'WovenRingChart(\n'
        '${chartArgs.map((String a) => '  $a').join('\n')}\n'
        ')';
  }

  // ---------------------------------------------------------------- internals

  double get _radians => startDegrees * math.pi / 180;

  WovenBorder? get _border => switch (border) {
    DemoBorder.none => null,
    DemoBorder.surface => const WovenBorder(),
    DemoBorder.darkerFill => const WovenBorder.darkerFill(),
  };

  WovenFill _fillFor(int index) {
    final List<Color> c = colors;
    final Color color = c[index % c.length];
    return switch (fill) {
      DemoFill.solid => WovenFill.solid(color),
      DemoFill.shaded => WovenFill.shaded(color),
      DemoFill.gradient => WovenFill.gradient(
        head: color,
        tail: c[(index + 1) % c.length],
      ),
    };
  }

  /// One line of source per segment, matching [buildSegments] entry for entry.
  String _segmentLines() {
    final List<double> v = values;
    final List<Color> c = colors;
    final List<String> lines = <String>[];
    for (int i = 0; i < v.length; i++) {
      final String value = _number(v[i]);
      final String color = _colorName(c[i % c.length]);
      final String borderArg = switch (border) {
        DemoBorder.none => '',
        DemoBorder.surface => ', border: const WovenBorder()',
        DemoBorder.darkerFill => ', border: const WovenBorder.darkerFill()',
      };
      final String line = switch (fill) {
        DemoFill.solid => 'WovenSegment.solid($value, $color$borderArg)',
        DemoFill.shaded =>
          'WovenSegment(value: $value, '
              'fill: WovenFill.shaded($color)$borderArg)',
        DemoFill.gradient =>
          'WovenSegment(value: $value, '
              'fill: WovenFill.gradient('
              'head: $color, tail: ${_colorName(c[(i + 1) % c.length])})'
              '$borderArg)',
      };
      lines.add('    $line,');
    }
    return lines.join('\n');
  }

  /// Style arguments that differ from [WovenRingStyle]'s defaults.
  List<String> _styleArguments() {
    return <String>[
      if (thicknessFraction != 0.20)
        'thicknessFraction: ${_number(thicknessFraction)},',
      if (overlapFraction != 0.5)
        'overlapFraction: ${_number(overlapFraction)},',
      if (startDegrees != -90)
        'startAngle: ${_number(startDegrees)} * math.pi / 180,',
      if (!clockwise) 'clockwise: false,',
      if (gradientAxis != WovenGradientAxis.alongSegment)
        'gradientAxis: WovenGradientAxis.${gradientAxis.name},',
      if (gradientDirection != WovenGradientDirection.headToTail)
        'gradientDirection: WovenGradientDirection.${gradientDirection.name},',
      if (shadow) 'shadow: WovenShadow(),',
      if (smallValuePolicy != WovenSmallValuePolicy.enforce)
        'smallValuePolicy: WovenSmallValuePolicy.${smallValuePolicy.name},',
      if (singleSegmentStyle != WovenSingleSegmentStyle.smooth)
        'singleSegmentStyle: WovenSingleSegmentStyle.${singleSegmentStyle.name},',
    ];
  }
}

/// `37.0` prints as `37`, `0.4` stays `0.4`.
///
/// Kept short because these numbers end up in source a visitor copies, and
/// `thicknessFraction: 0.24000000000000002` is not something to hand anybody.
String _number(double value) {
  final double rounded = double.parse(value.toStringAsFixed(4));
  if (rounded == rounded.roundToDouble()) return rounded.toInt().toString();
  return rounded.toString();
}

/// The `WovenPalette` name for a reference colour.
///
/// Every colour the playground can draw comes from the palette, so an unnamed
/// colour would mean the demo data and this table had drifted apart. It fails
/// loudly rather than emitting a hex literal that quietly still compiles.
String _colorName(Color color) {
  final String? name = _paletteNames[color];
  assert(name != null, 'No WovenPalette name for $color.');
  return name == null ? _hex(color) : 'WovenPalette.$name';
}

// Not const: Color overrides `==`, and a const map key may not.
final Map<Color, String> _paletteNames = <Color, String>{
  WovenPalette.blue: 'blue',
  WovenPalette.purple: 'purple',
  WovenPalette.green: 'green',
  WovenPalette.amber: 'amber',
  WovenPalette.rose: 'rose',
  WovenPalette.rust: 'rust',
  WovenPalette.navy: 'navy',
  WovenPalette.neutral: 'neutral',
  WovenPalette.surface: 'surface',
};

String _hex(Color color) {
  final int argb =
      (((color.a * 255).round() & 0xff) << 24) |
      (((color.r * 255).round() & 0xff) << 16) |
      (((color.g * 255).round() & 0xff) << 8) |
      ((color.b * 255).round() & 0xff);
  return 'Color(0x${argb.toRadixString(16).padLeft(8, '0').toUpperCase()})';
}
