// The showcase page itself: that a visitor can reach every section, that the
// hero hands over a working install line, and that the playground's chart and
// its code panel move together.
//
// The panel's contents are proved honest in playground_config_test.dart. What
// is proved here is the wiring: that a control reaches both of them.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woven_ring_chart/woven_ring_chart.dart';
import 'package:woven_ring_chart_example/main.dart';
import 'package:woven_ring_chart_example/src/package_info.dart';
import 'package:woven_ring_chart_example/src/ui/code_block.dart';

void main() {
  group('the page', () {
    testWidgets('opens on the hero, with the ring and the install line', (
      WidgetTester tester,
    ) async {
      await _pumpShowcase(tester);

      expect(find.text('woven_ring_chart'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('hero-ring')), findsOne);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey<String>('install-line')))
            .data,
        kInstallLine,
      );
      expect(kInstallLine, startsWith('woven_ring_chart: ^'));
    });

    testWidgets('carries every section, in order, down one scroll', (
      WidgetTester tester,
    ) async {
      await _pumpShowcase(tester);

      // Reached in the order they appear, so this fails if one is dropped or
      // if the page stops scrolling part way.
      for (final String title in <String>[
        'Quick start',
        'Playground',
        'Fills and borders',
        'Animation',
        'Nothing, and nearly nothing',
        'Colours',
        'Accessibility',
        'This page is the package example.',
      ]) {
        await _scrollTo(tester, find.text(title));
      }
    });

    testWidgets('leaves nothing running once it is torn down', (
      WidgetTester tester,
    ) async {
      await _pumpShowcase(tester);
      // Far enough in to have inflated the loading ring and the card whose
      // data changes on a timer, both of which own repeating work.
      await _scrollTo(tester, find.text('Nothing, and nearly nothing'));
      await tester.pump(const Duration(milliseconds: 400));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
      expect(tester.binding.transientCallbackCount, 0);
    });
  });

  group('the hero', () {
    testWidgets('copies the dependency line to the clipboard', (
      WidgetTester tester,
    ) async {
      final List<String> copied = _recordClipboard(tester);
      await _pumpShowcase(tester);

      await tester.tap(
        find.byKey(const ValueKey<String>('copy-install-button')),
      );
      await tester.pump();

      expect(copied, <String>[kInstallLine]);
      expect(find.text('Copied'), findsOneWidget);
    });
  });

  group('quick start', () {
    testWidgets('draws exactly the values its snippet lists', (
      WidgetTester tester,
    ) async {
      await _pumpShowcase(tester);
      await _scrollTo(tester, find.text('Quick start'));

      final WovenRingChart chart = tester.widget<WovenRingChart>(
        find.byKey(const ValueKey<String>('quick-start-ring')),
      );
      expect(chart.segments.map((WovenSegment s) => s.value).toList(), <double>[
        37,
        19,
        29,
        15,
      ]);
      expect(chart.semanticLabel, 'Spending by category');

      final String source = _sourceOf(tester, find.byType(CodeBlock).first);
      for (final String value in <String>['37', '19', '29', '15']) {
        expect(source, contains(value));
      }
      expect(source, contains("semanticLabel: 'Spending by category'"));
    });
  });

  group('the playground', () {
    testWidgets('starts at the defaults, with nothing extra in the code', (
      WidgetTester tester,
    ) async {
      await _pumpShowcase(tester);
      await _scrollTo(tester, find.text('Playground'));

      expect(_playgroundSource(tester), isNot(contains('WovenRingStyle')));
      expect(_playgroundChart(tester).style, const WovenRingStyle());
    });

    testWidgets('moves the chart and the code together', (
      WidgetTester tester,
    ) async {
      await _pumpShowcase(tester);
      await _scrollTo(tester, find.text('Playground'));

      await _toggle(tester, 'clockwise-control');

      expect(_playgroundChart(tester).style.clockwise, isFalse);
      expect(_playgroundSource(tester), contains('clockwise: false,'));

      await _toggle(tester, 'shadow-control');

      expect(_playgroundChart(tester).style.shadow, isNotNull);
      expect(_playgroundSource(tester), contains('shadow: WovenShadow(),'));
    });

    testWidgets('highlighting a segment reaches the chart and the code', (
      WidgetTester tester,
    ) async {
      await _pumpShowcase(tester);
      await _scrollTo(tester, find.text('Playground'));

      expect(_playgroundChart(tester).highlightedIndex, isNull);

      await _toggle(tester, 'highlight-control');
      expect(_playgroundChart(tester).highlightedIndex, 0);
      expect(_playgroundSource(tester), contains('highlightedIndex: 0,'));

      await tester.tap(
        find.byKey(const ValueKey<String>('highlight-next-button')),
      );
      await tester.pump();
      expect(_playgroundChart(tester).highlightedIndex, 1);
      expect(_playgroundSource(tester), contains('highlightedIndex: 1,'));
    });

    testWidgets('a slider retunes both the chart and the code', (
      WidgetTester tester,
    ) async {
      await _pumpShowcase(tester);
      await _scrollTo(tester, find.text('Playground'));

      final Finder slider = find.byKey(
        const ValueKey<String>('thickness-slider'),
      );
      await tester.ensureVisible(slider);
      await tester.pump();

      // Drag the thumb to the far right: the widest ring the style allows.
      final Rect box = tester.getRect(slider);
      await tester.dragFrom(box.centerLeft, Offset(box.width, 0));
      await tester.pump();

      final double thickness = _playgroundChart(tester).style.thicknessFraction;
      expect(thickness, greaterThan(0.20));
      expect(
        _playgroundSource(tester),
        contains('thicknessFraction: $thickness,'),
      );
    });

    testWidgets('reset puts everything back', (WidgetTester tester) async {
      await _pumpShowcase(tester);
      await _scrollTo(tester, find.text('Playground'));

      await _toggle(tester, 'clockwise-control');
      await _toggle(tester, 'shadow-control');
      expect(_playgroundSource(tester), contains('WovenRingStyle'));

      final Finder reset = find.byKey(const ValueKey<String>('reset-button'));
      await tester.ensureVisible(reset);
      await tester.pump();
      await tester.tap(reset);
      await tester.pump();

      expect(_playgroundChart(tester).style, const WovenRingStyle());
      expect(_playgroundSource(tester), isNot(contains('WovenRingStyle')));
    });

    testWidgets('the code panel copies what it is showing', (
      WidgetTester tester,
    ) async {
      final List<String> copied = _recordClipboard(tester);
      await _pumpShowcase(tester);
      await _scrollTo(tester, find.text('Playground'));

      await _toggle(tester, 'clockwise-control');
      final String shown = _playgroundSource(tester);

      final Finder copy = find.descendant(
        of: find.byKey(const ValueKey<String>('playground-code')),
        matching: find.byKey(const ValueKey<String>('copy-code-button')),
      );
      await tester.ensureVisible(copy);
      await tester.pump();
      await tester.tap(copy);
      await tester.pump();

      expect(copied, <String>[shown]);
    });
  });

  group('the animation section', () {
    testWidgets('replays an entrance without disturbing the others', (
      WidgetTester tester,
    ) async {
      await _pumpShowcase(tester);
      await _scrollTo(tester, find.text('Animation'));

      final Finder replay = find.byKey(const ValueKey<String>('replay-sweep'));
      await tester.ensureVisible(replay);
      await tester.pump();
      await tester.tap(replay);
      await tester.pump(const Duration(milliseconds: 120));

      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey<String>('entrance-ring-sweep')),
        findsOne,
      );
    });

    testWidgets('offers no replay for the animation that has none', (
      WidgetTester tester,
    ) async {
      await _pumpShowcase(tester);
      await _scrollTo(tester, find.text('Animation'));

      final Finder replay = find.byKey(const ValueKey<String>('replay-none'));
      await tester.ensureVisible(replay);
      await tester.pump();
      expect(tester.widget<TextButton>(replay).onPressed, isNull);
    });
  });
}

// ------------------------------------------------------------------- helpers

/// A viewport wide enough for the side-by-side layout and short enough that the
/// list still has to be scrolled, which is how a visitor meets the page.
Future<void> _pumpShowcase(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1200, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(const WovenRingChartDemoApp());
  await tester.pump(const Duration(milliseconds: 1200));
}

/// Scrolls the page until [target] exists.
///
/// Deliberately drag-and-pump rather than `pumpAndSettle`: the loading ring and
/// the card whose data changes on a timer both own repeating work, so settling
/// the tree is something this page never does.
Future<void> _scrollTo(
  WidgetTester tester,
  Finder target, {
  int maxDrags = 80,
}) async {
  for (int i = 0; i < maxDrags; i++) {
    if (target.evaluate().isNotEmpty) {
      await tester.ensureVisible(target);
      await tester.pump();
      return;
    }
    await tester.drag(find.byType(ListView), const Offset(0, -260));
    await tester.pump(const Duration(milliseconds: 60));
  }
  fail('Scrolled the whole page without reaching $target.');
}

Future<void> _toggle(WidgetTester tester, String id) async {
  final Finder control = find.byKey(ValueKey<String>(id));
  await tester.ensureVisible(control);
  await tester.pump();
  await tester.tap(control);
  await tester.pump();
}

WovenRingChart _playgroundChart(WidgetTester tester) {
  return tester.widget<WovenRingChart>(
    find.byKey(const ValueKey<String>('playground-ring')),
  );
}

String _playgroundSource(WidgetTester tester) {
  return _sourceOf(
    tester,
    find.byKey(const ValueKey<String>('playground-code')),
  );
}

String _sourceOf(WidgetTester tester, Finder codeBlock) {
  return tester.widget<CodeBlock>(codeBlock).source;
}

/// Captures whatever the page puts on the clipboard.
List<String> _recordClipboard(WidgetTester tester) {
  final List<String> copied = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (MethodCall call) async {
      if (call.method == 'Clipboard.setData') {
        copied.add((call.arguments as Map<Object?, Object?>)['text'] as String);
      }
      return null;
    },
  );
  addTearDown(() {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );
  });
  return copied;
}
