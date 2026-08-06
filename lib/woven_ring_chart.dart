/// A woven ring: a doughnut whose segments lap over one another like shingles,
/// so every edge between two colours is a true semicircle.
///
/// The whole component falls out of three facts:
///
///   1. A snake is a constant-width bar with semicircular ends, bent along the
///      ring. That is exactly a round-capped stroke, so the cap radius is half
///      the band by construction and can never drift.
///   2. Every snake is drawn over its predecessor, one consistent direction all
///      the way round. It is shingling, not braiding.
///   3. That ordering is cyclic and z-order is not, so the last tail is split
///      into a covered underlay and a normally ordered visible portion. This
///      gives the seam the same layering as every other joint without needing
///      a special angular cut or a final-frame order swap.
///
/// Nothing here is a fixed pixel value; everything is a ratio of the ring's
/// outer diameter.
///
/// ```dart
/// WovenRing(
///   snakes: const <WovenSnake>[
///     WovenSnake.solid(25, WovenPalette.purple),
///     WovenSnake.solid(25, WovenPalette.green),
///     WovenSnake.solid(25, WovenPalette.amber),
///     WovenSnake.solid(25, WovenPalette.rose),
///   ],
///   semanticLabel: 'Category distribution',
/// )
/// ```
library;

export 'src/enums.dart'
    show
        WovenGradientAxis,
        WovenGradientDirection,
        WovenMinimumPolicy,
        WovenRingIntro,
        WovenSingleSnakeStyle;
export 'src/geometry.dart'
    show WovenRingGeometry, WovenSnakeExtent, wovenFractions;
export 'src/palette.dart' show WovenPalette;
export 'src/snake.dart' show WovenBorder, WovenFill, WovenLift, WovenSnake;
export 'src/style.dart' show WovenRingStyle;
export 'src/woven_ring.dart' show WovenRing, WovenRingController;
