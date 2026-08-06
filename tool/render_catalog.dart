// Visual sweep of the whole demo control matrix, rendered straight from the
// production widget. Lives outside test/ so it is never part of the automated
// gate.
//
//   flutter test tool/render_catalog.dart
//
// Writes one PNG per configuration to build/catalog_png.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woven_ring_chart/woven_ring_chart.dart';

const String outDir = 'build/catalog_png';
const Color surface = Color(0xFFFBFAF7);
const double dim = 240;

enum Scenario { quartet, extended, tinyValue, singleValue }

enum FillMode { solid, gradient, diagnosticGradient, mixed }

enum BorderMode { none, selected, mixed, all, diagnosticAlternating }

List<double> valuesFor(Scenario s) => switch (s) {
  Scenario.quartet => <double>[25, 25, 25, 25],
  Scenario.extended => <double>[10, 9, 11, 8, 12, 10, 9, 11, 8, 12],
  Scenario.tinyValue => <double>[0.3, 39.7, 25, 35],
  Scenario.singleValue => <double>[100],
};

List<Color> colorsFor(Scenario s) => switch (s) {
  Scenario.extended => WovenPalette.extended,
  Scenario.singleValue => const <Color>[WovenPalette.purple],
  _ => WovenPalette.quartet,
};

WovenFill fillFor(Color c, FillMode m, int i) => switch (m) {
  FillMode.solid => WovenFill.solid(c),
  FillMode.gradient => WovenFill.shaded(c, step: 0.04),
  FillMode.diagnosticGradient => WovenFill.shaded(c, step: 0.20),
  FillMode.mixed =>
    i.isOdd ? WovenFill.shaded(c, step: 0.04) : WovenFill.solid(c),
};

WovenBorder? borderFor(BorderMode m, int i) => switch (m) {
  BorderMode.none || BorderMode.selected => null,
  BorderMode.mixed => i == 1 || i == 5 ? const WovenBorder() : null,
  BorderMode.all => const WovenBorder(),
  BorderMode.diagnosticAlternating =>
    i.isOdd ? const WovenBorder(widthFraction: 0.05) : null,
};

void main() {
  testWidgets('sweep', (WidgetTester tester) async {
    final GlobalKey key = GlobalKey();
    Directory(outDir).createSync(recursive: true);
    var written = 0;

    Future<void> shot(String name, Widget ring, {int settleMs = 2500}) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        Container(
          color: surface,
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: RepaintBoundary(
                key: key,
                child: SizedBox.square(dimension: dim, child: ring),
              ),
            ),
          ),
        ),
      );
      await tester.pump(Duration(milliseconds: settleMs));
      final RenderRepaintBoundary b =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final ui.Image image = await b.toImage(pixelRatio: 1);
        final ByteData d = (await image.toByteData(
          format: ui.ImageByteFormat.png,
        ))!;
        File('$outDir/$name.png').writeAsBytesSync(
          d.buffer.asUint8List(d.offsetInBytes, d.lengthInBytes),
        );
        image.dispose();
      });
      written++;
    }

    // ---- the full static cross-product -----------------------------------
    for (final Scenario scenario in Scenario.values) {
      for (final FillMode fill in FillMode.values) {
        for (final BorderMode border in BorderMode.values) {
          for (final bool cw in <bool>[true, false]) {
            final List<double> values = valuesFor(scenario);
            final List<Color> colors = colorsFor(scenario);
            await shot(
              'S_${scenario.name}__${fill.name}__${border.name}__'
              '${cw ? 'cw' : 'ccw'}',
              WovenRing(
                snakes: <WovenSnake>[
                  for (var i = 0; i < values.length; i++)
                    WovenSnake(
                      value: values[i],
                      fill: fillFor(colors[i % colors.length], fill, i),
                      border: borderFor(border, i),
                    ),
                ],
                style: WovenRingStyle(clockwise: cw, surface: surface),
                intro: WovenRingIntro.none,
                highlighted: border == BorderMode.selected ? 2 : null,
              ),
            );
          }
        }
      }
    }

    // ---- short segments, where whole overlap cycles form -------------------
    // Two and three snakes are the counts at which a covering run can close the
    // whole cycle, and a snake past about 88 percent laps its own tail.
    for (final List<double> values in <List<double>>[
      <double>[80, 10, 10],
      <double>[10, 80, 10],
      <double>[10, 10, 80],
      <double>[90, 10],
      <double>[10, 90],
      <double>[89, 11],
      <double>[91.5, 8.5],
      <double>[84, 8, 8],
      <double>[70, 10, 10, 10],
    ]) {
      for (final bool cw in <bool>[true, false]) {
        await shot(
          'W_${values.map((double v) => v.round()).join('_')}__'
          '${cw ? 'cw' : 'ccw'}',
          WovenRing(
            snakes: <WovenSnake>[
              for (var i = 0; i < values.length; i++)
                WovenSnake(
                  value: values[i],
                  fill: WovenFill.solid(WovenPalette.quartet[i % 4]),
                ),
            ],
            style: WovenRingStyle(clockwise: cw, surface: surface),
            intro: WovenRingIntro.none,
          ),
        );
      }
    }

    // ---- geometry sliders at their endpoints ------------------------------
    for (final double band in <double>[0.15, 0.20, 0.25]) {
      for (final double overlap in <double>[0.30, 0.50, 0.90]) {
        for (final double deg in <double>[-180, -90, 0, 45, 180]) {
          await shot(
            'G_band${(band * 100).round()}__ov${(overlap * 100).round()}__'
            'a${deg.round()}',
            WovenRing(
              snakes: <WovenSnake>[
                for (var i = 0; i < 4; i++)
                  WovenSnake(
                    value: <double>[25, 25, 25, 25][i],
                    fill: WovenFill.solid(WovenPalette.quartet[i]),
                  ),
              ],
              style: WovenRingStyle(
                bandFraction: band,
                overlapFraction: overlap,
                startAngle: deg * math.pi / 180,
                surface: surface,
              ),
              intro: WovenRingIntro.none,
            ),
          );
        }
      }
    }

    // ---- gradient axis and direction --------------------------------------
    for (final WovenGradientAxis axis in WovenGradientAxis.values) {
      for (final WovenGradientDirection dir in WovenGradientDirection.values) {
        for (final bool cw in <bool>[true, false]) {
          for (final int count in <int>[1, 2, 4, 10]) {
            await shot(
              'X_${axis.name}__${dir.name}__${cw ? 'cw' : 'ccw'}__n$count'
              '',
              WovenRing(
                snakes: <WovenSnake>[
                  for (var i = 0; i < count; i++)
                    WovenSnake(
                      value: 1,
                      fill: WovenFill.shaded(
                        WovenPalette.extended[i % 6],
                        step: 0.20,
                      ),
                    ),
                ],
                style: WovenRingStyle(
                  gradientAxis: axis,
                  gradientDirection: dir,
                  clockwise: cw,
                  surface: surface,
                ),
                intro: WovenRingIntro.none,
              ),
            );
          }
        }
      }
    }

    // ---- states ------------------------------------------------------------
    await shot('Z_empty', const WovenRing.empty(style: WovenRingStyle()));
    await shot('Z_loading', const WovenRing.loading(), settleMs: 400);
    for (final WovenSingleSnakeStyle single in WovenSingleSnakeStyle.values) {
      for (final FillMode fill in FillMode.values) {
        await shot(
          'Z_single_${single.name}__${fill.name}',
          WovenRing(
            snakes: <WovenSnake>[
              WovenSnake(
                value: 100,
                fill: fillFor(WovenPalette.purple, fill, 0),
              ),
            ],
            style: WovenRingStyle(singleSnakeStyle: single, surface: surface),
            intro: WovenRingIntro.none,
          ),
        );
      }
    }
    for (final WovenMinimumPolicy policy in WovenMinimumPolicy.values) {
      await shot(
        'Z_tiny_${policy.name}',
        WovenRing(
          snakes: <WovenSnake>[
            for (var i = 0; i < 4; i++)
              WovenSnake(
                value: <double>[0.3, 39.7, 25, 35][i],
                fill: WovenFill.solid(WovenPalette.quartet[i]),
              ),
          ],
          style: WovenRingStyle(minimumPolicy: policy, surface: surface),
          intro: WovenRingIntro.none,
        ),
      );
    }
    await shot(
      'Z_lift',
      WovenRing(
        snakes: <WovenSnake>[
          for (var i = 0; i < 4; i++)
            WovenSnake(
              value: <double>[37, 19, 29, 15][i],
              fill: WovenFill.solid(WovenPalette.quartet[i]),
            ),
        ],
        style: const WovenRingStyle(lift: WovenLift(), surface: surface),
        intro: WovenRingIntro.none,
      ),
    );

    // ---- intro animation frames -------------------------------------------
    for (final WovenRingIntro intro in <WovenRingIntro>[
      WovenRingIntro.relay,
      WovenRingIntro.bloom,
    ]) {
      for (final bool cw in <bool>[true, false]) {
        for (final int count in <int>[1, 4]) {
          for (final int ms in <int>[150, 350, 550, 750, 900, 1000]) {
            await shot(
              'A_${intro.name}__${cw ? 'cw' : 'ccw'}__n${count}__$ms',
              WovenRing(
                snakes: <WovenSnake>[
                  for (var i = 0; i < count; i++)
                    WovenSnake(
                      value: 1,
                      fill: WovenFill.shaded(
                        WovenPalette.quartet[i % 4],
                        step: 0.08,
                      ),
                      border: const WovenBorder(),
                    ),
                ],
                style: WovenRingStyle(clockwise: cw, surface: surface),
                intro: intro,
              ),
              settleMs: ms,
            );
          }
        }
      }
    }

    // ignore: avoid_print
    print('WROTE $written files to $outDir');
  });
}
