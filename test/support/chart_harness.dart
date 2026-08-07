/// Fixtures and painter probes shared by the widget suites.
///
/// These reach into the painter through `dynamic` on purpose: the painter is
/// private to the package, while its constructor fields are the deterministic
/// lifecycle state under test. The specification catalog under `test/spec/`
/// shares nothing with this file.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woven_ring_chart/woven_ring_chart.dart';

import 'numeric_matchers.dart';

/// Key on the chart under test, so a finder can address it directly.
const ValueKey<String> kRingKey = ValueKey<String>('ring-under-test');

/// Two equal, individually labelled segments.
const List<WovenSegment> kInitialSegments = <WovenSegment>[
  WovenSegment(
    value: 1,
    fill: WovenFill.solid(WovenPalette.purple),
    semanticLabel: 'Purple, 1',
  ),
  WovenSegment(
    value: 1,
    fill: WovenFill.solid(WovenPalette.green),
    semanticLabel: 'Green, 1',
  ),
];

Widget host(Widget child, {bool disableAnimations = false}) {
  return MediaQuery(
    data: MediaQueryData(disableAnimations: disableAnimations),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: WovenPalette.surface,
        child: Center(child: child),
      ),
    ),
  );
}

Finder customPaintFinder(Finder ring) {
  final Finder result = find.descendant(
    of: ring,
    matching: find.byType(CustomPaint),
  );
  expect(result, findsOneWidget);
  return result;
}

dynamic painterOf(WidgetTester tester, Finder ring) {
  final CustomPaint customPaint = tester.widget<CustomPaint>(
    customPaintFinder(ring),
  );
  expect(customPaint.painter, isNotNull);
  return customPaint.painter;
}

double animationProgress(WidgetTester tester, Finder ring) {
  final dynamic painter = painterOf(tester, ring);
  // The production painter is intentionally private, while these public
  // constructor fields are the deterministic lifecycle state under test.
  // ignore: avoid_dynamic_calls
  return painter.animationProgress as double;
}

double spinProgress(WidgetTester tester, Finder ring) {
  final dynamic painter = painterOf(tester, ring);
  // ignore: avoid_dynamic_calls
  return painter.spin as double;
}

WovenRingAnimation paintedAnimation(WidgetTester tester, Finder ring) {
  final dynamic painter = painterOf(tester, ring);
  // ignore: avoid_dynamic_calls
  return painter.animation as WovenRingAnimation;
}

List<WovenSegment> paintedSegments(WidgetTester tester, Finder ring) {
  final dynamic painter = painterOf(tester, ring);
  // ignore: avoid_dynamic_calls
  return List<WovenSegment>.from(painter.segments as List<WovenSegment>);
}

List<double> paintedFractions(WidgetTester tester, Finder ring) {
  final dynamic painter = painterOf(tester, ring);
  // ignore: avoid_dynamic_calls
  return List<double>.from(painter.fractions as List<double>);
}

WovenRingStyle paintedStyle(WidgetTester tester, Finder ring) {
  final dynamic painter = painterOf(tester, ring);
  // ignore: avoid_dynamic_calls
  return painter.style as WovenRingStyle;
}

int? paintedHighlightedIndex(WidgetTester tester, Finder ring) {
  final dynamic painter = painterOf(tester, ring);
  // ignore: avoid_dynamic_calls
  return painter.highlightedIndex as int?;
}

void expectVisibleDataFrame(
  WidgetTester tester,
  Finder ring, {
  required int count,
  double? tinyValue,
  bool expectAnimationComplete = true,
}) {
  final List<WovenSegment> segments = paintedSegments(tester, ring);
  expect(segments, hasLength(count));
  expect(
    segments.every(
      (WovenSegment segment) =>
          segment.value.isFinite && segment.value > 0 && segment.opacity == 1.0,
    ),
    isTrue,
    reason: 'the data transition must never expose an empty fallback frame',
  );
  if (tinyValue != null) {
    expect(segments.first.value, closeTo(tinyValue, 1e-9));
  }
  if (expectAnimationComplete) {
    expect(
      animationProgress(tester, ring),
      1.0,
      reason: 'Animate data must not restart the animation',
    );
  }
}

void expectPaintedFractions(List<double> actual, List<double> expected) {
  expect(actual, hasLength(expected.length));
  for (var i = 0; i < expected.length; i++) {
    expect(actual[i], closeTo(expected[i], 1e-9), reason: 'fraction $i');
  }
}

bool segmentValuesEqual(List<WovenSegment> segments, List<double> values) {
  if (segments.length != values.length) return false;
  for (var i = 0; i < values.length; i++) {
    if ((segments[i].value - values[i]).abs() > 1e-9) return false;
  }
  return true;
}

void expectSegmentContinuity(
  List<WovenSegment> before,
  List<WovenSegment> after,
) {
  expect(after, hasLength(before.length));
  for (var i = 0; i < before.length; i++) {
    expect(after[i].value, closeTo(before[i].value, 1e-9), reason: 'value $i');
    expect(after[i].fill, before[i].fill, reason: 'fill $i');
    expect(after[i].border, before[i].border, reason: 'border $i');
    expect(
      after[i].opacity,
      closeTo(before[i].opacity, 1e-9),
      reason: 'opacity $i',
    );
  }
}

void expectFractionContinuity(List<double> before, List<double> after) {
  expect(after, hasLength(before.length));
  for (var i = 0; i < before.length; i++) {
    expect(after[i], closeTo(before[i], 1e-9), reason: 'fraction $i');
  }
}

CompositorRecordingCanvas recordRingPaint(WidgetTester tester, Finder ring) {
  final CompositorRecordingCanvas canvas = CompositorRecordingCanvas();
  final dynamic painter = painterOf(tester, ring);
  // ignore: avoid_dynamic_calls
  painter.paint(canvas, tester.getSize(customPaintFinder(ring)));
  expect(canvas.events, isNotEmpty);
  return canvas;
}

List<String> expectCyclicOwnerMaskCompositor(WidgetTester tester, Finder ring) {
  final CompositorRecordingCanvas canvas = recordRingPaint(tester, ring);
  final List<WovenSegment> segments = paintedSegments(tester, ring);
  expect(segments.length, greaterThan(1));

  var cursor = 0;
  CompositorEvent nextEvent(String reason) {
    expect(cursor, lessThan(canvas.events.length), reason: reason);
    return canvas.events[cursor++];
  }

  // Every segment first lays down an unmasked coverage fill in stable data
  // order. This guarantees antialiased coverage without depending on which
  // cyclic owner is later painted on top.
  for (var i = 0; i < segments.length; i++) {
    final CompositorEvent event = nextEvent('missing base fill for segment $i');
    expect(event.kind, CompositorEventKind.drawPath, reason: 'base fill $i');
    expectColorNear(
      event.color!,
      segments[i].fill.head,
      reason: 'base fill color $i',
    );
  }

  // Each segment then owns exactly the portion inside its own silhouette and
  // outside its successor. The non-zero/even-odd pair is the cyclic shingle
  // rule, including the seam. Extra later passes, such as border clips, do not
  // make this assertion depend on a brittle total draw count.
  for (var i = 0; i < segments.length; i++) {
    final CompositorEvent ownPath = nextEvent(
      'missing owner path clip for segment $i',
    );
    expect(ownPath.kind, CompositorEventKind.clipPath, reason: 'owner $i');
    expect(ownPath.fillType, PathFillType.nonZero, reason: 'owner path $i');

    final CompositorEvent outsideSuccessor = nextEvent(
      'missing successor complement for segment $i',
    );
    expect(
      outsideSuccessor.kind,
      CompositorEventKind.clipPath,
      reason: 'successor mask $i',
    );
    expect(
      outsideSuccessor.fillType,
      PathFillType.evenOdd,
      reason: 'successor complement $i',
    );

    final CompositorEvent ownerFill = nextEvent(
      'missing masked owner fill for segment $i',
    );
    expect(ownerFill.kind, CompositorEventKind.drawPath, reason: 'owner $i');
    expectColorNear(
      ownerFill.color!,
      segments[i].fill.head,
      reason: 'owner fill color $i',
    );
  }

  return <String>[
    for (final CompositorEvent event in canvas.events.take(cursor))
      event.signature,
  ];
}

enum CompositorEventKind { clipPath, drawPath }

class CompositorEvent {
  const CompositorEvent.clip(this.fillType)
    : kind = CompositorEventKind.clipPath,
      color = null;

  const CompositorEvent.draw(this.color)
    : kind = CompositorEventKind.drawPath,
      fillType = null;

  final CompositorEventKind kind;
  final PathFillType? fillType;
  final Color? color;

  String get signature => switch (kind) {
    CompositorEventKind.clipPath => 'clip:${fillType!.name}',
    CompositorEventKind.drawPath => 'draw',
  };
}

class CompositorRecordingCanvas extends TestRecordingCanvas {
  final List<CompositorEvent> events = <CompositorEvent>[];

  @override
  void clipPath(Path path, {bool doAntiAlias = true}) {
    events.add(CompositorEvent.clip(path.fillType));
  }

  @override
  void drawPath(Path path, Paint paint) {
    events.add(CompositorEvent.draw(paint.color));
    super.drawPath(path, paint);
  }
}

class MutableRingHarness extends StatefulWidget {
  const MutableRingHarness({
    super.key,
    required this.initialSegments,
    this.initialStyle = const WovenRingStyle(),
    this.animation = WovenRingAnimation.none,
    this.controller,
  });

  final List<WovenSegment> initialSegments;
  final WovenRingStyle initialStyle;
  final WovenRingAnimation animation;
  final WovenRingChartController? controller;

  @override
  State<MutableRingHarness> createState() => MutableRingHarnessState();
}

class MutableRingHarnessState extends State<MutableRingHarness> {
  late final List<WovenSegment> segments = <WovenSegment>[
    ...widget.initialSegments,
  ];
  late WovenRingStyle style = widget.initialStyle;

  void replace(List<WovenSegment> value) {
    setState(() {
      segments
        ..clear()
        ..addAll(value);
    });
  }

  void mutateFirstInPlace(WovenSegment value) {
    setState(() => segments[0] = value);
  }

  void restyle(WovenRingStyle value) {
    setState(() => style = value);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 180,
      child: WovenRingChart(
        key: kRingKey,
        segments: segments,
        style: style,
        animation: widget.animation,
        animationDuration: const Duration(seconds: 1),
        transitionDuration: const Duration(seconds: 1),
        controller: widget.controller,
      ),
    );
  }
}

class ModeHarness extends StatefulWidget {
  const ModeHarness({super.key});

  @override
  State<ModeHarness> createState() => ModeHarnessState();
}

class ModeHarnessState extends State<ModeHarness> {
  bool _loading = true;

  void showData() => setState(() => _loading = false);

  void showLoading() => setState(() => _loading = true);

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 180,
      child: _loading
          ? const WovenRingChart.loading(key: kRingKey)
          : const WovenRingChart(
              key: kRingKey,
              segments: kInitialSegments,
              animation: WovenRingAnimation.none,
            ),
    );
  }
}
