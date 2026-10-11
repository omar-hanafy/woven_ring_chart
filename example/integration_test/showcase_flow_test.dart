// Requirements: the runnable snippet, the showcase's matching code/preview,
// replay and changing data, and the documented accessibility behavior.
// This suite runs in the real app with integration_test on desktop and web.
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:woven_ring_chart/src/painting/ring_painter.dart';
import 'package:woven_ring_chart/woven_ring_chart.dart';
import 'package:woven_ring_chart_example/main.dart' as snippet;
import 'package:woven_ring_chart_example/showcase.dart';
import 'package:woven_ring_chart_example/src/package_info.dart';
import 'package:woven_ring_chart_example/src/playground_config.dart';
import 'package:woven_ring_chart_example/src/ui/code_block.dart';
import 'package:woven_ring_chart_example/ten_segments.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  _captureClock = _CaptureClock(binding);
  tearDownAll(_captureClock.dispose);

  _flow('the published snippet runs and exposes its chart label', (
    tester,
  ) async {
    await tester.pumpWidget(const snippet.MyApp());
    await tester.pumpAndSettle();
    expect(find.text('100'), findsOneWidget);
    expect(find.bySemanticsLabel('Spending by category'), findsOneWidget);
    final chart = tester.widget<WovenRingChart>(find.byType(WovenRingChart));
    expect(chart.segments.map((segment) => segment.value), [37, 19, 29, 15]);
    expect(_frame(tester, find.byType(WovenRingChart)).animationProgress, 1);
    await _disposeApp(tester);
  });

  _flow('showcase controls change the painted ring and copied source', (
    tester,
  ) async {
    await binding.setSurfaceSize(const Size(1200, 900));
    await tester.pumpWidget(const WovenRingChartDemoApp());
    await tester.pump(const Duration(milliseconds: 1200));
    expect(find.byKey(_key('hero-ring')), findsOneWidget);
    if (!kIsWeb) {
      await _tap(tester, 'copy-install-button');
      expect(
        (await Clipboard.getData(Clipboard.kTextPlain))?.text,
        kInstallLine,
      );
    }
    await _reach(tester, find.text('Playground'));

    await _choose<DemoData>(tester, 'data-control', 'Ten segments');
    await tester.pump(const Duration(milliseconds: 500));
    expect(_chart(tester).segments, hasLength(10));
    expect(_frame(tester, _ring).segments, hasLength(10));
    await _tap(tester, 'highlight-control');
    for (var i = 0; i < 11; i++) {
      await _tap(tester, 'highlight-next-button');
    }
    expect(_chart(tester).highlightedIndex, 1);
    expect(_source(tester), contains('highlightedIndex: 1,'));
    if (!kIsWeb) {
      final source = _source(tester);
      final copy = find.descendant(
        of: find.byKey(_key('playground-code')),
        matching: find.byKey(_key('copy-code-button')),
      );
      await _reach(tester, copy);
      await tester.tap(copy);
      await tester.pump();
      expect((await Clipboard.getData(Clipboard.kTextPlain))?.text, source);
    }

    await _choose<DemoData>(
      tester,
      'data-control',
      'One value too small to draw',
    );
    await _choose<WovenSmallValuePolicy>(
      tester,
      'policy-control',
      'Let them vanish',
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(_chart(tester).highlightedIndex, isNull);
    expect(_chart(tester).segments.first.value, 0.4);
    expect(
      _chart(tester).style.smallValuePolicy,
      WovenSmallValuePolicy.allowVanish,
    );
    expect(_source(tester), contains('WovenSmallValuePolicy.allowVanish'));

    await _choose<DemoData>(tester, 'data-control', 'A single value at 100%');
    await _choose<WovenSingleSegmentStyle>(
      tester,
      'single-style-control',
      'Keep one hairline self-joint',
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(_frame(tester, _ring).segments, hasLength(1));
    expect(
      _chart(tester).style.singleSegmentStyle,
      WovenSingleSegmentStyle.jointed,
    );
    expect(_source(tester), contains('WovenSingleSegmentStyle.jointed'));

    await _sliderEnd(tester, 'thickness-slider', maximum: true);
    expect(_chart(tester).style.thicknessFraction, 0.30);
    expect(_source(tester), contains('thicknessFraction: 0.3,'));
    await _sliderEnd(tester, 'overlap-slider', maximum: true);
    expect(_chart(tester).style.overlapFraction, 1);
    await _sliderEnd(tester, 'start-angle-slider', maximum: false);
    expect(_chart(tester).style.startAngle, -math.pi);
    expect(_source(tester), contains('startAngle: -180 * math.pi / 180,'));

    await _tap(tester, 'reset-button');
    await tester.pump(const Duration(milliseconds: 500));
    expect(_chart(tester).style, const WovenRingStyle());
    expect(_chart(tester).segments, hasLength(4));
    expect(_source(tester), isNot(contains('WovenRingStyle')));
    expect(
      tester
          .widget<DropdownButtonFormField<DemoData>>(
            find.byKey(_key('data-control')),
          )
          .initialValue,
      DemoData.quartet,
    );
    await _reach(tester, _ring);
    await _tap(tester, 'replay-button');
    expect(_frame(tester, _ring).animationProgress, lessThan(1));
    await tester.pump(const Duration(milliseconds: 1200));
    expect(_frame(tester, _ring).animationProgress, 1);

    for (final title in [
      'Fills and borders',
      'Animation',
      'Nothing, and nearly nothing',
      'Colours',
      'Accessibility',
      'This page is the package example.',
    ]) {
      await _reach(tester, find.text(title));
      expect(tester.takeException(), isNull);
    }
    await _disposeApp(tester);
  });

  _flow('compact showcase honors reduced motion and semantic totals', (
    tester,
  ) async {
    await binding.setSurfaceSize(const Size(320, 844));
    binding.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    await tester.pumpWidget(const WovenRingChartDemoApp());
    await tester.pump();
    for (final label in ['pub.dev', 'GitHub', 'API docs']) {
      final link = find.byKey(_key('link-$label'));
      await _reach(tester, link);
      expect(link.hitTestable(), findsOneWidget);
      expect(tester.getRect(link).right, lessThanOrEqualTo(320));
    }
    expect(tester.takeException(), isNull);
    await _reach(tester, find.text('Animation'));
    final sweep = find.byKey(_key('entrance-ring-sweep'));
    await _reach(tester, sweep);
    expect(_frame(tester, sweep).animationProgress, 1);
    await _tap(tester, 'replay-sweep');
    expect(_frame(tester, sweep).animationProgress, 1);
    await _reach(tester, find.byKey(_key('state-card-loading')));
    final loading = find.descendant(
      of: find.byKey(_key('state-card-loading')),
      matching: find.byType(WovenRingChart),
    );
    expect(loading, findsOneWidget);
    expect(
      tester
          .getSemantics(loading)
          .getSemanticsData()
          .flagsCollection
          .isLiveRegion,
      isTrue,
    );
    expect(
      tester.getSemantics(loading).getSemanticsData().value,
      'Waiting for data',
    );
    await _reach(tester, find.byKey(_key('accessibility-ring')));
    expect(
      find.bySemanticsLabel(
        RegExp(
          'Housing, 37 percent.*Food, 19 percent.*Transport, 29 percent.*Everything else, 15 percent',
        ),
      ),
      findsOneWidget,
    );
    final chartSemantics = tester.getSemantics(
      find.byKey(_key('accessibility-ring')),
    );
    expect(
      _semanticLabels(chartSemantics).expand((label) => label.split('\n')),
      contains('100'),
    );
    expect(tester.takeException(), isNull);
    await _disposeApp(tester);
  });

  _flow('ten-segment app supports rapid changes, pause, and resume', (
    tester,
  ) async {
    await binding.setSurfaceSize(const Size(1200, 900));
    await tester.pumpWidget(const TenSegmentsApp());
    await tester.pump(const Duration(milliseconds: 1200));
    await tester.tap(find.byKey(_key('toggle')));
    await tester.pump();
    expect(find.text('Resume'), findsOneWidget);
    final ring = find.byKey(_key('ten-segment-ring'));
    final before = _frame(
      tester,
      ring,
    ).segments.map((segment) => segment.value).toList();
    await tester.pump(const Duration(milliseconds: 2400));
    expect(
      _frame(tester, ring).segments.map((segment) => segment.value),
      before,
    );
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byKey(_key('shuffle')));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('transitions: 3'), findsOneWidget);
    expect(_frame(tester, ring).segments.map((segment) => segment.value), [
      12,
      9,
      11,
      8,
      13,
      10,
      7,
      12,
      9,
      9,
    ]);
    await tester.tap(find.byKey(_key('replay')));
    await tester.pump();
    expect(_frame(tester, ring).animationProgress, lessThan(1));
    await tester.tap(find.byKey(_key('toggle')));
    await tester.pump();
    expect(find.text('Pause'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 2400));
    expect(find.text('transitions: 4'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _disposeApp(tester);
  });
  _flow(
    'extreme data, animation changes, and transparent borders stay correct',
    (tester) async {
      final controller = WovenRingChartController();
      var segments = <WovenSegment>[
        WovenSegment.solid(double.minPositive, WovenPalette.blue),
        WovenSegment.solid(double.maxFinite, WovenPalette.green),
      ];
      var animation = WovenRingAnimation.none;
      var startAngle = 1e20;
      var ringSize = 240.0;
      var clockwise = true;
      int? highlightedIndex;
      var background = const Color(0xFFFFFFFF);
      var transitionDuration = const Duration(milliseconds: 450);
      late StateSetter update;
      final ring = find.byKey(_key('extreme-ring'));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return Center(
                  child: RepaintBoundary(
                    key: _key('extreme-capture'),
                    child: ColoredBox(
                      color: background,
                      child: SizedBox.square(
                        dimension: ringSize,
                        child: WovenRingChart(
                          key: _key('extreme-ring'),
                          segments: segments,
                          controller: controller,
                          animation: animation,
                          highlightedIndex: highlightedIndex,
                          highlightBorder: const WovenBorder(
                            color: Color(0xFFFFFFFF),
                            widthFraction: .05,
                          ),
                          style: WovenRingStyle(
                            startAngle: startAngle,
                            clockwise: clockwise,
                            surfaceColor: background,
                          ),
                          animationDuration: const Duration(seconds: 5),
                          transitionDuration: transitionDuration,
                          semanticLabel: 'Extreme values ring',
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();
      expect(_frame(tester, ring).segments, hasLength(2));
      expect(_frame(tester, ring).fractions.first, greaterThan(0));
      expect(
        _frame(
          tester,
          ring,
        ).fractions.fold<double>(0, (sum, share) => sum + share),
        closeTo(1, 1e-12),
      );
      expect(tester.takeException(), isNull);

      update(() {
        segments = <WovenSegment>[
          WovenSegment.solid(0, WovenPalette.blue),
          WovenSegment.solid(-1, WovenPalette.green),
          WovenSegment.solid(double.nan, WovenPalette.amber),
          WovenSegment.solid(double.infinity, WovenPalette.rose),
        ];
        animation = WovenRingAnimation.sweep;
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(_frame(tester, ring).fractions, <double>[0, 0, 0, 0]);
      expect(_frame(tester, ring).animationProgress, 1);
      controller.replay();
      await tester.pump();
      expect(_frame(tester, ring).animationProgress, 1);
      expect(tester.binding.transientCallbackCount, 0);
      final neutralPixels = await _pixels(tester, ring);
      update(() {
        segments = <WovenSegment>[
          WovenSegment.solid(double.nan, WovenPalette.purple),
          WovenSegment.solid(-2, WovenPalette.rose),
        ];
      });
      await tester.pump();
      expect(_frame(tester, ring).fractions, <double>[0, 0]);
      expect(tester.binding.transientCallbackCount, 0);
      expect(await _pixels(tester, ring), orderedEquals(neutralPixels));
      update(() => segments = <WovenSegment>[]);
      await tester.pump();
      expect(_frame(tester, ring).fractions, isEmpty);
      expect(tester.binding.transientCallbackCount, 0);
      expect(await _pixels(tester, ring), orderedEquals(neutralPixels));

      update(() {
        segments = <WovenSegment>[
          WovenSegment.solid(1, WovenPalette.blue),
          WovenSegment.solid(2, WovenPalette.green),
          WovenSegment.solid(3, WovenPalette.amber),
          WovenSegment.solid(4, WovenPalette.rose),
        ];
      });
      await tester.pump();
      expect(_frame(tester, ring).animationProgress, lessThan(1));
      update(() => animation = WovenRingAnimation.none);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(_frame(tester, ring).animationProgress, 1);
      expect(_frame(tester, ring).fractions, hasLength(4));
      expect(
        _frame(
          tester,
          ring,
        ).fractions.every((share) => share > 0 && share.isFinite),
        isTrue,
      );
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
      final largeAnglePixels = await _pixels(tester, ring);
      expect(largeAnglePixels.any((channel) => channel != 0), isTrue);
      update(() => startAngle = math.atan2(math.sin(1e20), math.cos(1e20)));
      await tester.pump();
      expect(await _pixels(tester, ring), orderedEquals(largeAnglePixels));
      update(() => animation = WovenRingAnimation.sweep);
      await tester.pump();
      controller.replay();
      await tester.pump(const Duration(milliseconds: 100));
      expect(_frame(tester, ring).animationProgress, lessThan(1));
      update(() => segments = <WovenSegment>[]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(_frame(tester, ring).animationProgress, 1);
      expect(tester.binding.transientCallbackCount, 0);
      controller.replay();
      await tester.pump();
      expect(tester.binding.transientCallbackCount, 0);

      for (final opacity in [1.0, .5]) {
        update(() {
          animation = WovenRingAnimation.none;
          startAngle = 0;
          segments = [
            WovenSegment(
              value: 1,
              fill: const WovenFill.gradient(
                head: Color(0x80FF0000),
                tail: Color(0x800000FF),
              ),
              opacity: opacity,
            ),
          ];
        });
        await tester.pumpAndSettle();
        final pixels = await _boundaryPixels(
          tester,
          find.byKey(_key('extreme-capture')),
        );
        final x = (120 + 96 * math.cos(-.25)).round();
        final y = (120 + 96 * math.sin(-.25)).round();
        final index = (y * 240 + x) * 4;
        // Half-transparent fill over white contributes green once. A second
        // lap blend would instead reduce it to 63 (or 143 at half opacity).
        expect(pixels[index + 1], closeTo(opacity == 1 ? 127 : 191, 1));
        expect(pixels[index + 3], 255);
      }
      const borderCases = <({Color color, double opacity, int gray})>[
        (color: Color(0xFF000000), opacity: .5, gray: 128),
        (color: Color(0xFF000000), opacity: .25, gray: 191),
        (color: Color(0x80000000), opacity: .5, gray: 191),
      ];
      for (final direction in [true, false]) {
        for (final spec in borderCases) {
          update(() {
            ringSize = 480;
            clockwise = direction;
            segments = [
              for (var i = 0; i < 4; i++)
                WovenSegment(
                  value: 1,
                  fill: const WovenFill.solid(Color(0xFFFFFFFF)),
                  border: WovenBorder(
                    color: spec.color,
                    widthFraction: .05,
                    opacity: spec.opacity,
                  ),
                ),
            ];
          });
          await tester.pumpAndSettle();
          final capture = find.byKey(_key('extreme-capture'));
          expect(tester.getSize(capture), const Size.square(480));
          final pixels = await _boundaryPixels(tester, capture);
          // Pixel centres are 2.52px inside the visible head cap and 2.28px
          // before the stroke's inner edge, safely away from antialiasing.
          // Each border contributes once over white, including the seam.
          final heads = direction
              ? const [(414, 148), (331, 414), (65, 331), (148, 65)]
              : const [(414, 331), (331, 65), (65, 148), (148, 414)];
          for (final (x, y) in heads) {
            final index = (y * 480 + x) * 4;
            for (var channel = 0; channel < 3; channel++) {
              expect(
                pixels[index + channel],
                closeTo(spec.gray, 1),
                reason:
                    'border opacity=${spec.opacity} color=${spec.color} '
                    'clockwise=$direction cap=($x,$y) channel=$channel',
              );
            }
            expect(pixels[index + 3], 255);
          }
        }
      }
      update(() {
        ringSize = 240;
        clockwise = true;
        background = const Color(0xFF000000);
        transitionDuration = const Duration(seconds: 1);
        segments = const [
          WovenSegment(value: 1, fill: WovenFill.solid(Color(0xFFFF0000))),
        ];
      });
      await tester.pumpAndSettle();
      final capture = find.byKey(_key('extreme-capture'));
      final interior = (120 * 240 + 216) * 4;
      final opaque = await _boundaryPixels(tester, capture);
      expect(opaque.sublist(interior, interior + 4), [255, 0, 0, 255]);
      update(() => segments = [segments.single.copyWith(opacity: 0)]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(_frame(tester, ring).segments.single.opacity, greaterThan(0));
      expect(_frame(tester, ring).segments.single.opacity, lessThan(1));
      await tester.pump(const Duration(milliseconds: 490));
      final nearlyGone = await _boundaryPixels(tester, capture);
      expect(nearlyGone.sublist(interior, interior + 4), [0, 0, 0, 255]);
      await tester.pump(const Duration(milliseconds: 10));
      final gone = await _boundaryPixels(tester, capture);
      expect(gone.sublist(interior, interior + 4), [0, 0, 0, 255]);
      expect(_frame(tester, ring).segments.single.opacity, 0);
      await tester.pump(const Duration(milliseconds: 100));
      expect(await _boundaryPixels(tester, capture), orderedEquals(gone));
      // Opacity zero leaves a positive data segment invisible. Reaching the
      // exact endpoint must not replace it with the neutral empty track.
      final framePolicy = binding.framePolicy;
      binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;
      try {
        const handoffDuration = Duration(milliseconds: 480);
        const fillA = WovenFill.gradient(
          head: Color(0xFFFF0000),
          tail: Color(0xFF0000FF),
        );
        const fillB = WovenFill.gradient(
          head: Color(0xFF00FF00),
          tail: Color(0xFF000000),
        );
        for (final scenario in [
          (clockwise: true, highlighted: false, side: 240),
          (clockwise: false, highlighted: false, side: 240),
          (clockwise: true, highlighted: true, side: 480),
        ]) {
          final direction = scenario.clockwise;
          final side = scenario.side;
          final edgeAngle = .287 + math.pi;
          final edgeX = (side / 2 + side * .305 * math.cos(edgeAngle)).round();
          final edgeY = (side / 2 + side * .305 * math.sin(edgeAngle)).round();
          final edgeIndex = (edgeY * side + edgeX) * 4;
          update(() {
            ringSize = side.toDouble();
            highlightedIndex = scenario.highlighted ? 1 : null;
            background = const Color(0xFFFFFFFF);
            startAngle = .287;
            clockwise = direction;
            transitionDuration = handoffDuration;
            segments = const [
              WovenSegment(value: 100, fill: fillA),
              WovenSegment(value: 0, fill: fillB),
            ];
          });
          await tester.pumpAndSettle();
          final before = await _boundaryPixels(tester, capture);
          final frames = await _timedFrames(
            tester,
            capture,
            handoffDuration,
            () => update(() {
              segments = const [
                WovenSegment(value: 0, fill: fillA),
                WovenSegment(value: 100, fill: fillB),
              ];
            }),
          );
          final firstFraction = frames.firstFraction;
          final lastFraction = frames.lastFraction;
          debugPrint(
            'handoff clockwise=$direction highlighted=${scenario.highlighted} '
            'firstFraction=$firstFraction lastFraction=$lastFraction',
          );
          expect(frames.immediate, orderedEquals(before));
          final first = frames.first;
          final penultimate = frames.last;
          final end = frames.end;
          final firstEase = Curves.easeInOut.transform(firstFraction);
          final lastEase = Curves.easeInOut.transform(lastFraction);
          expect(
            _maxInteriorRgbDelta(before, first, side: side),
            lessThanOrEqualTo(255 * firstEase + 2),
            reason:
                'first handoff frame clockwise=$direction '
                'fraction=$firstFraction',
          );
          if (scenario.highlighted) {
            expect(
              _pixelRgbDelta(before, first, edgeIndex),
              lessThanOrEqualTo(510 * firstEase + 2),
              reason: 'first highlighted-border handoff frame',
            );
          }
          // Each opaque gradient channel can change by at most 255 times the
          // eased fraction. Allow one byte of rounding for each capture.
          expect(
            _maxInteriorRgbDelta(penultimate, end, side: side),
            lessThanOrEqualTo(255 * (1 - lastEase) + 2),
            reason:
                'last handoff frame clockwise=$direction '
                'fraction=$lastFraction',
          );
          if (scenario.highlighted) {
            // This sample lies 2.4px inside the inner border at size 480.
            // Fill color and highlight alpha each contribute at most 255 times
            // the eased distance; the interior-only bound above stays tighter.
            expect(end.sublist(edgeIndex, edgeIndex + 4), [255, 255, 255, 255]);
            expect(
              _pixelRgbDelta(penultimate, end, edgeIndex),
              lessThanOrEqualTo(510 * (1 - lastEase) + 2),
              reason: 'last highlighted-border handoff frame',
            );
          }
          await tester.pump(const Duration(milliseconds: 100));
          expect(await _boundaryPixels(tester, capture), orderedEquals(end));
        }
      } finally {
        binding.framePolicy = framePolicy;
      }
      await _disposeApp(tester);
      controller.dispose();
    },
  );

  _flow('translucent topology, entrances, and highlights stay continuous', (
    tester,
  ) async {
    final controller = WovenRingChartController();
    const duration = Duration(seconds: 1);
    const translucent = WovenSegment(
      value: 1,
      fill: WovenFill.solid(Color(0x80FF0000)),
    );
    var segments = <WovenSegment>[translucent];
    var animation = WovenRingAnimation.none;
    var surface = const Color(0x00000000);
    var backdrop = const Color(0x00000000);
    var startAngle = -math.pi / 2;
    var clockwise = true;
    var gradientDirection = WovenGradientDirection.headToTail;
    WovenShadow? shadow;
    var side = 240.0;
    int? highlightedIndex;
    late StateSetter update;
    final capture = find.byKey(_key('continuity-capture'));
    final framePolicy = binding.framePolicy;
    binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return Center(
                  child: RepaintBoundary(
                    key: _key('continuity-capture'),
                    child: ColoredBox(
                      color: backdrop,
                      child: SizedBox.square(
                        dimension: side,
                        child: WovenRingChart(
                          segments: segments,
                          animation: animation,
                          animationDuration: duration,
                          transitionDuration: duration,
                          controller: controller,
                          highlightedIndex: highlightedIndex,
                          highlightBorder: const WovenBorder(
                            color: Color(0xFF000000),
                            widthFraction: .05,
                          ),
                          style: WovenRingStyle(
                            startAngle: startAngle,
                            clockwise: clockwise,
                            gradientDirection: gradientDirection,
                            shadow: shadow,
                            surfaceColor: surface,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      const interior = (120 * 240 + 24) * 4;
      for (final surfaceCase in [
        (
          color: const Color(0x00000000),
          backdrop: const Color(0x00000000),
          rgba: [128, 0, 0, 128],
        ),
        (
          color: const Color(0x800000FF),
          backdrop: const Color(0x00000000),
          rgba: [128, 0, 64, 192],
        ),
        (
          color: const Color(0x00000000),
          backdrop: const Color(0xFF00FF00),
          rgba: [128, 127, 0, 255],
        ),
        (
          color: const Color(0x800000FF),
          backdrop: const Color(0xFF00FF00),
          rgba: [128, 63, 64, 255],
        ),
      ]) {
        update(() {
          surface = surfaceCase.color;
          backdrop = surfaceCase.backdrop;
        });
        await tester.pumpAndSettle();
        for (final next in [
          <WovenSegment>[translucent, translucent, translucent],
          <WovenSegment>[translucent],
        ]) {
          final previousCount = segments.length;
          final before = await _boundaryPixels(tester, capture);
          _expectPixelNear(before, interior, surfaceCase.rgba, 1);
          final frames = await _timedFrames(
            tester,
            capture,
            duration,
            () => update(() => segments = next),
            diagnose: true,
          );
          // The centreline pixel is 23px inside either annulus edge. Identical
          // half-alpha fills keep the same premultiplied result in both shapes.
          for (final (phase, pixels) in [
            ('immediate', frames.immediate),
            ('first', frames.first),
            ('middle', frames.middle),
            ('last', frames.last),
            ('end', frames.end),
          ]) {
            _expectPixelNear(
              pixels,
              interior,
              surfaceCase.rgba,
              1,
              reason:
                  'surface=${surfaceCase.color} backdrop=${surfaceCase.backdrop} '
                  'owners=$previousCount->${next.length} phase=$phase '
                  'xy=(24,120) rgba=${pixels.sublist(interior, interior + 4)} '
                  'first=${frames.firstFraction} middle=${frames.middleFraction} '
                  'last=${frames.lastFraction} capture=${frames.diagnostics[phase]}',
            );
          }
        }
      }
      for (final entrance in [
        WovenRingAnimation.sweep,
        WovenRingAnimation.grow,
      ]) {
        update(() {
          surface = const Color(0x00000000);
          backdrop = const Color(0x00000000);
          animation = entrance;
          segments = const [
            WovenSegment(
              value: 1,
              fill: WovenFill.gradient(
                head: Color(0xFFFF0000),
                tail: Color(0xFF0000FF),
              ),
            ),
          ];
        });
        await tester.pumpAndSettle();
        final frames = await _timedFrames(
          tester,
          capture,
          duration,
          controller.replay,
        );
        final progress = Curves.easeInOutCubic.transform(frames.lastFraction);
        expect((1 - progress) * 2 * math.pi * 96, lessThan(.5));
        // The framework easing leaves less than half a pixel of tip movement.
        // These points clear the inner and outer annulus edges by at least 4px
        // and must keep their gradient phase.
        for (final (x, y) in const [(74, 13), (24, 120), (216, 120)]) {
          final index = (y * 240 + x) * 4;
          expect(frames.last[index + 3], 255);
          expect(frames.end[index + 3], 255);
          expect(
            _pixelRgbDelta(frames.last, frames.end, index),
            lessThanOrEqualTo(2),
            reason: '$entrance closing gradient at ($x,$y)',
          );
        }
      }
      update(() {
        animation = WovenRingAnimation.none;
        side = 480;
        startAngle = 0;
        surface = const Color(0xFFFFFFFF);
        highlightedIndex = 2;
        segments = const [
          WovenSegment(value: 50, fill: WovenFill.solid(Color(0xFFFF0000))),
          WovenSegment(value: 50, fill: WovenFill.solid(Color(0xFF00FF00))),
          WovenSegment(value: 0, fill: WovenFill.solid(Color(0xFF0000FF))),
        ];
      });
      await tester.pumpAndSettle();
      final frames = await _timedFrames(
        tester,
        capture,
        duration,
        () => update(() {
          segments = const [
            WovenSegment(value: 0, fill: WovenFill.solid(Color(0xFFFF0000))),
            WovenSegment(value: 0, fill: WovenFill.solid(Color(0xFF00FF00))),
            WovenSegment(value: 100, fill: WovenFill.solid(Color(0xFF0000FF))),
          ];
        }),
      );
      const innerBorder = (386 * 480 + 240) * 4;
      expect(frames.end.sublist(innerBorder, innerBorder + 4), [0, 0, 0, 255]);
      final dataEase = Curves.easeInOut.transform(frames.lastFraction);
      final topologyEase = Curves.easeInCubic.transform(dataEase);
      // The previously zero destination's highlight becomes opaque while the
      // canonical ring gains coverage. Bound their two independent eased
      // contributions, without consulting the painter's index or frame styles.
      expect(
        _pixelRgbDelta(frames.last, frames.end, innerBorder),
        lessThanOrEqualTo(255 * (2 - dataEase - topologyEase) + 2),
        reason: 'previously invisible destination highlight must converge',
      );
      for (final direction in WovenGradientDirection.values) {
        for (final drawsClockwise in [true, false]) {
          update(() {
            surface = const Color(0x00000000);
            backdrop = const Color(0x00000000);
            highlightedIndex = null;
            clockwise = drawsClockwise;
            gradientDirection = direction;
            segments = const [
              WovenSegment(
                value: 90,
                fill: WovenFill.gradient(
                  head: Color(0xFFFF0000),
                  tail: Color(0xFF0000FF),
                ),
              ),
              WovenSegment(value: 10, fill: WovenFill.solid(Color(0xFF00FF00))),
            ];
          });
          await tester.pumpAndSettle();
          final pixels = await _boundaryPixels(tester, capture);
          final headY = drawsClockwise ? 164 : 479 - 164;
          final head = (headY * 480 + 416) * 4;
          final channel = direction == WovenGradientDirection.headToTail
              ? 0
              : 2;
          expect(pixels[head + channel], greaterThan(240));
          expect(pixels[head + 2 - channel], lessThan(15));
          // Green is checked by the dither-aware RGB enclosure below.
          expect(pixels[head + 3], 255);
          // Public geometry puts the head at -.25, its cap tip at
          // -.25-asin(.25), and the tail tip at .9*tau+asin(.25).
          // Mirrored cap pixel centres have over18px of silhouette clearance.
          final capExtent = math.asin(.25);
          final span = .9 * 2 * math.pi + .25 + 2 * capExtent;
          final probes = <(int, int)>[
            (416, 164),
            for (final fraction in [.25, .5, .75])
              (
                (240 + 192 * math.cos(.9 * 2 * math.pi * fraction)).floor(),
                (240 + 192 * math.sin(.9 * 2 * math.pi * fraction)).floor(),
              ),
          ];
          for (final (x, clockwiseY) in probes) {
            final y = drawsClockwise ? clockwiseY : 479 - clockwiseY;
            final index = (y * 480 + x) * 4;
            final angle = math.atan2(clockwiseY + .5 - 240, x + .5 - 240);
            final phase = ((angle + .25 + capExtent) % (2 * math.pi)) / span;
            final red =
                255 *
                (direction == WovenGradientDirection.headToTail
                    ? 1 - phase
                    : phase);
            final blue = 255 - red;
            // Active Impeller gradient dithering adds the SAME offset to RGB,
            // bounded by (63/128)/64. It cancels in R-B. Rounding the two
            // channels can move the rounded difference by at most one byte.
            expect(
              pixels[index] - pixels[index + 2],
              closeTo((red - blue).round(), 1),
              reason: '$direction clockwise=$drawsClockwise at($x,$y)',
            );
            const ditherAndRounding = 255 * (63 / 128) / 64 + .5;
            for (var component = 0; component < 3; component++) {
              final expected = [red, 0.0, blue][component];
              expect(
                pixels[index + component],
                closeTo(expected, ditherAndRounding),
              );
            }
            expect(pixels[index + 3], 255);
          }
        }
      }
      for (final drawsClockwise in [true, false]) {
        for (final entrance in [
          WovenRingAnimation.sweep,
          WovenRingAnimation.grow,
        ]) {
          update(() {
            clockwise = drawsClockwise;
            gradientDirection = WovenGradientDirection.headToTail;
            startAngle = -math.pi / 2;
            animation = entrance;
            shadow = const WovenShadow(color: Color(0xCC000000));
            segments = const [
              WovenSegment(
                value: 1,
                fill: WovenFill.gradient(
                  head: Color(0xFFFF0000),
                  tail: Color(0xFF0000FF),
                ),
                border: WovenBorder(
                  color: Color(0xFF000000),
                  widthFraction: .05,
                ),
              ),
            ];
          });
          await tester.pumpAndSettle();
          final reveal = await _timedFrames(
            tester,
            capture,
            duration,
            controller.replay,
            diagnose: true,
          );
          // Public defaults: shadow reach=.35, thicknessFraction=.2 and
          // overlap=.5. Re-derive the inset ring without painter geometry.
          const outer = 240 - 480 * .2 * .35;
          const thickness = 2 * outer * .2;
          const track = outer - thickness / 2;
          const cap = thickness / 2;
          const inner = track - cap;
          const borderWidth = thickness * .05;
          const sigma = thickness * .1;
          final dir = drawsClockwise ? 1.0 : -1.0;
          final head = -math.pi / 2 - dir * .5 * thickness / track;
          final middleProgress = Curves.easeInOutCubic.transform(
            reveal.middleFraction,
          );
          final end = head + dir * 2 * math.pi * middleProgress;
          final capCenter = Offset(
            240 + track * math.cos(end),
            240 + track * math.sin(end),
          );
          final tangent = Offset(-math.sin(end), math.cos(end)) * dir;
          final radial = Offset(math.cos(end), math.sin(end));
          final borderPoint = capCenter + tangent * (cap - borderWidth / 2);
          final borderIndex =
              (borderPoint.dy.floor() * 480 + borderPoint.dx.floor()) * 4;
          _expectPixelNear(reveal.middle, borderIndex, [0, 0, 0, 255], 0);
          for (final angle in [-math.pi / 4, math.pi / 4]) {
            final ray = tangent * math.cos(angle) + radial * math.sin(angle);
            final inside = capCenter + ray * (cap - borderWidth - 2);
            final outside = capCenter + ray * (cap + 3);
            final insideIndex =
                (inside.dy.floor() * 480 + inside.dx.floor()) * 4;
            final outsideIndex =
                (outside.dy.floor() * 480 + outside.dx.floor()) * 4;
            expect(reveal.middle[insideIndex + 3], 255);
            expect(
              reveal.middle[outsideIndex + 3],
              0,
              reason: '$entrance clockwise=$drawsClockwise cap exterior',
            );
          }
          final finalProgress = Curves.easeInOutCubic.transform(
            reveal.lastFraction,
          );
          final gap = 2 * math.pi * (1 - finalProgress);
          final displacement = 2 * track * math.sin(gap / 2);
          final intersection =
              2 * cap * cap * math.acos(displacement / (2 * cap)) -
              displacement /
                  2 *
                  math.sqrt(4 * cap * cap - displacement * displacement);
          final exposedArea = math.max(0.0, math.pi * cap * cap - intersection);
          // The blurred caster is bounded by its exposed area times the peak
          // of a normalized Gaussian. Two bytes cover capture quantization.
          final alphaBound =
              204 * exposedArea / (2 * math.pi * sigma * sigma) + 2;
          var middleExteriorAlpha = 0;
          var lastExteriorAlpha = 0;
          var endExteriorAlpha = 0;
          var holeAlpha = 0;
          for (var y = 0; y < 480; y++) {
            for (var x = 0; x < 480; x++) {
              final radius = math.sqrt(
                (x + .5 - 240) * (x + .5 - 240) +
                    (y + .5 - 240) * (y + .5 - 240),
              );
              final alphaIndex = (y * 480 + x) * 4 + 3;
              if (radius > outer + 2) {
                middleExteriorAlpha = math.max(
                  middleExteriorAlpha,
                  reveal.middle[alphaIndex],
                );
                lastExteriorAlpha = math.max(
                  lastExteriorAlpha,
                  reveal.last[alphaIndex],
                );
                endExteriorAlpha = math.max(
                  endExteriorAlpha,
                  reveal.end[alphaIndex],
                );
              } else if (radius < inner - 2) {
                for (final pixels in [reveal.middle, reveal.last, reveal.end]) {
                  holeAlpha = math.max(holeAlpha, pixels[alphaIndex]);
                }
              }
            }
          }
          debugPrint(
            'shadow entrance=$entrance clockwise=$drawsClockwise '
            'middleFraction=${reveal.middleFraction} '
            'lastFraction=${reveal.lastFraction} '
            'middleEase=$middleProgress lastEase=$finalProgress '
            'captures=${reveal.diagnostics} '
            'holeMiddle=${_holeDiagnostics(reveal.middle, 480, inner - 2)} '
            'holeLast=${_holeDiagnostics(reveal.last, 480, inner - 2)} '
            'holeEnd=${_holeDiagnostics(reveal.end, 480, inner - 2)}',
          );
          expect(middleExteriorAlpha, greaterThan(0));
          expect(lastExteriorAlpha, lessThanOrEqualTo(alphaBound));
          expect(
            endExteriorAlpha,
            0,
            reason: '$entrance clockwise=$drawsClockwise exterior',
          );
          expect(
            holeAlpha,
            0,
            reason: '$entrance clockwise=$drawsClockwise hole',
          );
          for (final (x, y) in const [(405, 240), (74, 240), (240, 405)]) {
            final index = (y * 480 + x) * 4;
            expect(
              _pixelRgbDelta(reveal.last, reveal.end, index),
              lessThanOrEqualTo(2),
              reason:
                  '$entrance bordered/shadowed gradient clockwise=$drawsClockwise',
            );
          }
        }
      }
      await _disposeApp(tester);
    } finally {
      binding.framePolicy = framePolicy;
      controller.dispose();
    }
  });

  _flow('dense successors and retargeted borders keep live ownership', (
    tester,
  ) async {
    final controller = WovenRingChartController();
    const duration = Duration(seconds: 1);
    const colors = [
      Color(0xFFFF0000),
      Color(0xFF00FF00),
      Color(0xFF0000FF),
      Color(0xFFFFFF00),
      Color(0xFFFF00FF),
      Color(0xFF00FFFF),
      Color(0xFFFFFFFF),
      Color(0xFF000000),
    ];
    var segments = <WovenSegment>[];
    var surface = const Color(0xFFFFFFFF);
    var clockwise = true;
    var thickness = .30;
    var overlap = 1.0;
    var animation = WovenRingAnimation.none;
    late StateSetter update;
    final capture = find.byKey(_key('ownership-capture'));
    final framePolicy = binding.framePolicy;
    binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return Center(
                  child: RepaintBoundary(
                    key: _key('ownership-capture'),
                    child: SizedBox.square(
                      dimension: 480,
                      child: WovenRingChart(
                        segments: segments,
                        animation: animation,
                        animationDuration: duration,
                        transitionDuration: duration,
                        controller: controller,
                        style: WovenRingStyle(
                          startAngle: 0,
                          clockwise: clockwise,
                          thicknessFraction: thickness,
                          overlapFraction: overlap,
                          surfaceColor: surface,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      for (final drawsClockwise in [true, false]) {
        final dir = drawsClockwise ? 1.0 : -1.0;
        // Public equal-share geometry: track168, cap72, lag144/168.
        double distance(int index, Offset point) {
          final start = dir * (index * math.pi / 4 - 144 / 168);
          final end = dir * ((index + 1) * math.pi / 4);
          final radial = point - const Offset(240, 240);
          final along =
              (dir * (math.atan2(radial.dy, radial.dx) - start)) %
              (2 * math.pi);
          if (along <= dir * (end - start)) {
            return (radial.distance - 168).abs() - 72;
          }
          Offset on(double angle) =>
              Offset(240 + 168 * math.cos(angle), 240 + 168 * math.sin(angle));
          return math.min(
                (point - on(start)).distance,
                (point - on(end)).distance,
              ) -
              72;
        }

        for (final bordered in [false, true]) {
          update(() {
            clockwise = drawsClockwise;
            segments = [
              for (var index = 0; index < colors.length; index++)
                WovenSegment(
                  value: 1,
                  fill: WovenFill.solid(colors[index]),
                  border: bordered
                      ? WovenBorder(
                          color: index == 1
                              ? const Color(0xFFFFFFFF)
                              : colors[index],
                          widthFraction: .05,
                        )
                      : null,
                ),
            ];
          });
          await tester.pumpAndSettle();
          final pixels = await _boundaryPixels(tester, capture);
          final fillY = drawsClockwise ? 174 : 479 - 174;
          final fillPoint = Offset(394.5, fillY + .5);
          expect(
            [
              for (var index = 0; index < 8; index++)
                if (distance(index, fillPoint) < 0) index,
            ],
            [0, 1, 6, 7],
          );
          for (var index = 0; index < 8; index++) {
            expect(distance(index, fillPoint).abs(), greaterThan(5));
          }
          _expectPixelNear(pixels, (fillY * 480 + 394) * 4, [
            0,
            255,
            0,
            255,
          ], 0);
          if (bordered) {
            final borderY = drawsClockwise ? 172 : 479 - 172;
            final borderPoint = Offset(367.5, borderY + .5);
            expect(
              [
                for (var index = 0; index < 8; index++)
                  if (distance(index, borderPoint) < 0) index,
              ],
              [0, 1, 6, 7],
            );
            // The owner1 stroke is7.2px wide. This pixel centre is3.58px
            // inside its cap and3.62px before the inner stroke edge.
            expect(distance(1, borderPoint), closeTo(-3.58265, .00001));
            for (var index = 0; index < 8; index++) {
              if (index != 1) {
                expect(distance(index, borderPoint).abs(), greaterThan(5));
              }
            }
            _expectPixelNear(pixels, (borderY * 480 + 367) * 4, [
              255,
              255,
              255,
              255,
            ], 0);
            final image = await tester
                .renderObject<RenderRepaintBoundary>(capture)
                .toImage(pixelRatio: 1);
            try {
              final png = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              binding.reportData ??= <String, dynamic>{};
              binding.reportData!['dense-${drawsClockwise ? "clockwise" : "counterclockwise"}-png'] =
                  png!.buffer.asUint8List().toList();
            } finally {
              image.dispose();
            }
          }
        }
      }
      for (final drawsClockwise in [true, false]) {
        List<WovenSegment> values(double first, double second) => [
          WovenSegment(
            value: first,
            fill: const WovenFill.solid(Color(0xFFFF0000)),
            border: const WovenBorder(widthFraction: .05),
          ),
          WovenSegment(
            value: second,
            fill: const WovenFill.solid(Color(0xFF0000FF)),
            border: const WovenBorder(widthFraction: .05),
          ),
        ];
        update(() {
          clockwise = drawsClockwise;
          thickness = .20;
          overlap = .50;
          surface = const Color(0xFFFFFFFF);
          segments = values(1, 1);
        });
        await tester.pumpAndSettle();
        // Both borders derive their colour from the surface. The bottom/top
        // body point is2.50px outside the144px hole edge and2.30px before the
        // stroke inner edge, away from both moving head caps.
        final borderY = drawsClockwise ? 386 : 479 - 386;
        final borderIndex = (borderY * 480 + 240) * 4;
        _expectPixelNear(await _boundaryPixels(tester, capture), borderIndex, [
          255,
          255,
          255,
          255,
        ], 0);
        update(() => segments = values(3, 1));
        final firstStart = await _pumpTimestamp(tester);
        final retargetAt = await _pumpTimestamp(
          tester,
          const Duration(milliseconds: 400),
        );
        expect(retargetAt - firstStart, greaterThan(Duration.zero));
        expect(retargetAt - firstStart, lessThan(duration));
        update(() => segments = values(1, 3));
        final secondStart = await _pumpTimestamp(tester);
        final themeAt = await _pumpTimestamp(
          tester,
          const Duration(milliseconds: 100),
        );
        expect(themeAt - secondStart, greaterThan(Duration.zero));
        expect(themeAt - secondStart, lessThan(duration));
        for (final theme in const [
          Color(0xFF000000),
          Color(0xFFFFFFFF),
          Color(0xFF000000),
        ]) {
          update(() => surface = theme);
          await tester.pump();
          _expectPixelNear(
            await _boundaryPixels(tester, capture),
            borderIndex,
            theme == const Color(0xFF000000)
                ? [0, 0, 0, 255]
                : [255, 255, 255, 255],
            0,
          );
        }
        await tester.pumpAndSettle();
      }
      for (final clustered in [false, true]) {
        for (final drawsClockwise in [true, false]) {
          final count = clustered ? 100 : 30;
          final label =
              '${clustered ? "cluster100" : "equal30"}-${drawsClockwise ? "cw" : "ccw"}';
          update(() {
            clockwise = drawsClockwise;
            thickness = .30;
            overlap = 1;
            surface = const Color(0x00000000);
            animation = clustered
                ? WovenRingAnimation.none
                : WovenRingAnimation.grow;
            segments = [
              for (var index = 0; index < count; index++)
                WovenSegment.solid(
                  clustered ? (index == count - 1 ? 1 : 0) : 1,
                  colors[index % colors.length],
                ),
            ];
          });
          await tester.pumpAndSettle();
          if (clustered) {
            // Public normalization cannot produce a static tiny-head cluster.
            // A sole-heavy to equal data transition does produce one while
            // its ninety-nine new positive fractions are still near zero.
            update(() {
              segments = [
                for (var index = 0; index < count; index++)
                  WovenSegment.solid(1, colors[index % colors.length]),
              ];
            });
          } else {
            controller.replay();
          }
          final startedAt = await _pumpTimestamp(tester);
          final partialAt = await _pumpTimestamp(
            tester,
            Duration(milliseconds: clustered ? 1 : 550),
          );
          final partialFraction =
              (partialAt - startedAt).inMicroseconds / duration.inMicroseconds;
          expect(partialFraction, greaterThan(0));
          expect(partialFraction, lessThan(1));
          if (clustered) {
            expect(partialFraction, lessThan(.1));
            final fractions = _frame(
              tester,
              find.byType(WovenRingChart),
            ).fractions;
            expect(fractions, hasLength(count));
            expect(fractions.every((fraction) => fraction > 0), isTrue);
            expect(
              fractions.take(count - 1).reduce((a, b) => a + b),
              lessThan(.99 * Curves.easeInOut.transform(.1)),
            );
          }
          for (final settled in [false, true]) {
            if (settled) await tester.pumpAndSettle();
            final normalImage = tester
                .renderObject<RenderRepaintBoundary>(capture)
                .toImageSync(pixelRatio: 1);
            ui.Image? preciseImage;
            try {
              // Native default Metal snapshot targets can introduce one-byte
              // alpha fringes. Explicit float targets bypass that MSAA/resolve
              // route. Borrow the actual recorded picture without repainting;
              // retain the normal boundary image for visual evidence.
              if (!kIsWeb) {
                final innerCapture = find.descendant(
                  of: find.byType(WovenRingChart),
                  matching: find.byType(RepaintBoundary),
                );
                expect(innerCapture, findsOneWidget);
                final boundary = tester.renderObject<RenderRepaintBoundary>(
                  innerCapture,
                );
                expect(boundary.size, const Size(480, 480));
                // debugLayer is intentionally unavailable in release builds.
                final layer = boundary.debugLayer;
                expect(layer, isA<OffsetLayer>());
                final offsetLayer = layer! as OffsetLayer;
                expect(offsetLayer.offset, Offset.zero);
                final child = offsetLayer.firstChild;
                expect(child, isA<PictureLayer>());
                expect(child!.nextSibling, isNull);
                final picture = (child as PictureLayer).picture;
                expect(picture, isNotNull);
                preciseImage = picture!.toImageSync(
                  480,
                  480,
                  targetFormat: ui.TargetPixelFormat.rgbaFloat32,
                );
              }
              final pixels = await _imagePixels(preciseImage ?? normalImage);
              const inner = 96.0;
              const outer = 240.0;
              const track = 168.0;
              const cap = 72.0;
              final dir = drawsClockwise ? 1.0 : -1.0;
              final headAngle = -dir * 144 / track;
              final headCenter = Offset(
                240 + track * math.cos(headAngle),
                240 + track * math.sin(headAngle),
              );
              final tangent =
                  Offset(-math.sin(headAngle), math.cos(headAngle)) * dir;
              var holeAlpha = 0;
              var outsideAlpha = 0;
              var interiorAlpha = 255;
              var interiorCount = 0;
              for (var y = 0; y < 480; y++) {
                for (var x = 0; x < 480; x++) {
                  final point = Offset(x + .5, y + .5);
                  final radius = (point - const Offset(240, 240)).distance;
                  final alpha = pixels[(y * 480 + x) * 4 + 3];
                  if (radius < inner - 2) {
                    holeAlpha = math.max(holeAlpha, alpha);
                  } else if (radius > outer + 2) {
                    outsideAlpha = math.max(outsideAlpha, alpha);
                  } else if (radius > inner + 2 && radius < outer - 2) {
                    final fromHead = point - headCenter;
                    // In a partial grow the first head's backward half-cap
                    // is already exposed; the whole annulus need not be.
                    final inHead =
                        fromHead.distance < cap - 3 &&
                        fromHead.dx * tangent.dx + fromHead.dy * tangent.dy <
                            -3;
                    if (settled || inHead) {
                      interiorAlpha = math.min(interiorAlpha, alpha);
                      interiorCount++;
                    }
                  }
                }
              }
              expect(holeAlpha, 0, reason: '$label settled=$settled hole');
              expect(
                outsideAlpha,
                0,
                reason: '$label settled=$settled outside',
              );
              expect(interiorCount, greaterThan(0));
              expect(
                interiorAlpha,
                255,
                reason: '$label settled=$settled opaque revealed interior',
              );
              final png = await normalImage.toByteData(
                format: ui.ImageByteFormat.png,
              );
              binding.reportData ??= <String, dynamic>{};
              binding.reportData!['stress-$label-${settled ? "settled" : "partial"}-png'] =
                  png!.buffer.asUint8List().toList();
            } finally {
              preciseImage?.dispose();
              normalImage.dispose();
            }
          }
        }
      }
      await _disposeApp(tester);
    } finally {
      binding.framePolicy = framePolicy;
      controller.dispose();
    }
  });
  _flow('whole-segment opacity composes fill and border together', (
    tester,
  ) async {
    final capture = find.byKey(_key('whole-opacity-capture'));
    for (final count in [1, 4]) {
      for (final surface in const [
        Color(0x00000000),
        Color(0x800000FF),
        Color(0xFFFFFFFF),
      ]) {
        for (final opacity in [1.0, .5]) {
          await _disposeApp(tester);
          await tester.pumpWidget(
            Directionality(
              textDirection: TextDirection.ltr,
              child: Center(
                child: RepaintBoundary(
                  key: _key('whole-opacity-capture'),
                  child: SizedBox.square(
                    dimension: 480,
                    child: WovenRingChart(
                      animation: WovenRingAnimation.none,
                      style: WovenRingStyle(
                        startAngle: 0,
                        surfaceColor: surface,
                      ),
                      segments: [
                        for (var index = 0; index < count; index++)
                          WovenSegment(
                            value: 1,
                            fill: const WovenFill.solid(Color(0xFFFF0000)),
                            opacity: opacity,
                            border: const WovenBorder(
                              color: Color(0xFF000000),
                              widthFraction: .05,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          // Pixel centre radius236.50053 is3.49947px inside outer240,
          // and1.30053px outside the inner edge of the4.8px border.
          // The full-opacity reference proves fully covered black here.
          final pixels = await _boundaryPixels(tester, capture);
          const borderPixel = (240 * 480 + 476) * 4;
          final expected = [
            (255 * (1 - opacity) * surface.r * surface.a).round(),
            (255 * (1 - opacity) * surface.g * surface.a).round(),
            (255 * (1 - opacity) * surface.b * surface.a).round(),
            (255 * (opacity + (1 - opacity) * surface.a)).round(),
          ];
          // One byte accommodates quantizing the composed layer's alpha;
          // it cannot admit the old residual red64/alpha192 border result.
          _expectPixelNear(pixels, borderPixel, expected, opacity == 1 ? 0 : 1);
        }
      }
    }
    await _disposeApp(tester);
  });
  _flow('ignored zero data preserves partial entrance pixels', (tester) async {
    final framePolicy = binding.framePolicy;
    binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;
    try {
      final capture = find.byKey(_key('ignored-zero-capture'));
      for (final animation in [
        WovenRingAnimation.sweep,
        WovenRingAnimation.grow,
      ]) {
        List<int>? base;
        for (final withZero in [false, true]) {
          await _disposeApp(tester);
          final controller = WovenRingChartController();
          try {
            await tester.pumpWidget(
              Directionality(
                textDirection: TextDirection.ltr,
                child: Center(
                  child: RepaintBoundary(
                    key: _key('ignored-zero-capture'),
                    child: SizedBox.square(
                      dimension: 480,
                      child: WovenRingChart(
                        animation: animation,
                        animationDuration: const Duration(seconds: 1),
                        controller: controller,
                        style: const WovenRingStyle(startAngle: 0),
                        segments: [
                          const WovenSegment(
                            value: 1,
                            fill: WovenFill.solid(Color(0xFFFF0000)),
                          ),
                          if (withZero)
                            const WovenSegment(
                              value: 0,
                              fill: WovenFill.solid(Color(0xFF0000FF)),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            controller.replay();
            final startedAt = await _pumpTimestamp(tester);
            final capturedAt = await _pumpTimestamp(
              tester,
              const Duration(milliseconds: 250),
            );
            final fraction = (capturedAt - startedAt).inMicroseconds / 1000000;
            expect(fraction, greaterThan(0));
            expect(fraction, lessThan(.3));
            // At elapsed<.3, eased progress<.188. The revealed cap ends
            // before1.19 radians; this far-side track point is near pi,
            // over1.9 radians away and47.5px inside both annulus edges.
            final image = tester
                .renderObject<RenderRepaintBoundary>(capture)
                .toImageSync(pixelRatio: 1);
            try {
              final pixels = await _imagePixels(image);
              const farSide = (240 * 480 + 48) * 4;
              final actual = pixels.sublist(farSide, farSide + 4);
              if (withZero) {
                expect(actual, base, reason: '$animation ignored zero');
              } else {
                expect(actual, [0, 0, 0, 0]);
                base = actual;
              }
            } finally {
              image.dispose();
            }
            await _disposeApp(tester);
          } finally {
            controller.dispose();
          }
        }
      }
    } finally {
      binding.framePolicy = framePolicy;
    }
  });
  _flow('mixed-gamut borders match the renderer opacity group', (tester) async {
    const surface = Color(0xFFFF0000);
    const ink = Color.from(
      alpha: 1,
      red: 0,
      green: 1,
      blue: 0,
      colorSpace: ui.ColorSpace.displayP3,
    );
    final capture = find.byKey(_key('mixed-gamut-capture'));
    Future<({List<int> boundary, List<int>? picture})> sample(
      Widget content, {
      int x = 476,
      int y = 240,
    }) async {
      await _disposeApp(tester);
      final isChart = content is WovenRingChart;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: RepaintBoundary(
              key: _key('mixed-gamut-capture'),
              child: SizedBox.square(
                dimension: 480,
                child: isChart
                    ? content
                    : RepaintBoundary(
                        key: _key('mixed-gamut-reference'),
                        child: content,
                      ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final index = (y * 480 + x) * 4;
      final ordinaryImage = tester
          .renderObject<RenderRepaintBoundary>(capture)
          .toImageSync(pixelRatio: 1);
      final List<int> ordinary;
      try {
        final pixels = await _imagePixels(ordinaryImage);
        ordinary = pixels.sublist(index, index + 4);
      } finally {
        ordinaryImage.dispose();
      }
      // Default boundary capture is the primary color contract. Also retain
      // the actual native draw-list control; its float destination can have
      // different gamut conversion/quantization behavior.
      if (kIsWeb) return (boundary: ordinary, picture: null);
      final pictureCapture = isChart
          ? find.descendant(
              of: find.byType(WovenRingChart),
              matching: find.byType(RepaintBoundary),
            )
          : find.byKey(_key('mixed-gamut-reference'));
      expect(pictureCapture, findsOneWidget);
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        pictureCapture,
      );
      expect(boundary.size, const Size(480, 480));
      final layer = boundary.debugLayer;
      expect(layer, isA<OffsetLayer>());
      final offsetLayer = layer! as OffsetLayer;
      expect(offsetLayer.offset, Offset.zero);
      final child = offsetLayer.firstChild;
      expect(child, isA<PictureLayer>());
      expect(child!.nextSibling, isNull);
      final picture = (child as PictureLayer).picture;
      expect(picture, isNotNull);
      final image = picture!.toImageSync(
        480,
        480,
        targetFormat: ui.TargetPixelFormat.rgbaFloat32,
      );
      try {
        final pixels = await _imagePixels(image);
        return (boundary: ordinary, picture: pixels.sublist(index, index + 4));
      } finally {
        image.dispose();
      }
    }

    void report(String name, ({List<int> boundary, List<int>? picture}) value) {
      binding.reportData ??= <String, dynamic>{};
      binding.reportData![name] = {
        'boundary': value.boundary,
        if (!kIsWeb) 'pictureFloat': value.picture,
      };
    }

    WovenRingChart chart(int count) => WovenRingChart(
      animation: WovenRingAnimation.none,
      style: const WovenRingStyle(startAngle: 0, surfaceColor: surface),
      segments: [
        for (var index = 0; index < count; index++)
          const WovenSegment(
            value: 1,
            fill: WovenFill.solid(Color(0xFF0000FF)),
            opacity: .5,
            border: WovenBorder(color: ink, widthFraction: .05),
          ),
      ],
    );

    // Pixel(476,240) is3.5px inside the outer radius and fully covered by
    // the4.8px border. Both controls delegate gamut conversion to the renderer.
    final saveLayerReference = await sample(
      const CustomPaint(painter: _RendererOpacityReference(surface, ink)),
    );
    final dstInReference = await sample(
      const CustomPaint(
        painter: _RendererOpacityReference(surface, ink, dstIn: true),
      ),
    );
    final single = await sample(chart(1));
    final multi = await sample(chart(4));
    report('mixed-gamut-save-layer-reference', saveLayerReference);
    report('mixed-gamut-dst-in-reference', dstInReference);
    report('mixed-gamut-single', single);
    report('mixed-gamut-multi', multi);
    for (final reference in [saveLayerReference, dstInReference]) {
      expect(reference.boundary[3], 255);
      expect(reference.boundary[0], greaterThan(0));
      expect(reference.boundary[1], greaterThan(0));
    }
    // Native controls prove that saveLayer opacity restoration and dstIn
    // scaling can quantize differently on the default8-bit target. Compare
    // each chart to its independent primitive control with exact bytes.
    expect(single.boundary, saveLayerReference.boundary);
    expect(multi.boundary, dstInReference.boundary);
    if (!kIsWeb) {
      expect(dstInReference.picture, saveLayerReference.picture);
      expect(single.picture, saveLayerReference.picture);
      expect(multi.picture, saveLayerReference.picture);
    }

    const overlapColors = [
      Color(0xFFFF0000),
      Color(0xFF00FF00),
      Color(0xFF0000FF),
      Color(0xFFFFFF00),
      Color(0xFFFF00FF),
      Color(0xFF00FFFF),
      Color(0xFFFFFFFF),
      Color(0xFF000000),
    ];
    for (final clockwise in [true, false]) {
      // The existing dense flow independently proves this mirrored point
      // belongs to green owner1, >5px from every silhouette edge. Equivalent
      // P3black on owner0 must not reset the later owner's visible lap.
      final y = clockwise ? 174 : 305;
      final directReference = await sample(
        const CustomPaint(
          painter: _RendererOpacityReference(
            Color(0xFFFFFFFF),
            Color(0xFF000000),
            fill: Color(0xFF00FF00),
            directAlpha: true,
          ),
        ),
        x: 394,
        y: y,
      );
      final groupedReference = await sample(
        const CustomPaint(
          painter: _RendererOpacityReference(
            Color(0xFFFFFFFF),
            Color(0xFF000000),
            fill: Color(0xFF00FF00),
            dstIn: true,
          ),
        ),
        x: 394,
        y: y,
      );
      for (final reference in [directReference, groupedReference]) {
        expect(reference.boundary[3], 255);
        expect(reference.boundary[1], 255);
        expect(reference.boundary[0], reference.boundary[2]);
        expect(reference.boundary[0], greaterThan(0));
        expect(reference.boundary[0], lessThan(reference.boundary[1]));
      }
      report('mixed-lap-direct-reference-$clockwise', directReference);
      report('mixed-lap-group-reference-$clockwise', groupedReference);
      for (final groupedOwner in [false, true]) {
        final actual = await sample(
          WovenRingChart(
            animation: WovenRingAnimation.none,
            style: WovenRingStyle(
              startAngle: 0,
              clockwise: clockwise,
              thicknessFraction: .30,
              overlapFraction: 1,
              surfaceColor: const Color(0xFFFFFFFF),
            ),
            segments: [
              for (var index = 0; index < overlapColors.length; index++)
                WovenSegment(
                  value: 1,
                  fill: WovenFill.solid(overlapColors[index]),
                  opacity: .5,
                  border: WovenBorder(
                    color: groupedOwner && index == 0
                        ? const Color.from(
                            alpha: 1,
                            red: 0,
                            green: 0,
                            blue: 0,
                            colorSpace: ui.ColorSpace.displayP3,
                          )
                        : const Color(0xFF000000),
                    widthFraction: .05,
                  ),
                ),
            ],
          ),
          x: 394,
          y: y,
        );
        report('mixed-lap-$clockwise-$groupedOwner', actual);
        // Direct alpha=.5 and grouped byte alpha128/255 differ by.5/255.
        // The independent controls establish the resulting exact renderer
        // bytes rather than imposing bit identity across those two paths.
        final reference = groupedOwner ? groupedReference : directReference;
        expect(actual.boundary, reference.boundary);
        if (!kIsWeb) expect(actual.picture, reference.picture);
      }
    }
    await _disposeApp(tester);
  });
  _flow('shrinking data ignores highlights outside the current list', (
    tester,
  ) async {
    final framePolicy = binding.framePolicy;
    binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;
    try {
      for (final remaining in [1, 2]) {
        var count = 4;
        int? highlightedIndex;
        var tickersEnabled = true;
        late StateSetter update;
        final capture = find.byKey(_key('shrinking-highlight-capture'));
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return TickerMode(
                  enabled: tickersEnabled,
                  child: Center(
                    child: RepaintBoundary(
                      key: _key('shrinking-highlight-capture'),
                      child: SizedBox.square(
                        dimension: 480,
                        child: WovenRingChart(
                          animation: WovenRingAnimation.none,
                          transitionDuration: const Duration(seconds: 1),
                          highlightedIndex: highlightedIndex,
                          highlightBorder: const WovenBorder(
                            color: Color(0xFF000000),
                            widthFraction: .05,
                          ),
                          segments: [
                            for (final color in const [
                              Color(0xFFFF0000),
                              Color(0xFF00FF00),
                              Color(0xFF0000FF),
                              Color(0xFFFF00FF),
                            ].take(count))
                              WovenSegment.solid(1, color),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        update(() => count = remaining);
        final startedAt = await _pumpTimestamp(tester);
        final partialAt = await _pumpTimestamp(
          tester,
          const Duration(milliseconds: 300),
        );
        expect(partialAt - startedAt, greaterThan(Duration.zero));
        expect(partialAt - startedAt, lessThan(const Duration(seconds: 1)));
        update(() => tickersEnabled = false);
        await tester.pump();
        final fractions = List<double>.of(
          _frame(tester, find.byType(WovenRingChart)).fractions,
        );
        expect(fractions, hasLength(4));
        expect(fractions.last, greaterThan(0));
        expect(fractions.last, lessThan(.25));
        final base = await _boundaryPixels(tester, capture);
        int changedBytes(Uint8List actual) {
          expect(actual, hasLength(base.length));
          var count = 0;
          for (var index = 0; index < base.length; index++) {
            if (actual[index] != base[index]) count++;
          }
          return count;
        }

        update(() => highlightedIndex = 3);
        await tester.pump();
        expect(
          _frame(tester, find.byType(WovenRingChart)).fractions,
          orderedEquals(fractions),
        );
        expect(
          changedBytes(await _boundaryPixels(tester, capture)),
          0,
          reason: 'index3 is outside the current $remaining entries',
        );
        update(() => highlightedIndex = 0);
        await tester.pump();
        expect(
          _frame(tester, find.byType(WovenRingChart)).fractions,
          orderedEquals(fractions),
        );
        expect(
          changedBytes(await _boundaryPixels(tester, capture)),
          greaterThan(0),
          reason: 'valid index0 must still highlight the frozen partial frame',
        );
        await _disposeApp(tester);
      }
    } finally {
      binding.framePolicy = framePolicy;
    }
  });
  _flow('retained selection replaces only its original border contribution', (
    tester,
  ) async {
    final framePolicy = binding.framePolicy;
    binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;
    try {
      var active = 0;
      int? highlightedIndex;
      var tickersEnabled = true;
      late StateSetter update;
      const colors = [Color(0xFFFF0000), Color(0xFF0000FF), Color(0xFFFFFF00)];
      final capture = find.byKey(_key('retained-selection-capture'));
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return TickerMode(
                enabled: tickersEnabled,
                child: Center(
                  child: RepaintBoundary(
                    key: _key('retained-selection-capture'),
                    child: SizedBox.square(
                      dimension: 480,
                      child: WovenRingChart(
                        animation: WovenRingAnimation.none,
                        transitionDuration: const Duration(seconds: 1),
                        highlightedIndex: highlightedIndex,
                        highlightBorder: const WovenBorder(
                          color: Color(0xFF00FF00),
                          widthFraction: .05,
                        ),
                        segments: [
                          for (var index = 0; index < colors.length; index++)
                            WovenSegment(
                              value: index == active ? 1 : 0,
                              fill: const WovenFill.solid(Color(0xFFFFFFFF)),
                              border: WovenBorder(
                                color: colors[index],
                                widthFraction: .05,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      update(() => active = 1);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      update(() => tickersEnabled = false);
      await tester.pump();
      Color borderColor() {
        final frame = _frame(tester, find.byType(WovenRingChart));
        final segment =
            frame.segments[frame.fractions.indexWhere((f) => f > 0)];
        return segment.border!.resolve(segment.fill, WovenPalette.surface);
      }

      final normal = borderColor();
      expect(normal.r, greaterThan(0));
      expect(normal.b, greaterThan(0));
      expect(normal.g, 0);
      final normalPixels = await _boundaryPixels(tester, capture);
      update(() => highlightedIndex = 0);
      await tester.pump();
      final expected = borderColor();
      // The red endpoint is replaced by green; the blue endpoint is unchanged.
      expect(expected.r, 0);
      expect(expected.g, closeTo(normal.r, 1e-12));
      expect(expected.b, closeTo(normal.b, 1e-12));
      final highlightedPixels = await _boundaryPixels(tester, capture);
      update(() => highlightedIndex = null);
      await tester.pump();
      expect(
        await _boundaryPixels(tester, capture),
        orderedEquals(normalPixels),
      );
      update(() => active = 2);
      await tester.pump();
      expect(
        await _boundaryPixels(tester, capture),
        orderedEquals(normalPixels),
      );
      update(() => highlightedIndex = 0);
      await tester.pump();
      final retained = borderColor();
      expect(retained.r, closeTo(expected.r, 1e-12));
      expect(retained.g, closeTo(expected.g, 1e-12));
      expect(retained.b, closeTo(expected.b, 1e-12));
      expect(
        await _boundaryPixels(tester, capture),
        orderedEquals(highlightedPixels),
        reason: 'retargeting a frozen frame must not alter live selection',
      );
      await _disposeApp(tester);
    } finally {
      binding.framePolicy = framePolicy;
    }
  });
  _flow('equal translucent owners keep the interior annulus uniform', (
    tester,
  ) async {
    for (final surface in [const Color(0x00000000), WovenPalette.surface]) {
      for (final clockwise in [true, false]) {
        final capture = find.byKey(_key('uniform-translucency-capture'));
        Future<Uint8List> render(int count) async {
          await _disposeApp(tester);
          await tester.pumpWidget(
            Directionality(
              textDirection: TextDirection.ltr,
              child: Center(
                child: RepaintBoundary(
                  key: _key('uniform-translucency-capture'),
                  child: SizedBox.square(
                    dimension: 480,
                    child: WovenRingChart(
                      animation: WovenRingAnimation.none,
                      style: WovenRingStyle(
                        surfaceColor: surface,
                        clockwise: clockwise,
                      ),
                      segments: [
                        for (var index = 0; index < count; index++)
                          WovenSegment.solid(1, const Color(0x80FF0000)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          return _boundaryPixels(tester, capture);
        }

        final single = await render(1);
        final four = await render(4);
        var worst = 0;
        var minimumAlpha = 255;
        for (var y = 0; y < 480; y++) {
          for (var x = 0; x < 480; x++) {
            final radius =
                (Offset(x + .5, y + .5) - const Offset(240, 240)).distance;
            // Exclude only the true inner/outer silhouette; internal owner
            // edges remain in the scan, where identical ink must stay uniform.
            if (radius < 149 || radius > 235) continue;
            final offset = (y * 480 + x) * 4;
            minimumAlpha = math.min(minimumAlpha, four[offset + 3]);
            for (var channel = 0; channel < 4; channel++) {
              worst = math.max(
                worst,
                (four[offset + channel] - single[offset + channel]).abs(),
              );
            }
          }
        }
        binding.reportData ??= <String, dynamic>{};
        binding.reportData!['uniform-translucency-${surface.a}-$clockwise'] = {
          'maximumChannelDifference': worst,
          'minimumAlpha': minimumAlpha,
        };
        expect(
          worst,
          lessThanOrEqualTo(2),
          reason: 'surface=$surface clockwise=$clockwise',
        );
        if (surface.a == 1) expect(minimumAlpha, 255);
      }
    }
    await _disposeApp(tester);
  });
}

// A primitive renderer control: compose P3 ink over the sRGB surface through
// native layers, never through CPU arithmetic on encoded colour components.
class _RendererOpacityReference extends CustomPainter {
  const _RendererOpacityReference(
    this.surface,
    this.ink, {
    this.fill = const Color(0xFF0000FF),
    this.dstIn = false,
    this.directAlpha = false,
  });

  final Color surface;
  final Color ink;
  final Color fill;
  final bool dstIn;
  final bool directAlpha;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    // Public default geometry: outer radius=.5*side, thickness=.2*side,
    // inner radius=.3*side. Strokes sit inside the annulus at .05*thickness.
    // The sampled dense point also lies well inside this primitive annulus.
    final center = size.center(Offset.zero);
    final outer = size.shortestSide * .5;
    final inner = size.shortestSide * .3;
    final width = size.shortestSide * .2 * .05;
    final ring = Path()
      ..fillType = PathFillType.evenOdd
      ..addOval(Rect.fromCircle(center: center, radius: outer))
      ..addOval(Rect.fromCircle(center: center, radius: inner));
    if (directAlpha) {
      // Resolve raw ink first and place the common surface behind it. Although
      // surface-first srcOver is mathematically equivalent, an 8-bit target
      // can round those operations differently. This independent primitive
      // follows the translucent-owner contract without package geometry.
      canvas.saveLayer(bounds, Paint());
      canvas.drawPath(
        ring,
        Paint()
          ..color = fill.withValues(alpha: .5)
          ..blendMode = BlendMode.src,
      );
      canvas.drawPath(
        ring,
        Paint()
          ..color = surface
          ..blendMode = BlendMode.dstOver,
      );
      canvas.restore();
      return;
    }
    canvas.saveLayer(bounds, Paint());
    canvas.drawRect(bounds, Paint()..color = surface);
    canvas.saveLayer(
      bounds,
      dstIn ? Paint() : (Paint()..color = const Color(0x80FFFFFF)),
    );
    canvas.drawPath(ring, Paint()..color = fill);
    final border = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = width;
    canvas.drawCircle(center, outer - width / 2, border);
    canvas.drawCircle(center, inner + width / 2, border);
    if (dstIn) {
      canvas.drawPaint(
        Paint()
          ..color = const Color(0x80FFFFFF)
          ..blendMode = BlendMode.dstIn,
      );
    }
    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(_RendererOpacityReference oldDelegate) =>
      surface != oldDelegate.surface || ink != oldDelegate.ink;
}

ValueKey<String> _key(String value) => ValueKey<String>(value);
Finder get _ring => find.byKey(_key('playground-ring'));
WovenRingChart _chart(WidgetTester tester) =>
    tester.widget<WovenRingChart>(_ring);
String _source(WidgetTester tester) =>
    tester.widget<CodeBlock>(find.byKey(_key('playground-code'))).source;

WovenRingChartPainter _frame(WidgetTester tester, Finder ring) {
  final paint = find.descendant(of: ring, matching: find.byType(CustomPaint));
  return tester.widget<CustomPaint>(paint).painter! as WovenRingChartPainter;
}

Future<void> _reach(WidgetTester tester, Finder target) async {
  for (var i = 0; i < 150; i++) {
    if (target.evaluate().isNotEmpty) {
      await tester.ensureVisible(target);
      await tester.pump();
      return;
    }
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pump(const Duration(milliseconds: 80));
  }
  fail('Could not reach $target in the showcase.');
}

Future<void> _tap(WidgetTester tester, String id) async {
  final target = find.byKey(_key(id));
  await _reach(tester, target);
  await tester.tap(target);
  await tester.pump();
}

Future<void> _choose<T>(WidgetTester tester, String id, String label) async {
  await _tap(tester, id);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(find.text(label).last);
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _sliderEnd(
  WidgetTester tester,
  String id, {
  required bool maximum,
}) async {
  final slider = find.byKey(_key(id));
  await _reach(tester, slider);
  final rect = tester.getRect(slider);
  await tester.dragFrom(
    rect.center,
    Offset(maximum ? rect.width : -rect.width, 0),
  );
  await tester.pump();
}

Future<void> _disposeApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  expect(tester.takeException(), isNull);
  expect(tester.binding.transientCallbackCount, 0);
}

void _flow(String description, Future<void> Function(WidgetTester) body) {
  testWidgets(description, (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await body(tester);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      semantics.dispose();
      tester.platformDispatcher.clearAccessibilityFeaturesTestValue();
      await tester.binding.setSurfaceSize(null);
    }
  });
}

List<String> _semanticLabels(SemanticsNode node) {
  final labels = <String>[node.getSemanticsData().label];
  node.visitChildren((child) {
    labels.addAll(_semanticLabels(child));
    return true;
  });
  return labels;
}

Future<Uint8List> _pixels(WidgetTester tester, Finder ring) async {
  return _boundaryPixels(
    tester,
    find.descendant(of: ring, matching: find.byType(RepaintBoundary)),
  );
}

Future<Uint8List> _boundaryPixels(WidgetTester tester, Finder finder) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(finder);
  final image = await boundary.toImage(pixelRatio: 1);
  try {
    final data = await image.toByteData();
    return data!.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

// Sixty-four centreline samples are over 23px inside the annulus edges. The
// fixture has size 240 or 480 and startAngle .287; painter state is not consulted.
int _maxInteriorRgbDelta(Uint8List before, Uint8List after, {int side = 240}) {
  var maximum = 0;
  for (var sample = 0; sample < 64; sample++) {
    final angle = .287 + (sample + .5) * 2 * math.pi / 64;
    final x = (side / 2 + side * .4 * math.cos(angle)).round();
    final y = (side / 2 + side * .4 * math.sin(angle)).round();
    final index = (y * side + x) * 4;
    for (var channel = 0; channel < 3; channel++) {
      maximum = math.max(
        maximum,
        (before[index + channel] - after[index + channel]).abs(),
      );
    }
  }
  return maximum;
}

int _pixelRgbDelta(Uint8List before, Uint8List after, int index) {
  var maximum = 0;
  for (var channel = 0; channel < 3; channel++) {
    maximum = math.max(
      maximum,
      (before[index + channel] - after[index + channel]).abs(),
    );
  }
  return maximum;
}

// The scheduler exposes currentFrameTimeStamp only while executing a frame.
Future<Duration> _pumpTimestamp(
  WidgetTester tester, [
  Duration duration = Duration.zero,
]) async {
  Duration? timestamp;
  tester.binding.addPostFrameCallback((value) => timestamp = value);
  await tester.pump(duration);
  expect(timestamp, isNotNull);
  return timestamp!;
}

Future<Uint8List> _imagePixels(ui.Image image) async {
  final data = await image.toByteData();
  return data!.buffer.asUint8List();
}

// Request real engine frames at controlled animation timestamps. Complete each
// asynchronous GPU capture before advancing the next phase, so readback latency
// cannot change the state being compared or overlap retained capture handles.
Future<
  ({
    Uint8List immediate,
    Uint8List first,
    Uint8List middle,
    Uint8List last,
    Uint8List end,
    double firstFraction,
    double middleFraction,
    double lastFraction,
    Map<String, Map<String, Object?>> diagnostics,
  })
>
_timedFrames(
  WidgetTester tester,
  Finder capture,
  Duration duration,
  VoidCallback trigger, {
  bool diagnose = false,
}) async {
  final binding = tester.binding as IntegrationTestWidgetsFlutterBinding;
  final framePolicy = binding.framePolicy;
  final diagnostics = <String, Map<String, Object?>>{};
  final boundary = tester.renderObject<RenderRepaintBoundary>(capture);
  final paint = diagnose
      ? tester.renderObject<RenderCustomPaint>(
          find.descendant(of: capture, matching: find.byType(CustomPaint)),
        )
      : null;
  Future<Uint8List> snapshot(String phase) async {
    if (diagnose) {
      final frame = paint!.painter! as WovenRingChartPainter;
      final shadow = frame.style.shadow;
      diagnostics[phase] = {
        'boundarySize': boundary.size.toString(),
        'paintSize': paint.size.toString(),
        'progress': frame.animationProgress,
        'fractions': frame.fractions,
        'opacities': frame.segments.map((value) => value.opacity).toList(),
        'borders': frame.segments
            .map((value) => value.border.toString())
            .toList(),
        'surface': frame.style.surfaceColor.toString(),
        'shadow': shadow == null
            ? null
            : [shadow.color.toString(), shadow.reach, shadow.blurFraction],
        'highlight': frame.highlightedIndex,
        'topologyMerge': frame.topologyMerge,
        'topologyAnchor': frame.topologyAnchor,
      };
    }
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final data = (await image.toByteData())!;
      if (diagnose) {
        diagnostics[phase]!.addAll({
          'imageSize': [image.width, image.height],
          'byteLength': data.lengthInBytes,
          'byteOffset': data.offsetInBytes,
          'bufferLength': data.buffer.lengthInBytes,
        });
      }
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } finally {
      image.dispose();
    }
  }

  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;
  var clockActive = false;
  try {
    _captureClock.beginCaptureClock();
    clockActive = true;
    trigger();
    final startedAt = await _pumpTimestamp(tester);
    final immediate = await snapshot('immediate');
    _captureClock.advanceCaptureClock(const Duration(milliseconds: 1));
    final firstAt = await _pumpTimestamp(tester);
    expect(firstAt - startedAt, const Duration(milliseconds: 1));
    final firstFraction =
        (firstAt - startedAt).inMicroseconds / duration.inMicroseconds;
    expect(firstFraction, greaterThan(0));
    expect(firstFraction, lessThan(.1));
    final first = await snapshot('first');
    final middleOffset = Duration(
      microseconds: (duration.inMicroseconds * .4).round(),
    );
    _captureClock.advanceCaptureClock(middleOffset - (firstAt - startedAt));
    final middleAt = await _pumpTimestamp(tester);
    expect(middleAt - startedAt, middleOffset);
    final middle = await snapshot('middle');
    final lastOffset = Duration(
      microseconds: (duration.inMicroseconds * .98).round(),
    );
    _captureClock.advanceCaptureClock(lastOffset - (middleAt - startedAt));
    final lastAt = await _pumpTimestamp(tester);
    expect(lastAt - startedAt, lastOffset);
    final lastFraction =
        (lastAt - startedAt).inMicroseconds / duration.inMicroseconds;
    expect(lastFraction, greaterThanOrEqualTo(.97));
    expect(lastFraction, lessThan(1));
    final last = await snapshot('last');
    _captureClock.advanceCaptureClock(duration - (lastAt - startedAt));
    final endAt = await _pumpTimestamp(tester);
    expect(endAt - startedAt, duration);
    final end = await snapshot('end');
    _captureClock.advanceCaptureClock(const Duration(milliseconds: 100));
    await _pumpTimestamp(tester);
    expect(await snapshot('stable'), orderedEquals(end));
    return (
      immediate: immediate,
      first: first,
      middle: middle,
      last: last,
      end: end,
      firstFraction: firstFraction,
      middleFraction:
          (middleAt - startedAt).inMicroseconds / duration.inMicroseconds,
      lastFraction: lastFraction,
      diagnostics: diagnostics,
    );
  } finally {
    if (clockActive) _captureClock.endCaptureClock();
    binding.framePolicy = framePolicy;
  }
}

late final _CaptureClock _captureClock;

// Control only animation time during isolated captures. Delegate the existing
// engine callback so LiveTestWidgetsFlutterBinding still decides which frames
// to draw and SchedulerBinding retains its warm-up/reschedule handling.
class _CaptureClock {
  _CaptureClock(this.binding) {
    // The launcher can initialize the binding before the app is resumed.
    // Forced scheduling registers callbacks even while framesEnabled is false.
    binding.scheduleForcedFrame();
    _originalCallback = binding.platformDispatcher.onBeginFrame!;
    // Install in main's initialization zone, before individual test zones.
    binding.platformDispatcher.onBeginFrame = (rawTimeStamp) {
      _latestEngineRaw = rawTimeStamp;
      _originalCallback(_captureRaw ?? rawTimeStamp - _offset);
    };
  }

  final IntegrationTestWidgetsFlutterBinding binding;
  final Zone _initializationZone = Zone.current;
  late final ui.FrameCallback _originalCallback;
  Duration _latestEngineRaw = Duration.zero;
  Duration _offset = Duration.zero;
  Duration? _captureRaw;

  void beginCaptureClock() {
    assert(_captureRaw == null);
    assert(timeDilation == 1);
    _captureRaw = binding.currentSystemFrameTimeStamp;
  }

  void advanceCaptureClock(Duration elapsed) {
    assert(_captureRaw != null);
    assert(!elapsed.isNegative);
    _captureRaw = _captureRaw! + elapsed;
  }

  void endCaptureClock() {
    _offset = _latestEngineRaw - _captureRaw!;
    _captureRaw = null;
  }

  void dispose() {
    assert(_captureRaw == null);
    _initializationZone.run(() {
      // Restore the engine's raw-time domain only after all test captures.
      // A new epoch keeps the scheduler's adjusted time monotonic across this
      // final domain change; captures never reset epochs or change dilation.
      binding.resetEpoch();
      binding.platformDispatcher.onBeginFrame = _originalCallback;
    });
  }
}

Map<String, Object?> _holeDiagnostics(
  Uint8List pixels,
  int side,
  double holeRadius,
) {
  var maximum = 0;
  var count = 0;
  var maxX = 0;
  var maxY = 0;
  var minX = side;
  var minY = side;
  var right = -1;
  var bottom = -1;
  for (var y = 0; y < side; y++) {
    for (var x = 0; x < side; x++) {
      final radius = math.sqrt(
        math.pow(x + .5 - side / 2, 2) + math.pow(y + .5 - side / 2, 2),
      );
      if (radius >= holeRadius) continue;
      final alpha = pixels[(y * side + x) * 4 + 3];
      if (alpha == 0) continue;
      count++;
      minX = math.min(minX, x);
      minY = math.min(minY, y);
      right = math.max(right, x);
      bottom = math.max(bottom, y);
      if (alpha > maximum) {
        maximum = alpha;
        maxX = x;
        maxY = y;
      }
    }
  }
  List<int> rgba(int x, int y) {
    final index = (y * side + x) * 4;
    return pixels.sublist(index, index + 4);
  }

  return {
    'maxAlpha': maximum,
    'nonzeroCount': count,
    'center': rgba(side ~/ 2, side ~/ 2),
    if (count > 0) ...{
      'xy': [maxX, maxY],
      'rgba': rgba(maxX, maxY),
      'radius': math.sqrt(
        math.pow(maxX + .5 - side / 2, 2) + math.pow(maxY + .5 - side / 2, 2),
      ),
      'bounds': [minX, minY, right, bottom],
      'neighbors': [
        for (
          var y = math.max(0, maxY - 1);
          y <= math.min(side - 1, maxY + 1);
          y++
        )
          [
            for (
              var x = math.max(0, maxX - 1);
              x <= math.min(side - 1, maxX + 1);
              x++
            )
              rgba(x, y),
          ],
      ],
    },
  };
}

void _expectPixelNear(
  Uint8List pixels,
  int index,
  List<int> expected,
  int tolerance, {
  String? reason,
}) {
  for (var channel = 0; channel < 4; channel++) {
    expect(
      pixels[index + channel],
      closeTo(expected[channel], tolerance),
      reason: 'premultiplied topology pixel, channel=$channel ${reason ?? ''}',
    );
  }
}
