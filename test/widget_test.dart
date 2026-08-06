// The painter internals and the widget lifecycle, checked through the
// public widget. The catalog is the gate; this file covers what the
// catalog deliberately does not reach into.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woven_ring_chart/woven_ring_chart.dart';

const ValueKey<String> _ringKey = ValueKey<String>('ring-under-test');

const List<WovenSnake> _initialSnakes = <WovenSnake>[
  WovenSnake(
    value: 1,
    fill: WovenFill.solid(WovenPalette.purple),
    semanticLabel: 'Purple, 1',
  ),
  WovenSnake(
    value: 1,
    fill: WovenFill.solid(WovenPalette.green),
    semanticLabel: 'Green, 1',
  ),
];

void main() {
  group('accessibility', () {
    testWidgets('publishes aggregate and per-snake fallback semantics', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle semantics = tester.ensureSemantics();

      await tester.pumpWidget(
        _host(
          const SizedBox.square(
            dimension: 180,
            child: WovenRing(
              key: _ringKey,
              snakes: _initialSnakes,
              intro: WovenRingIntro.none,
              semanticLabel: 'Quarterly distribution',
              semanticValue: 'Two visible entries',
            ),
          ),
        ),
      );

      expect(find.bySemanticsLabel('Quarterly distribution'), findsOneWidget);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Quarterly distribution')),
        matchesSemantics(
          label: 'Quarterly distribution',
          value: 'Two visible entries',
          isImage: true,
        ),
      );

      await tester.pumpWidget(
        _host(
          const SizedBox.square(
            dimension: 180,
            child: WovenRing(
              key: _ringKey,
              snakes: _initialSnakes,
              intro: WovenRingIntro.none,
            ),
          ),
        ),
      );

      expect(find.bySemanticsLabel('Purple, 1, Green, 1'), findsOneWidget);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Purple, 1, Green, 1')),
        matchesSemantics(label: 'Purple, 1, Green, 1', isImage: true),
      );
      semantics.dispose();
    });

    testWidgets('explicit aggregate semantics exclude decorative center text', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          _host(
            const SizedBox.square(
              dimension: 180,
              child: WovenRing(
                key: _ringKey,
                snakes: _initialSnakes,
                intro: WovenRingIntro.none,
                semanticLabel: 'Allocation chart',
                semanticValue: '42 percent',
                center: Text('42 percent'),
              ),
            ),
          ),
        );

        expect(find.text('42 percent'), findsOneWidget);
        expect(
          tester.getSemantics(find.bySemanticsLabel('Allocation chart')),
          matchesSemantics(
            label: 'Allocation chart',
            value: '42 percent',
            isImage: true,
          ),
        );
        expect(
          find.bySemanticsLabel('42 percent'),
          findsNothing,
          reason: 'center text is visual content of the aggregate image',
        );
      } finally {
        semantics.dispose();
      }
    });

    testWidgets(
      'fallback semantics omit non-visible and nonfinite snake labels',
      (WidgetTester tester) async {
        final SemanticsHandle semantics = tester.ensureSemantics();
        try {
          await tester.pumpWidget(
            _host(
              const SizedBox.square(
                dimension: 180,
                child: WovenRing(
                  key: _ringKey,
                  snakes: <WovenSnake>[
                    WovenSnake(
                      value: 4,
                      fill: WovenFill.solid(WovenPalette.blue),
                      semanticLabel: 'Blue visible',
                    ),
                    WovenSnake(
                      value: 0,
                      fill: WovenFill.solid(WovenPalette.purple),
                      semanticLabel: 'Zero hidden',
                    ),
                    WovenSnake(
                      value: -2,
                      fill: WovenFill.solid(WovenPalette.green),
                      semanticLabel: 'Negative hidden',
                    ),
                    WovenSnake(
                      value: double.nan,
                      fill: WovenFill.solid(WovenPalette.amber),
                      semanticLabel: 'NaN hidden',
                    ),
                    WovenSnake(
                      value: double.infinity,
                      fill: WovenFill.solid(WovenPalette.rose),
                      semanticLabel: 'Infinity hidden',
                    ),
                    WovenSnake(
                      value: 6,
                      fill: WovenFill.solid(WovenPalette.navy),
                      semanticLabel: 'Navy visible',
                    ),
                  ],
                  intro: WovenRingIntro.none,
                ),
              ),
            ),
          );

          const String visibleLabels = 'Blue visible, Navy visible';
          expect(find.bySemanticsLabel(visibleLabels), findsOneWidget);
          expect(
            tester.getSemantics(find.bySemanticsLabel(visibleLabels)),
            matchesSemantics(label: visibleLabels, isImage: true),
          );
          for (final String hiddenLabel in <String>[
            'Zero hidden',
            'Negative hidden',
            'NaN hidden',
            'Infinity hidden',
          ]) {
            expect(find.bySemanticsLabel(hiddenLabel), findsNothing);
          }
        } finally {
          semantics.dispose();
        }
      },
    );

    testWidgets('marks loading announcements as a live image region', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle semantics = tester.ensureSemantics();

      await tester.pumpWidget(
        _host(
          const SizedBox.square(
            dimension: 180,
            child: WovenRing.loading(
              key: _ringKey,
              semanticLabel: 'Loading chart',
              semanticValue: 'Please wait',
            ),
          ),
        ),
      );

      expect(
        tester.getSemantics(find.bySemanticsLabel('Loading chart')),
        matchesSemantics(
          label: 'Loading chart',
          value: 'Please wait',
          isImage: true,
          isLiveRegion: true,
        ),
      );

      await tester.pumpWidget(const SizedBox.shrink());
      semantics.dispose();
    });

    testWidgets(
      'empty, single, and selected states keep meaningful semantics',
      (WidgetTester tester) async {
        final SemanticsHandle semantics = tester.ensureSemantics();

        await tester.pumpWidget(
          _host(
            const SizedBox.square(
              dimension: 180,
              child: WovenRing.empty(
                key: _ringKey,
                semanticLabel: 'No distribution data',
                semanticValue: 'Empty',
              ),
            ),
          ),
        );
        expect(
          tester.getSemantics(find.bySemanticsLabel('No distribution data')),
          matchesSemantics(
            label: 'No distribution data',
            value: 'Empty',
            isImage: true,
          ),
        );

        await tester.pumpWidget(
          _host(
            const SizedBox.square(
              dimension: 180,
              child: WovenRing(
                key: _ringKey,
                snakes: <WovenSnake>[
                  WovenSnake(
                    value: 100,
                    fill: WovenFill.solid(WovenPalette.purple),
                    semanticLabel: 'Purple, 100 percent',
                  ),
                ],
                intro: WovenRingIntro.none,
              ),
            ),
          ),
        );
        expect(
          tester.getSemantics(find.bySemanticsLabel('Purple, 100 percent')),
          matchesSemantics(label: 'Purple, 100 percent', isImage: true),
        );

        await tester.pumpWidget(
          _host(
            const SizedBox.square(
              dimension: 180,
              child: WovenRing(
                key: _ringKey,
                snakes: _initialSnakes,
                intro: WovenRingIntro.none,
                highlighted: 1,
                semanticLabel: 'Selected distribution',
                semanticValue: 'Green selected',
              ),
            ),
          ),
        );
        expect(_paintedHighlighted(tester, find.byKey(_ringKey)), 1);
        expect(
          tester.getSemantics(find.bySemanticsLabel('Selected distribution')),
          matchesSemantics(
            label: 'Selected distribution',
            value: 'Green selected',
            isImage: true,
          ),
        );

        await tester.pumpWidget(
          _host(
            const SizedBox.square(
              dimension: 180,
              child: WovenRing(
                key: _ringKey,
                snakes: _initialSnakes,
                intro: WovenRingIntro.none,
                highlighted: 0,
                semanticLabel: 'Selected distribution',
                semanticValue: 'Purple selected',
              ),
            ),
          ),
        );
        expect(_paintedHighlighted(tester, find.byKey(_ringKey)), 0);
        expect(
          tester.getSemantics(find.bySemanticsLabel('Selected distribution')),
          matchesSemantics(
            label: 'Selected distribution',
            value: 'Purple selected',
            isImage: true,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        semantics.dispose();
      },
    );
  });

  group('layout and fallback state', () {
    testWidgets('normal empty data takes the neutral fallback path safely', (
      WidgetTester tester,
    ) async {
      const ValueKey<String> normalKey = ValueKey<String>('normal-empty');
      const ValueKey<String> explicitKey = ValueKey<String>('explicit-empty');

      await tester.pumpWidget(
        _host(
          const Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SizedBox.square(
                dimension: 140,
                child: WovenRing(
                  key: normalKey,
                  snakes: <WovenSnake>[],
                  intro: WovenRingIntro.relay,
                ),
              ),
              SizedBox(width: 20),
              SizedBox.square(
                dimension: 140,
                child: WovenRing.empty(key: explicitKey),
              ),
            ],
          ),
        ),
      );

      expect(_paintedSnakes(tester, find.byKey(normalKey)), isEmpty);
      expect(_introProgress(tester, find.byKey(normalKey)), 1.0);
      expect(_paintedSnakes(tester, find.byKey(explicitKey)), isEmpty);
      expect(_introProgress(tester, find.byKey(explicitKey)), 1.0);
      expect(
        tester.getSize(_customPaintFinder(find.byKey(normalKey))),
        tester.getSize(_customPaintFinder(find.byKey(explicitKey))),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('uses the smallest bound and a safe unbounded default', (
      WidgetTester tester,
    ) async {
      const ValueKey<String> boxKey = ValueKey<String>('bounded-box');

      await tester.pumpWidget(
        _host(
          const SizedBox(
            key: boxKey,
            width: 320,
            height: 180,
            child: WovenRing(
              key: _ringKey,
              snakes: _initialSnakes,
              intro: WovenRingIntro.none,
            ),
          ),
        ),
      );

      final Finder boundedPaint = _customPaintFinder(find.byKey(_ringKey));
      expect(tester.getSize(boundedPaint), const Size.square(180));
      expect(
        tester.getCenter(boundedPaint),
        tester.getCenter(find.byKey(boxKey)),
      );

      await tester.pumpWidget(
        _host(
          const UnconstrainedBox(
            child: WovenRing(
              key: _ringKey,
              snakes: _initialSnakes,
              intro: WovenRingIntro.none,
            ),
          ),
        ),
      );

      expect(
        tester.getSize(_customPaintFinder(find.byKey(_ringKey))),
        const Size.square(240),
      );

      await tester.pumpWidget(
        _host(
          const UnconstrainedBox(
            child: SizedBox(
              height: 150,
              child: WovenRing(
                key: _ringKey,
                snakes: _initialSnakes,
                intro: WovenRingIntro.none,
              ),
            ),
          ),
        ),
      );

      expect(
        tester.getSize(_customPaintFinder(find.byKey(_ringKey))),
        const Size.square(150),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('intro animation', () {
    for (final WovenRingIntro intro in <WovenRingIntro>[
      WovenRingIntro.relay,
      WovenRingIntro.bloom,
    ]) {
      testWidgets('$intro advances from an unfinished to a completed drawing', (
        WidgetTester tester,
      ) async {
        await tester.pumpWidget(
          _host(
            SizedBox.square(
              dimension: 180,
              child: WovenRing(
                key: _ringKey,
                snakes: _initialSnakes,
                intro: intro,
                introDuration: const Duration(seconds: 1),
              ),
            ),
          ),
        );

        final dynamic startPainter = _painter(tester, find.byKey(_ringKey));
        expect(_paintedIntro(tester, find.byKey(_ringKey)), intro);
        expect(_introProgress(tester, find.byKey(_ringKey)), 0.0);

        await tester.pump(const Duration(milliseconds: 500));
        final dynamic middlePainter = _painter(tester, find.byKey(_ringKey));
        expect(
          _introProgress(tester, find.byKey(_ringKey)),
          inExclusiveRange(0.45, 0.60),
        );
        // ignore: avoid_dynamic_calls
        expect(middlePainter.shouldRepaint(startPainter), isTrue);

        await tester.pump(const Duration(milliseconds: 500));
        final dynamic endPainter = _painter(tester, find.byKey(_ringKey));
        expect(_introProgress(tester, find.byKey(_ringKey)), 1.0);
        // ignore: avoid_dynamic_calls
        expect(endPainter.shouldRepaint(middlePainter), isTrue);
      });
    }

    for (final WovenRingIntro intro in <WovenRingIntro>[
      WovenRingIntro.relay,
      WovenRingIntro.bloom,
    ]) {
      testWidgets('$intro keeps its timeline through a mid-flight retarget', (
        WidgetTester tester,
      ) async {
        final GlobalKey<_MutableRingHarnessState> harnessKey =
            GlobalKey<_MutableRingHarnessState>();
        const List<WovenSnake> replacement = <WovenSnake>[
          WovenSnake(value: 3, fill: WovenFill.solid(WovenPalette.blue)),
          WovenSnake(value: 1, fill: WovenFill.solid(WovenPalette.amber)),
        ];

        await tester.pumpWidget(
          _host(
            _MutableRingHarness(
              key: harnessKey,
              initialSnakes: _initialSnakes,
              intro: intro,
            ),
          ),
        );
        final Finder ring = find.byKey(_ringKey);

        await tester.pump(const Duration(milliseconds: 250));
        final double introBeforeData = _introProgress(tester, ring);
        expect(introBeforeData, inExclusiveRange(0.0, 1.0));

        harnessKey.currentState!.replace(replacement);
        await tester.pump();
        expect(_paintedSnakes(tester, ring), _initialSnakes);
        expect(_introProgress(tester, ring), introBeforeData);

        await tester.pump(const Duration(milliseconds: 200));
        final List<WovenSnake> beforeRetarget = _paintedSnakes(tester, ring);
        final List<double> fractionsBeforeRetarget = _paintedFractions(
          tester,
          ring,
        );
        final double introBeforeRetarget = _introProgress(tester, ring);
        expect(_snakeValuesEqual(beforeRetarget, <double>[1, 1]), isFalse);
        expect(_snakeValuesEqual(beforeRetarget, <double>[3, 1]), isFalse);
        expect(introBeforeRetarget, greaterThan(introBeforeData));
        expect(introBeforeRetarget, lessThan(1.0));
        _expectVisibleDataFrame(
          tester,
          ring,
          count: 2,
          expectIntroComplete: false,
        );

        harnessKey.currentState!.replace(_initialSnakes);
        await tester.pump();
        _expectSnakeContinuity(beforeRetarget, _paintedSnakes(tester, ring));
        _expectFractionContinuity(
          fractionsBeforeRetarget,
          _paintedFractions(tester, ring),
        );
        expect(_introProgress(tester, ring), introBeforeRetarget);
        expect(_paintedIntro(tester, ring), intro);
        _expectVisibleDataFrame(
          tester,
          ring,
          count: 2,
          expectIntroComplete: false,
        );

        await tester.pump(const Duration(seconds: 1));
        expect(_introProgress(tester, ring), 1.0);
        expect(_paintedSnakes(tester, ring), _initialSnakes);
        await tester.pumpAndSettle();
        expect(tester.binding.transientCallbackCount, 0);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets(
      'cyclic owner masks stay identical across relay frames 59 and 60',
      (WidgetTester tester) async {
        const List<WovenSnake> snakes = <WovenSnake>[
          WovenSnake(value: 25, fill: WovenFill.solid(WovenPalette.purple)),
          WovenSnake(value: 25, fill: WovenFill.solid(WovenPalette.green)),
          WovenSnake(value: 25, fill: WovenFill.solid(WovenPalette.amber)),
          WovenSnake(value: 25, fill: WovenFill.solid(WovenPalette.rose)),
        ];

        await tester.pumpWidget(
          _host(
            const SizedBox.square(
              dimension: 180,
              child: WovenRing(
                key: _ringKey,
                snakes: snakes,
                intro: WovenRingIntro.relay,
                introDuration: Duration(seconds: 1),
              ),
            ),
          ),
        );

        await tester.pump(const Duration(milliseconds: 966));
        expect(
          _introProgress(tester, find.byKey(_ringKey)),
          inExclusiveRange(0.0, 1.0),
        );
        final List<String> frame59 = _expectCyclicOwnerMaskCompositor(
          tester,
          find.byKey(_ringKey),
        );

        await tester.pump(const Duration(milliseconds: 34));
        expect(_introProgress(tester, find.byKey(_ringKey)), 1.0);
        final List<String> frame60 = _expectCyclicOwnerMaskCompositor(
          tester,
          find.byKey(_ringKey),
        );
        expect(frame60, orderedEquals(frame59));
      },
    );

    testWidgets('controller replay restarts a completed relay exactly once', (
      WidgetTester tester,
    ) async {
      final WovenRingController controller = WovenRingController();

      await tester.pumpWidget(
        _host(
          SizedBox.square(
            dimension: 180,
            child: WovenRing(
              key: _ringKey,
              snakes: _initialSnakes,
              intro: WovenRingIntro.relay,
              introDuration: const Duration(seconds: 1),
              controller: controller,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(_introProgress(tester, find.byKey(_ringKey)), 1.0);

      controller.replay();
      await tester.pump();
      expect(_introProgress(tester, find.byKey(_ringKey)), 0.0);

      await tester.pump(const Duration(milliseconds: 250));
      expect(
        _introProgress(tester, find.byKey(_ringKey)),
        inExclusiveRange(0.0, 0.5),
      );
      await tester.pump(const Duration(milliseconds: 750));
      expect(_introProgress(tester, find.byKey(_ringKey)), 1.0);

      await tester.pumpWidget(const SizedBox.shrink());
      controller.replay();
      expect(tester.takeException(), isNull);
      controller.dispose();
    });

    testWidgets('empty to data uses the configured intro instead of blinking', (
      WidgetTester tester,
    ) async {
      final GlobalKey<_MutableRingHarnessState> harnessKey =
          GlobalKey<_MutableRingHarnessState>();

      await tester.pumpWidget(
        _host(
          _MutableRingHarness(
            key: harnessKey,
            initialSnakes: const <WovenSnake>[],
            intro: WovenRingIntro.bloom,
          ),
        ),
      );
      expect(_introProgress(tester, find.byKey(_ringKey)), 1.0);

      harnessKey.currentState!.replace(_initialSnakes);
      await tester.pump();
      expect(_introProgress(tester, find.byKey(_ringKey)), 0.0);
      expect(_paintedSnakes(tester, find.byKey(_ringKey)), _initialSnakes);

      await tester.pump(const Duration(milliseconds: 500));
      expect(
        _introProgress(tester, find.byKey(_ringKey)),
        inExclusiveRange(0.45, 0.60),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(_introProgress(tester, find.byKey(_ringKey)), 1.0);
    });
  });

  group('data transitions', () {
    testWidgets('stretches and crossfades replacement data in place', (
      WidgetTester tester,
    ) async {
      final GlobalKey<_MutableRingHarnessState> harnessKey =
          GlobalKey<_MutableRingHarnessState>();
      const List<WovenSnake> replacement = <WovenSnake>[
        WovenSnake(value: 3, fill: WovenFill.solid(WovenPalette.blue)),
        WovenSnake(value: 1, fill: WovenFill.solid(WovenPalette.amber)),
      ];

      await tester.pumpWidget(
        _host(
          _MutableRingHarness(key: harnessKey, initialSnakes: _initialSnakes),
        ),
      );

      harnessKey.currentState!.replace(replacement);
      await tester.pump();
      List<WovenSnake> painted = _paintedSnakes(tester, find.byKey(_ringKey));
      expect(painted[0].value, 1.0);
      expect(painted[0].fill, _initialSnakes[0].fill);

      await tester.pump(const Duration(milliseconds: 500));
      painted = _paintedSnakes(tester, find.byKey(_ringKey));
      expect(painted[0].value, closeTo(2.0, 0.001));
      expect(painted[0].fill.head, isNot(_initialSnakes[0].fill.head));
      expect(painted[0].fill.head, isNot(replacement[0].fill.head));

      await tester.pump(const Duration(milliseconds: 500));
      painted = _paintedSnakes(tester, find.byKey(_ringKey));
      expect(painted, replacement);
    });

    testWidgets(
      'CW, CCW, and ring style switches preserve an active data frame',
      (WidgetTester tester) async {
        final GlobalKey<_MutableRingHarnessState> harnessKey =
            GlobalKey<_MutableRingHarnessState>();
        const WovenRingStyle initialStyle = WovenRingStyle(
          clockwise: true,
          gradientAxis: WovenGradientAxis.alongLength,
          gradientDirection: WovenGradientDirection.headToTail,
        );
        const List<WovenSnake> styled = <WovenSnake>[
          WovenSnake(
            value: 3,
            fill: WovenFill.gradient(
              head: WovenPalette.blue,
              tail: WovenPalette.purple,
            ),
            border: WovenBorder(),
          ),
          WovenSnake(
            value: 1,
            fill: WovenFill.gradient(
              head: WovenPalette.amber,
              tail: WovenPalette.rose,
            ),
            border: WovenBorder.darkerFill(),
          ),
        ];

        await tester.pumpWidget(
          _host(
            _MutableRingHarness(
              key: harnessKey,
              initialSnakes: _initialSnakes,
              initialStyle: initialStyle,
            ),
          ),
        );
        final Finder ring = find.byKey(_ringKey);

        harnessKey.currentState!.replace(styled);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        final List<WovenSnake> beforeCcw = _paintedSnakes(tester, ring);
        final List<double> fractionsBeforeCcw = _paintedFractions(tester, ring);
        expect(
          beforeCcw.any((WovenSnake snake) => snake.border != null),
          isTrue,
        );
        expect(beforeCcw, isNot(styled));

        harnessKey.currentState!.restyle(
          initialStyle.copyWith(
            clockwise: false,
            overlapFraction: 0.90,
            startAngle: math.pi / 8,
            gradientAxis: WovenGradientAxis.acrossBand,
            gradientDirection: WovenGradientDirection.tailToHead,
            lift: const WovenLift(),
          ),
        );
        await tester.pump();
        _expectSnakeContinuity(beforeCcw, _paintedSnakes(tester, ring));
        _expectFractionContinuity(
          fractionsBeforeCcw,
          _paintedFractions(tester, ring),
        );
        WovenRingStyle paintedStyle = _paintedStyle(tester, ring);
        expect(paintedStyle.clockwise, isFalse);
        expect(paintedStyle.gradientAxis, WovenGradientAxis.acrossBand);
        expect(
          paintedStyle.gradientDirection,
          WovenGradientDirection.tailToHead,
        );
        expect(paintedStyle.resolvedOverlapFraction, 0.90);
        expect(paintedStyle.resolvedStartAngle, closeTo(math.pi / 8, 1e-12));
        expect(paintedStyle.lift, isNotNull);

        await tester.pump(const Duration(milliseconds: 125));
        final List<WovenSnake> beforeCw = _paintedSnakes(tester, ring);
        final List<double> fractionsBeforeCw = _paintedFractions(tester, ring);
        harnessKey.currentState!.restyle(
          initialStyle.copyWith(
            overlapFraction: 0.30,
            startAngle: -math.pi / 2,
          ),
        );
        await tester.pump();
        _expectSnakeContinuity(beforeCw, _paintedSnakes(tester, ring));
        _expectFractionContinuity(
          fractionsBeforeCw,
          _paintedFractions(tester, ring),
        );
        paintedStyle = _paintedStyle(tester, ring);
        expect(paintedStyle.clockwise, isTrue);
        expect(paintedStyle.gradientAxis, WovenGradientAxis.alongLength);
        expect(
          paintedStyle.gradientDirection,
          WovenGradientDirection.headToTail,
        );
        expect(paintedStyle.resolvedOverlapFraction, 0.30);
        expect(paintedStyle.resolvedStartAngle, closeTo(-math.pi / 2, 1e-12));
        expect(paintedStyle.lift, isNull);

        await tester.pump(const Duration(milliseconds: 625));
        expect(_paintedSnakes(tester, ring), styled);
        _expectFractions(_paintedFractions(tester, ring), const <double>[
          0.75,
          0.25,
        ]);
        await tester.pumpAndSettle();
        expect(tester.binding.transientCallbackCount, 0);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'detects mutation when the caller reuses the same List object',
      (WidgetTester tester) async {
        final GlobalKey<_MutableRingHarnessState> harnessKey =
            GlobalKey<_MutableRingHarnessState>();
        const WovenSnake mutated = WovenSnake(
          value: 5,
          fill: WovenFill.solid(WovenPalette.rose),
          semanticLabel: 'Mutated, 5',
        );

        await tester.pumpWidget(
          _host(
            _MutableRingHarness(key: harnessKey, initialSnakes: _initialSnakes),
          ),
        );
        final List<WovenSnake> originalListObject =
            harnessKey.currentState!.snakes;

        harnessKey.currentState!.mutateFirstInPlace(mutated);
        await tester.pump();
        expect(
          identical(harnessKey.currentState!.snakes, originalListObject),
          isTrue,
        );
        expect(
          _paintedSnakes(tester, find.byKey(_ringKey))[0].value,
          _initialSnakes[0].value,
        );

        await tester.pump(const Duration(milliseconds: 500));
        expect(
          _paintedSnakes(tester, find.byKey(_ringKey))[0].value,
          closeTo(3.0, 0.001),
        );

        await tester.pump(const Duration(milliseconds: 500));
        final WovenSnake painted = _paintedSnakes(
          tester,
          find.byKey(_ringKey),
        ).first;
        expect(painted.value, mutated.value);
        expect(painted.fill, mutated.fill);
        expect(painted.semanticLabel, mutated.semanticLabel);
      },
    );

    testWidgets(
      'animates entering and leaving fractions without opacity popping',
      (WidgetTester tester) async {
        final GlobalKey<_MutableRingHarnessState> harnessKey =
            GlobalKey<_MutableRingHarnessState>();
        const List<WovenSnake> one = <WovenSnake>[
          WovenSnake(value: 1, fill: WovenFill.solid(WovenPalette.purple)),
        ];
        const List<WovenSnake> three = <WovenSnake>[
          WovenSnake(value: 1, fill: WovenFill.solid(WovenPalette.purple)),
          WovenSnake(value: 1, fill: WovenFill.solid(WovenPalette.green)),
          WovenSnake(value: 1, fill: WovenFill.solid(WovenPalette.amber)),
        ];

        await tester.pumpWidget(
          _host(_MutableRingHarness(key: harnessKey, initialSnakes: one)),
        );
        final Finder ring = find.byKey(_ringKey);

        expect(_paintedSnakes(tester, ring), one);
        _expectFractions(_paintedFractions(tester, ring), const <double>[1.0]);

        harnessKey.currentState!.replace(three);
        await tester.pump();
        expect(
          _paintedSnakes(tester, ring),
          one,
          reason: 't0 is the exact source endpoint, without padded entries',
        );
        _expectFractions(_paintedFractions(tester, ring), const <double>[1.0]);

        await tester.pump(const Duration(milliseconds: 500));
        List<WovenSnake> painted = _paintedSnakes(tester, ring);
        List<double> fractions = _paintedFractions(tester, ring);
        expect(painted, hasLength(3));
        expect(
          painted.every((WovenSnake snake) => snake.opacity == 1.0),
          isTrue,
        );
        expect(fractions, hasLength(3));
        expect(fractions[0], inExclusiveRange(1 / 3, 1.0));
        expect(fractions[1], inExclusiveRange(0.0, 1 / 3));
        expect(fractions[2], inExclusiveRange(0.0, 1 / 3));
        expect(
          fractions.reduce((double a, double b) => a + b),
          closeTo(1, 1e-9),
        );

        await tester.pump(const Duration(milliseconds: 500));
        expect(_paintedSnakes(tester, ring), three);
        _expectFractions(_paintedFractions(tester, ring), const <double>[
          1 / 3,
          1 / 3,
          1 / 3,
        ]);

        harnessKey.currentState!.replace(one);
        await tester.pump();
        expect(
          _paintedSnakes(tester, ring),
          three,
          reason: 't0 is the exact source endpoint, without padded entries',
        );
        _expectFractions(_paintedFractions(tester, ring), const <double>[
          1 / 3,
          1 / 3,
          1 / 3,
        ]);

        await tester.pump(const Duration(milliseconds: 500));
        painted = _paintedSnakes(tester, ring);
        fractions = _paintedFractions(tester, ring);
        expect(painted, hasLength(3));
        expect(
          painted.every((WovenSnake snake) => snake.opacity == 1.0),
          isTrue,
        );
        expect(fractions[0], inExclusiveRange(1 / 3, 1.0));
        expect(fractions[1], inExclusiveRange(0.0, 1 / 3));
        expect(fractions[2], inExclusiveRange(0.0, 1 / 3));
        expect(
          fractions.reduce((double a, double b) => a + b),
          closeTo(1, 1e-9),
        );

        await tester.pump(const Duration(milliseconds: 500));
        expect(
          _paintedSnakes(tester, ring),
          one,
          reason: 'completion drops transition-only padded entries',
        );
        _expectFractions(_paintedFractions(tester, ring), const <double>[1.0]);
      },
    );
  });

  group('motion preferences and ticker lifecycle', () {
    testWidgets('reduced motion completes intros, replays, and transitions', (
      WidgetTester tester,
    ) async {
      final WovenRingController controller = WovenRingController();
      final GlobalKey<_MutableRingHarnessState> harnessKey =
          GlobalKey<_MutableRingHarnessState>();
      const List<WovenSnake> replacement = <WovenSnake>[
        WovenSnake(value: 9, fill: WovenFill.solid(WovenPalette.navy)),
        WovenSnake(value: 1, fill: WovenFill.solid(WovenPalette.amber)),
      ];

      await tester.pumpWidget(
        _host(
          _MutableRingHarness(
            key: harnessKey,
            initialSnakes: _initialSnakes,
            intro: WovenRingIntro.relay,
            controller: controller,
          ),
          disableAnimations: true,
        ),
      );
      expect(_introProgress(tester, find.byKey(_ringKey)), 1.0);

      controller.replay();
      await tester.pump();
      expect(_introProgress(tester, find.byKey(_ringKey)), 1.0);

      harnessKey.currentState!.replace(replacement);
      await tester.pump();
      expect(_paintedSnakes(tester, find.byKey(_ringKey)), replacement);

      await tester.pumpWidget(
        _host(
          const SizedBox.square(
            dimension: 180,
            child: WovenRing.loading(key: _ringKey),
          ),
          disableAnimations: true,
        ),
      );
      final double spin = _spin(tester, find.byKey(_ringKey));
      await tester.pump(const Duration(seconds: 2));
      expect(_spin(tester, find.byKey(_ringKey)), spin);
      expect(tester.binding.transientCallbackCount, 0);

      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    });

    testWidgets(
      'enabling reduced motion mid-flight completes bloom and data motion',
      (WidgetTester tester) async {
        final WovenRingController controller = WovenRingController();
        final GlobalKey<_MutableRingHarnessState> harnessKey =
            GlobalKey<_MutableRingHarnessState>();
        const List<WovenSnake> replacement = <WovenSnake>[
          WovenSnake(value: 9, fill: WovenFill.solid(WovenPalette.navy)),
          WovenSnake(value: 1, fill: WovenFill.solid(WovenPalette.amber)),
        ];

        await tester.pumpWidget(
          _host(
            _MutableRingHarness(
              key: harnessKey,
              initialSnakes: _initialSnakes,
              intro: WovenRingIntro.bloom,
              controller: controller,
            ),
          ),
        );
        final Finder ring = find.byKey(_ringKey);

        await tester.pump(const Duration(milliseconds: 250));
        expect(_introProgress(tester, ring), inExclusiveRange(0.0, 1.0));

        harnessKey.currentState!.replace(replacement);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(_introProgress(tester, ring), inExclusiveRange(0.0, 1.0));
        expect(_paintedSnakes(tester, ring), isNot(replacement));

        await tester.pumpWidget(
          _host(
            _MutableRingHarness(
              key: harnessKey,
              initialSnakes: _initialSnakes,
              intro: WovenRingIntro.bloom,
              controller: controller,
            ),
            disableAnimations: true,
          ),
        );
        expect(_introProgress(tester, ring), 1.0);
        expect(_paintedSnakes(tester, ring), replacement);

        controller.replay();
        await tester.pump();
        expect(_introProgress(tester, ring), 1.0);
        expect(tester.binding.transientCallbackCount, 0);
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
      },
    );

    testWidgets('loading ticker starts, stops across modes, and disposes', (
      WidgetTester tester,
    ) async {
      final GlobalKey<_ModeHarnessState> harnessKey =
          GlobalKey<_ModeHarnessState>();

      await tester.pumpWidget(_host(_ModeHarness(key: harnessKey)));
      final double start = _spin(tester, find.byKey(_ringKey));
      await tester.pump(const Duration(milliseconds: 350));
      final double moving = _spin(tester, find.byKey(_ringKey));
      expect(moving, isNot(start));
      expect(moving, closeTo(0.25, 0.02));

      harnessKey.currentState!.showData();
      await tester.pump();
      final double stopped = _spin(tester, find.byKey(_ringKey));
      await tester.pump(const Duration(milliseconds: 700));
      expect(_spin(tester, find.byKey(_ringKey)), stopped);

      harnessKey.currentState!.showLoading();
      await tester.pump();
      final double resumedAt = _spin(tester, find.byKey(_ringKey));
      await tester.pump(const Duration(milliseconds: 350));
      expect(_spin(tester, find.byKey(_ringKey)), isNot(resumedAt));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
      expect(tester.binding.transientCallbackCount, 0);
    });
  });
}

Widget _host(Widget child, {bool disableAnimations = false}) {
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

double _spin(WidgetTester tester, Finder ring) {
  final dynamic painter = _painter(tester, ring);
  // ignore: avoid_dynamic_calls
  return painter.spin as double;
}

WovenRingIntro _paintedIntro(WidgetTester tester, Finder ring) {
  final dynamic painter = _painter(tester, ring);
  // ignore: avoid_dynamic_calls
  return painter.intro as WovenRingIntro;
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

int? _paintedHighlighted(WidgetTester tester, Finder ring) {
  final dynamic painter = _painter(tester, ring);
  // ignore: avoid_dynamic_calls
  return painter.highlighted as int?;
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

void _expectFractions(List<double> actual, List<double> expected) {
  expect(actual, hasLength(expected.length));
  for (var i = 0; i < expected.length; i++) {
    expect(actual[i], closeTo(expected[i], 1e-9), reason: 'fraction $i');
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

class _MutableRingHarness extends StatefulWidget {
  const _MutableRingHarness({
    super.key,
    required this.initialSnakes,
    this.initialStyle = const WovenRingStyle(),
    this.intro = WovenRingIntro.none,
    this.controller,
  });

  final List<WovenSnake> initialSnakes;
  final WovenRingStyle initialStyle;
  final WovenRingIntro intro;
  final WovenRingController? controller;

  @override
  State<_MutableRingHarness> createState() => _MutableRingHarnessState();
}

class _MutableRingHarnessState extends State<_MutableRingHarness> {
  late final List<WovenSnake> snakes = <WovenSnake>[...widget.initialSnakes];
  late WovenRingStyle style = widget.initialStyle;

  void replace(List<WovenSnake> value) {
    setState(() {
      snakes
        ..clear()
        ..addAll(value);
    });
  }

  void mutateFirstInPlace(WovenSnake value) {
    setState(() => snakes[0] = value);
  }

  void restyle(WovenRingStyle value) {
    setState(() => style = value);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 180,
      child: WovenRing(
        key: _ringKey,
        snakes: snakes,
        style: style,
        intro: widget.intro,
        introDuration: const Duration(seconds: 1),
        transitionDuration: const Duration(seconds: 1),
        controller: widget.controller,
      ),
    );
  }
}

class _ModeHarness extends StatefulWidget {
  const _ModeHarness({super.key});

  @override
  State<_ModeHarness> createState() => _ModeHarnessState();
}

class _ModeHarnessState extends State<_ModeHarness> {
  bool _loading = true;

  void showData() => setState(() => _loading = false);

  void showLoading() => setState(() => _loading = true);

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 180,
      child: _loading
          ? const WovenRing.loading(key: _ringKey)
          : const WovenRing(
              key: _ringKey,
              snakes: _initialSnakes,
              intro: WovenRingIntro.none,
            ),
    );
  }
}
