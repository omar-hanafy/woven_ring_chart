# woven_ring_chart

A doughnut chart whose segments lap over one another like shingles.

![A four segment woven ring drawing itself, then reshaping as its data changes](https://raw.githubusercontent.com/omar-hanafy/woven_ring_chart/main/doc/woven_ring_chart.gif)

Most donut charts cut between segments with a straight radial line. This one
does not have a straight line anywhere. Each segment is a constant-width bar
with semicircular ends, bent along the ring, and each is drawn over the one
before it. What you see at every boundary is the backward half of a round cap,
including at the seam where the last segment closes onto the first.

That one rule is the whole component. The cap radius is half the band width by
construction, so it cannot drift when you resize the chart, change the band, or
animate the data.

## Install

```yaml
dependencies:
  woven_ring_chart: ^1.0.0-dev.2
```

```dart
import 'package:woven_ring_chart/woven_ring_chart.dart';
```

## Use it

```dart
WovenRing(
  snakes: const <WovenSnake>[
    WovenSnake.solid(37, WovenPalette.purple),
    WovenSnake.solid(19, WovenPalette.green),
    WovenSnake.solid(29, WovenPalette.amber),
    WovenSnake.solid(15, WovenPalette.rose),
  ],
  center: const Text('100'),
  semanticLabel: 'Spending by category',
)
```

Values are yours to pick: percentages, counts, currency, anything. They get
normalized against each other. Order is kept exactly as you wrote it, and the
ring never sorts or rebalances to look tidier.

The chart is square. It takes the smaller of whatever constraints it is given
and centres itself in the box, so it is safe inside a `Row`, a `Card`, or an
unbounded `SingleChildScrollView`.

![Four woven rings: solid, gradient with borders, ten segments, and one with a head shadow](https://raw.githubusercontent.com/omar-hanafy/woven_ring_chart/main/screenshots/woven_ring_chart.png)

## Shape

`WovenRingStyle` holds everything that is not data. Nothing in it is a pixel
count, so a style you like at 120 logical pixels still works at 600.

```dart
const WovenRingStyle(
  bandFraction: 0.20,     // thickness, as a fraction of the outer diameter
  overlapFraction: 0.5,   // how far a joint sits behind its data boundary
  startAngle: -math.pi / 2,
  clockwise: true,
)
```

`overlapFraction` is measured in band widths and only moves the joint. It never
changes the cap shape, which stays a half circle of radius `band / 2`. Counter-
clockwise is a mirror image rather than a rotation, so the heads flip too.

## Fills and borders

A fill is solid or a gradient between two colours. `WovenFill.shaded` builds a
deliberately quiet one from a single colour:

```dart
WovenSnake(
  value: 40,
  fill: WovenFill.shaded(WovenPalette.blue, step: 0.04),
  border: const WovenBorder(),
)
```

Which way the gradient runs is a ring-level decision, not a per-snake one, so
`WovenRingStyle.gradientAxis` picks between running along each segment and
running across the band for a tube look.

Borders sit inside the segment, stroked at double width and clipped to the
silhouette. A bordered segment is never fatter than an unbordered one and the
outer edge of the ring stays a circle. Leave the colour out and it resolves to
`WovenRingStyle.surface`, which reads as the segments being cut out of each
other rather than merely stacked. `WovenBorder.darkerFill` is the other option
that works. A flat dark outline is not: it makes the chart look like a colouring
book.

Borders belong to whichever segment owns a pixel, so a tail buried under its
successor does not draw one.

## States

```dart
const WovenRing.empty()     // flat neutral annulus, same size, no joints
const WovenRing.loading()   // one neutral segment chasing itself round
```

Both keep the band width and diameter of a ring with data in it, so nothing on
the screen jumps when the data lands.

A single value covering the whole ring has no boundary to show, so by default it
shows none. Set `singleSnakeStyle: WovenSingleSnakeStyle.jointed` if you would
rather keep one hairline self-joint, drawn in the surface colour on the head
cap's backward semicircle.

## Values too small to draw

A segment shorter than one band width of arc is two overlapping caps and reads
as a blob. There is no good answer to this, only two defensible ones, and the
chart makes you pick:

```dart
WovenMinimumPolicy.enforce      // lift it to the minimum, rescale the rest
WovenMinimumPolicy.allowVanish  // let it disappear under its neighbour
```

`enforce` is the default. It keeps the ring readable and gives up exact
proportions, so do not use it where the arc lengths are the message. `allowVanish`
keeps the proportions honest and drops anything under half the minimum.

## Animation

The first time a ring appears it draws itself. `WovenRingIntro.relay`, the
default, sends one head once round the circle, handing the colour over at each
boundary. `WovenRingIntro.bloom` opens every segment at once with a stagger.
`WovenRingIntro.none` appears finished.

Changing the data animates in place over `transitionDuration`, which defaults to
450ms. Segments stretch and shrink, colours crossfade, and nothing is torn down
and rebuilt, so the ring never blinks. Changing the data again mid-transition
picks up from the frame that is on screen instead of restarting.

To replay an intro later, hand the ring a controller:

```dart
final WovenRingController controller = WovenRingController();
// ...
WovenRing(snakes: snakes, controller: controller);
// ...
controller.replay();
```

Under `MediaQuery.disableAnimations` every intro and data change completes
immediately.

## Accessibility

Give the chart a `semanticLabel` and `semanticValue`, or label the segments
individually and let their labels be joined. Labelling the segments does not
take the centre widget out of the accessibility tree, because a segment label
describes a segment and says nothing about the total.

## The example

```sh
cd example
flutter run                          # the validation lab
flutter run -t lib/ten_snakes.dart   # ten segments, all animating
```

The lab has three tabs. Playground drives data, fill, border, intro, direction,
gradient axis, minimum policy, band, overlap, start angle, lift, selection, and
live data updates from real controls. Style matrix shows the fill by border by
direction cross product, plus the deliberately exaggerated diagnostic cases.
States shows empty, loading, both single-value styles, both minimum policies,
selection, and the head lift.

## How this is checked

288 tests run against the package and another 10 against the example app. Most
of the first number is one file, `test/catalog_test.dart`, which shares no
helper with the rest and re-derives the geometry from the written
specification instead of from `WovenRingGeometry`, so a bug in the production
geometry cannot hide inside the checker meant to catch it. The whole
specification collapses into one predicate it applies everywhere:

> at any covered point the visible owner is the covering segment whose head tip
> is the closest one behind that point in the drawing direction.

On top of that it measures rather than assumes. Every visible colour boundary is
checked to sit on a circle of radius `band / 2` centred on the next head's cap,
sampled at eighteen radii across the band, which is what rejects a radial seam
that happens to land in the right place. Thirteen configurations render at four
device pixels per logical pixel and scan every one of them to prove nothing
paints outside the silhouette, with a quarter of a logical pixel of margin for
antialiasing and nothing more.

[doc/TEST_MATRIX.md](https://github.com/omar-hanafy/woven_ring_chart/blob/main/doc/TEST_MATRIX.md) lists what each section covers.

```sh
dart analyze
flutter test
```

## License

MIT. See [LICENSE](https://github.com/omar-hanafy/woven_ring_chart/blob/main/LICENSE).
