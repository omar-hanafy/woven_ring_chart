/// A woven ring chart: a doughnut whose segments lap over one another like
/// shingles, so every edge between two colours is a true semicircle.
///
/// The whole chart falls out of three facts:
///
///   1. A segment is a constant-width bar with semicircular ends, bent along
///      the ring. That is exactly a round-capped stroke, so the cap radius is
///      half the ring's thickness by construction and can never drift.
///   2. Every segment is drawn over its predecessor, in one consistent
///      direction all the way round. It is shingling, not braiding.
///   3. That ordering is cyclic and z-order is not, so the last tail is split
///      into a covered underlay and a normally ordered visible portion. This
///      gives the seam the same layering as every other joint without needing
///      a special angular cut or a final-frame order swap.
///
/// Nothing here is a fixed pixel value; every measurement is a fraction of the
/// ring's outer diameter, so one style renders correctly at any size.
///
/// ```dart
/// import 'package:woven_ring_chart/woven_ring_chart.dart';
///
/// WovenRingChart(
///   segments: <WovenSegment>[
///     WovenSegment.solid(37, WovenPalette.purple),
///     WovenSegment.solid(19, WovenPalette.green),
///     WovenSegment.solid(29, WovenPalette.amber),
///     WovenSegment.solid(15, WovenPalette.rose),
///   ],
///   center: const Text('100'),
///   semanticLabel: 'Spending by category',
/// )
/// ```
///
/// Start at [WovenRingChart]. Data lives on [WovenSegment], everything else on
/// [WovenRingStyle], and [WovenRingGeometry] exposes the resolved geometry for
/// callers that need to measure or reproduce it.
library;

export 'src/geometry/ring_geometry.dart' show WovenRingGeometry;
export 'src/geometry/segment_extent.dart' show WovenSegmentExtent;
export 'src/geometry/segment_fractions.dart' show wovenSegmentFractions;
export 'src/model/animation.dart' show WovenRingAnimation;
export 'src/model/border.dart' show WovenBorder;
export 'src/model/fill.dart' show WovenFill;
export 'src/model/gradient.dart' show WovenGradientAxis, WovenGradientDirection;
export 'src/model/palette.dart' show WovenPalette;
export 'src/model/policy.dart'
    show WovenSingleSegmentStyle, WovenSmallValuePolicy;
export 'src/model/segment.dart' show WovenSegment;
export 'src/model/shadow.dart' show WovenShadow;
export 'src/model/style.dart' show WovenRingStyle;
export 'src/widgets/controller.dart' show WovenRingChartController;
export 'src/widgets/woven_ring_chart.dart' show WovenRingChart;
