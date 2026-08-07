/// What a woven ring does with a value too small to draw as a segment.
///
/// A segment shorter than one ring-thickness of arc is two overlapping caps
/// and reads as a blob. There is no answer that is right for every chart, only
/// two defensible ones, so the choice is explicit.
enum WovenSmallValuePolicy {
  /// Raise anything below the minimum to the minimum and rescale the rest.
  ///
  /// The ring stays legible and the proportions stop being exact. The default.
  /// Avoid it where the arc lengths themselves are the message.
  enforce,

  /// Let small values disappear under their neighbour.
  ///
  /// Proportions stay truthful and anything below half the minimum is dropped
  /// entirely.
  allowVanish,
}

/// How a woven ring renders a single value that covers the whole circle.
enum WovenSingleSegmentStyle {
  /// Keep one visible self-joint, so the result still reads as woven.
  ///
  /// The mark is the head cap's own backward semicircle drawn in the chart's
  /// surface colour. It is the one edge the chart draws that no fill produced,
  /// and on a borderless ring it reads as a line rather than as a lap, which
  /// is why it is opt-in.
  jointed,

  /// Render a plain continuous ring. The default: one value has no boundary
  /// to show, so the ring shows none.
  smooth,
}
