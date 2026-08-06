// Renders the README animation and the pub.dev screenshot straight from the
// widget, so the pictures are the component rather than a screen recording of
// it. Everything is deterministic: same frames on every machine, no cursor, no
// window chrome, no display colour profile baked in.
//
//   flutter test tool/render_media.dart
//
// Writes build/media/screenshot.png and build/media/frames/*.png. The GIF is
// assembled from those frames by tool/build_media.sh.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woven_ring_chart/woven_ring_chart.dart';

const String outDir = 'build/media';
const Color surface = WovenPalette.surface;

/// The animation runs at 20fps, which is as fast as a GIF is worth playing and
/// keeps the file under a megabyte.
const Duration frameStep = Duration(milliseconds: 50);

List<WovenSnake> gradientSnakes(List<double> values, {bool border = false}) =>
    <WovenSnake>[
      for (var i = 0; i < values.length; i++)
        WovenSnake(
          value: values[i],
          fill: WovenFill.shaded(
            WovenPalette.extended[i % WovenPalette.extended.length],
            step: 0.045,
          ),
          border: border ? const WovenBorder() : null,
        ),
    ];

void main() {
  testWidgets('render media', (WidgetTester tester) async {
    final GlobalKey shot = GlobalKey();
    Directory('$outDir/frames').createSync(recursive: true);

    Future<void> capture(File file) async {
      final RenderRepaintBoundary boundary =
          shot.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final ui.Image image = await boundary.toImage(pixelRatio: 2);
        final ByteData data = (await image.toByteData(
          format: ui.ImageByteFormat.png,
        ))!;
        file.writeAsBytesSync(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        );
        image.dispose();
      });
    }

    Widget stage(
      Widget child, {
      required double width,
      required double height,
    }) {
      // The surface has to be inside the boundary. Captured from outside it the
      // frames come out transparent, and a GIF has one bit of transparency, so
      // every antialiased edge is then cut to a hard stair-step. It also makes
      // the picture honest: a border with no colour of its own paints in the
      // surface colour, so a ring is only drawn correctly against the surface
      // it was given.
      return Directionality(
        textDirection: TextDirection.ltr,
        child: ColoredBox(
          color: surface,
          child: Center(
            child: RepaintBoundary(
              key: shot,
              child: ColoredBox(
                color: surface,
                child: SizedBox(width: width, height: height, child: child),
              ),
            ),
          ),
        ),
      );
    }

    // ---- the animation -----------------------------------------------------
    // One ring, three acts: the relay reveal, then two data changes that
    // stretch the segments in place. Re-pumping the same keyed widget with new
    // values is exactly what an app does, so this is the real transition and
    // not a scripted approximation of one.
    const ValueKey<String> ring = ValueKey<String>('media-ring');
    var frame = 0;

    Widget ringWith(List<double> values) => stage(
      Padding(
        // Room to breathe, so the outer circle never reads as cropped by the
        // edge of the frame.
        padding: const EdgeInsets.all(18),
        child: WovenRing(
          key: ring,
          snakes: gradientSnakes(values),
          style: const WovenRingStyle(surface: surface),
          introDuration: const Duration(milliseconds: 1100),
        ),
      ),
      width: 320,
      height: 320,
    );

    Future<void> run(List<double> values, int frames) async {
      await tester.pumpWidget(ringWith(values));
      for (var i = 0; i < frames; i++) {
        await capture(
          File('$outDir/frames/f${frame.toString().padLeft(3, '0')}.png'),
        );
        frame++;
        await tester.pump(frameStep);
      }
    }

    // The relay travels once round, then the ring sits still long enough to be
    // read before anything moves again.
    await run(const <double>[37, 19, 29, 15], 30);
    await run(const <double>[12, 34, 22, 32], 16);
    await run(const <double>[26, 24, 25, 25], 16);
    await run(const <double>[37, 19, 29, 15], 14);

    // ---- the still ---------------------------------------------------------
    // Four rings that between them say what the component is: the plain
    // reference ring, the same ring bordered so the lap reads as a cut, a ten
    // segment ring, and a lifted one.
    await tester.pumpWidget(const SizedBox.shrink());
    // The test surface defaults to 800x600, which would clip the still.
    await tester.binding.setSurfaceSize(const Size(820, 820));
    await tester.pumpWidget(
      stage(
        Padding(
          padding: const EdgeInsets.all(36),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: <Widget>[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: <Widget>[
                  SizedBox.square(
                    dimension: 300,
                    child: WovenRing(
                      snakes: <WovenSnake>[
                        for (var i = 0; i < 4; i++)
                          WovenSnake.solid(
                            const <double>[37, 19, 29, 15][i],
                            WovenPalette.quartet[i],
                          ),
                      ],
                      style: const WovenRingStyle(surface: surface),
                      intro: WovenRingIntro.none,
                    ),
                  ),
                  SizedBox.square(
                    dimension: 300,
                    child: WovenRing(
                      snakes: gradientSnakes(const <double>[
                        30,
                        22,
                        26,
                        22,
                      ], border: true),
                      style: const WovenRingStyle(surface: surface),
                      intro: WovenRingIntro.none,
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: <Widget>[
                  SizedBox.square(
                    dimension: 300,
                    child: WovenRing(
                      snakes: gradientSnakes(const <double>[
                        11,
                        8,
                        13,
                        9,
                        12,
                        7,
                        10,
                        11,
                        9,
                        10,
                      ]),
                      style: const WovenRingStyle(surface: surface),
                      intro: WovenRingIntro.none,
                    ),
                  ),
                  SizedBox.square(
                    dimension: 300,
                    child: WovenRing(
                      snakes: <WovenSnake>[
                        for (var i = 0; i < 4; i++)
                          WovenSnake.solid(
                            const <double>[25, 25, 25, 25][i],
                            WovenPalette.quartet[i],
                          ),
                      ],
                      style: const WovenRingStyle(
                        surface: surface,
                        lift: WovenLift(),
                        bandFraction: 0.26,
                      ),
                      intro: WovenRingIntro.none,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        width: 760,
        height: 760,
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    await capture(File('$outDir/screenshot.png'));
    await tester.binding.setSurfaceSize(null);

    // ignore: avoid_print
    print('WROTE $frame frames and 1 still to $outDir');
  });
}
