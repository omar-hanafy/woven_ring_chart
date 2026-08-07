import 'package:flutter/foundation.dart';

/// Where one segment is actually drawn, in centreline angles, alongside the
/// data boundaries it came from.
///
/// Angles run clockwise from three o'clock, in radians, and are not wrapped.
@immutable
class WovenSegmentExtent {
  /// An extent with both its data boundaries and its drawn endpoints given.
  const WovenSegmentExtent({
    required this.boundaryStart,
    required this.boundaryEnd,
    required this.start,
    required this.end,
  });

  /// The invisible data line this segment starts on, before any overlap.
  final double boundaryStart;

  /// The invisible data line this segment ends on, which is also where the
  /// next segment's boundary begins.
  final double boundaryEnd;

  /// Centreline angle where the drawn bar starts, one joint lag behind
  /// [boundaryStart].
  ///
  /// The head cap sits one `WovenRingGeometry.capAngle` beyond it.
  final double start;

  /// Centreline angle where the drawn bar ends, on [boundaryEnd].
  ///
  /// The tail cap sits one `WovenRingGeometry.capAngle` beyond it, under the
  /// next segment.
  final double end;

  /// The tip of the head cap, the only edge of this segment anybody sees.
  ///
  /// [capAngle] is `WovenRingGeometry.capAngle` for the ring being drawn.
  double headApex(double capAngle, {required bool clockwise}) =>
      start - (clockwise ? 1.0 : -1.0) * capAngle;

  /// The tip of the tail cap, always underneath the next segment.
  ///
  /// [capAngle] is `WovenRingGeometry.capAngle` for the ring being drawn.
  double tailApex(double capAngle, {required bool clockwise}) =>
      end + (clockwise ? 1.0 : -1.0) * capAngle;
}
