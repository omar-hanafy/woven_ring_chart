# woven_ring_chart example

The smallest thing that draws a woven ring. Paste it into `lib/main.dart` and
run.

```dart
import 'package:flutter/material.dart';
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

**[The live demo](https://omar-hanafy.github.io/woven_ring_chart/)** is this
directory, running in your browser. It is one page, and every section on it
puts a chart that is really running next to the Dart that produced it: quick
start, an interactive playground, fills and borders, animation, the empty and
loading states, the palette, and accessibility.

The playground is the point. Move any control and the code beside it rewrites
itself, carrying only what you have taken away from its default, so the snippet
stays the shortest one that produces what you are looking at.

```sh
flutter run                            # the showcase
flutter run -t lib/ten_segments.dart   # ten segments, all animating
flutter test                           # the showcase's own tests
```

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
