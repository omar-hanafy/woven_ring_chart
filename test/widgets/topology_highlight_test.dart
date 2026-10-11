import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woven_ring_chart/woven_ring_chart.dart';

import '../support/chart_harness.dart';

const int _side = 200;
const List<Color> _colors = <Color>[
  Color(0xFFFF0000),
  Color(0xFF00FF00),
  Color(0xFF0000FF),
  Color(0xFFFFD060),
];
const WovenBorder _highlight = WovenBorder(
  color: Color(0xFF000000),
  widthFraction: 0.05,
);

void main() {
  testWidgets('many to sole topology carries its destination highlight', (
    WidgetTester tester,
  ) async {
    final List<String> failures = <String>[];
    for (final bool clockwise in <bool>[true, false]) {
      for (var destination = 0; destination < 3; destination++) {
        final List<double> initial = <double>[
          for (var i = 0; i < 3; i++) i == destination ? 0 : 50,
        ];
        final int source = initial.indexWhere((double value) => value > 0);
        for (final int? highlighted in <int?>[destination, source, null]) {
          await tester.pumpWidget(const SizedBox.shrink());
          final WovenRingStyle style = WovenRingStyle(clockwise: clockwise);
          Widget chart(List<double> values) =>
              _chart(values, highlighted: highlighted, style: style);
          await tester.pumpWidget(chart(initial));
          final Uint8List before = await _capture(tester);
          await tester.pumpWidget(
            chart(<double>[
              for (var i = 0; i < 3; i++) i == destination ? 100 : 0,
            ]),
          );
          final Uint8List immediate = await _capture(tester);
          expect(immediate, before, reason: 'topology setup must not repaint');
          await tester.pump(const Duration(milliseconds: 999));
          final Uint8List nearEnd = await _capture(tester);
          await tester.pump(const Duration(milliseconds: 1));
          final Uint8List end = await _capture(tester);
          final Color expected = highlighted == destination
              ? const Color(0xFF000000)
              : _colors[destination];
          for (final (int, int) point in <(int, int)>[
            (100, 1),
            (198, 100),
            (100, 198),
            (1, 100),
          ]) {
            final List<int> actual = _pixel(nearEnd, point);
            final List<int> finalPixel = _pixel(end, point);
            expect(finalPixel, <int>[
              (expected.r * 255).round(),
              (expected.g * 255).round(),
              (expected.b * 255).round(),
              255,
            ]);
            final int change = _channelDelta(actual, finalPixel);
            if (change > 2) {
              failures.add(
                'clockwise=$clockwise destination=$destination '
                'highlighted=$highlighted point=$point '
                '999ms=$actual 1000ms=$finalPixel delta=$change',
              );
            }
          }
        }
      }
    }
    expect(failures, isEmpty, reason: failures.take(24).join('\n'));
  });

  testWidgets('retargeted topology preserves its highlight and current frame', (
    WidgetTester tester,
  ) async {
    for (final bool clockwise in <bool>[true, false]) {
      for (final bool reverse in <bool>[false, true]) {
        final List<double> initial = reverse
            ? <double>[0, 0, 50, 50]
            : <double>[50, 50, 0, 0];
        final int first = reverse ? 1 : 2;
        final int destination = reverse ? 0 : 3;
        final int source = initial.indexWhere((double value) => value > 0);
        final WovenRingStyle style = WovenRingStyle(clockwise: clockwise);
        for (final int highlighted in <int>[first, destination, source]) {
          await tester.pumpWidget(const SizedBox.shrink());
          Widget chart(List<double> values) =>
              _chart(values, highlighted: highlighted, style: style);
          await tester.pumpWidget(chart(initial));
          await tester.pumpWidget(
            chart(<double>[for (var i = 0; i < 4; i++) i == first ? 100 : 0]),
          );
          await tester.pump(const Duration(milliseconds: 400));
          final Uint8List before = await _capture(tester);
          await tester.pumpWidget(
            chart(<double>[
              for (var i = 0; i < 4; i++) i == destination ? 100 : 0,
            ]),
          );
          expect(await _capture(tester), before);
          await tester.pump(const Duration(milliseconds: 999));
          final Uint8List nearEnd = await _capture(tester);
          await tester.pump(const Duration(milliseconds: 1));
          final Uint8List end = await _capture(tester);
          for (final (int, int) point in <(int, int)>[
            (100, 1),
            (198, 100),
            (100, 198),
            (1, 100),
          ]) {
            expect(
              _channelDelta(_pixel(nearEnd, point), _pixel(end, point)),
              lessThanOrEqualTo(2),
              reason:
                  'clockwise=$clockwise reverse=$reverse '
                  'highlighted=$highlighted point=$point',
            );
          }
          final List<double> expectedFractions = <double>[
            for (var i = 0; i < 4; i++) i == destination ? 1 : 0,
          ];
          expect(
            paintedFractions(tester, find.byKey(kRingKey)),
            expectedFractions,
          );
        }
      }
    }
  });

  testWidgets('retained topology identity accepts live highlight styling', (
    WidgetTester tester,
  ) async {
    final Finder ring = find.byKey(kRingKey);
    const List<double> initial = <double>[50, 50, 0, 0];
    const List<double> first = <double>[0, 0, 100, 0];
    const List<double> destination = <double>[0, 0, 0, 100];
    await tester.pumpWidget(_chart(initial, highlighted: 2));
    await tester.pumpWidget(_chart(first, highlighted: 2));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpWidget(_chart(destination, highlighted: 2));
    await tester.pump(const Duration(milliseconds: 250));
    final List<WovenSegment> before = paintedSegments(tester, ring);
    final List<double> fractions = paintedFractions(tester, ring);

    const WovenBorder derived = WovenBorder.darkerFill(widthFraction: 0.05);
    await tester.pumpWidget(
      _chart(destination, highlighted: 3, highlight: derived),
    );
    List<WovenSegment> styled = paintedSegments(tester, ring);
    expect(paintedFractions(tester, ring), fractions);
    for (var i = 0; i < styled.length; i++) {
      expect(styled[i].fill, before[i].fill);
      expect(styled[i].opacity, before[i].opacity);
    }
    // The retained geometry anchor is still index 0. Its effective border
    // must already follow the new logical destination at index 3.
    expect(styled[0].border, isNotNull);
    expect(styled[0].border!.resolvedOpacity, greaterThan(0));
    expect(
      styled[0].border!.resolve(styled[0].fill, WovenPalette.surface),
      derived.resolve(styled[0].fill, WovenPalette.surface),
    );

    const WovenBorder p3 = WovenBorder(
      color: ui.Color.from(
        alpha: 0.75,
        red: 0,
        green: 1,
        blue: 0,
        colorSpace: ui.ColorSpace.displayP3,
      ),
      widthFraction: 0.05,
    );
    await tester.pumpWidget(_chart(destination, highlighted: 3, highlight: p3));
    styled = paintedSegments(tester, ring);
    expect(styled[0].border!.color, p3.color);
    expect(styled[0].border!.color!.colorSpace, ui.ColorSpace.displayP3);
    expect(styled[0].fill, before[0].fill);
    expect(paintedFractions(tester, ring), fractions);

    await tester.pumpWidget(_chart(destination, highlighted: null));
    expect(
      paintedSegments(tester, ring).every((WovenSegment s) => s.border == null),
      isTrue,
    );
    final Uint8List current = await _capture(tester);
    await tester.pumpWidget(_chart(first, highlighted: null));
    expect(await _capture(tester), current);
    await tester.pump(const Duration(seconds: 1));
    expect(paintedFractions(tester, ring), <double>[0, 0, 1, 0]);
  });
}

Widget _chart(
  List<double> values, {
  required int? highlighted,
  WovenRingStyle style = const WovenRingStyle(),
  WovenBorder highlight = _highlight,
}) => host(
  SizedBox.square(
    dimension: _side.toDouble(),
    child: WovenRingChart(
      key: kRingKey,
      animation: WovenRingAnimation.none,
      transitionDuration: const Duration(seconds: 1),
      style: style,
      highlightedIndex: highlighted,
      highlightBorder: highlight,
      segments: <WovenSegment>[
        for (var i = 0; i < values.length; i++)
          WovenSegment.solid(values[i], _colors[i]),
      ],
    ),
  ),
);

Future<Uint8List> _capture(WidgetTester tester) async {
  final CustomPaint paint = tester.widget<CustomPaint>(
    customPaintFinder(find.byKey(kRingKey)),
  );
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  paint.painter!.paint(ui.Canvas(recorder), const Size.square(200));
  final ui.Picture picture = recorder.endRecording();
  final ui.Image image = (await tester.runAsync(
    () => picture.toImage(_side, _side),
  ))!;
  final ByteData bytes = (await tester.runAsync<ByteData?>(
    () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
  ))!;
  final Uint8List result = Uint8List.fromList(bytes.buffer.asUint8List());
  image.dispose();
  picture.dispose();
  return result;
}

List<int> _pixel(Uint8List bytes, (int, int) point) {
  final int offset = (point.$2 * _side + point.$1) * 4;
  return bytes.sublist(offset, offset + 4);
}

int _channelDelta(List<int> a, List<int> b) {
  var delta = 0;
  for (var channel = 0; channel < 4; channel++) {
    final int distance = (a[channel] - b[channel]).abs();
    if (distance > delta) delta = distance;
  }
  return delta;
}
