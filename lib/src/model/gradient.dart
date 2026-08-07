/// Which way gradients run on a woven ring. One axis for the whole chart,
/// never mixed.
enum WovenGradientAxis {
  /// Along each segment's own length, head to tail. The default.
  ///
  /// The gradient restarts at every segment and runs cap tip to cap tip, so
  /// the rounded ends are shaded too.
  alongSegment,

  /// Radially across the ring's thickness, for a tube look. Lighter on the
  /// outer edge.
  ///
  /// This axis has no angular variation at all: every segment shows the same
  /// shading and the ring reads as a bent pipe.
  acrossThickness,
}

/// Which end of a `WovenFill` lands on a segment's visible cap.
enum WovenGradientDirection {
  /// `WovenFill.head` sits at the visible rounded end. The default.
  headToTail,

  /// `WovenFill.tail` sits at the visible rounded end.
  tailToHead,
}
