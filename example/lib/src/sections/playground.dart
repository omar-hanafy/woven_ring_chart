import 'package:flutter/material.dart';

import 'package:woven_ring_chart/woven_ring_chart.dart';

import '../playground_config.dart';
import '../showcase_theme.dart';
import '../ui/code_block.dart';
import '../ui/section.dart';

/// The centrepiece: one chart, every control that shapes it, and the Dart that
/// would build what is currently on screen.
///
/// The chart and the code are two readings of the same [PlaygroundConfig], so
/// what a visitor copies is what a visitor is looking at.
class PlaygroundSection extends StatefulWidget {
  const PlaygroundSection({super.key});

  @override
  State<PlaygroundSection> createState() => _PlaygroundSectionState();
}

class _PlaygroundSectionState extends State<PlaygroundSection> {
  final WovenRingChartController _controller = WovenRingChartController();
  PlaygroundConfig _config = const PlaygroundConfig();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _update(PlaygroundConfig next) => setState(() => _config = next);

  @override
  Widget build(BuildContext context) {
    return Section(
      title: 'Playground',
      lede:
          'Move any control and the code rewrites itself to match. Only what '
          'you have taken away from its default shows up, so the snippet '
          'stays the shortest one that produces what you are looking at. Copy '
          'it and you get this chart.',
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final Widget preview = _Preview(
            config: _config,
            controller: _controller,
          );
          final Widget controls = _Controls(
            config: _config,
            onChanged: _update,
            onReplay: _controller.replay,
          );
          final Widget code = CodeBlock(
            key: const ValueKey<String>('playground-code'),
            source: _config.toDartSource(),
            label: 'what you are looking at',
          );

          if (constraints.maxWidth < ShowcaseLayout.sideBySideBreakpoint) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                preview,
                const SizedBox(height: 20),
                code,
                const SizedBox(height: 20),
                controls,
              ],
            );
          }
          // The chart and its code stay stacked on one side and the controls
          // sit opposite them, so that reaching for a control never scrolls
          // the code you are changing off the screen.
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                flex: 6,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[preview, const SizedBox(height: 20), code],
                ),
              ),
              const SizedBox(width: 28),
              Expanded(flex: 5, child: controls),
            ],
          );
        },
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.config, required this.controller});

  final PlaygroundConfig config;
  final WovenRingChartController controller;

  @override
  Widget build(BuildContext context) {
    // The preview's own accessibility lives out here rather than on the chart,
    // so that nothing is set on the widget which the code panel does not show.
    return Semantics(
      container: true,
      label: 'Interactive woven ring preview',
      value: '${config.values.length} segments',
      child: ChartStage(
        size: 300,
        child: WovenRingChart(
          key: const ValueKey<String>('playground-ring'),
          segments: config.buildSegments(),
          style: config.buildStyle(),
          animation: config.animation,
          controller: controller,
          highlightedIndex: config.resolvedHighlightedIndex,
        ),
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.config,
    required this.onChanged,
    required this.onReplay,
  });

  final PlaygroundConfig config;
  final ValueChanged<PlaygroundConfig> onChanged;
  final VoidCallback onReplay;

  @override
  Widget build(BuildContext context) {
    // A real Material rather than a DecoratedBox: the switches in here paint
    // their ink on the nearest Material ancestor, and a coloured box in
    // between would hide every splash.
    return Material(
      color: ShowcaseColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: ShowcaseColors.line),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _dropdown<DemoData>(
              id: 'data-control',
              label: 'Data',
              value: config.data,
              values: DemoData.values,
              text: (DemoData v) => v.label,
              onChanged: (DemoData v) =>
                  onChanged(config.copyWith(data: v, clearHighlight: true)),
            ),
            _dropdown<DemoFill>(
              id: 'fill-control',
              label: 'Fill',
              value: config.fill,
              values: DemoFill.values,
              text: (DemoFill v) => v.label,
              onChanged: (DemoFill v) => onChanged(config.copyWith(fill: v)),
            ),
            _dropdown<DemoBorder>(
              id: 'border-control',
              label: 'Border',
              value: config.border,
              values: DemoBorder.values,
              text: (DemoBorder v) => v.label,
              onChanged: (DemoBorder v) =>
                  onChanged(config.copyWith(border: v)),
            ),
            _dropdown<WovenRingAnimation>(
              id: 'animation-control',
              label: 'Entrance animation',
              value: config.animation,
              values: WovenRingAnimation.values,
              text: (WovenRingAnimation v) => switch (v) {
                WovenRingAnimation.sweep => 'Sweep, one head round the circle',
                WovenRingAnimation.grow => 'Grow, all segments at once',
                WovenRingAnimation.none => 'None, appears finished',
              },
              onChanged: (WovenRingAnimation v) =>
                  onChanged(config.copyWith(animation: v)),
            ),
            _dropdown<WovenGradientAxis>(
              id: 'gradient-axis-control',
              label: 'Gradient axis',
              value: config.gradientAxis,
              values: WovenGradientAxis.values,
              text: (WovenGradientAxis v) => v == WovenGradientAxis.alongSegment
                  ? 'Along each segment'
                  : 'Across the thickness',
              onChanged: (WovenGradientAxis v) =>
                  onChanged(config.copyWith(gradientAxis: v)),
            ),
            _dropdown<WovenSmallValuePolicy>(
              id: 'policy-control',
              label: 'Values too small to draw',
              value: config.smallValuePolicy,
              values: WovenSmallValuePolicy.values,
              text: (WovenSmallValuePolicy v) =>
                  v == WovenSmallValuePolicy.enforce
                  ? 'Enforce a minimum'
                  : 'Let them vanish',
              onChanged: (WovenSmallValuePolicy v) =>
                  onChanged(config.copyWith(smallValuePolicy: v)),
            ),
            if (config.data == DemoData.single)
              _dropdown<WovenSingleSegmentStyle>(
                id: 'single-style-control',
                label: 'A single value',
                value: config.singleSegmentStyle,
                values: WovenSingleSegmentStyle.values,
                text: (WovenSingleSegmentStyle v) =>
                    v == WovenSingleSegmentStyle.smooth
                    ? 'No joint to show'
                    : 'Keep one hairline self-joint',
                onChanged: (WovenSingleSegmentStyle v) =>
                    onChanged(config.copyWith(singleSegmentStyle: v)),
              ),
            const SizedBox(height: 4),
            _switch(
              id: 'clockwise-control',
              title: 'Clockwise',
              subtitle: 'Off is a mirror image, so the heads flip too',
              value: config.clockwise,
              onChanged: (bool v) => onChanged(config.copyWith(clockwise: v)),
            ),
            _switch(
              id: 'gradient-direction-control',
              title: 'Head-to-tail gradient',
              subtitle: 'Which end lands on the visible cap',
              value:
                  config.gradientDirection == WovenGradientDirection.headToTail,
              onChanged: (bool v) => onChanged(
                config.copyWith(
                  gradientDirection: v
                      ? WovenGradientDirection.headToTail
                      : WovenGradientDirection.tailToHead,
                ),
              ),
            ),
            _switch(
              id: 'shadow-control',
              title: 'Head shadow',
              subtitle: 'If you notice it, it is twice too strong',
              value: config.shadow,
              onChanged: (bool v) => onChanged(config.copyWith(shadow: v)),
            ),
            _switch(
              id: 'highlight-control',
              title: 'Highlight one segment',
              subtitle: 'Takes highlightBorder for as long as it is set',
              value: config.resolvedHighlightedIndex != null,
              onChanged: (bool v) => onChanged(
                v
                    ? config.copyWith(highlightedIndex: 0)
                    : config.copyWith(clearHighlight: true),
              ),
            ),
            if (config.resolvedHighlightedIndex != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const ValueKey<String>('highlight-next-button'),
                  onPressed: () => onChanged(
                    config.copyWith(
                      highlightedIndex:
                          (config.resolvedHighlightedIndex! + 1) %
                          config.values.length,
                    ),
                  ),
                  icon: const Icon(Icons.skip_next_rounded, size: 18),
                  label: const Text('Highlight the next one'),
                ),
              ),
            _slider(
              id: 'thickness-slider',
              label: 'Thickness',
              value: config.thicknessFraction,
              min: 0.12,
              max: 0.30,
              divisions: 18,
              format: (double v) => '${(v * 100).round()}% of the diameter',
              onChanged: (double v) =>
                  onChanged(config.copyWith(thicknessFraction: _round(v, 2))),
            ),
            _slider(
              id: 'overlap-slider',
              label: 'Overlap',
              value: config.overlapFraction,
              min: 0.25,
              max: 1.0,
              divisions: 15,
              format: (double v) => '${(v * 100).round()}% of a thickness',
              onChanged: (double v) =>
                  onChanged(config.copyWith(overlapFraction: _round(v, 2))),
            ),
            _slider(
              id: 'start-angle-slider',
              label: 'Start angle',
              value: config.startDegrees,
              min: -180,
              max: 180,
              divisions: 24,
              format: (double v) => '${v.round()} degrees',
              onChanged: (double v) =>
                  onChanged(config.copyWith(startDegrees: v.roundToDouble())),
            ),
            const SizedBox(height: 4),
            Row(
              children: <Widget>[
                FilledButton.icon(
                  key: const ValueKey<String>('replay-button'),
                  onPressed: onReplay,
                  icon: const Icon(Icons.replay_rounded, size: 18),
                  label: const Text('Replay'),
                ),
                const SizedBox(width: 8),
                TextButton(
                  key: const ValueKey<String>('reset-button'),
                  onPressed: () => onChanged(const PlaygroundConfig()),
                  child: const Text('Reset'),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _dropdown<T>({
    required String id,
    required String label,
    required T value,
    required List<T> values,
    required String Function(T value) text,
    required ValueChanged<T> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<T>(
        key: ValueKey<String>(id),
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
          filled: true,
          fillColor: ShowcaseColors.surface,
        ),
        items: <DropdownMenuItem<T>>[
          for (final T item in values)
            DropdownMenuItem<T>(
              value: item,
              child: Text(text(item), overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (T? item) {
          if (item != null) onChanged(item);
        },
      ),
    );
  }

  Widget _switch({
    required String id,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile.adaptive(
      key: ValueKey<String>(id),
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(title, style: ShowcaseText.cardTitle),
      subtitle: Text(subtitle, style: ShowcaseText.caption),
      value: value,
      onChanged: onChanged,
    );
  }

  Widget _slider({
    required String id,
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String Function(double value) format,
    required ValueChanged<double> onChanged,
  }) {
    final double clamped = value.clamp(min, max).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text.rich(
            TextSpan(
              children: <TextSpan>[
                TextSpan(text: label, style: ShowcaseText.cardTitle),
                TextSpan(
                  text: '  ${format(clamped)}',
                  style: ShowcaseText.caption,
                ),
              ],
            ),
          ),
        ),
        Slider(
          key: ValueKey<String>(id),
          value: clamped,
          min: min,
          max: max,
          divisions: divisions,
          onChanged: (double next) =>
              onChanged(next.clamp(min, max).toDouble()),
        ),
      ],
    );
  }
}

/// Slider output, rounded before it reaches the config.
///
/// The rounding happens here rather than in the code generator so that the
/// chart and the snippet are built from the same number, not from a number and
/// a tidied-up copy of it.
double _round(double value, int places) {
  return double.parse(value.toStringAsFixed(places));
}
