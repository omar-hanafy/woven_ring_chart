/// Which of the three renderings a `WovenRingChart` is showing.
///
/// Internal: the mode is chosen by which constructor the caller used, not by a
/// parameter.
enum WovenRingChartMode {
  /// The woven ring built from the caller's segments.
  data,

  /// A flat neutral annulus with no joints.
  empty,

  /// A single neutral segment chasing itself around the track.
  loading,
}
