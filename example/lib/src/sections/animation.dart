import 'dart:async';

import 'package:flutter/material.dart';

import 'package:woven_ring_chart/woven_ring_chart.dart';

import '../showcase_theme.dart';
import '../ui/code_block.dart';
import '../ui/section.dart';

/// The same four values everywhere in this section, so the only thing that
/// differs between the cards is the animation.
const List<WovenSegment> _segments = <WovenSegment>[
  WovenSegment(value: 34, fill: WovenFill.solid(WovenPalette.purple)),
  WovenSegment(value: 26, fill: WovenFill.solid(WovenPalette.green)),
  WovenSegment(value: 22, fill: WovenFill.solid(WovenPalette.amber)),
  WovenSegment(value: 18, fill: WovenFill.solid(WovenPalette.rose)),
];

/// The three entrances, replayable, and what happens when the data changes.
class AnimationSection extends StatelessWidget {
  const AnimationSection({super.key});

  static const String _source = '''
final WovenRingChartController controller = WovenRingChartController();

WovenRingChart(
  segments: segments,
  animation: WovenRingAnimation.sweep,
  animationDuration: const Duration(milliseconds: 1000),
  transitionDuration: const Duration(milliseconds: 450),
  controller: controller,
);

// Later, to play the entrance again:
controller.replay();''';

  @override
  Widget build(BuildContext context) {
    return Section(
      title: 'Animation',
      lede:
          'The first time a chart appears it draws itself. Changing the data '
          'after that animates in place over transitionDuration: segments '
          'stretch and shrink, colours crossfade, and nothing is torn down and '
          'rebuilt, so the chart never blinks. Changing the data again '
          'mid-transition picks up from the frame that is on screen instead of '
          'restarting. Under MediaQuery.disableAnimations every entrance and '
          'data change completes immediately.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: const <Widget>[
              _EntranceCard(
                id: 'sweep',
                animation: WovenRingAnimation.sweep,
                title: 'Sweep',
                note:
                    'One head goes once round the circle, handing the colour '
                    'over at each boundary. The default.',
              ),
              _EntranceCard(
                id: 'grow',
                animation: WovenRingAnimation.grow,
                title: 'Grow',
                note: 'Every segment opens at once, with a stagger.',
              ),
              _EntranceCard(
                id: 'none',
                animation: WovenRingAnimation.none,
                title: 'None',
                note: 'Appears finished. Nothing to replay.',
              ),
              _TransitionCard(),
            ],
          ),
          const SizedBox(height: 24),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 660),
            child: const CodeBlock(
              source: _source,
              label: 'replaying the entrance',
            ),
          ),
        ],
      ),
    );
  }
}

/// One entrance animation, with a button that plays it again.
class _EntranceCard extends StatefulWidget {
  const _EntranceCard({
    required this.id,
    required this.animation,
    required this.title,
    required this.note,
  });

  final String id;
  final WovenRingAnimation animation;
  final String title;
  final String note;

  @override
  State<_EntranceCard> createState() => _EntranceCardState();
}

class _EntranceCardState extends State<_EntranceCard> {
  final WovenRingChartController _controller = WovenRingChartController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 226,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: ShowcaseColors.surface,
          border: Border.all(color: ShowcaseColors.line),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Center(
                child: SizedBox.square(
                  dimension: 150,
                  child: WovenRingChart(
                    key: ValueKey<String>('entrance-ring-${widget.id}'),
                    segments: _segments,
                    animation: widget.animation,
                    controller: _controller,
                    semanticLabel: '${widget.title} entrance animation',
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(widget.title, style: ShowcaseText.cardTitle),
              const SizedBox(height: 4),
              Text(widget.note, style: ShowcaseText.caption),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: ValueKey<String>('replay-${widget.id}'),
                  onPressed: widget.animation == WovenRingAnimation.none
                      ? null
                      : _controller.replay,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: const Icon(Icons.replay_rounded, size: 16),
                  label: const Text('Replay'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A ring whose data keeps changing, to show the in-place transition.
class _TransitionCard extends StatefulWidget {
  const _TransitionCard();

  @override
  State<_TransitionCard> createState() => _TransitionCardState();
}

class _TransitionCardState extends State<_TransitionCard> {
  static const List<List<double>> _sets = <List<double>>[
    <double>[34, 26, 22, 18],
    <double>[18, 31, 23, 28],
    <double>[45, 15, 25, 15],
    <double>[25, 25, 25, 25],
  ];

  Timer? _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 2200), (Timer _) {
      if (!mounted) return;
      setState(() => _index = (_index + 1) % _sets.length);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 226,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: ShowcaseColors.surface,
          border: Border.all(color: ShowcaseColors.line),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Center(
                child: SizedBox.square(
                  dimension: 150,
                  child: WovenRingChart(
                    key: const ValueKey<String>('transition-ring'),
                    segments: <WovenSegment>[
                      for (int i = 0; i < _sets[_index].length; i++)
                        WovenSegment(
                          value: _sets[_index][i],
                          fill: WovenFill.solid(WovenPalette.quartet[i]),
                        ),
                    ],
                    semanticLabel: 'A ring whose data keeps changing',
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text('Changing data', style: ShowcaseText.cardTitle),
              const SizedBox(height: 4),
              Text(
                'New values every 2.2 seconds. Segments stretch in place; the '
                'chart never blinks.',
                style: ShowcaseText.caption,
              ),
              // Keeps this card's height in step with the replayable ones,
              // which carry a button here.
              const SizedBox(height: 36),
            ],
          ),
        ),
      ),
    );
  }
}
