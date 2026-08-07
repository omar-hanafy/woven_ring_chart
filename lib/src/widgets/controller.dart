import 'package:flutter/foundation.dart';

/// Replays a chart's entrance animation on demand.
///
/// Useful for demos and for "refresh" affordances. Create one, hand it to a
/// `WovenRingChart`, and dispose it with the state that owns it.
///
/// ```dart
/// final WovenRingChartController controller = WovenRingChartController();
/// // ...
/// WovenRingChart(segments: segments, controller: controller);
/// // ...
/// controller.replay();
/// ```
///
/// A controller attached to a chart whose animation is `WovenRingAnimation.none`
/// does nothing.
class WovenRingChartController extends ChangeNotifier {
  /// Creates a controller. Dispose it with the state that owns it.
  WovenRingChartController();

  /// Runs the chart's entrance animation again from the beginning, even if it
  /// had already finished.
  ///
  /// Under reduced motion the animation jumps straight to its final frame.
  void replay() => notifyListeners();
}
