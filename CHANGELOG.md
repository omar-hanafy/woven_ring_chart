# Changelog

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0-dev.3] - 2026-08-06

### Fixed

- The README animation and the screenshot are rendered against the ring's
  surface colour again. The capture boundary sat inside the coloured
  background rather than around it, so both came out transparent. A GIF has
  one bit of transparency, which cut every antialiased edge into a hard
  stair-step; the animation is now smooth, and smaller for it. It also makes
  the pictures honest, since a border with no colour of its own paints in the
  surface colour and only reads correctly against that surface.

## [1.0.0-dev.2] - 2026-08-06

### Fixed

- The README's images and links now point at absolute URLs. pub.dev does not
  resolve relative paths in a README: it drops the image and leaves the alt
  text, so on 1.0.0-dev.1 the animation, the screenshot, and the links to the
  test matrix and the licence were all missing from the package page.

## [1.0.0-dev.1] - 2026-08-06

First prerelease. The API is complete and the suite is green; the dev
line runs until the release is proven, and 1.0.0 follows unchanged unless
something turns up.

### Added

- `WovenRing`, a doughnut chart whose segments lap over one another in one
  consistent direction. Every boundary between two colours is the backward
  semicircle of a round cap, including the seam where the last segment closes
  onto the first.
- `WovenRing.empty` and `WovenRing.loading`, both the same size and band width
  as a ring with data, so a screen does not reflow when the data arrives.
- `WovenRingStyle`: band width, overlap depth, start angle, direction, gradient
  axis and direction, surface colour, an optional head shadow, and the two
  policies below. Every measurement is a ratio of the outer diameter, so one
  style renders correctly at any size.
- `WovenSnake` with `WovenFill` (solid, explicit gradient, or `WovenFill.shaded`
  from a single colour) and an optional `WovenBorder`. Borders are clipped
  inside the snake, so a bordered segment is never fatter than its neighbours
  and the ring's outer edge stays a circle.
- `WovenMinimumPolicy`, choosing whether a value too small to draw is inflated
  to one band width of arc and the rest rescaled, or allowed to vanish under its
  neighbour with the proportions left truthful.
- `WovenSingleSnakeStyle`, choosing whether a lone 100 percent value keeps a
  visible self-joint. It renders as a plain continuous ring by default.
- Two intros, `WovenRingIntro.relay` and `WovenRingIntro.bloom`, and
  `WovenRingController.replay()` to run one again. Data changes animate in
  place: segments stretch and shrink and colours crossfade, so the ring never
  blinks. Retargeting mid-flight starts from the frame already on screen.
- `MediaQuery.disableAnimations` support, completing intros and data changes
  immediately.
- Semantics: `semanticLabel` and `semanticValue` for the chart, or per-snake
  labels that are joined when no chart-level label is given. Labelling segments
  does not remove the centre widget from the accessibility tree.
- `WovenPalette`, the reference colours plus `WovenPalette.cycle`, which repeats
  a palette without letting a colour touch itself across the seam.
- `WovenRingGeometry` and `wovenFractions`, the geometry and normalization the
  widget uses, exported so they can be tested or reused directly.
