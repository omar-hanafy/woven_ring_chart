/// How a woven ring draws itself the first time it appears.
///
/// This covers the entrance, which runs again whenever a chart that had
/// nothing to draw is given data. Every other data change animates in place
/// over `WovenRingChart.transitionDuration`.
enum WovenRingAnimation {
  /// One head travels once around the circle, handing the colour over at each
  /// boundary as a new segment emerges on top of the one before it. The
  /// default.
  sweep,

  /// Every segment opens from its own starting boundary at once, staggered by
  /// index.
  grow,

  /// No entrance: the chart appears finished.
  none,
}
