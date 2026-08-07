# Changelog

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.2] - 2026-08-07

### Changed

- `example/lib/main.dart` is the short getting-started example, which is what
  pub.dev shows under Example. The showcase moved to
  `example/lib/showcase.dart`.

## [1.0.1] - 2026-08-07

### Changed

- The example is now a single-page showcase, live at
  <https://omar-hanafy.github.io/woven_ring_chart/>, and the README links to it.

## [1.0.0] - 2026-08-07

Initial release.

### Added

- `WovenRingChart`, a doughnut chart whose segments lap over one another in one
  consistent direction. Every boundary between two colours is the backward
  semicircle of a round cap, including the seam where the last segment closes
  onto the first. The chart is square and centres itself in whatever box it is
  given.
- `WovenRingChart.empty` and `WovenRingChart.loading`, both the same diameter
  and thickness as a chart with data, so a screen does not reflow when the data
  arrives.
- `WovenSegment`, one coloured piece of the ring, carrying a value in any unit,
  a fill, an optional border, an optional accessibility label, and an opacity.
  Values are normalized against each other and their order is never changed.
- `WovenFill`, solid, an explicit gradient, or `WovenFill.shaded` derived from a
  single colour, and `WovenBorder`, an optional hairline. Borders are clipped
  inside the segment, so a bordered segment is never fatter than its neighbours
  and the ring's outer edge stays a circle.
- `WovenRingStyle`: thickness, overlap depth, start angle, direction, gradient
  axis and direction, surface colour, an optional `WovenShadow` under every
  segment head, and the two policies below. Every measurement is a fraction of
  the outer diameter, so one style renders correctly at any size.
- `WovenSmallValuePolicy`, choosing whether a value too small to draw is raised
  to one ring-thickness of arc with the rest rescaled, or allowed to vanish
  under its neighbour with the proportions left truthful.
- `WovenSingleSegmentStyle`, choosing whether a lone value covering the whole
  ring keeps a visible self-joint. It renders as a plain continuous ring by
  default.
- Two entrance animations, `WovenRingAnimation.sweep` and
  `WovenRingAnimation.grow`, and `WovenRingChartController.replay()` to run one
  again. Data changes animate in place: segments stretch and shrink and colours
  crossfade, so the chart never blinks. Retargeting mid-flight starts from the
  frame already on screen.
- `highlightedIndex` and `highlightBorder`, giving one segment a border while
  the others stay unbordered.
- `MediaQuery.disableAnimations` support, completing entrances and data changes
  immediately.
- Semantics: `semanticLabel` and `semanticValue` for the chart, or per-segment
  labels that are joined when no chart-level label is given. Labelling segments
  does not remove the centre widget from the accessibility tree, and the
  loading chart announces itself as a live region.
- `WovenPalette`, a reference set of colours plus `WovenPalette.cycle`, which
  repeats a palette without letting a colour touch itself across the seam.
- `WovenRingGeometry`, `WovenSegmentExtent`, and `wovenSegmentFractions`, the
  geometry and normalization the chart uses, exported so they can be measured
  against or reused directly.
