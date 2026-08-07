// Semantics: the aggregate description, joined segment labels, and what the centre widget contributes.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woven_ring_chart/woven_ring_chart.dart';

import '../support/chart_harness.dart';

void main() {
  group('accessibility', () {
    testWidgets('publishes aggregate and per-segment fallback semantics', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle semantics = tester.ensureSemantics();

      await tester.pumpWidget(
        host(
          const SizedBox.square(
            dimension: 180,
            child: WovenRingChart(
              key: kRingKey,
              segments: kInitialSegments,
              animation: WovenRingAnimation.none,
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
        host(
          const SizedBox.square(
            dimension: 180,
            child: WovenRingChart(
              key: kRingKey,
              segments: kInitialSegments,
              animation: WovenRingAnimation.none,
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
          host(
            const SizedBox.square(
              dimension: 180,
              child: WovenRingChart(
                key: kRingKey,
                segments: kInitialSegments,
                animation: WovenRingAnimation.none,
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
      'fallback semantics omit non-visible and nonfinite segment labels',
      (WidgetTester tester) async {
        final SemanticsHandle semantics = tester.ensureSemantics();
        try {
          await tester.pumpWidget(
            host(
              const SizedBox.square(
                dimension: 180,
                child: WovenRingChart(
                  key: kRingKey,
                  segments: <WovenSegment>[
                    WovenSegment(
                      value: 4,
                      fill: WovenFill.solid(WovenPalette.blue),
                      semanticLabel: 'Blue visible',
                    ),
                    WovenSegment(
                      value: 0,
                      fill: WovenFill.solid(WovenPalette.purple),
                      semanticLabel: 'Zero hidden',
                    ),
                    WovenSegment(
                      value: -2,
                      fill: WovenFill.solid(WovenPalette.green),
                      semanticLabel: 'Negative hidden',
                    ),
                    WovenSegment(
                      value: double.nan,
                      fill: WovenFill.solid(WovenPalette.amber),
                      semanticLabel: 'NaN hidden',
                    ),
                    WovenSegment(
                      value: double.infinity,
                      fill: WovenFill.solid(WovenPalette.rose),
                      semanticLabel: 'Infinity hidden',
                    ),
                    WovenSegment(
                      value: 6,
                      fill: WovenFill.solid(WovenPalette.navy),
                      semanticLabel: 'Navy visible',
                    ),
                  ],
                  animation: WovenRingAnimation.none,
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
        host(
          const SizedBox.square(
            dimension: 180,
            child: WovenRingChart.loading(
              key: kRingKey,
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
          host(
            const SizedBox.square(
              dimension: 180,
              child: WovenRingChart.empty(
                key: kRingKey,
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
          host(
            const SizedBox.square(
              dimension: 180,
              child: WovenRingChart(
                key: kRingKey,
                segments: <WovenSegment>[
                  WovenSegment(
                    value: 100,
                    fill: WovenFill.solid(WovenPalette.purple),
                    semanticLabel: 'Purple, 100 percent',
                  ),
                ],
                animation: WovenRingAnimation.none,
              ),
            ),
          ),
        );
        expect(
          tester.getSemantics(find.bySemanticsLabel('Purple, 100 percent')),
          matchesSemantics(label: 'Purple, 100 percent', isImage: true),
        );

        await tester.pumpWidget(
          host(
            const SizedBox.square(
              dimension: 180,
              child: WovenRingChart(
                key: kRingKey,
                segments: kInitialSegments,
                animation: WovenRingAnimation.none,
                highlightedIndex: 1,
                semanticLabel: 'Selected distribution',
                semanticValue: 'Green selected',
              ),
            ),
          ),
        );
        expect(paintedHighlightedIndex(tester, find.byKey(kRingKey)), 1);
        expect(
          tester.getSemantics(find.bySemanticsLabel('Selected distribution')),
          matchesSemantics(
            label: 'Selected distribution',
            value: 'Green selected',
            isImage: true,
          ),
        );

        await tester.pumpWidget(
          host(
            const SizedBox.square(
              dimension: 180,
              child: WovenRingChart(
                key: kRingKey,
                segments: kInitialSegments,
                animation: WovenRingAnimation.none,
                highlightedIndex: 0,
                semanticLabel: 'Selected distribution',
                semanticValue: 'Purple selected',
              ),
            ),
          ),
        );
        expect(paintedHighlightedIndex(tester, find.byKey(kRingKey)), 0);
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
}
