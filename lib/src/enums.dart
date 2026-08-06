/// Which way a gradient runs. One axis for the entire ring, never mixed.
enum WovenGradientAxis {
  /// Along each snake's own length, head to tail. The default.
  ///
  /// The gradient restarts at every snake and runs cap tip to cap tip, so the
  /// rounded ends are shaded too.
  alongLength,

  /// Across the band, a tube look. Lighter on the outer edge.
  ///
  /// This one is radial, so it has no angular variation at all: every snake
  /// shows the same shading and the ring reads as a bent pipe.
  acrossBand,
}

/// Every gradient snake runs the same way round the ring.
enum WovenGradientDirection {
  /// The `WovenFill.head` colour sits at the visible rounded end.
  headToTail,

  /// The `WovenFill.tail` colour sits at the visible rounded end.
  tailToHead,
}

/// How the ring draws itself the first time it appears.
enum WovenRingIntro {
  /// One head travels once round the circle, changing colour at each
  /// boundary as a new snake emerges on top of the one before it.
  relay,

  /// Every snake grows from its own start at once, with a stagger by index.
  bloom,

  /// Appears finished.
  none,
}

/// What to do with values too small to read as a snake.
enum WovenMinimumPolicy {
  /// Inflate anything under one band width of arc, and rescale the rest.
  /// Proportions stop being truthful; the ring stays legible.
  enforce,

  /// Let small values disappear under their neighbour. Proportions stay
  /// truthful; small values vanish completely.
  allowVanish,
}

/// How a 100 percent single value is rendered.
enum WovenSingleSnakeStyle {
  /// Keep one visible self-joint so the result still reads as a woven snake.
  ///
  /// The mark is the head cap's own backward semicircle, drawn in the surface
  /// colour. It is the one place the component draws an edge that no fill
  /// produced, and on a borderless ring it reads as a line rather than as a
  /// lap, so it is opt-in rather than the default.
  jointed,

  /// Render a plain continuous ring, the simpler alternative from the spec.
  /// The default: one value has no boundary to show, so the ring shows none.
  smooth,
}

/// Which of the three renderings a `WovenRing` is showing.
enum WovenRingMode {
  /// The woven ring built from the caller's snakes.
  data,

  /// A flat neutral annulus with no joints.
  empty,

  /// A single neutral snake chasing itself around the track.
  loading,
}
