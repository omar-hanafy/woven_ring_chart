// `lib/main.dart` is what pub.dev renders under its Example tab, so it is the
// first code most people ever see of this package. This proves the thing they
// are about to paste actually runs.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woven_ring_chart/woven_ring_chart.dart';
import 'package:woven_ring_chart_example/main.dart';

void main() {
  testWidgets('the getting-started example draws the ring it describes', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    final WovenRingChart chart = tester.widget<WovenRingChart>(
      find.byType(WovenRingChart),
    );
    expect(chart.segments.map((WovenSegment s) => s.value).toList(), <double>[
      37,
      19,
      29,
      15,
    ]);
    expect(chart.semanticLabel, 'Spending by category');
    expect(find.text('100'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
    expect(tester.binding.transientCallbackCount, 0);
  });
}
