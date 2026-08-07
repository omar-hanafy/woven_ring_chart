// The code panel on the showcase promises that what you copy is what you are
// looking at. These tests are that promise.
//
// Rather than checking the generated string against another string, they read
// the generated source back, rebuild the widget's inputs from it, and compare
// those against the inputs the chart is actually handed. A change to either
// side that is not matched on the other fails here, which is the only way the
// panel can be trusted without a human re-reading it every time.
import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woven_ring_chart/woven_ring_chart.dart';
import 'package:woven_ring_chart_example/src/playground_config.dart';

void main() {
  group('emitted source describes the chart that is drawn', () {
    for (final PlaygroundConfig config in _configurations()) {
      test(_describe(config), () {
        _expectSegmentsMatch(config);
        _expectStyleMatches(config);
        _expectChartArgumentsMatch(config);
      });
    }
  });

  group('emitted source is well formed', () {
    test('every colour is named, never a raw hex literal', () {
      for (final PlaygroundConfig config in _configurations()) {
        expect(
          config.toDartSource(),
          isNot(contains('Color(0x')),
          reason:
              'A hex literal means the demo data uses a colour the emitter '
              'has no WovenPalette name for.',
        );
      }
    });

    test('a default configuration emits the shortest thing that works', () {
      const PlaygroundConfig config = PlaygroundConfig();
      final String source = config.toDartSource();

      expect(source, startsWith('WovenRingChart(\n'));
      expect(source, contains('segments: <WovenSegment>['));
      // Nothing is at anything but its default, so no style, no animation, no
      // highlight, and no dart:math note.
      expect(source, isNot(contains('WovenRingStyle')));
      expect(source, isNot(contains('animation:')));
      expect(source, isNot(contains('highlightedIndex:')));
      expect(source, isNot(contains('dart:math')));
    });

    test('the dart:math note appears exactly when startAngle does', () {
      for (final PlaygroundConfig config in _configurations()) {
        final String source = config.toDartSource();
        expect(
          source.contains('dart:math'),
          source.contains('startAngle:'),
          reason:
              'startAngle is emitted as an expression over math.pi, so the '
              'note has to travel with it: ${_describe(config)}',
        );
      }
    });
  });

  group('highlight index', () {
    test('is dropped when the data no longer has that many segments', () {
      const PlaygroundConfig quartet = PlaygroundConfig(highlightedIndex: 3);
      expect(quartet.resolvedHighlightedIndex, 3);

      final PlaygroundConfig single = quartet.copyWith(data: DemoData.single);
      expect(single.resolvedHighlightedIndex, isNull);
      expect(single.toDartSource(), isNot(contains('highlightedIndex:')));
    });

    test('is never emitted for an index the chart would ignore', () {
      const PlaygroundConfig config = PlaygroundConfig(
        data: DemoData.single,
        highlightedIndex: 9,
      );
      expect(config.resolvedHighlightedIndex, isNull);
      expect(config.toDartSource(), isNot(contains('highlightedIndex:')));
    });
  });

  group('segments', () {
    test('carry no semantic labels the snippet does not mention', () {
      for (final PlaygroundConfig config in _configurations()) {
        for (final WovenSegment segment in config.buildSegments()) {
          expect(
            segment.semanticLabel,
            isNull,
            reason:
                'Anything set on a segment has to appear in the snippet, and '
                'per-segment labels are taught in their own section instead.',
          );
        }
      }
    });

    test('are drawn in the order they are written', () {
      const PlaygroundConfig config = PlaygroundConfig(data: DemoData.extended);
      final List<double> built = config
          .buildSegments()
          .map((WovenSegment s) => s.value)
          .toList();
      expect(built, config.values);
    });
  });
}

// ---------------------------------------------------------------- the checks

/// Rebuilds every segment from the emitted text and compares it to the segment
/// the chart is given.
void _expectSegmentsMatch(PlaygroundConfig config) {
  final List<WovenSegment> built = config.buildSegments();
  final List<String> lines = _segmentLines(config.toDartSource());

  expect(
    lines.length,
    built.length,
    reason: 'The snippet lists a different number of segments than it draws.',
  );

  for (int i = 0; i < built.length; i++) {
    expect(
      _parseSegment(lines[i]),
      built[i],
      reason: 'Segment $i reads back differently from how it is drawn.',
    );
  }
}

/// Checks that every style field is emitted when it differs from the package
/// default and left out when it does not.
void _expectStyleMatches(PlaygroundConfig config) {
  final String source = config.toDartSource();
  final WovenRingStyle style = config.buildStyle();
  const WovenRingStyle defaults = WovenRingStyle();

  void expectNumber(String name, double actual, double fallback) {
    if (actual == fallback) {
      expect(source, isNot(contains('$name:')), reason: '$name is default');
      return;
    }
    final RegExpMatch? match = RegExp(
      '$name: ($_numberPattern),',
    ).firstMatch(source);
    expect(match, isNotNull, reason: '$name should be emitted');
    expect(double.parse(match![1]!), closeTo(actual, 1e-9), reason: name);
  }

  expectNumber(
    'thicknessFraction',
    style.thicknessFraction,
    defaults.thicknessFraction,
  );
  expectNumber(
    'overlapFraction',
    style.overlapFraction,
    defaults.overlapFraction,
  );

  if (style.startAngle == defaults.startAngle) {
    expect(source, isNot(contains('startAngle:')));
  } else {
    final RegExpMatch? match = RegExp(
      'startAngle: ($_numberPattern) \\* math\\.pi / 180,',
    ).firstMatch(source);
    expect(match, isNotNull, reason: 'startAngle should be emitted');
    expect(
      double.parse(match![1]!) * math.pi / 180,
      closeTo(style.startAngle, 1e-9),
    );
  }

  expect(source.contains('clockwise: false,'), !style.clockwise);
  expect(
    source.contains(
      'gradientAxis: WovenGradientAxis.${style.gradientAxis.name},',
    ),
    style.gradientAxis != defaults.gradientAxis,
  );
  expect(
    source.contains(
      'gradientDirection: WovenGradientDirection.${style.gradientDirection.name},',
    ),
    style.gradientDirection != defaults.gradientDirection,
  );
  expect(source.contains('shadow: WovenShadow(),'), style.shadow != null);
  expect(
    source.contains(
      'smallValuePolicy: WovenSmallValuePolicy.${style.smallValuePolicy.name},',
    ),
    style.smallValuePolicy != defaults.smallValuePolicy,
  );
  expect(
    source.contains(
      'singleSegmentStyle: WovenSingleSegmentStyle.${style.singleSegmentStyle.name},',
    ),
    style.singleSegmentStyle != defaults.singleSegmentStyle,
  );

  // A style block appears if and only if something in it does.
  final bool anyStyleField =
      style.thicknessFraction != defaults.thicknessFraction ||
      style.overlapFraction != defaults.overlapFraction ||
      style.startAngle != defaults.startAngle ||
      style.clockwise != defaults.clockwise ||
      style.gradientAxis != defaults.gradientAxis ||
      style.gradientDirection != defaults.gradientDirection ||
      style.shadow != null ||
      style.smallValuePolicy != defaults.smallValuePolicy ||
      style.singleSegmentStyle != defaults.singleSegmentStyle;
  expect(source.contains('style: const WovenRingStyle('), anyStyleField);
}

/// Checks the arguments that live on the chart rather than on the style.
void _expectChartArgumentsMatch(PlaygroundConfig config) {
  final String source = config.toDartSource();

  expect(
    source.contains('animation: WovenRingAnimation.${config.animation.name},'),
    config.animation != WovenRingAnimation.sweep,
  );

  final int? highlighted = config.resolvedHighlightedIndex;
  if (highlighted == null) {
    expect(source, isNot(contains('highlightedIndex:')));
  } else {
    expect(source, contains('highlightedIndex: $highlighted,'));
  }
}

// -------------------------------------------------------------- reading back

const String _numberPattern = r'-?\d+(?:\.\d+)?';

/// The segment lines out of a generated snippet, in order.
List<String> _segmentLines(String source) {
  return source
      .split('\n')
      .map((String line) => line.trim())
      .where(
        (String line) =>
            line.startsWith('WovenSegment.solid(') ||
            line.startsWith('WovenSegment(value:'),
      )
      .toList();
}

/// Rebuilds one segment from its generated line.
///
/// Written against the text alone, with no reference to the config that
/// produced it, so that a mistake in the emitter cannot be reproduced here.
WovenSegment _parseSegment(String line) {
  final String text = line.endsWith(',')
      ? line.substring(0, line.length - 1)
      : line;

  final WovenBorder? border =
      text.contains('border: const WovenBorder.darkerFill()')
      ? const WovenBorder.darkerFill()
      : text.contains('border: const WovenBorder()')
      ? const WovenBorder()
      : null;

  final RegExpMatch? solid = RegExp(
    r'^WovenSegment\.solid\((' + _numberPattern + r'), WovenPalette\.(\w+)',
  ).firstMatch(text);
  if (solid != null) {
    return WovenSegment(
      value: double.parse(solid[1]!),
      fill: WovenFill.solid(_colorNamed(solid[2]!)),
      border: border,
    );
  }

  final double value = double.parse(
    RegExp('value: ($_numberPattern)').firstMatch(text)![1]!,
  );

  final RegExpMatch? shaded = RegExp(
    r'fill: WovenFill\.shaded\(WovenPalette\.(\w+)\)',
  ).firstMatch(text);
  if (shaded != null) {
    return WovenSegment(
      value: value,
      fill: WovenFill.shaded(_colorNamed(shaded[1]!)),
      border: border,
    );
  }

  final RegExpMatch gradient = RegExp(
    r'fill: WovenFill\.gradient\(head: WovenPalette\.(\w+), '
    r'tail: WovenPalette\.(\w+)\)',
  ).firstMatch(text)!;
  return WovenSegment(
    value: value,
    fill: WovenFill.gradient(
      head: _colorNamed(gradient[1]!),
      tail: _colorNamed(gradient[2]!),
    ),
    border: border,
  );
}

Color _colorNamed(String name) {
  final Color? color = <String, Color>{
    'blue': WovenPalette.blue,
    'purple': WovenPalette.purple,
    'green': WovenPalette.green,
    'amber': WovenPalette.amber,
    'rose': WovenPalette.rose,
    'rust': WovenPalette.rust,
    'navy': WovenPalette.navy,
    'neutral': WovenPalette.neutral,
    'surface': WovenPalette.surface,
  }[name];
  expect(color, isNotNull, reason: 'WovenPalette.$name is not a colour.');
  return color!;
}

// ------------------------------------------------------------ the sweep

/// Every combination worth checking.
///
/// The enum fields are taken as a full cross product, because that is what a
/// visitor clicking through the controls produces. The numeric fields are
/// checked one at a time and then all at once, which is enough to catch a
/// field that is emitted with the wrong name, the wrong value, or not at all.
List<PlaygroundConfig> _configurations() {
  return <PlaygroundConfig>[
    for (final DemoData data in DemoData.values)
      for (final DemoFill fill in DemoFill.values)
        for (final DemoBorder border in DemoBorder.values)
          PlaygroundConfig(data: data, fill: fill, border: border),
    for (final WovenRingAnimation animation in WovenRingAnimation.values)
      PlaygroundConfig(animation: animation),
    for (final WovenGradientAxis axis in WovenGradientAxis.values)
      PlaygroundConfig(gradientAxis: axis),
    for (final WovenGradientDirection direction
        in WovenGradientDirection.values)
      PlaygroundConfig(gradientDirection: direction),
    for (final WovenSmallValuePolicy policy in WovenSmallValuePolicy.values)
      PlaygroundConfig(data: DemoData.tiny, smallValuePolicy: policy),
    for (final WovenSingleSegmentStyle single in WovenSingleSegmentStyle.values)
      PlaygroundConfig(data: DemoData.single, singleSegmentStyle: single),
    const PlaygroundConfig(thicknessFraction: 0.12),
    const PlaygroundConfig(thicknessFraction: 0.27),
    const PlaygroundConfig(overlapFraction: 0.25),
    const PlaygroundConfig(overlapFraction: 1),
    const PlaygroundConfig(startDegrees: 0),
    const PlaygroundConfig(startDegrees: 45),
    const PlaygroundConfig(startDegrees: -180),
    const PlaygroundConfig(clockwise: false),
    const PlaygroundConfig(shadow: true),
    const PlaygroundConfig(highlightedIndex: 0),
    const PlaygroundConfig(highlightedIndex: 2),
    // Everything moved at once, which is the state the panel is least likely
    // to have been eyeballed in.
    const PlaygroundConfig(
      data: DemoData.extended,
      fill: DemoFill.gradient,
      border: DemoBorder.darkerFill,
      animation: WovenRingAnimation.grow,
      gradientAxis: WovenGradientAxis.acrossThickness,
      gradientDirection: WovenGradientDirection.tailToHead,
      smallValuePolicy: WovenSmallValuePolicy.allowVanish,
      thicknessFraction: 0.28,
      overlapFraction: 0.85,
      startDegrees: 137,
      clockwise: false,
      shadow: true,
      highlightedIndex: 6,
    ),
  ];
}

String _describe(PlaygroundConfig c) {
  return '${c.data.name}/${c.fill.name}/${c.border.name}'
      '/${c.animation.name}/${c.gradientAxis.name}'
      '/${c.gradientDirection.name}/${c.smallValuePolicy.name}'
      '/${c.singleSegmentStyle.name}'
      '/t${c.thicknessFraction}/o${c.overlapFraction}/a${c.startDegrees}'
      '/${c.clockwise ? 'cw' : 'ccw'}/${c.shadow ? 'shadow' : 'flat'}'
      '/h${c.highlightedIndex}';
}
