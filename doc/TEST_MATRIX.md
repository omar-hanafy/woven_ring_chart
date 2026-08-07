# Validation matrix

No focused check replaces this gate. After every Dart change, run:

```sh
bash tool/validate_all.sh
```

The change is not complete unless the whole command passes.

## How the suite is layered

`test/spec/catalog_test.dart` is the A-to-Z gate. It shares no helper with the
other test files and re-derives geometry and ownership from the written specification
rather than from `WovenRingGeometry`, so a bug in the production geometry cannot
hide inside the checker meant to catch it. The whole spec collapses into one
predicate it applies everywhere:

> at any covered point the visible owner is the covering segment whose head tip is
> the closest one behind that point in the drawing direction.

The suites under `test/geometry/`, `test/model/`, `test/painting/`, and
`test/widgets/` cover the value types, the painter's internals, and the widget's
lifecycle. They share fixtures through `test/support/`. They are not the gate: a
regression must be caught by the catalog. `example/test/demo_app_test.dart`
covers the example app's own wiring and runs from the example directory.

Any check that is deliberately narrowed says so at the call site and names what
covers it instead. `_TopologyTransitionCase.checkCyclicOwnership` is `required`
for exactly this reason. A case that silently inherits "off" verifies only alpha
and frame-to-frame smoothness, which is how a seam regression can pass that file
untouched.

## 1. Geometry and data (catalog section A)

- Cap radius is exactly half the thickness at every thickness, and the silhouette
  closes on the outer circle.
- The independent ring derivation agrees with `WovenRingGeometry` on thickness,
  track, and joint lag.
- Fractions stay finite, ordered, non-negative, and sum to one for empty,
  negative, zero, NaN, infinity, subnormal, and overflow-scale input under both
  minimum policies.
- Enforcement raises every positive value to the minimum and is continuous across
  the threshold; too many entries fall back to an honest equal share.
- Allow-vanish removes only values below its documented threshold.
- CW and CCW mirror about the start angle, preserve input order, and chain each
  tail onto the next data boundary exactly.
- Palette cycling never repeats a colour across the seam.

## 2. Static raster (catalog sections B, C, H)

Fifty-two configurations, each checked for full ring coverage, an exact
two-circle silhouette with an untouched hole, and the spec's owner at every
unambiguous pixel on a five-radius polar grid:

- One, two, three, four, ten, and twelve segments; equal, unequal, tiny-enforced,
  tiny-vanished, and zero-mixed data; CW and CCW; cardinal and non-cardinal
  start angles including negative wrap.
- Short segments, which is where a covering run can close the whole cycle and
  leave the successor mask with no answer: two and three segments at 90/10 and
  80/10/10 in every rotation, and a segment past 88 percent, where its own head
  and tail caps touch and its outline self-intersects.
- Thickness at its minimum, default, maximum, and both clamps. Overlap at 25, 30, 50,
  90, and 100 percent, including thin and wide rings at 90 percent.
- Solid, along-segment gradient, tail-to-head gradient, across-thickness gradient, and
  mixed fills. No border, all borders, mixed borders, diagnostic wide borders,
  darker-fill borders, and selection. Head shadow. Dark surface.

Then, measured rather than assumed:

- Every visible colour boundary sits on a circle of radius `thickness / 2` centred on
  the successor head's cap centre, sampled at eighteen radii across the ring.
- Nothing paints outside the silhouette, measured below the pixel. The ring
  probe two pixels clear of each edge cannot see a stroke that spills less than
  a whole pixel, and a stroke centred on the boundary spills exactly half its
  width. Thirteen cases render at four device pixels per logical pixel and scan
  every one of them, over both single-value styles, both directions, both thickness   clamps, an off-axis start, borders plain and diagnostic, plain and bordered
  four-segment rings, a self-lapping segment, and every frame of a four-to-one
  merge. The margin allowed is a quarter of a logical pixel, which is the
  antialiasing of the true circles and nothing more.
- A segment that laps its own tail joins with that same cap circle and shows no
  second edge anywhere else, so a sweep gradient's radial wrap is rejected even
  when a joint hairline sits on the correct edge and could mask it.
- Along-segment gradients run head to tail the right way round for both gradient
  directions and both senses of rotation; across-thickness gradients have no angular
  variation at all and do shade across it.

## 3. States (catalog section D)

- Empty is one uniform neutral annulus with no joint and the right silhouette,
  and its exact alpha is pinned because the transition checks lean on it.
- Loading animates and stops dead when the ring is replaced.
- A single 100 percent segment fills the whole annulus; jointed keeps a hairline
  self-joint, smooth keeps none. Smooth is the default, and the default is
  pinned by its own check that walks seven radii across the whole ring, so a
  seam mark cannot come back by way of a changed default.
- All-zero data falls back to the empty track without painting any segment.

## 4. Motion (catalog sections E, F)

- Sweep and grow, CW and CCW, settle bit-for-bit onto the static rendering, so
  a seam that changes owner on the final frame fails.
- Neither ever paints outside the outer circle or into the hole, at any frame.
- Every free end of a growing ring is a true cap circle, both ends of every
  covered run, sampled through completion in both directions and both animations.
- A self-lapping segment buries no border: every border pixel has background
  within a stroke width, so stroking an outline through two overlapped caps
  fails.
- Replay restarts and re-settles on the same frame, five times over.
- Fourteen data moves in both directions, including value changes, four to ten,
  ten to four, four to one, one to four, four to two, two to four, two to one,
  one to two, three to two, to-zero and from-zero, keep the ring covered at
  every frame and land exactly on the static destination.
- Joint ownership holds through the whole transition for flat, gradient,
  bordered, and shadowed rings in both directions, checked by colour-run order
  round the centreline so it needs no knowledge of the interpolated fractions.
- Retargeting mid-flight begins from the exact frame already on screen and never
  opens a gap.

## 5. Widget contract (catalog section G)

- Nine layout shapes, including both unbounded axes, zero, one pixel, and huge.
- Reduced motion completes the animation and every data change immediately.
- Disposal leaves no live ticker in any mode.
- Aggregate and per-segment semantics are both reachable, and adding a per-segment
  label does not take the centre away from assistive technology.
- Mutating a reused list instance is still picked up.

## 6. Manual runtime gate

Automated checks run against a software rasteriser. Once per painter change,
also look at the real thing:

```sh
flutter test tool/render_catalog.dart   # 316 PNGs to build/catalog_png
cd example && flutter run
```

The sweep covers the whole demo control matrix: every data case by fill by
border by direction, the geometry sliders at their endpoints, the gradient axis
and direction cross-product at one, two, four, and ten segments, the short-segment
cases in both rotations, every state, and six frames through each animation. Montage
them and look; then in the running app walk all three tabs and confirm the
console holds no exception or failed assertion.
