# woven_ring_chart example

Requires Flutter 3.47.7 or later and Dart 3.13.5 or later. The example uses
`material_ui` for Material widgets.

The smallest thing that draws a woven ring. This is `lib/main.dart` here, and
it is the whole file.

```dart
import 'package:material_ui/material_ui.dart';
import 'package:woven_ring_chart/woven_ring_chart.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: WovenRingChart(
            segments: <WovenSegment>[
              WovenSegment.solid(37, WovenPalette.purple),
              WovenSegment.solid(19, WovenPalette.green),
              WovenSegment.solid(29, WovenPalette.amber),
              WovenSegment.solid(15, WovenPalette.rose),
            ],
            center: const Text('100'),
            semanticLabel: 'Spending by category',
          ),
        ),
      ),
    );
  }
}
```

Values are yours to pick: percentages, counts, currency, anything. They are
normalized against each other, and the order you write them is the order they
are drawn.

The chart is square, takes the smaller of whatever constraints it is given, and
settles at 240 logical pixels with nothing bounded on either side.

## Everything else

**[The live demo](https://omar-hanafy.github.io/woven_ring_chart/)** is
`lib/showcase.dart` in this directory, running in your browser. It is one page,
and every section on it puts a chart that is really running next to the Dart
that produced it: quick start, an interactive playground, fills and borders,
animation, the empty and loading states, the palette, and accessibility.

The playground is the point. Move any control and the code beside it rewrites
itself, carrying only what you have taken away from its default, so the snippet
stays the shortest one that produces what you are looking at.

```sh
flutter run                            # the snippet above
flutter run -t lib/showcase.dart       # the showcase, as deployed
flutter run -t lib/ten_segments.dart   # ten segments, all animating
flutter test                           # every test in this directory
```

The showcase is a separate entrypoint on purpose. pub.dev renders
`example/lib/main.dart` under its Example tab, and a page of showcase
scaffolding is the wrong first thing to hand someone; that slot belongs to the
shortest runnable example there is.

`lib/ten_segments.dart` is one screen with ten segments, every one gradient
filled and bordered. It replays the entrance animation every 11 seconds and
changes data every 2.2 seconds between four fixed sets, so both animated paths
stay on screen without touching a control.

### How the code panel is kept honest

A demo that shows code next to a chart is only useful if the two agree, and
keeping them in step by hand is exactly the sort of thing that quietly stops
being true. So one object, `PlaygroundConfig`, is the only description of the
configuration: the chart is built from it, and the snippet is printed from it.

`test/playground_config_test.dart` then closes the loop from the other side. It
takes the generated text, parses the segments and the style back out of it
without looking at the config that produced them, and compares those against
the values the widget was actually handed. It does this over the whole cross
product of the controls, so neither side can move without the other.

Full documentation is in the
[package README](https://github.com/omar-hanafy/woven_ring_chart#readme).

## Runtime flow checks

`integration_test/showcase_flow_test.dart` runs the published snippet, changes
playground data and controls, checks that the preview and source stay in sync,
replays animations, verifies reduced motion and semantics in a narrow layout,
pauses and resumes the ten-segment app, and exercises invalid values, extreme
finite values, and equivalent large-angle rendering. On native platforms it also
reads back the install line and generated code from the system clipboard.

Run native integration checks in debug mode (the `flutter test` command below).
Dense-ring alpha checks borrow the chart's actual single `PictureLayer` and
capture it with `TargetPixelFormat.rgbaFloat32`, avoiding the default Metal
snapshot target's MSAA/resolve precision artifacts. They retain exact alpha
assertions and save normal boundary captures for visual review. Browser checks
use the original boundary capture; the native layer inspection requires debug
mode.

Desktop scaffolds are generated locally and excluded from the package archive.
To prepare macOS without changing the Android, iOS, or web projects:

```sh
template_dir="$(mktemp -d)/woven_ring_chart_example"
flutter create --no-pub --platforms=macos \
  --project-name woven_ring_chart_example --org com.omarhanafy "$template_dir"
cp -R "$template_dir/macos" ./macos
flutter pub get
flutter test integration_test/showcase_flow_test.dart -d macos
```

Generate the scaffold only when `macos/` is absent. For browser runtime checks,
start a ChromeDriver compatible with the installed Chrome on port 4444, then:

```sh
flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/showcase_flow_test.dart -d web-server --wasm \
  --web-hostname=127.0.0.1 --web-port=7357
```

Browser clipboard access depends on the browser's permission and user-gesture
policy, so clipboard readback is covered by the native runtime checks.
