import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'enums.dart';
import 'geometry.dart';
import 'painter.dart';
import 'palette.dart';
import 'snake.dart';
import 'style.dart';

/// Replays the intro animation. Handy for demos and for "refresh" affordances.
///
/// Create one, hand it to a [WovenRing], and dispose it with the surrounding
/// state. A controller attached to a ring whose intro is [WovenRingIntro.none]
/// does nothing.
class WovenRingController extends ChangeNotifier {
  /// Creates a controller. Dispose it with the state that owns it.
  WovenRingController();

  /// Runs the ring's intro again from the beginning, even if it had finished.
  ///
  /// Under reduced motion the intro jumps straight to its final frame.
  void replay() => notifyListeners();
}

/// A doughnut chart whose segments lap over one another like shingles.
///
/// Every boundary between two colours is the backward semicircle of a round
/// cap, because a snake is a constant-width bar with semicircular ends bent
/// along the ring. The ring is square: it takes the smaller of its
/// constraints and centres itself in whatever box it is given.
///
/// ```dart
/// WovenRing(
///   snakes: const <WovenSnake>[
///     WovenSnake.solid(37, WovenPalette.purple),
///     WovenSnake.solid(19, WovenPalette.green),
///     WovenSnake.solid(29, WovenPalette.amber),
///     WovenSnake.solid(15, WovenPalette.rose),
///   ],
///   center: const Text('100'),
///   semanticLabel: 'Spending by category',
/// )
/// ```
///
/// Use [WovenRing.empty] for a ring with no data yet and [WovenRing.loading]
/// while data is on its way, so the shape on screen never changes size.
class WovenRing extends StatefulWidget {
  /// A ring built from [snakes].
  ///
  /// The list is snapshotted on every build, so a caller may keep and mutate
  /// its own list. Changing the data animates over [transitionDuration]:
  /// snakes stretch and shrink in place rather than being torn down.
  const WovenRing({
    super.key,
    required this.snakes,
    this.style = const WovenRingStyle(),
    this.intro = WovenRingIntro.relay,
    this.introDuration = const Duration(milliseconds: 1000),
    this.transitionDuration = const Duration(milliseconds: 450),
    this.center,
    this.highlighted,
    this.highlightBorder = const WovenBorder(),
    this.controller,
    this.semanticLabel,
    this.semanticValue,
  }) : _mode = WovenRingMode.data;

  /// A flat neutral ring at low opacity. Same band width, no joints.
  const WovenRing.empty({
    super.key,
    this.style = const WovenRingStyle(),
    this.center,
    this.semanticLabel,
    this.semanticValue,
  }) : snakes = const <WovenSnake>[],
       intro = WovenRingIntro.none,
       introDuration = Duration.zero,
       transitionDuration = Duration.zero,
       highlighted = null,
       highlightBorder = const WovenBorder(),
       controller = null,
       _mode = WovenRingMode.empty;

  /// A single neutral snake chasing itself around the track.
  const WovenRing.loading({
    super.key,
    this.style = const WovenRingStyle(),
    this.center,
    this.semanticLabel,
    this.semanticValue,
  }) : snakes = const <WovenSnake>[],
       intro = WovenRingIntro.none,
       introDuration = const Duration(milliseconds: 1400),
       transitionDuration = Duration.zero,
       highlighted = null,
       highlightBorder = const WovenBorder(),
       controller = null,
       _mode = WovenRingMode.loading;

  /// The segments, in the order they are laid round the ring.
  ///
  /// Order is kept exactly as given: the component never sorts or rebalances
  /// for looks. Each snake is drawn over the one before it, so the last one
  /// laps the first at the seam.
  final List<WovenSnake> snakes;

  /// Proportions, direction, gradient axis, and the surface the ring sits on.
  final WovenRingStyle style;

  /// How the ring draws itself the first time it appears.
  final WovenRingIntro intro;

  /// How long [intro] takes.
  final Duration introDuration;

  /// On data change snakes stretch and shrink in place and colours crossfade.
  /// Nothing disappears and gets redrawn; the ring never blinks.
  final Duration transitionDuration;

  /// Optically centred, with real breathing room from the band.
  final Widget? center;

  /// Gives one snake a border while the others stay unbordered.
  ///
  /// The index is into [snakes]. It replaces that snake's own border for as
  /// long as it is set.
  final int? highlighted;

  /// The border the [highlighted] snake takes.
  final WovenBorder highlightBorder;

  /// Replays the intro on demand. The caller owns it and must dispose it.
  final WovenRingController? controller;

  /// Localized aggregate accessibility text for the chart.
  ///
  /// Without one, the labels of every visible snake are joined instead.
  /// Setting either this or [semanticValue] means the caller has described the
  /// whole chart, so [center] is hidden from assistive technology to avoid
  /// reading the same number twice.
  final String? semanticLabel;

  /// Localized value text for the chart, such as the total the centre shows.
  final String? semanticValue;

  final WovenRingMode _mode;

  @override
  State<WovenRing> createState() => _WovenRingState();
}

@immutable
class _WovenFrame {
  const _WovenFrame({
    required this.snakes,
    required this.fractions,
    this.topologyMerge = 0.0,
    this.topologyAnchor,
  });

  final List<WovenSnake> snakes;
  final List<double> fractions;
  final double topologyMerge;
  final int? topologyAnchor;

  _WovenFrame withTopology(double merge, int? anchor) => _WovenFrame(
    snakes: snakes,
    fractions: fractions,
    topologyMerge: merge,
    topologyAnchor: anchor,
  );
}

class _WovenRingState extends State<WovenRing> with TickerProviderStateMixin {
  late final AnimationController _intro;
  late final AnimationController _transition;
  late final AnimationController _spin;
  late Listenable _repaint;

  _WovenFrame _fromFrame = const _WovenFrame(
    snakes: <WovenSnake>[],
    fractions: <double>[],
  );
  _WovenFrame _toFrame = const _WovenFrame(
    snakes: <WovenSnake>[],
    fractions: <double>[],
  );
  List<WovenSnake> _inputSnapshot = const <WovenSnake>[];
  bool _disableAnimations = false;

  @override
  void initState() {
    super.initState();
    _intro = AnimationController(
      vsync: this,
      duration: _safeDuration(widget.introDuration),
    );
    _transition = AnimationController(
      vsync: this,
      duration: _safeDuration(widget.transitionDuration),
    );
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _repaint = Listenable.merge(<Listenable>[_intro, _transition, _spin]);

    _inputSnapshot = _snapshot(widget.snakes);
    _fromFrame = _resolveFrame(_inputSnapshot, widget.style);
    _toFrame = _fromFrame;

    if (widget._mode == WovenRingMode.loading) {
      _spin.repeat();
    } else if (widget.intro == WovenRingIntro.none || _inputSnapshot.isEmpty) {
      _intro.value = 1;
    } else {
      _intro.forward();
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
      _intro.value = 1.0;
      _transition.value = 1.0;
      _spin.stop();
    } else if (widget._mode == WovenRingMode.loading && !_spin.isAnimating) {
      _spin.repeat();
    }
  }

  @override
  void didUpdateWidget(WovenRing old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller?.removeListener(_replay);
      widget.controller?.addListener(_replay);
    }
    _intro.duration = _safeDuration(widget.introDuration);
    _transition.duration = _safeDuration(widget.transitionDuration);

    if (widget._mode == WovenRingMode.loading &&
        !_disableAnimations &&
        !_spin.isAnimating) {
      _spin.repeat();
    } else if (widget._mode != WovenRingMode.loading && _spin.isAnimating) {
      _spin.stop();
    }

    final List<WovenSnake> nextSnapshot = _snapshot(widget.snakes);
    final bool dataChanged = !listEquals(_inputSnapshot, nextSnapshot);
    final bool fractionRulesChanged =
        old.style.resolvedBandFraction != widget.style.resolvedBandFraction ||
        old.style.minimumPolicy != widget.style.minimumPolicy;
    if (dataChanged || fractionRulesChanged) {
      final _WovenFrame current = _currentFrame();
      final bool hadData = current.fractions.any(
        (double fraction) => fraction > 1e-12,
      );
      final bool hasData = nextSnapshot.any((WovenSnake s) => s.value > 0.0);
      _inputSnapshot = nextSnapshot;
      final _WovenFrame next = _resolveFrame(nextSnapshot, widget.style);

      if (!hadData && hasData) {
        _fromFrame = next;
        _toFrame = next;
        _transition.value = 1.0;
        if (!_disableAnimations && widget.intro != WovenRingIntro.none) {
          _intro.forward(from: 0.0);
        } else {
          _intro.value = 1.0;
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
          // requested sole snake did not exist in the current data, use a
          // visible current snake and morph its visual style to the destination.
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

    if (old.intro != widget.intro && !_intro.isAnimating) {
      _intro.value = widget.intro == WovenRingIntro.none ? 1.0 : _intro.value;
    }
  }

  void _replay() {
    if (widget.intro == WovenRingIntro.none) return;
    if (_disableAnimations) {
      _intro.value = 1.0;
    } else {
      _intro.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_replay);
    _intro.dispose();
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

    final int n = math.max(_fromFrame.snakes.length, _toFrame.snakes.length);
    final _WovenFrame from = _padFrame(_fromFrame, n);
    final _WovenFrame to = _padFrame(_toFrame, n);
    final double t = Curves.easeInOut.transform(_transition.value);
    final List<WovenSnake> snakes = <WovenSnake>[];
    final List<double> fractions = <double>[];

    for (var i = 0; i < n; i++) {
      WovenSnake a = from.snakes[i];
      WovenSnake b = to.snakes[i];
      if (from.fractions[i] <= 1e-12 && to.fractions[i] > 1e-12) {
        a = WovenSnake(
          value: 0,
          fill: _neighborFill(from, i),
          semanticLabel: a.semanticLabel,
        );
      }
      if (to.fractions[i] <= 1e-12 && from.fractions[i] > 1e-12) {
        WovenSnake? topologyDestination;
        if (to.topologyMerge > 0.0 && from.topologyAnchor == i) {
          for (
            var destination = 0;
            destination < to.fractions.length;
            destination++
          ) {
            if (to.fractions[destination] > 1e-12) {
              topologyDestination = to.snakes[destination];
              break;
            }
          }
        }
        b = WovenSnake(
          value: 0,
          fill: topologyDestination?.fill ?? _neighborFill(to, i),
          border: topologyDestination?.border,
          semanticLabel: topologyDestination?.semanticLabel ?? b.semanticLabel,
          opacity: topologyDestination?.opacity ?? 1.0,
        );
      }
      snakes.add(WovenSnake.lerp(a, b, t, surface: widget.style.surface));
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
      snakes: List<WovenSnake>.unmodifiable(snakes),
      fractions: List<double>.unmodifiable(fractions),
      topologyMerge: topologyMerge,
      topologyAnchor: from.topologyAnchor ?? to.topologyAnchor,
    );
  }

  static _WovenFrame _resolveFrame(
    List<WovenSnake> snakes,
    WovenRingStyle style,
  ) {
    final double band = style.resolvedBandFraction;
    final double capToTrack = band / (1 - band);
    final double minimum = math.asin(capToTrack.clamp(0.0, 1.0)) / math.pi;
    return _WovenFrame(
      snakes: List<WovenSnake>.unmodifiable(snakes),
      fractions: List<double>.unmodifiable(
        wovenFractions(
          <double>[for (final WovenSnake snake in snakes) snake.value],
          minimumFraction: minimum,
          policy: style.minimumPolicy,
        ),
      ),
    );
  }

  /// Zero-fraction placeholders use their adjacent visible colour at full
  /// opacity. Their geometry grows or shrinks from zero, so fading them over a
  /// neutral track would only create a background flash.
  static _WovenFrame _padFrame(_WovenFrame frame, int n) {
    if (frame.snakes.length >= n) return frame;
    final WovenFill fill = frame.snakes.isEmpty
        ? const WovenFill.solid(WovenPalette.neutral)
        : frame.snakes.last.fill;
    return _WovenFrame(
      snakes: List<WovenSnake>.unmodifiable(<WovenSnake>[
        ...frame.snakes,
        for (var i = frame.snakes.length; i < n; i++)
          WovenSnake(value: 0, fill: fill),
      ]),
      fractions: List<double>.unmodifiable(<double>[
        ...frame.fractions,
        for (var i = frame.fractions.length; i < n; i++) 0.0,
      ]),
      topologyMerge: frame.topologyMerge,
      topologyAnchor: frame.topologyAnchor,
    );
  }

  static WovenFill _neighborFill(_WovenFrame frame, int index) {
    final int n = frame.snakes.length;
    if (n == 0) return const WovenFill.solid(WovenPalette.neutral);
    for (var offset = 1; offset <= n; offset++) {
      final int candidate = (index - offset + n) % n;
      if (frame.fractions[candidate] > 1e-12) {
        return frame.snakes[candidate].fill;
      }
    }
    return frame.snakes[index.clamp(0, n - 1)].fill;
  }

  static List<WovenSnake> _snapshot(List<WovenSnake> source) {
    return List<WovenSnake>.unmodifiable(<WovenSnake>[
      for (final WovenSnake snake in source)
        snake.copyWith(
          value: snake.value.isFinite && snake.value > 0.0 ? snake.value : 0.0,
          opacity: snake.value.isFinite && snake.value > 0.0
              ? (snake.opacity.isFinite ? snake.opacity.clamp(0.0, 1.0) : 1.0)
              : 0.0,
        ),
    ]);
  }

  static Duration _safeDuration(Duration duration) =>
      duration.isNegative ? Duration.zero : duration;

  @override
  Widget build(BuildContext context) {
    final List<String> snakeLabels = <String>[
      for (final WovenSnake snake in _inputSnapshot)
        if (snake.value > 0.0 && snake.semanticLabel != null)
          snake.semanticLabel!,
    ];
    final String? label =
        widget.semanticLabel ??
        (snakeLabels.isEmpty ? null : snakeLabels.join(', '));
    final bool hasAggregateSemantics =
        label != null || widget.semanticValue != null;
    // The centre is hidden from assistive tech only when the caller has given
    // the ring its own description, because that description is written to
    // stand for the whole chart. Per-snake labels describe segments and say
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
        // Nothing closer to the band than about 10% of the hole's diameter.
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
                      painter: WovenRingPainter(
                        snakes: frame.snakes,
                        fractions: frame.fractions,
                        style: widget.style,
                        mode: widget._mode,
                        intro: widget.intro,
                        // Soft in, soft out. No bounce, no overshoot: the ring
                        // is being drawn, not thrown.
                        introProgress: Curves.easeInOutCubic.transform(
                          _intro.value,
                        ),
                        spin: _spin.value,
                        highlighted: widget.highlighted,
                        highlightBorder: widget.highlightBorder,
                        topologyMerge: frame.topologyMerge,
                        topologyAnchor: frame.topologyAnchor,
                      ),
                    ),
                    if (widget.center != null)
                      Center(
                        child: SizedBox(
                          width: centreBox,
                          height: centreBox,
                          child: Center(
                            child: centreIsDescribedByRing
                                ? ExcludeSemantics(child: widget.center!)
                                : widget.center!,
                          ),
                        ),
                      ),
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
        liveRegion: widget._mode == WovenRingMode.loading,
        child: result,
      );
    }
    return result;
  }
}
