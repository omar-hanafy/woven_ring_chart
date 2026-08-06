// The demo lab itself: that every control is wired to the ring and that
// driving them cannot break the chart.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woven_ring_chart/woven_ring_chart.dart';
import 'package:woven_ring_chart_example/main.dart';

void main() {
  group('demo app', () {
    testWidgets('smoke test exposes all three validation tabs', (
      WidgetTester tester,
    ) async {
      // The narrow demo layout gives its form fields the available width;
      // this keeps the smoke test focused on navigation instead of desktop
      // font-metric overflow in the fixed-width wide controls rail.
      await tester.binding.setSurfaceSize(const Size(850, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(const WovenRingDemoApp());
      await tester.pumpAndSettle();

      expect(find.text('woven_ring_chart'), findsOneWidget);
      expect(
        find.text('Every control, every state, every animated path'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey<String>('playground-tab')), findsOne);
      expect(find.byKey(const ValueKey<String>('matrix-tab')), findsOne);
      expect(find.byKey(const ValueKey<String>('states-tab')), findsOne);
      expect(find.byKey(const ValueKey<String>('playground-ring')), findsOne);
      expect(
        find.text('4 snakes | Solid | No border | clockwise'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey<String>('replay-button')), findsOne);
      expect(
        find.byKey(const ValueKey<String>('update-data-button')),
        findsOne,
      );

      await tester.tap(find.byKey(const ValueKey<String>('matrix-tab')));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Full solid/gradient, border/no-border, CW/CCW cross-product',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey<String>('matrix-case-0')), findsOne);
      expect(find.byKey(const ValueKey<String>('matrix-case-9')), findsOne);
      expect(find.byKey(const ValueKey<String>('matrix-case-11')), findsOne);
      expect(find.text('CW | solid | no border'), findsOneWidget);
      expect(
        find.text('Diagnostic gradient | high contrast | no border'),
        findsOneWidget,
      );
      expect(
        find.text('Solid | diagnostic alternating border'),
        findsOneWidget,
      );
      expect(
        find.text('Mixed fill | mixed border | non-cardinal CCW'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey<String>('states-tab')));
      await tester.pump();
      // Do not pumpAndSettle here: the loading case intentionally owns a
      // repeating ticker while this tab is visible.
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.byKey(const ValueKey<String>('state-case-0')), findsOne);
      expect(find.byKey(const ValueKey<String>('state-case-7')), findsOne);
      expect(find.text('Empty / no data'), findsOneWidget);
      expect(find.text('Loading'), findsOneWidget);
      expect(find.text('Single 100% | jointed'), findsOneWidget);
      expect(find.text('Optional head lift'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
      expect(tester.binding.transientCallbackCount, 0);
    });

    testWidgets('all geometry sliders accept both endpoints safely', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(850, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(const WovenRingDemoApp());
      await tester.pumpAndSettle();

      final Finder ring = find.byKey(const ValueKey<String>('playground-ring'));

      Future<void> exerciseSlider({
        required int index,
        required double minimum,
        required double maximum,
        required String minimumLabel,
        required String maximumLabel,
        required double Function(WovenRingStyle style) readStyle,
        required double expectedMinimumStyle,
        required double expectedMaximumStyle,
      }) async {
        final Finder slider = find.byType(Slider).at(index);

        await _dragSliderToEndpoint(tester, slider, toMaximum: false);
        expect(tester.widget<Slider>(slider).value, closeTo(minimum, 1e-12));
        expect(find.text(minimumLabel), findsOneWidget);
        expect(
          readStyle(_paintedStyle(tester, ring)),
          closeTo(expectedMinimumStyle, 1e-12),
        );
        expect(tester.takeException(), isNull);

        await _dragSliderToEndpoint(tester, slider, toMaximum: true);
        expect(tester.widget<Slider>(slider).value, closeTo(maximum, 1e-12));
        expect(find.text(maximumLabel), findsOneWidget);
        expect(
          readStyle(_paintedStyle(tester, ring)),
          closeTo(expectedMaximumStyle, 1e-12),
        );
        expect(tester.takeException(), isNull);
      }

      await exerciseSlider(
        index: 0,
        minimum: 0.15,
        maximum: 0.25,
        minimumLabel: 'Band: 15%',
        maximumLabel: 'Band: 25%',
        readStyle: (WovenRingStyle style) => style.resolvedBandFraction,
        expectedMinimumStyle: 0.15,
        expectedMaximumStyle: 0.25,
      );
      await exerciseSlider(
        index: 1,
        minimum: 0.30,
        maximum: 0.90,
        minimumLabel: 'Overlap: 30%',
        maximumLabel: 'Overlap: 90%',
        readStyle: (WovenRingStyle style) => style.resolvedOverlapFraction,
        expectedMinimumStyle: 0.30,
        expectedMaximumStyle: 0.90,
      );
      await exerciseSlider(
        index: 2,
        minimum: -180,
        maximum: 180,
        minimumLabel: 'Start angle: -180 degrees',
        maximumLabel: 'Start angle: 180 degrees',
        readStyle: (WovenRingStyle style) => style.resolvedStartAngle,
        expectedMinimumStyle: -math.pi,
        expectedMaximumStyle: math.pi,
      );

      // Exercise another frame with the exact 90% overlap endpoint retained.
      // This is the frame that used to assert after floating-point drift.
      await tester.pump();
      expect(_paintedStyle(tester, ring).resolvedOverlapFraction, 0.9);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'diagnostic styles are explicit while production defaults stay flat',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(850, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(const WovenRingDemoApp());
        await tester.pumpAndSettle();

        final Finder playgroundRing = find.byKey(
          const ValueKey<String>('playground-ring'),
        );
        List<WovenSnake> painted = _paintedSnakes(tester, playgroundRing);
        expect(painted, hasLength(4));
        expect(painted.every((WovenSnake snake) => snake.fill.isSolid), isTrue);
        expect(
          painted.every((WovenSnake snake) => snake.border == null),
          isTrue,
        );
        expect(
          find.byKey(const ValueKey<String>('diagnostic-style-note')),
          findsNothing,
        );
        expect(
          find.text('4 snakes | Solid | No border | clockwise'),
          findsOneWidget,
        );

        final Finder fillControl = find.byKey(
          const ValueKey<String>('fill-control'),
        );
        await tester.ensureVisible(fillControl);
        await tester.pumpAndSettle();
        await tester.tap(fillControl);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Diagnostic gradient (high contrast)').last);
        await tester.pumpAndSettle();

        painted = _paintedSnakes(tester, playgroundRing);
        expect(
          painted.every((WovenSnake snake) {
            final double headLightness = HSLColor.fromColor(
              snake.fill.head,
            ).lightness;
            final double tailLightness = HSLColor.fromColor(
              snake.fill.tail,
            ).lightness;
            return !snake.fill.isSolid &&
                (headLightness - tailLightness).abs() >= 0.39;
          }),
          isTrue,
        );
        expect(
          find.byKey(const ValueKey<String>('diagnostic-style-note')),
          findsOneWidget,
        );
        expect(
          find.text(
            'Diagnostic contrast is intentionally exaggerated. Production defaults remain solid and borderless.',
          ),
          findsOneWidget,
        );

        final Finder borderControl = find.byKey(
          const ValueKey<String>('border-control'),
        );
        await tester.ensureVisible(borderControl);
        await tester.pumpAndSettle();
        await tester.tap(borderControl);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Diagnostic alternating (5%)').last);
        await tester.pumpAndSettle();

        painted = _paintedSnakes(tester, playgroundRing);
        for (var i = 0; i < painted.length; i++) {
          final WovenBorder? border = painted[i].border;
          if (i.isEven) {
            expect(border, isNull, reason: 'snake $i stays borderless');
          } else {
            expect(border, isNotNull, reason: 'snake $i is diagnostic');
            expect(border!.resolvedWidthFraction, 0.05);
          }
        }
        expect(
          find.text(
            '4 snakes | Diagnostic gradient (high contrast) | Diagnostic alternating (5%) | clockwise',
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Animate data toggles forward and back and retargets continuously',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(850, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(const WovenRingDemoApp());
        await tester.pumpAndSettle();

        final Finder ring = find.byKey(
          const ValueKey<String>('playground-ring'),
        );
        final Finder update = find.byKey(
          const ValueKey<String>('update-data-button'),
        );
        const List<double> base = <double>[25, 25, 25, 25];
        const List<double> alternate = <double>[18, 31, 23, 28];

        _expectVisibleDataFrame(tester, ring, count: 4);
        _expectSnakeValues(_paintedSnakes(tester, ring), base);

        await tester.tap(update);
        await tester.pump();
        _expectSnakeValues(_paintedSnakes(tester, ring), base);
        _expectVisibleDataFrame(tester, ring, count: 4);

        await tester.pump(const Duration(milliseconds: 225));
        final List<WovenSnake> forwardMiddle = _paintedSnakes(tester, ring);
        _expectVisibleDataFrame(tester, ring, count: 4);
        expect(_snakeValuesEqual(forwardMiddle, base), isFalse);
        expect(_snakeValuesEqual(forwardMiddle, alternate), isFalse);
        _expectCyclicOwnerMaskCompositor(tester, ring);

        await tester.pumpAndSettle();
        _expectSnakeValues(_paintedSnakes(tester, ring), alternate);
        _expectVisibleDataFrame(tester, ring, count: 4);

        await tester.tap(update);
        await tester.pump();
        _expectSnakeValues(_paintedSnakes(tester, ring), alternate);
        await tester.pumpAndSettle();
        _expectSnakeValues(_paintedSnakes(tester, ring), base);

        // Interrupt a second forward trip. The retarget frame must be exactly
        // the frame already on screen, not either endpoint or an empty ring.
        await tester.tap(update);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 150));
        final List<WovenSnake> beforeInterrupt = _paintedSnakes(tester, ring);
        _expectVisibleDataFrame(tester, ring, count: 4);

        await tester.tap(update);
        await tester.pump();
        final List<WovenSnake> afterInterrupt = _paintedSnakes(tester, ring);
        _expectSnakeContinuity(beforeInterrupt, afterInterrupt);
        _expectVisibleDataFrame(tester, ring, count: 4);

        await tester.pumpAndSettle();
        _expectSnakeValues(_paintedSnakes(tester, ring), base);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'ten rapid Animate data presses preserve every retarget frame',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(850, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(const WovenRingDemoApp());
        await tester.pumpAndSettle();

        final Finder ring = find.byKey(
          const ValueKey<String>('playground-ring'),
        );
        final Finder update = find.byKey(
          const ValueKey<String>('update-data-button'),
        );
        const List<double> base = <double>[25, 25, 25, 25];

        await tester.ensureVisible(update);
        await tester.pumpAndSettle();

        for (var press = 0; press < 10; press++) {
          final List<WovenSnake> before = _paintedSnakes(tester, ring);
          final List<double> beforeFractions = _paintedFractions(tester, ring);

          await tester.tap(update);
          await tester.pump();

          _expectSnakeContinuity(before, _paintedSnakes(tester, ring));
          _expectFractionContinuity(
            beforeFractions,
            _paintedFractions(tester, ring),
          );
          _expectVisibleDataFrame(tester, ring, count: 4);

          await tester.pump(Duration(milliseconds: press.isEven ? 25 : 40));
          _expectVisibleDataFrame(tester, ring, count: 4);
        }

        await tester.pumpAndSettle();
        _expectSnakeValues(_paintedSnakes(tester, ring), base);
        _expectVisibleDataFrame(tester, ring, count: 4);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('five rapid Replay intro presses restart one clean timeline', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(850, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(const WovenRingDemoApp());
      await tester.pumpAndSettle();

      final Finder ring = find.byKey(const ValueKey<String>('playground-ring'));
      final Finder replay = find.byKey(const ValueKey<String>('replay-button'));
      await tester.ensureVisible(replay);
      await tester.pumpAndSettle();

      for (var press = 0; press < 5; press++) {
        await tester.tap(replay);
        await tester.pump();
        expect(
          _introProgress(tester, ring),
          0.0,
          reason: 'replay press $press restarts the same intro controller',
        );
        _expectSnakeValues(_paintedSnakes(tester, ring), const <double>[
          25,
          25,
          25,
          25,
        ]);

        await tester.pump(const Duration(milliseconds: 35));
        expect(
          _introProgress(tester, ring),
          inExclusiveRange(0.0, 0.1),
          reason: 'replay press $press owns one advancing timeline',
        );
      }

      await tester.pump(const Duration(seconds: 1));
      expect(_introProgress(tester, ring), 1.0);
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Animate data preserves all ten snakes across interruption', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(850, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(const WovenRingDemoApp());
      await tester.pumpAndSettle();
      await _selectDemoDropdown(
        tester,
        key: 'scenario-control',
        option: 'Reference 2 | 10 snakes',
      );

      final Finder ring = find.byKey(const ValueKey<String>('playground-ring'));
      final Finder update = find.byKey(
        const ValueKey<String>('update-data-button'),
      );
      const List<double> base = <double>[10, 9, 11, 8, 12, 10, 9, 11, 8, 12];
      const List<double> alternate = <double>[
        6,
        14,
        8,
        12,
        9,
        15,
        7,
        11,
        10,
        8,
      ];

      await tester.ensureVisible(update);
      await tester.pumpAndSettle();
      _expectSnakeValues(_paintedSnakes(tester, ring), base);
      _expectVisibleDataFrame(tester, ring, count: 10);

      await tester.tap(update);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 175));
      final List<WovenSnake> beforeInterrupt = _paintedSnakes(tester, ring);
      _expectVisibleDataFrame(tester, ring, count: 10);
      expect(_snakeValuesEqual(beforeInterrupt, base), isFalse);
      expect(_snakeValuesEqual(beforeInterrupt, alternate), isFalse);

      await tester.tap(update);
      await tester.pump();
      _expectSnakeContinuity(beforeInterrupt, _paintedSnakes(tester, ring));
      _expectVisibleDataFrame(tester, ring, count: 10);
      await tester.pumpAndSettle();
      _expectSnakeValues(_paintedSnakes(tester, ring), base);

      await tester.tap(update);
      await tester.pumpAndSettle();
      _expectSnakeValues(_paintedSnakes(tester, ring), alternate);
      _expectVisibleDataFrame(tester, ring, count: 10);
      await tester.tap(update);
      await tester.pumpAndSettle();
      _expectSnakeValues(_paintedSnakes(tester, ring), base);
      _expectVisibleDataFrame(tester, ring, count: 10);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Animate data never swallows the tiny-value data frame', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(850, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(const WovenRingDemoApp());
      await tester.pumpAndSettle();
      await _selectDemoDropdown(
        tester,
        key: 'scenario-control',
        option: 'Tiny-value stress case',
      );

      final Finder ring = find.byKey(const ValueKey<String>('playground-ring'));
      final Finder update = find.byKey(
        const ValueKey<String>('update-data-button'),
      );
      const List<double> base = <double>[0.3, 39.7, 25, 35];
      const List<double> alternate = <double>[0.3, 30, 42, 27.7];

      await tester.ensureVisible(update);
      await tester.pumpAndSettle();
      _expectSnakeValues(_paintedSnakes(tester, ring), base);
      _expectVisibleDataFrame(tester, ring, count: 4, tinyValue: 0.3);

      await tester.tap(update);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      final List<WovenSnake> beforeInterrupt = _paintedSnakes(tester, ring);
      _expectVisibleDataFrame(tester, ring, count: 4, tinyValue: 0.3);
      expect(_snakeValuesEqual(beforeInterrupt, base), isFalse);
      expect(_snakeValuesEqual(beforeInterrupt, alternate), isFalse);

      await tester.tap(update);
      await tester.pump();
      _expectSnakeContinuity(beforeInterrupt, _paintedSnakes(tester, ring));
      _expectVisibleDataFrame(tester, ring, count: 4, tinyValue: 0.3);
      await tester.pumpAndSettle();
      _expectSnakeValues(_paintedSnakes(tester, ring), base);

      await tester.tap(update);
      await tester.pumpAndSettle();
      _expectSnakeValues(_paintedSnakes(tester, ring), alternate);
      _expectVisibleDataFrame(tester, ring, count: 4, tinyValue: 0.3);
      await tester.tap(update);
      await tester.pumpAndSettle();
      _expectSnakeValues(_paintedSnakes(tester, ring), base);
      _expectVisibleDataFrame(tester, ring, count: 4, tinyValue: 0.3);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'Animate data during the initial relay never blanks or restarts',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(850, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(const WovenRingDemoApp());
        await tester.pump(const Duration(milliseconds: 300));

        final Finder ring = find.byKey(
          const ValueKey<String>('playground-ring'),
        );
        final Finder update = find.byKey(
          const ValueKey<String>('update-data-button'),
        );
        expect(_introProgress(tester, ring), inExclusiveRange(0.0, 1.0));

        await tester.tap(update);
        await tester.pump();
        _expectVisibleDataFrame(
          tester,
          ring,
          count: 4,
          expectIntroComplete: false,
        );

        await tester.pump(const Duration(milliseconds: 450));
        expect(_introProgress(tester, ring), lessThan(1.0));

        await tester.pump(const Duration(milliseconds: 250));
        expect(_introProgress(tester, ring), 1.0);
        _expectSnakeValues(_paintedSnakes(tester, ring), const <double>[
          18,
          31,
          23,
          28,
        ]);
        _expectVisibleDataFrame(tester, ring, count: 4);
      },
    );

    testWidgets(
      'Animate data during replay never blanks or starts another intro',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(const Size(850, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(const WovenRingDemoApp());
        await tester.pumpAndSettle();

        final Finder ring = find.byKey(
          const ValueKey<String>('playground-ring'),
        );
        final Finder update = find.byKey(
          const ValueKey<String>('update-data-button'),
        );
        final Finder replay = find.byKey(
          const ValueKey<String>('replay-button'),
        );

        await tester.tap(replay);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(_introProgress(tester, ring), inExclusiveRange(0.0, 1.0));

        await tester.tap(update);
        await tester.pump();
        _expectVisibleDataFrame(
          tester,
          ring,
          count: 4,
          expectIntroComplete: false,
        );

        await tester.pump(const Duration(milliseconds: 450));
        expect(_introProgress(tester, ring), lessThan(1.0));

        await tester.pump(const Duration(milliseconds: 250));
        expect(_introProgress(tester, ring), 1.0);
        _expectSnakeValues(_paintedSnakes(tester, ring), const <double>[
          18,
          31,
          23,
          28,
        ]);
        _expectVisibleDataFrame(tester, ring, count: 4);
      },
    );
  });
}

Finder _customPaintFinder(Finder ring) {
  final Finder result = find.descendant(
    of: ring,
    matching: find.byType(CustomPaint),
  );
  expect(result, findsOneWidget);
  return result;
}

dynamic _painter(WidgetTester tester, Finder ring) {
  final CustomPaint customPaint = tester.widget<CustomPaint>(
    _customPaintFinder(ring),
  );
  expect(customPaint.painter, isNotNull);
  return customPaint.painter;
}

double _introProgress(WidgetTester tester, Finder ring) {
  final dynamic painter = _painter(tester, ring);
  // The production painter is intentionally private, while these public
  // constructor fields are the deterministic lifecycle state under test.
  // ignore: avoid_dynamic_calls
  return painter.introProgress as double;
}

List<WovenSnake> _paintedSnakes(WidgetTester tester, Finder ring) {
  final dynamic painter = _painter(tester, ring);
  // ignore: avoid_dynamic_calls
  return List<WovenSnake>.from(painter.snakes as List<WovenSnake>);
}

List<double> _paintedFractions(WidgetTester tester, Finder ring) {
  final dynamic painter = _painter(tester, ring);
  // ignore: avoid_dynamic_calls
  return List<double>.from(painter.fractions as List<double>);
}

WovenRingStyle _paintedStyle(WidgetTester tester, Finder ring) {
  final dynamic painter = _painter(tester, ring);
  // ignore: avoid_dynamic_calls
  return painter.style as WovenRingStyle;
}

Future<void> _dragSliderToEndpoint(
  WidgetTester tester,
  Finder slider, {
  required bool toMaximum,
}) async {
  await tester.ensureVisible(slider);
  await tester.pumpAndSettle();
  await tester.drag(slider, Offset(toMaximum ? 2000 : -2000, 0));
  await tester.pump();
}

Future<void> _selectDemoDropdown(
  WidgetTester tester, {
  required String key,
  required String option,
}) async {
  final Finder control = find.byKey(ValueKey<String>(key));
  await tester.ensureVisible(control);
  await tester.pumpAndSettle();
  await tester.tap(control);
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

void _expectVisibleDataFrame(
  WidgetTester tester,
  Finder ring, {
  required int count,
  double? tinyValue,
  bool expectIntroComplete = true,
}) {
  final List<WovenSnake> snakes = _paintedSnakes(tester, ring);
  expect(snakes, hasLength(count));
  expect(
    snakes.every(
      (WovenSnake snake) =>
          snake.value.isFinite && snake.value > 0 && snake.opacity == 1.0,
    ),
    isTrue,
    reason: 'the data transition must never expose an empty fallback frame',
  );
  if (tinyValue != null) {
    expect(snakes.first.value, closeTo(tinyValue, 1e-9));
  }
  if (expectIntroComplete) {
    expect(
      _introProgress(tester, ring),
      1.0,
      reason: 'Animate data must not restart the intro animation',
    );
  }
}

void _expectSnakeValues(List<WovenSnake> actual, List<double> expected) {
  expect(actual, hasLength(expected.length));
  for (var i = 0; i < expected.length; i++) {
    expect(actual[i].value, closeTo(expected[i], 1e-9), reason: 'snake $i');
  }
}

bool _snakeValuesEqual(List<WovenSnake> snakes, List<double> values) {
  if (snakes.length != values.length) return false;
  for (var i = 0; i < values.length; i++) {
    if ((snakes[i].value - values[i]).abs() > 1e-9) return false;
  }
  return true;
}

void _expectSnakeContinuity(List<WovenSnake> before, List<WovenSnake> after) {
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

void _expectFractionContinuity(List<double> before, List<double> after) {
  expect(after, hasLength(before.length));
  for (var i = 0; i < before.length; i++) {
    expect(after[i], closeTo(before[i], 1e-9), reason: 'fraction $i');
  }
}

_CompositorRecordingCanvas _recordRingPaint(WidgetTester tester, Finder ring) {
  final _CompositorRecordingCanvas canvas = _CompositorRecordingCanvas();
  final dynamic painter = _painter(tester, ring);
  // ignore: avoid_dynamic_calls
  painter.paint(canvas, tester.getSize(_customPaintFinder(ring)));
  expect(canvas.events, isNotEmpty);
  return canvas;
}

List<String> _expectCyclicOwnerMaskCompositor(
  WidgetTester tester,
  Finder ring,
) {
  final _CompositorRecordingCanvas canvas = _recordRingPaint(tester, ring);
  final List<WovenSnake> snakes = _paintedSnakes(tester, ring);
  expect(snakes.length, greaterThan(1));

  var cursor = 0;
  _CompositorEvent nextEvent(String reason) {
    expect(cursor, lessThan(canvas.events.length), reason: reason);
    return canvas.events[cursor++];
  }

  // Every snake first lays down an unmasked coverage fill in stable data
  // order. This guarantees antialiased coverage without depending on which
  // cyclic owner is later painted on top.
  for (var i = 0; i < snakes.length; i++) {
    final _CompositorEvent event = nextEvent('missing base fill for snake $i');
    expect(event.kind, _CompositorEventKind.drawPath, reason: 'base fill $i');
    _expectColorNear(
      event.color!,
      snakes[i].fill.head,
      reason: 'base fill color $i',
    );
  }

  // Each snake then owns exactly the portion inside its own silhouette and
  // outside its successor. The non-zero/even-odd pair is the cyclic shingle
  // rule, including the seam. Extra later passes, such as border clips, do not
  // make this assertion depend on a brittle total draw count.
  for (var i = 0; i < snakes.length; i++) {
    final _CompositorEvent ownPath = nextEvent(
      'missing owner path clip for snake $i',
    );
    expect(ownPath.kind, _CompositorEventKind.clipPath, reason: 'owner $i');
    expect(ownPath.fillType, PathFillType.nonZero, reason: 'owner path $i');

    final _CompositorEvent outsideSuccessor = nextEvent(
      'missing successor complement for snake $i',
    );
    expect(
      outsideSuccessor.kind,
      _CompositorEventKind.clipPath,
      reason: 'successor mask $i',
    );
    expect(
      outsideSuccessor.fillType,
      PathFillType.evenOdd,
      reason: 'successor complement $i',
    );

    final _CompositorEvent ownerFill = nextEvent(
      'missing masked owner fill for snake $i',
    );
    expect(ownerFill.kind, _CompositorEventKind.drawPath, reason: 'owner $i');
    _expectColorNear(
      ownerFill.color!,
      snakes[i].fill.head,
      reason: 'owner fill color $i',
    );
  }

  return <String>[
    for (final _CompositorEvent event in canvas.events.take(cursor))
      event.signature,
  ];
}

void _expectColorNear(Color actual, Color expected, {required String reason}) {
  const double oneChannelStep = 1 / 255 + 1e-6;
  expect(actual.a, closeTo(expected.a, oneChannelStep), reason: reason);
  expect(actual.r, closeTo(expected.r, oneChannelStep), reason: reason);
  expect(actual.g, closeTo(expected.g, oneChannelStep), reason: reason);
  expect(actual.b, closeTo(expected.b, oneChannelStep), reason: reason);
}

enum _CompositorEventKind { clipPath, drawPath }

class _CompositorEvent {
  const _CompositorEvent.clip(this.fillType)
    : kind = _CompositorEventKind.clipPath,
      color = null;

  const _CompositorEvent.draw(this.color)
    : kind = _CompositorEventKind.drawPath,
      fillType = null;

  final _CompositorEventKind kind;
  final PathFillType? fillType;
  final Color? color;

  String get signature => switch (kind) {
    _CompositorEventKind.clipPath => 'clip:${fillType!.name}',
    _CompositorEventKind.drawPath => 'draw',
  };
}

class _CompositorRecordingCanvas extends TestRecordingCanvas {
  final List<_CompositorEvent> events = <_CompositorEvent>[];

  @override
  void clipPath(Path path, {bool doAntiAlias = true}) {
    events.add(_CompositorEvent.clip(path.fillType));
  }

  @override
  void drawPath(Path path, Paint paint) {
    events.add(_CompositorEvent.draw(paint.color));
    super.drawPath(path, paint);
  }
}
