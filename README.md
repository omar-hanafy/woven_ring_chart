# woven_ring_chart

[![pub package](https://img.shields.io/pub/v/woven_ring_chart.svg)](https://pub.dev/packages/woven_ring_chart)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/omar-hanafy/woven_ring_chart/blob/main/LICENSE)

**[Try the live demo →](https://omar-hanafy.github.io/woven_ring_chart/)**

A doughnut chart for Flutter whose segments lap over one another like shingles.

[![A four segment woven ring drawing itself, then reshaping as its data changes](https://raw.githubusercontent.com/omar-hanafy/woven_ring_chart/5ca191d40a7fdd0517f0bfb59e8ebe8cfd09d220/doc/woven_ring_chart.gif)](https://omar-hanafy.github.io/woven_ring_chart/)

Most doughnut charts cut between segments with a straight radial line. This one
does not have a straight line anywhere. Each segment is a constant-width bar
with semicircular ends, bent along the ring, and each is drawn over the one
before it. What you see at every boundary is the backward half of a round cap,
including at the seam where the last segment closes onto the first.

That one rule is the whole chart. The cap radius is half the ring's thickness by
construction, so it cannot drift when you resize the chart, change the
thickness, or animate the data.

## Install

```yaml
dependencies:
  woven_ring_chart: ^1.0.0
```

```dart
import 'package:woven_ring_chart/woven_ring_chart.dart';
```

There are no platform channels, no native code, and no transitive dependencies
beyond Flutter itself. It runs on Android, iOS, macOS, Windows, Linux, and web.

## Quick start

```dart
WovenRingChart(
  segments: <WovenSegment>[
    WovenSegment.solid(37, WovenPalette.purple),
    WovenSegment.solid(19, WovenPalette.green),
    WovenSegment.solid(29, WovenPalette.amber),
    WovenSegment.solid(15, WovenPalette.rose),
  ],
  center: const Text('100'),
  semanticLabel: 'Spending by category',
)
```

Values are yours to pick: percentages, counts, currency, anything. They are
normalized against each other. Order is kept exactly as you wrote it, and the
chart never sorts or rebalances to look tidier.

`WovenSegment.solid` builds its fill from the colour you pass, so it is not a
`const` constructor. Use the primary constructor for a `const` list:

```dart
segments: const <WovenSegment>[
  WovenSegment(value: 37, fill: WovenFill.solid(WovenPalette.purple)),
  WovenSegment(value: 19, fill: WovenFill.solid(WovenPalette.green)),
],
```

The chart is square. It takes the smaller of whatever constraints it is given
and centres itself in the box, so it is safe inside a `Row`, a `Card`, or an
unbounded `SingleChildScrollView`. With nothing bounded on either side it
settles at 240 logical pixels.

[![Four woven rings: solid, gradient with borders, ten segments, and one with a head shadow](https://raw.githubusercontent.com/omar-hanafy/woven_ring_chart/5ca191d40a7fdd0517f0bfb59e8ebe8cfd09d220/screenshots/woven_ring_chart.png)](https://omar-hanafy.github.io/woven_ring_chart/)

## Shape

`WovenRingStyle` holds everything that is not data. Nothing in it is a pixel
count, so a style you like at 120 logical pixels still works at 600.

```dart
const WovenRingStyle(
  thicknessFraction: 0.20,   // thickness, as a fraction of the outer diameter
  overlapFraction: 0.5,      // how far a joint sits behind its data boundary
  startAngle: -math.pi / 2,  // 12 o'clock
  clockwise: true,
)
```

`overlapFraction` is measured in ring thicknesses and only moves the joint. It
never changes the cap shape, which stays a half circle of radius
`thickness / 2`. Counter-clockwise is a mirror image rather than a rotation, so
the heads flip too.

Every field with a clamped range has a `resolved` counterpart that reports the
value actually drawn: `resolvedThicknessFraction`, `resolvedOverlapFraction`,
`resolvedStartAngle`. The raw value survives a round trip through `copyWith`.

## Fills and borders

A fill is solid or a gradient between two colours. `WovenFill.shaded` builds a
deliberately quiet one from a single colour:

```dart
WovenSegment(
  value: 40,
  fill: WovenFill.shaded(WovenPalette.blue, step: 0.04),
  border: const WovenBorder(),
)
```

Which way the gradient runs is a chart-level decision, not a per-segment one:

```dart
const WovenRingStyle(
  gradientAxis: WovenGradientAxis.alongSegment,     // default
  // gradientAxis: WovenGradientAxis.acrossThickness,  // radial, tube look
  gradientDirection: WovenGradientDirection.headToTail,
)
```

Borders sit inside the segment, stroked at double width and clipped to the
silhouette. A bordered segment is never fatter than an unbordered one and the
outer edge of the ring stays a circle. Leave the colour out and it resolves to
`WovenRingStyle.surfaceColor`, which reads as the segments being cut out of each
other rather than merely stacked. `WovenBorder.darkerFill` is the other option
that works. A flat dark outline is not: it makes the chart look like a colouring
book.

Borders belong to whichever segment owns a pixel, so a tail buried under its
successor does not draw one.

## Highlighting one segment

```dart
WovenRingChart(
  segments: segments,
  highlightedIndex: selected,
  highlightBorder: const WovenBorder(),
)
```

The highlighted segment takes `highlightBorder` in place of its own for as long
as the index is set.

## Shadow

```dart
const WovenRingStyle(shadow: WovenShadow())
```

A soft, tight shadow falls backwards from each segment head onto the segment
beneath it. It is clipped out of the hole, and the chart shrinks inside its box
to give the blur room. If you notice it as a shadow it is twice too strong.

## States

```dart
const WovenRingChart.empty()     // flat neutral annulus, same size, no joints
const WovenRingChart.loading()   // one neutral segment chasing itself round
```

Both keep the thickness and diameter of a chart with data in it, so nothing on
the screen jumps when the data lands. Give the loading chart a `semanticLabel`
or a `semanticValue` and it announces itself as a live region to assistive
technology.

A single value covering the whole ring has no boundary to show, so by default it
shows none. Set `singleSegmentStyle: WovenSingleSegmentStyle.jointed` if you
would rather keep one hairline self-joint, drawn in the surface colour on the
head cap's backward semicircle.

## Values too small to draw

A segment shorter than one ring-thickness of arc is two overlapping caps and
reads as a blob. There is no answer that is right for every chart, only two
defensible ones, and the chart makes you pick:

```dart
WovenSmallValuePolicy.enforce      // raise it to the minimum, rescale the rest
WovenSmallValuePolicy.allowVanish  // let it disappear under its neighbour
```

`enforce` is the default. It keeps the chart readable and gives up exact
proportions, so do not use it where the arc lengths are the message.
`allowVanish` keeps the proportions honest and drops anything under half the
minimum.

## Animation

The first time a chart appears it draws itself. `WovenRingAnimation.sweep`, the
default, sends one head once round the circle, handing the colour over at each
boundary. `WovenRingAnimation.grow` opens every segment at once with a stagger.
`WovenRingAnimation.none` appears finished.

```dart
WovenRingChart(
  segments: segments,
  animation: WovenRingAnimation.sweep,
  animationDuration: const Duration(milliseconds: 1000),
  transitionDuration: const Duration(milliseconds: 450),
)
```

Changing the data animates in place over `transitionDuration`. Segments stretch
and shrink, colours crossfade, and nothing is torn down and rebuilt, so the
chart never blinks. Changing the data again mid-transition picks up from the
frame that is on screen instead of restarting.

The exception is a chart that had nothing to draw. Build one with an empty list
and it waits, finished, until real values arrive, then plays the entrance
animation rather than growing out of an empty ring.

To replay the entrance later, hand the chart a controller:

```dart
final WovenRingChartController controller = WovenRingChartController();
// ...
WovenRingChart(segments: segments, controller: controller);
// ...
controller.replay();
```

Under `MediaQuery.disableAnimations` every entrance and data change completes
immediately.

## Accessibility

Give the chart a `semanticLabel` and `semanticValue`, or label the segments
individually and let their labels be joined. Labelling the segments does not
take the centre widget out of the accessibility tree, because a segment label
describes a segment and says nothing about the total.

```dart
WovenRingChart(
  segments: const <WovenSegment>[
    WovenSegment(
      value: 37,
      fill: WovenFill.solid(WovenPalette.purple),
      semanticLabel: 'Housing, 37 percent',
    ),
    // ...
  ],
)
```

## Colours

`WovenPalette` is a reference set of mid-saturation colours that stay distinct
where two of them meet on a cap. The chart never reaches for them on its own; a
ring paints exactly the colours its segments carry.

```dart
WovenPalette.quartet    // four colours
WovenPalette.extended   // ten, with one dark anchor among the brights
WovenPalette.cycle(WovenPalette.quartet, 7)
```

`cycle` repeats a palette up to a count without letting a colour touch itself,
including where the ring closes.

## Geometry

The geometry the chart resolves is public, so you can measure against it or
reproduce it:

```dart
const WovenRingStyle style = WovenRingStyle();
final WovenRingGeometry g = WovenRingGeometry.forSize(
  const Size(240, 240),
  style,
);
g.thickness;        // 48.0
g.capRadius;        // 24.0, always thickness / 2
g.holeDiameter;     // 144.0, what a centre widget has to fit inside
g.minimumFraction;  // the smallest share that still draws as a segment

final List<double> fractions = wovenSegmentFractions(
  <double>[37, 19, 29, 15],
  minimumFraction: g.minimumFraction,
  policy: style.smallValuePolicy,
);
final List<WovenSegmentExtent> extents = g.extents(
  fractions,
  style.resolvedStartAngle,
  clockwise: style.clockwise,
);
extents.first.headApex(g.capAngle, clockwise: style.clockwise);
```

## API at a glance

| Type | What it is |
| --- | --- |
| `WovenRingChart` | The chart widget, plus `.empty` and `.loading` |
| `WovenRingChartController` | Replays the entrance animation |
| `WovenSegment` | One coloured piece: value, fill, border, label |
| `WovenFill` | `.solid`, `.gradient`, `.shaded` |
| `WovenBorder` | Hairline inside a segment, plus `.darkerFill` |
| `WovenShadow` | Chart-level shadow under every head |
| `WovenRingStyle` | Everything that is not data |
| `WovenPalette` | Reference colours and `cycle` |
| `WovenRingAnimation` | `sweep`, `grow`, `none` |
| `WovenGradientAxis` | `alongSegment`, `acrossThickness` |
| `WovenGradientDirection` | `headToTail`, `tailToHead` |
| `WovenSmallValuePolicy` | `enforce`, `allowVanish` |
| `WovenSingleSegmentStyle` | `jointed`, `smooth` |
| `WovenRingGeometry` | Resolved geometry for a given size |
| `WovenSegmentExtent` | Where one segment is drawn, in angles |
| `wovenSegmentFractions` | Normalization and the small-value policy |

## The example

The example is the showcase, and it is
[live in your browser](https://omar-hanafy.github.io/woven_ring_chart/). Every
push to `main` that touches the package or the example redeploys it, so what is
on that page is what is on `main`.

```sh
cd example
flutter run                            # the getting-started snippet
flutter run -t lib/showcase.dart       # the showcase, as deployed
flutter run -t lib/ten_segments.dart   # ten segments, all animating
```

It is one page. Every section on it pairs a chart that is really running with
the Dart that produced it, so a look you like is a snippet you can take. The
playground in the middle goes further: move any control and the code beside it
rewrites itself, showing only what you have taken away from its default. Copy
that and you get the chart you are looking at, which is checked rather than
promised — see below.

## How this is checked

298 tests run against the package and another 79 against the showcase. Most of
the first number is one file, `test/spec/catalog_test.dart`, which shares no
helper with the rest and re-derives the geometry from the written specification
instead of from `WovenRingGeometry`, so a bug in the production geometry cannot
hide inside the checker meant to catch it. The whole specification collapses
into one predicate it applies everywhere:

> at any covered point the visible owner is the covering segment whose head tip
> is the closest one behind that point in the drawing direction.

On top of that it measures rather than assumes. Every visible colour boundary is
checked to sit on a circle of radius `thickness / 2` centred on the next head's
cap, sampled at eighteen radii across the ring, which is what rejects a radial
seam that happens to land in the right place. Thirteen configurations render at
four device pixels per logical pixel and scan every one of them to prove nothing
paints outside the silhouette, with a quarter of a logical pixel of margin for
antialiasing and nothing more.

[doc/TEST_MATRIX.md](https://github.com/omar-hanafy/woven_ring_chart/blob/main/doc/TEST_MATRIX.md)
lists what each section covers.

The showcase's own suite is mostly one idea: the live demo claims that the code
beside a chart is the code that built it, and
`example/test/playground_config_test.dart` makes that claim checkable. It takes
the generated snippet, parses the segments and style back out of the text, and
compares them against the values the widget was actually handed, across the
whole cross product of the controls. Neither the page nor the generator can
drift from the other without a red test.

```sh
dart analyze
flutter test
cd example && flutter test
```

## License

MIT. See [LICENSE](https://github.com/omar-hanafy/woven_ring_chart/blob/main/LICENSE).
