import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../geometry/ring_geometry.dart';
import '../geometry/segment_fractions.dart';
import '../model/animation.dart';
import '../model/border.dart';
import '../model/chart_mode.dart';
import '../model/fill.dart';
import '../model/palette.dart';
import '../model/segment.dart';
import '../model/style.dart';
import '../painting/ring_painter.dart';
import 'controller.dart';

/// A doughnut chart whose segments lap over one another like shingles.
///
/// Every boundary between two colours is the backward semicircle of a round
/// cap, because a segment is a constant-width bar with semicircular ends bent
/// along the ring. The chart is square: it takes the smaller of its constraints
/// and centres itself in whatever box it is given, so it is safe inside a
/// [Row], a card, or an unbounded scroll view. With no bounded side at all it
/// settles at 240 logical pixels.
///
/// ```dart
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
/// Use [WovenRingChart.empty] for a chart with no data yet and
/// [WovenRingChart.loading] while data is on its way: both keep the diameter
/// and thickness of a chart with data, so nothing on screen jumps when the
/// data lands.
class WovenRingChart extends StatefulWidget {
  /// A ring built from [segments].
  ///
  /// The list is snapshotted on every build, so a caller may keep and mutate
  /// its own list. Changing the data animates over [transitionDuration]:
  /// segments stretch and shrink in place rather than being torn down. The
  /// first data to arrive plays [animation] instead.
  const WovenRingChart({
    super.key,
    required this.segments,
    this.style = const WovenRingStyle(),
    this.animation = WovenRingAnimation.sweep,
    this.animationDuration = const Duration(milliseconds: 1000),
    this.transitionDuration = const Duration(milliseconds: 450),
    this.center,
    this.highlightedIndex,
    this.highlightBorder = const WovenBorder(),
    this.controller,
    this.semanticLabel,
    this.semanticValue,
  }) : _mode = WovenRingChartMode.data;

  /// A flat neutral ring at low opacity, with no joints.
  ///
  /// Same diameter and thickness as a chart with data.
  const WovenRingChart.empty({
    super.key,
    this.style = const WovenRingStyle(),
    this.center,
    this.semanticLabel,
    this.semanticValue,
  }) : segments = const <WovenSegment>[],
       animation = WovenRingAnimation.none,
       animationDuration = Duration.zero,
       transitionDuration = Duration.zero,
       highlightedIndex = null,
       highlightBorder = const WovenBorder(),
       controller = null,
       _mode = WovenRingChartMode.empty;

  /// A single neutral segment chasing itself around the track.
  ///
  /// Same diameter and thickness as a chart with data. A [semanticLabel] or a
  /// [semanticValue] is what makes the chart announce itself as a live region
  /// while it is loading; with neither, it publishes no semantics at all.
  const WovenRingChart.loading({
    super.key,
    this.style = const WovenRingStyle(),
    this.center,
    this.semanticLabel,
    this.semanticValue,
  }) : segments = const <WovenSegment>[],
       animation = WovenRingAnimation.none,
       animationDuration = const Duration(milliseconds: 1400),
       transitionDuration = Duration.zero,
       highlightedIndex = null,
       highlightBorder = const WovenBorder(),
       controller = null,
       _mode = WovenRingChartMode.loading;

  /// The segments, in the order they are laid around the ring.
  ///
  /// Order is kept exactly as given: the chart never sorts or rebalances for
  /// looks. Each segment is drawn over the one before it, so the last one laps
  /// the first at the seam. Values are normalized against each other, so
  /// percentages, counts, and currency all work.
  final List<WovenSegment> segments;

  /// Proportions, direction, colours, and policies. Everything that is not
  /// data.
  ///
  /// A new style takes effect on the next frame. Changing the resolved
  /// thickness or the small-value policy also re-runs the rules that turn
  /// values into shares of the ring, so the segments animate to their new
  /// shares over [transitionDuration]; every other field simply repaints.
  final WovenRingStyle style;

  /// How the chart draws itself the first time it appears.
  ///
  /// It runs again whenever a chart that had nothing to draw is given data: a
  /// chart built with an empty list waits, finished, until values arrive and
  /// then draws itself. Every other data change animates in place over
  /// [transitionDuration] instead.
  final WovenRingAnimation animation;

  /// How long [animation] takes. One second by default.
  final Duration animationDuration;

  /// How long a data change takes. 450ms by default.
  ///
  /// Segments stretch and shrink in place and colours crossfade; nothing is
  /// torn down and rebuilt, so the chart never blinks. Changing the data again
  /// mid-transition picks up from the frame already on screen.
  final Duration transitionDuration;

  /// A widget shown in the ring's hole, optically centred with real breathing
  /// room from the ring itself.
  ///
  /// It is laid out in a centred square that clears the ring on every side:
  /// about 57 percent of [WovenRingGeometry.holeDiameter], which is roughly a
  /// third of the chart at the default thickness. A larger widget is
  /// constrained to that square, not to the whole hole.
  final Widget? center;

  /// Index into [segments] of the one segment to highlight, or null for none.
  ///
  /// The highlighted segment takes [highlightBorder] in place of its own
  /// border for as long as this is set. An index outside the list highlights
  /// nothing and is not an error.
  final int? highlightedIndex;

  /// The border given to the segment at [highlightedIndex].
  final WovenBorder highlightBorder;

  /// Replays [animation] on demand.
  ///
  /// The caller owns the controller and must dispose it.
  final WovenRingChartController? controller;

  /// Localized accessibility text describing the chart as a whole.
  ///
  /// Without one, the labels of every segment carrying a positive value are
  /// joined instead, in order; a segment the small-value policy dropped still
  /// contributes its label. A chart with none of this, [semanticValue], or a
  /// segment label publishes no semantics of its own.
  ///
  /// Setting either this or [semanticValue] means the caller has described the
  /// whole chart, so [center] is hidden from assistive technology to avoid
  /// reading the same number twice.
  final String? semanticLabel;

  /// Localized value text for the chart, such as the total the centre shows.
  final String? semanticValue;

  final WovenRingChartMode _mode;

  @override
  State<WovenRingChart> createState() => _WovenRingChartState();
}

@immutable
class _WovenFrame {
  const _WovenFrame({
    required this.segments,
    required this.fractions,
    this.topologyMerge = 0.0,
    this.topologyAnchor,
    this.visualStyles,
  });

  final List<WovenSegment> segments;
  final List<double> fractions;
  final double topologyMerge;
  final int? topologyAnchor;
  final List<_WovenVisualStyle>? visualStyles;

  _WovenFrame withTopology(double merge, int? anchor) => _WovenFrame(
    segments: segments,
    fractions: fractions,
    topologyMerge: merge,
    topologyAnchor: anchor,
    visualStyles: visualStyles,
  );
}

// A canonical ring can move between logical indices while its visible style
// morphs in place. Each logical index retains a bounded border substitution,
// so highlighting replaces that index without changing other contributions.
class _WovenVisualStyle {
  const _WovenVisualStyle.segment(this.segment, this.index)
    : substitutions = const <int, WovenBorderSubstitution>{};

  factory _WovenVisualStyle.lerp(
    _WovenVisualStyle a,
    _WovenVisualStyle b,
    double t,
    Color surfaceColor,
  ) {
    final WovenSegment segment = WovenSegment.lerp(
      a.segment,
      b.segment,
      t,
      surfaceColor: surfaceColor,
    );
    // The destination is always a freshly resolved logical segment. Captured
    // visual state occurs only at the source of a retargeted transition.
    assert(b.index != null);
    final substitutions = <int, WovenBorderSubstitution>{};
    for (final selected in <int>{
      ...a.substitutions.keys,
      if (a.index != null) a.index!,
      b.index!,
    }) {
      final previous =
          a.substitutions[selected] ??
          (a.index == selected
              ? WovenBorderSubstitution.highlight(a.segment.fill, surfaceColor)
              : WovenBorderSubstitution.border(
                  a.segment.border,
                  a.segment.fill,
                  surfaceColor,
                ));
      substitutions[selected] = previous.lerpTo(
        b.segment.border,
        t,
        replace: b.index == selected,
        fill: segment.fill,
        surface: surfaceColor,
      );
    }
    return _WovenVisualStyle._(
      segment: segment,
      substitutions: Map<int, WovenBorderSubstitution>.unmodifiable(
        substitutions,
      ),
    );
  }

  const _WovenVisualStyle._({
    required this.segment,
    required this.substitutions,
  }) : index = null;

  final WovenSegment segment;
  final int? index;
  final Map<int, WovenBorderSubstitution> substitutions;

  WovenSegment resolve(int? highlighted, WovenBorder highlight, Color surface) {
    final WovenBorder? border;
    if (index != null) {
      border = index == highlighted ? highlight : segment.border;
    } else {
      final substitution = substitutions[highlighted];
      border = substitution == null
          ? segment.border
          : substitution.resolve(highlight, segment.fill, surface);
    }
    return segment.copyWith(border: border, removeBorder: border == null);
  }
}

class _WovenRingChartState extends State<WovenRingChart>
    with TickerProviderStateMixin {
  late final AnimationController _animation;
  late final AnimationController _transition;
  late final AnimationController _spin;
  late Listenable _repaint;

  _WovenFrame _fromFrame = const _WovenFrame(
    segments: <WovenSegment>[],
    fractions: <double>[],
  );
  _WovenFrame _toFrame = const _WovenFrame(
    segments: <WovenSegment>[],
    fractions: <double>[],
  );
  List<WovenSegment> _inputSnapshot = const <WovenSegment>[];
  bool _disableAnimations = false;

  // A transition can retain outgoing entries beyond the current public list.
  // They must not extend the range of selectable indices.
  int? get _resolvedHighlightedIndex {
    final int? index = widget.highlightedIndex;
    return index != null && index >= 0 && index < widget.segments.length
        ? index
        : null;
  }

  @override
  void initState() {
    super.initState();
    _animation = AnimationController(
      vsync: this,
      duration: _safeDuration(widget.animationDuration),
    );
    _transition = AnimationController(
      vsync: this,
      duration: _safeDuration(widget.transitionDuration),
    );
    _transition.addListener(() {
      if (_transition.value >= 1.0 &&
          !_toFrame.fractions.any((double fraction) => fraction > 0.0)) {
        // The fade has removed the final drawable segment. Completing the
        // entrance now stops its ticker without changing the fade or a
        // mid-flight retarget that brings data back before the fade finishes.
        _animation.value = 1.0;
        // The controller can reach its final value before its simulation
        // reports completion. No extra transition tick can change this frame.
        _transition.stop(canceled: false);
      }
    });
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _repaint = Listenable.merge(<Listenable>[_animation, _transition, _spin]);

    _inputSnapshot = _snapshot(widget.segments);
    _fromFrame = _resolveFrame(_inputSnapshot, widget.style);
    _toFrame = _fromFrame;

    if (widget._mode == WovenRingChartMode.loading) {
      _spin.repeat();
    } else if (widget.animation == WovenRingAnimation.none ||
        !_fromFrame.fractions.any((double fraction) => fraction > 0.0)) {
      _animation.value = 1;
    } else {
      _animation.forward();
    }
    widget.controller?.addListener(_replay);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bool disable =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (_disableAnimations == disable) return;
    _disableAnimations = disable;
    if (disable) {
      _animation.value = 1.0;
      _transition.value = 1.0;
      _spin.stop();
    } else if (widget._mode == WovenRingChartMode.loading &&
        !_spin.isAnimating) {
      _spin.repeat();
    }
  }

  @override
  void didUpdateWidget(WovenRingChart old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller?.removeListener(_replay);
      widget.controller?.addListener(_replay);
    }
    _animation.duration = _safeDuration(widget.animationDuration);
    _transition.duration = _safeDuration(widget.transitionDuration);

    if (widget._mode == WovenRingChartMode.loading &&
        !_disableAnimations &&
        !_spin.isAnimating) {
      _spin.repeat();
    } else if (widget._mode != WovenRingChartMode.loading &&
        _spin.isAnimating) {
      _spin.stop();
    }

    final List<WovenSegment> nextSnapshot = _snapshot(widget.segments);
    final bool dataChanged = !listEquals(_inputSnapshot, nextSnapshot);
    final bool fractionRulesChanged =
        old.style.resolvedThicknessFraction !=
            widget.style.resolvedThicknessFraction ||
        old.style.smallValuePolicy != widget.style.smallValuePolicy;
    if (dataChanged || fractionRulesChanged) {
      final _WovenFrame current = _currentFrame();
      final bool hadData = current.fractions.any(
        (double fraction) => fraction > 1e-12,
      );
      final bool hasData = nextSnapshot.any((WovenSegment s) => s.value > 0.0);
      _inputSnapshot = nextSnapshot;
      final _WovenFrame next = _resolveFrame(nextSnapshot, widget.style);

      if (!hadData) {
        _fromFrame = next;
        _toFrame = next;
        _transition.value = 1.0;
        if (hasData &&
            !_disableAnimations &&
            widget.animation != WovenRingAnimation.none) {
          _animation.forward(from: 0.0);
        } else {
          _animation.value = 1.0;
        }
      } else {
        final List<int> currentActive = <int>[
          for (var i = 0; i < current.fractions.length; i++)
            if (current.fractions[i] > 1e-12) i,
        ];
        final List<int> nextActive = <int>[
          for (var i = 0; i < next.fractions.length; i++)
            if (next.fractions[i] > 1e-12) i,
        ];
        _WovenFrame transitionFrom = current;
        _WovenFrame transitionTo = next;
        if (currentActive.length == 1 && nextActive.length > 1) {
          final int anchor = currentActive.single;
          transitionFrom = current.withTopology(1.0, anchor);
          transitionTo = next.withTopology(0.0, anchor);
        } else if (currentActive.length > 1 && nextActive.length == 1) {
          final int requestedAnchor =
              current.topologyMerge > 0.0 && current.topologyAnchor != null
              ? current.topologyAnchor!
              : nextActive.single;
          // Retargeting an in-flight many-to-single transition must keep the
          // anchor that is already on screen. Switching it immediately changes
          // the canonical overlay before animation time advances. If the
          // requested sole segment did not exist in the current data, use a
          // visible current segment and morph its visual style to the destination.
          final int anchor = currentActive.contains(requestedAnchor)
              ? requestedAnchor
              : currentActive.first;
          transitionFrom = current.withTopology(current.topologyMerge, anchor);
          transitionTo = next.withTopology(1.0, anchor);
        } else if (current.topologyMerge > 0.0) {
          transitionTo = next.withTopology(0.0, current.topologyAnchor);
        }
        _fromFrame = transitionFrom;
        _toFrame = transitionTo;
        if (_disableAnimations || widget.transitionDuration == Duration.zero) {
          _transition.value = 1.0;
        } else {
          _transition.forward(from: 0.0);
        }
      }
    }

    if (old.animation != widget.animation &&
        widget.animation == WovenRingAnimation.none) {
      _animation.value = 1.0;
    }
  }

  void _replay() {
    if (widget.animation == WovenRingAnimation.none) return;
    if (_disableAnimations ||
        !_currentFrame().fractions.any((double fraction) => fraction > 0.0)) {
      _animation.value = 1.0;
    } else {
      _animation.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_replay);
    _animation.dispose();
    _transition.dispose();
    _spin.dispose();
    super.dispose();
  }

  /// The exact frame currently on screen. Fractions are interpolated directly
  /// instead of re-running the nonlinear minimum policy on every tick. This is
  /// what makes zero/count/allow-vanish transitions continuous and lets a
  /// mid-flight retarget begin from the bit-for-bit current geometry.
  _WovenFrame _currentFrame() {
    if (identical(_fromFrame, _toFrame) || _transition.value >= 1.0) {
      return _toFrame;
    }
    if (_transition.value <= 0.0) return _fromFrame;

    final int n = math.max(
      _fromFrame.segments.length,
      _toFrame.segments.length,
    );
    final _WovenFrame from = _padFrame(_fromFrame, n);
    final _WovenFrame to = _padFrame(_toFrame, n);
    final double t = Curves.easeInOut.transform(_transition.value);
    final List<int> fromActive = <int>[
      for (var i = 0; i < n; i++)
        if (from.fractions[i] > 0.0) i,
    ];
    final List<int> toActive = <int>[
      for (var i = 0; i < n; i++)
        if (to.fractions[i] > 0.0) i,
    ];
    if (fromActive.length == 1 &&
        toActive.length == 1 &&
        (fromActive.single != toActive.single || from.visualStyles != null)) {
      final int anchor = fromActive.single;
      final _WovenVisualStyle visible = _WovenVisualStyle.lerp(
        _visualStyleAt(from, anchor),
        _visualStyleAt(to, toActive.single),
        t,
        widget.style.surfaceColor,
      );
      // Both endpoints are the same full-circle topology. Interpolating their
      // logical indices as fractions would invent two woven heads, rotate the
      // gradient, and expose a new shadow on the first tick. Morph one fixed
      // canonical ring instead, retaining partial coverage from an empty fade.
      final double coverage =
          from.fractions[anchor] +
          (to.fractions[toActive.single] - from.fractions[anchor]) * t;
      final List<WovenSegment> canonical = <WovenSegment>[
        for (var i = 0; i < n; i++)
          i == anchor
              ? visible.segment
              : to.segments[i].copyWith(value: 0, opacity: 0),
      ];
      return _WovenFrame(
        segments: List<WovenSegment>.unmodifiable(canonical),
        fractions: List<double>.unmodifiable(<double>[
          for (var i = 0; i < n; i++) i == anchor ? coverage : 0.0,
        ]),
        visualStyles: List<_WovenVisualStyle>.unmodifiable(<_WovenVisualStyle>[
          for (var i = 0; i < n; i++)
            i == anchor ? visible : _WovenVisualStyle.segment(canonical[i], i),
        ]),
      );
    }
    final List<WovenSegment> segments = <WovenSegment>[];
    final List<double> fractions = <double>[];
    // A canonical overlay keeps a visible geometry anchor even when its
    // destination has a different logical index. Carry that visual identity
    // through topology transitions so highlights morph with the destination.
    final List<_WovenVisualStyle>? visualStyles =
        from.visualStyles == null &&
            from.topologyMerge <= 0.0 &&
            to.topologyMerge <= 0.0
        ? null
        : <_WovenVisualStyle>[];

    for (var i = 0; i < n; i++) {
      WovenSegment a = from.segments[i];
      WovenSegment b = to.segments[i];
      _WovenVisualStyle? aStyle = visualStyles == null
          ? null
          : _visualStyleAt(from, i);
      _WovenVisualStyle? bStyle = visualStyles == null
          ? null
          : _visualStyleAt(to, i);
      if (from.fractions[i] <= 1e-12 && to.fractions[i] > 1e-12) {
        a = WovenSegment(
          value: 0,
          fill: _neighborFill(from, i),
          semanticLabel: a.semanticLabel,
        );
        if (visualStyles != null) aStyle = _WovenVisualStyle.segment(a, i);
      }
      if (to.fractions[i] <= 1e-12 && from.fractions[i] > 1e-12) {
        WovenSegment? topologyDestination;
        int? destinationIndex;
        if (to.topologyMerge > 0.0 && from.topologyAnchor == i) {
          for (
            var destination = 0;
            destination < to.fractions.length;
            destination++
          ) {
            if (to.fractions[destination] > 1e-12) {
              topologyDestination = to.segments[destination];
              destinationIndex = destination;
              break;
            }
          }
        }
        b = WovenSegment(
          value: 0,
          fill: topologyDestination?.fill ?? _neighborFill(to, i),
          border: topologyDestination?.border,
          semanticLabel: topologyDestination?.semanticLabel ?? b.semanticLabel,
          opacity: topologyDestination?.opacity ?? 1.0,
        );
        if (visualStyles != null) {
          bStyle = _WovenVisualStyle.segment(b, destinationIndex ?? i);
        }
      }
      segments.add(
        WovenSegment.lerp(a, b, t, surfaceColor: widget.style.surfaceColor),
      );
      visualStyles?.add(
        _WovenVisualStyle.lerp(aStyle!, bStyle!, t, widget.style.surfaceColor),
      );
      fractions.add(
        from.fractions[i] + (to.fractions[i] - from.fractions[i]) * t,
      );
    }

    // A topology handoff must reveal the destination slowly at both ends:
    // one-to-many fades the woven layer in, while many-to-one lets the
    // canonical single ring emerge from underneath. Using the same ease-in
    // curve in both directions prevents the first animated frame from
    // exposing a large patch of the destination topology.
    final double topologyT = Curves.easeInCubic.transform(t);
    final double topologyMerge =
        from.topologyMerge +
        (to.topologyMerge - from.topologyMerge) * topologyT;

    return _WovenFrame(
      segments: List<WovenSegment>.unmodifiable(segments),
      fractions: List<double>.unmodifiable(fractions),
      topologyMerge: topologyMerge,
      topologyAnchor: from.topologyAnchor ?? to.topologyAnchor,
      visualStyles: visualStyles == null
          ? null
          : List<_WovenVisualStyle>.unmodifiable(visualStyles),
    );
  }

  static _WovenVisualStyle _visualStyleAt(_WovenFrame frame, int index) =>
      frame.visualStyles?[index] ??
      _WovenVisualStyle.segment(frame.segments[index], index);

  static _WovenFrame _resolveFrame(
    List<WovenSegment> segments,
    WovenRingStyle style,
  ) {
    final double thickness = style.resolvedThicknessFraction;
    final double capToTrack = thickness / (1 - thickness);
    final double minimum = math.asin(capToTrack.clamp(0.0, 1.0)) / math.pi;
    return _WovenFrame(
      segments: List<WovenSegment>.unmodifiable(segments),
      fractions: List<double>.unmodifiable(
        wovenSegmentFractions(
          <double>[for (final WovenSegment segment in segments) segment.value],
          minimumFraction: minimum,
          policy: style.smallValuePolicy,
        ),
      ),
    );
  }

  /// Zero-fraction placeholders use their adjacent visible colour at full
  /// opacity. Their geometry grows or shrinks from zero, so fading them over a
  /// neutral track would only create a background flash.
  static _WovenFrame _padFrame(_WovenFrame frame, int n) {
    if (frame.segments.length >= n) return frame;
    final WovenFill fill = frame.segments.isEmpty
        ? const WovenFill.solid(WovenPalette.neutral)
        : frame.segments.last.fill;
    return _WovenFrame(
      segments: List<WovenSegment>.unmodifiable(<WovenSegment>[
        ...frame.segments,
        for (var i = frame.segments.length; i < n; i++)
          WovenSegment(value: 0, fill: fill),
      ]),
      fractions: List<double>.unmodifiable(<double>[
        ...frame.fractions,
        for (var i = frame.fractions.length; i < n; i++) 0.0,
      ]),
      topologyMerge: frame.topologyMerge,
      topologyAnchor: frame.topologyAnchor,
      visualStyles: frame.visualStyles == null
          ? null
          : List<_WovenVisualStyle>.unmodifiable(<_WovenVisualStyle>[
              ...frame.visualStyles!,
              for (var i = frame.segments.length; i < n; i++)
                _WovenVisualStyle.segment(
                  WovenSegment(value: 0, fill: fill),
                  i,
                ),
            ]),
    );
  }

  static WovenFill _neighborFill(_WovenFrame frame, int index) {
    final int n = frame.segments.length;
    if (n == 0) return const WovenFill.solid(WovenPalette.neutral);
    for (var offset = 1; offset <= n; offset++) {
      final int candidate = (index - offset + n) % n;
      if (frame.fractions[candidate] > 1e-12) {
        return frame.segments[candidate].fill;
      }
    }
    return frame.segments[index.clamp(0, n - 1)].fill;
  }

  static List<WovenSegment> _snapshot(List<WovenSegment> source) {
    return List<WovenSegment>.unmodifiable(<WovenSegment>[
      for (final WovenSegment segment in source)
        segment.copyWith(
          value: segment.value.isFinite && segment.value > 0.0
              ? segment.value
              : 0.0,
          opacity: segment.value.isFinite && segment.value > 0.0
              ? (segment.opacity.isFinite
                    ? segment.opacity.clamp(0.0, 1.0)
                    : 1.0)
              : 0.0,
        ),
    ]);
  }

  static Duration _safeDuration(Duration duration) =>
      duration.isNegative ? Duration.zero : duration;

  @override
  Widget build(BuildContext context) {
    final List<String> segmentLabels = <String>[
      for (final WovenSegment segment in _inputSnapshot)
        if (segment.value > 0.0 && segment.semanticLabel != null)
          segment.semanticLabel!,
    ];
    final String? label =
        widget.semanticLabel ??
        (segmentLabels.isEmpty ? null : segmentLabels.join(', '));
    final bool hasAggregateSemantics =
        label != null || widget.semanticValue != null;
    // The centre is hidden from assistive tech only when the caller has given
    // the ring its own description, because that description is written to
    // stand for the whole chart. Per-segment labels describe segments and say
    // nothing about the centre, so they must not silence it: labelling your
    // data should never remove the total from the accessibility tree.
    final bool centreIsDescribedByRing =
        widget.semanticLabel != null || widget.semanticValue != null;

    Widget result = LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final List<double> finiteMaximums = <double>[
          if (constraints.maxWidth.isFinite) constraints.maxWidth,
          if (constraints.maxHeight.isFinite) constraints.maxHeight,
        ];
        final double side = finiteMaximums.isEmpty
            ? 240.0
            : finiteMaximums.reduce(math.min).clamp(0.0, double.infinity);
        final WovenRingGeometry g = WovenRingGeometry.forSize(
          Size(side, side),
          widget.style,
        );
        // Nothing closer to the thickness than about 10% of the hole's diameter.
        final double centreBox = g.holeDiameter * 0.8 / math.sqrt2;

        // Built once per layout, not once per tick. Loading spins forever, so
        // rebuilding an arbitrary caller-supplied subtree inside the animation
        // callback would keep rebuilding it for as long as the ring is on
        // screen. Only the painter depends on the animation.
        final Widget? centre = widget.center == null
            ? null
            : Center(
                child: SizedBox(
                  width: centreBox,
                  height: centreBox,
                  child: Center(
                    child: centreIsDescribedByRing
                        ? ExcludeSemantics(child: widget.center!)
                        : widget.center!,
                  ),
                ),
              );

        return Center(
          child: SizedBox.square(
            dimension: side,
            child: AnimatedBuilder(
              animation: _repaint,
              child: centre,
              builder: (BuildContext context, Widget? child) {
                final _WovenFrame frame = _currentFrame();
                return Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    CustomPaint(
                      painter: WovenRingChartPainter(
                        segments: frame.visualStyles == null
                            ? frame.segments
                            : <WovenSegment>[
                                for (final _WovenVisualStyle s
                                    in frame.visualStyles!)
                                  s.resolve(
                                    _resolvedHighlightedIndex,
                                    widget.highlightBorder,
                                    widget.style.surfaceColor,
                                  ),
                              ],
                        fractions: frame.fractions,
                        style: widget.style,
                        mode: widget._mode,
                        animation: widget.animation,
                        // Soft in, soft out. No bounce, no overshoot: the ring
                        // is being drawn, not thrown.
                        animationProgress: Curves.easeInOutCubic.transform(
                          _animation.value,
                        ),
                        spin: _spin.value,
                        highlightedIndex: frame.visualStyles == null
                            ? _resolvedHighlightedIndex
                            : null,
                        highlightBorder: widget.highlightBorder,
                        topologyMerge: frame.topologyMerge,
                        topologyAnchor: frame.topologyAnchor,
                      ),
                    ),
                    ?child,
                  ],
                );
              },
            ),
          ),
        );
      },
    );

    result = RepaintBoundary(child: result);
    if (hasAggregateSemantics) {
      result = Semantics(
        image: true,
        label: label,
        value: widget.semanticValue,
        liveRegion: widget._mode == WovenRingChartMode.loading,
        child: result,
      );
    }
    return result;
  }
}
