// Requirements: the runnable snippet, the showcase's matching code/preview,
// replay and changing data, and the documented accessibility behavior.
// This suite runs in the real app with integration_test on desktop and web.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
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

  _flow('the published snippet runs and exposes its chart label', (
    tester,
  ) async {
    await tester.pumpWidget(const snippet.MyApp());
    await tester.pump(const Duration(milliseconds: 1200));
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
      final snapshots = <ui.Image>[];
      ui.Image snapshot() {
        final image = tester
            .renderObject<RenderRepaintBoundary>(capture)
            .toImageSync(pixelRatio: 1);
        snapshots.add(image);
        return image;
      }

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
          update(() {
            segments = const [
              WovenSegment(value: 0, fill: fillA),
              WovenSegment(value: 100, fill: fillB),
            ];
          });
          final startedAt = await _pumpTimestamp(tester);
          final immediateImage = snapshot();
          final firstAt = await _pumpTimestamp(
            tester,
            const Duration(milliseconds: 1),
          );
          final firstFraction =
              (firstAt - startedAt).inMicroseconds /
              handoffDuration.inMicroseconds;
          // Live pumps are display frames, not exact fake-clock milliseconds.
          // Require an actual first frame before 10% of the duration elapsed.
          expect(firstFraction, greaterThan(0));
          expect(firstFraction, lessThan(.1));
          final firstImage = snapshot();
          var lastAt = await _pumpTimestamp(
            tester,
            const Duration(milliseconds: 360),
          );
          for (var step = 0; step < 100; step++) {
            final elapsed = lastAt - startedAt;
            if (elapsed.inMicroseconds >= handoffDuration.inMicroseconds * .9) {
              break;
            }
            lastAt = await _pumpTimestamp(
              tester,
              const Duration(milliseconds: 1),
            );
          }
          final lastFraction =
              (lastAt - startedAt).inMicroseconds /
              handoffDuration.inMicroseconds;
          expect(lastFraction, greaterThanOrEqualTo(.9));
          expect(lastFraction, lessThan(1));
          final penultimateImage = snapshot();
          await tester.pumpAndSettle();
          final endImage = snapshot();
          // Capture scene handles synchronously, then read pixels afterward.
          // GPU readback latency must not consume the timed endpoint windows.
          expect(await _imagePixels(immediateImage), orderedEquals(before));
          final first = await _imagePixels(firstImage);
          final penultimate = await _imagePixels(penultimateImage);
          final end = await _imagePixels(endImage);
          final firstEase = Curves.easeInOut.transform(firstFraction);
          final lastEase = Curves.easeInOut.transform(lastFraction);
          expect(
            _maxInteriorRgbDelta(before, first, side: side),
            lessThanOrEqualTo(255 * firstEase + 2),
            reason:
                'first handoff frame clockwise=$direction '
                'elapsed=${firstAt - startedAt}',
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
                'elapsed=${lastAt - startedAt}',
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
        for (final image in snapshots) {
          image.dispose();
        }
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
          final before = await _boundaryPixels(tester, capture);
          _expectPixelNear(before, interior, surfaceCase.rgba, 1);
          final frames = await _timedFrames(
            tester,
            capture,
            duration,
            () => update(() => segments = next),
          );
          // The centreline pixel is 23px inside either annulus edge. Identical
          // half-alpha fills keep the same premultiplied result in both shapes.
          for (final pixels in [
            frames.immediate,
            frames.first,
            frames.middle,
            frames.last,
            frames.end,
          ]) {
            _expectPixelNear(pixels, interior, surfaceCase.rgba, 1);
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
          expect(pixels[head + 1], 0);
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

// Collect real display-frame snapshots before asynchronous GPU byte readback.
Future<
  ({
    Uint8List immediate,
    Uint8List first,
    Uint8List middle,
    Uint8List last,
    Uint8List end,
    double middleFraction,
    double lastFraction,
  })
>
_timedFrames(
  WidgetTester tester,
  Finder capture,
  Duration duration,
  VoidCallback trigger,
) async {
  final images = <ui.Image>[];
  ui.Image snapshot() {
    final image = tester
        .renderObject<RenderRepaintBoundary>(capture)
        .toImageSync(pixelRatio: 1);
    images.add(image);
    return image;
  }

  try {
    trigger();
    final startedAt = await _pumpTimestamp(tester);
    final immediate = snapshot();
    final firstAt = await _pumpTimestamp(
      tester,
      const Duration(milliseconds: 1),
    );
    final firstFraction =
        (firstAt - startedAt).inMicroseconds / duration.inMicroseconds;
    expect(firstFraction, greaterThan(0));
    expect(firstFraction, lessThan(.1));
    final first = snapshot();
    final remainingToMiddle =
        (duration.inMicroseconds * .4).round() -
        (firstAt - startedAt).inMicroseconds;
    final middleAt = await _pumpTimestamp(
      tester,
      Duration(microseconds: math.max(0, remainingToMiddle)),
    );
    final middle = snapshot();
    final remainingToTarget =
        (duration.inMicroseconds * .85).round() -
        (middleAt - startedAt).inMicroseconds;
    var lastAt = await _pumpTimestamp(
      tester,
      Duration(microseconds: math.max(0, remainingToTarget)),
    );
    for (var step = 0; step < 200; step++) {
      if ((lastAt - startedAt).inMicroseconds >=
          duration.inMicroseconds * .97) {
        break;
      }
      lastAt = await _pumpTimestamp(tester, const Duration(milliseconds: 1));
    }
    final lastFraction =
        (lastAt - startedAt).inMicroseconds / duration.inMicroseconds;
    expect(lastFraction, greaterThanOrEqualTo(.97));
    expect(lastFraction, lessThan(1));
    final last = snapshot();
    await tester.pumpAndSettle();
    final end = snapshot();
    final result = (
      immediate: await _imagePixels(immediate),
      first: await _imagePixels(first),
      middle: await _imagePixels(middle),
      last: await _imagePixels(last),
      end: await _imagePixels(end),
      middleFraction:
          (middleAt - startedAt).inMicroseconds / duration.inMicroseconds,
      lastFraction: lastFraction,
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(await _boundaryPixels(tester, capture), orderedEquals(result.end));
    return result;
  } finally {
    for (final image in images) {
      image.dispose();
    }
  }
}

void _expectPixelNear(
  Uint8List pixels,
  int index,
  List<int> expected,
  int tolerance,
) {
  for (var channel = 0; channel < 4; channel++) {
    expect(
      pixels[index + channel],
      closeTo(expected[channel], tolerance),
      reason: 'premultiplied topology pixel, channel=$channel',
    );
  }
}
