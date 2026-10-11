import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woven_ring_chart/woven_ring_chart.dart';

const double _side = 480;

void main() {
  for (final _BorderCase c in <_BorderCase>[
    const _BorderCase('half-opacity border'),
    const _BorderCase('quarter-opacity border', opacity: 0.25),
    const _BorderCase('alpha border colour', color: Color(0x80000000)),
    const _BorderCase('partial segment opacity', segmentOpacity: 0.5),
    const _BorderCase('highlighted seam', highlightedIndex: 0),
    const _BorderCase('highlighted ordinary head', highlightedIndex: 2),
  ]) {
    testWidgets('each visible head border composites once: ${c.name}', (
      WidgetTester tester,
    ) async {
      final WovenBorder border = WovenBorder(
        color: c.color,
        widthFraction: 0.05,
        opacity: c.opacity,
      );
      final _Raster reference = await _render(
        tester,
        // The transparent border layer stores byte alpha. Compare with this
        // colour blended once, including the intermediate byte rounding.
        ColoredBox(
          color: c.color.withAlpha(
            (c.color.a * c.opacity * c.segmentOpacity * 255).round(),
          ),
        ),
      );
      final (int, int, int, int) expected = reference.at(240, 240);
      final List<String> failures = <String>[];
      for (final bool clockwise in <bool>[true, false]) {
        final WovenRingStyle style = WovenRingStyle(
          startAngle: 0,
          clockwise: clockwise,
          surfaceColor: const Color(0xFFFFFFFF),
        );
        final WovenRingGeometry g = WovenRingGeometry.forSize(
          const Size.square(_side),
          style,
        );
        final List<WovenSegmentExtent> extents = g.extents(
          const <double>[0.25, 0.25, 0.25, 0.25],
          0,
          clockwise: clockwise,
        );
        final _Raster raster = await _render(
          tester,
          WovenRingChart(
            style: style,
            animation: WovenRingAnimation.none,
            highlightedIndex: c.highlightedIndex,
            highlightBorder: border,
            segments: <WovenSegment>[
              for (var i = 0; i < 4; i++)
                WovenSegment(
                  value: 1,
                  fill: const WovenFill.solid(Color(0xFFFFFFFF)),
                  opacity: c.segmentOpacity,
                  border: c.highlightedIndex == null ? border : null,
                ),
            ],
          ),
        );
        for (var i = 0; i < extents.length; i++) {
          final double head = extents[i].start;
          final Offset center = g.pointOn(g.trackRadius, head);
          final Offset tangent =
              Offset(-math.sin(head), math.cos(head)) * (clockwise ? 1 : -1);
          final double width = g.thickness * border.widthFraction;
          final Offset requested = center - tangent * (g.capRadius - width / 2);
          final int x = (requested.dx - 0.5).round();
          final int y = (requested.dy - 0.5).round();
          final Offset pixel = Offset(x + 0.5, y + 0.5);
          final double inset = g.capRadius - (pixel - center).distance;
          expect(inset, greaterThan(1.25));
          expect(width - inset, greaterThan(1.25));
          final Path own = g.segmentPath(
            extents[i].start,
            extents[i].end,
            clockwise: clockwise,
          );
          final Path successor = g.segmentPath(
            extents[(i + 1) % 4].start,
            extents[(i + 1) % 4].end,
            clockwise: clockwise,
          );
          for (var probe = 0; probe < 16; probe++) {
            final double angle = probe * math.pi * 2 / 16;
            final Offset p =
                pixel + Offset(math.cos(angle), math.sin(angle)) * 1.25;
            expect(own.contains(p), isTrue);
            expect(successor.contains(p), isFalse);
          }
          final (int, int, int, int) actual = raster.at(x, y);
          final (int, int, int, int) target =
              c.highlightedIndex == null || c.highlightedIndex == i
              ? expected
              : (255, 255, 255, 255);
          if (actual != target) {
            failures.add(
              'head=$i clockwise=$clockwise pixel=($x,$y) inset=$inset actual=$actual expected=$target',
            );
          }
        }
      }
      expect(failures, isEmpty, reason: failures.join('\n'));
    });
  }

  testWidgets('short overlapping heads retain half border opacity', (
    WidgetTester tester,
  ) async {
    for (final bool clockwise in <bool>[true, false]) {
      final WovenRingStyle style = WovenRingStyle(
        startAngle: 0,
        clockwise: clockwise,
        thicknessFraction: 0.30,
        overlapFraction: 1,
        smallValuePolicy: WovenSmallValuePolicy.allowVanish,
      );
      for (final List<double> values in <List<double>>[
        <double>[88, 12],
        <double>[82, 9, 9],
      ]) {
        final _Raster opaque = await _render(
          tester,
          _chart(values, style, borderOpacity: 1),
        );
        final _Raster half = await _render(
          tester,
          _chart(values, style, borderOpacity: 0.5),
        );
        _expectHalfBorder(
          opaque,
          half,
          '${clockwise ? 'CW' : 'CCW'} $values',
          headInterior: WovenRingGeometry.forSize(
            const Size.square(_side),
            style,
          ),
        );
      }
    }
  });

  testWidgets('single-to-many topology changes keep partial borders affine', (
    WidgetTester tester,
  ) async {
    for (final bool clockwise in <bool>[true, false]) {
      final WovenRingStyle style = WovenRingStyle(
        startAngle: 0,
        clockwise: clockwise,
      );
      for (final bool toMany in <bool>[true, false]) {
        final List<double> from = toMany
            ? <double>[100]
            : <double>[25, 25, 25, 25];
        final List<double> to = toMany
            ? <double>[25, 25, 25, 25]
            : <double>[100];
        final List<_Raster> opaque = await _transitionFrames(
          tester,
          from,
          to,
          style,
          borderOpacity: 1,
        );
        final List<_Raster> half = await _transitionFrames(
          tester,
          from,
          to,
          style,
          borderOpacity: 0.5,
        );
        expect(half, hasLength(opaque.length));
        for (var i = 0; i < opaque.length; i++) {
          _expectHalfBorder(
            opaque[i],
            half[i],
            '${clockwise ? 'CW' : 'CCW'} ${toMany ? 'to many' : 'to one'} '
            'frame $i',
            silhouette: WovenRingGeometry.forSize(
              const Size.square(_side),
              style,
            ),
          );
        }
      }
    }
  });
}

WovenRingChart _chart(
  List<double> values,
  WovenRingStyle style, {
  required double borderOpacity,
}) => WovenRingChart(
  animation: WovenRingAnimation.none,
  transitionDuration: const Duration(seconds: 1),
  style: style,
  segments: <WovenSegment>[
    for (final double value in values)
      WovenSegment(
        value: value,
        fill: const WovenFill.solid(Color(0xFFFFFFFF)),
        border: WovenBorder(
          color: const Color(0xFF000000),
          widthFraction: 0.05,
          opacity: borderOpacity,
        ),
      ),
  ],
);

void _expectHalfBorder(
  _Raster opaque,
  _Raster half,
  String label, {
  WovenRingGeometry? headInterior,
  WovenRingGeometry? silhouette,
}) {
  var checked = 0;
  final List<String> failures = <String>[];
  for (var y = 0; y < _side; y++) {
    for (var x = 0; x < _side; x++) {
      if (opaque.at(x, y) != (0, 0, 0, 255)) continue;
      if (silhouette != null) {
        final double radius =
            (Offset(x + 0.5, y + 0.5) - silhouette.center).distance;
        // The affine-opacity oracle applies where the ring itself has full
        // coverage. Keep each pixel 1.25px inside both silhouette circles, the
        // same antialiasing margin used by the exact head probes above.
        if (radius < silhouette.innerRadius + 1.25 ||
            radius > silhouette.outerRadius - 1.25) {
          continue;
        }
      }
      if (headInterior != null) {
        final double radius =
            (Offset(x + 0.5, y + 0.5) - headInterior.center).distance;
        final double edgeMargin = headInterior.thickness * 0.05 + 2;
        if (radius < headInterior.innerRadius + edgeMargin ||
            radius > headInterior.outerRadius - edgeMargin) {
          continue;
        }
      }
      final (int r, int g, int b, int a) = half.at(x, y);
      // Fully black opaque coverage must become half black over white. A
      // canonical topology overlay may interpolate the direct-paint byte 128
      // with the isolated-border byte 127; both are the same single half blend.
      if (r < 127 || r > 128) {
        final double radius =
            (Offset(x + 0.5, y + 0.5) - const Offset(_side / 2, _side / 2))
                .distance;
        failures.add('$label at ($x,$y) gray=$r radius=$radius');
      }
      expect((g, b, a), (r, r, 255), reason: '$label at ($x,$y)');
      checked++;
    }
  }
  expect(
    checked,
    greaterThan(headInterior == null ? 500 : 20),
    reason: '$label must include unambiguous border pixels',
  );
  expect(failures, isEmpty, reason: failures.take(12).join('\n'));
}

Future<List<_Raster>> _transitionFrames(
  WidgetTester tester,
  List<double> from,
  List<double> to,
  WovenRingStyle style, {
  required double borderOpacity,
}) async {
  await tester.pumpWidget(const SizedBox.shrink());
  final GlobalKey key = GlobalKey();
  await _pump(tester, key, _chart(from, style, borderOpacity: borderOpacity));
  await _pump(tester, key, _chart(to, style, borderOpacity: borderOpacity));
  final List<_Raster> frames = <_Raster>[await _capture(tester, key)];
  var elapsed = 0;
  for (final int time in <int>[10, 100, 250, 500, 750, 990, 1000]) {
    await tester.pump(Duration(milliseconds: time - elapsed));
    frames.add(await _capture(tester, key));
    elapsed = time;
  }
  await tester.pumpWidget(const SizedBox.shrink());
  return frames;
}

class _BorderCase {
  const _BorderCase(
    this.name, {
    this.color = const Color(0xFF000000),
    this.opacity = 0.5,
    this.segmentOpacity = 1,
    this.highlightedIndex,
  });

  final String name;
  final Color color;
  final double opacity;
  final double segmentOpacity;
  final int? highlightedIndex;
}

Future<_Raster> _render(WidgetTester tester, Widget child) async {
  final GlobalKey key = GlobalKey();
  await _pump(tester, key, child);
  return _capture(tester, key);
}

Future<void> _pump(WidgetTester tester, GlobalKey key, Widget child) async {
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: RepaintBoundary(
          key: key,
          child: SizedBox.square(
            dimension: _side,
            child: ColoredBox(color: const Color(0xFFFFFFFF), child: child),
          ),
        ),
      ),
    ),
  );
}

Future<_Raster> _capture(WidgetTester tester, GlobalKey key) async {
  final RenderRepaintBoundary boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  return (await tester.runAsync<_Raster>(() async {
    final ui.Image image = await boundary.toImage(pixelRatio: 1);
    final ByteData bytes = (await image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!;
    final _Raster result = _Raster(
      image.width,
      Uint8List.fromList(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      ),
    );
    image.dispose();
    return result;
  }))!;
}

class _Raster {
  const _Raster(this.width, this.bytes);
  final int width;
  final Uint8List bytes;
  (int, int, int, int) at(int x, int y) {
    final int offset = (y * width + x) * 4;
    return (
      bytes[offset],
      bytes[offset + 1],
      bytes[offset + 2],
      bytes[offset + 3],
    );
  }
}
