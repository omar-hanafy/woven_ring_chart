# woven_ring_chart example

Two entrypoints.

```sh
flutter run                            # the validation lab
flutter run -t lib/ten_segments.dart   # ten segments, all animating
```

The lab has three tabs:

- **Playground** drives data, fill, border, animation, direction, gradient axis,
  small-value policy, thickness, overlap, start angle, shadow, selection, and
  live data updates from real controls.
- **Style matrix** shows the fill by border by direction cross product, plus
  mixed, across-thickness, dense-seam, and deliberately exaggerated diagnostic
  cases. The normal gradient is subtle and the normal border is a hairline on
  purpose, so the diagnostic modes exist to make the geometry unambiguous while
  you look at it. They are inspection aids, not a recommendation.
- **States** shows empty, loading, both single-segment styles, both small-value
  policies, selection, and the head shadow.

`lib/ten_segments.dart` is one screen with ten segments, every one gradient
filled and bordered. It replays the entrance animation every 11 seconds and
changes data every 2.2 seconds between four fixed sets, so both animated paths
stay on screen without touching a control.

```sh
flutter test
```

runs the lab's own widget tests: that every control is wired to the chart, and
that driving them cannot break it.
