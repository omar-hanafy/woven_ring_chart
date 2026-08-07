import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:woven_ring_chart/woven_ring_chart.dart';

void main() => runApp(const WovenRingChartDemoApp());

class WovenRingChartDemoApp extends StatelessWidget {
  const WovenRingChartDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    const Color surfaceColor = Color(0xFFFBFAF7);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Woven ring validation lab',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: WovenPalette.purple,
          surface: surfaceColor,
        ),
        scaffoldBackgroundColor: surfaceColor,
        useMaterial3: true,
      ),
      home: const WovenRingChartLabPage(),
    );
  }
}

enum _Scenario { quartet, extended, tinyValue, singleValue }

enum _FillMode { solid, gradient, diagnosticGradient, mixed }

enum _BorderMode { none, selected, mixed, all, diagnosticAlternating }

class WovenRingChartLabPage extends StatefulWidget {
  const WovenRingChartLabPage({super.key});

  @override
  State<WovenRingChartLabPage> createState() => _WovenRingChartLabPageState();
}

class _WovenRingChartLabPageState extends State<WovenRingChartLabPage> {
  static const Color _surface = Color(0xFFFBFAF7);
  static const Color _ink = Color(0xFF202532);

  final WovenRingChartController _controller = WovenRingChartController();

  _Scenario _scenario = _Scenario.quartet;
  _FillMode _fillMode = _FillMode.solid;
  _BorderMode _borderMode = _BorderMode.none;
  WovenRingAnimation _animation = WovenRingAnimation.sweep;
  WovenGradientAxis _gradientAxis = WovenGradientAxis.alongSegment;
  WovenGradientDirection _gradientDirection = WovenGradientDirection.headToTail;
  WovenSmallValuePolicy _minimumPolicy = WovenSmallValuePolicy.enforce;
  bool _clockwise = true;
  bool _shadow = false;
  bool _alternateData = false;
  int _selected = 0;
  double _thicknessFraction = 0.20;
  double _overlapFraction = 0.50;
  double _startDegrees = -90.0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('woven_ring_chart'),
              Text(
                'Every control, every state, every animated path',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
              ),
            ],
          ),
          bottom: const TabBar(
            tabs: <Widget>[
              Tab(key: ValueKey<String>('playground-tab'), text: 'Playground'),
              Tab(key: ValueKey<String>('matrix-tab'), text: 'Style matrix'),
              Tab(key: ValueKey<String>('states-tab'), text: 'States'),
            ],
          ),
        ),
        body: TabBarView(
          children: <Widget>[
            _buildPlayground(),
            _buildStyleMatrix(),
            _buildStates(),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayground() {
    final List<WovenSegment> segments = _segmentsFor(
      _scenario,
      fillMode: _fillMode,
      borderMode: _borderMode,
      alternate: _alternateData,
    );
    final int? highlightedIndex =
        _borderMode == _BorderMode.selected && _selected < segments.length
        ? _selected
        : null;
    final WovenRingStyle style = _style(
      clockwise: _clockwise,
      gradientAxis: _gradientAxis,
      gradientDirection: _gradientDirection,
      smallValuePolicy: _minimumPolicy,
      thicknessFraction: _thicknessFraction,
      overlapFraction: _overlapFraction,
      startDegrees: _startDegrees,
      shadow: _shadow,
    );

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool wide = constraints.maxWidth >= 900;
        final Widget preview = _previewCard(
          segments: segments,
          style: style,
          highlightedIndex: highlightedIndex,
        );
        final Widget controls = _controlsCard();
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(child: preview),
                    const SizedBox(width: 24),
                    SizedBox(width: 430, child: controls),
                  ],
                )
              : Column(
                  children: <Widget>[
                    preview,
                    const SizedBox(height: 24),
                    controls,
                  ],
                ),
        );
      },
    );
  }

  Widget _previewCard({
    required List<WovenSegment> segments,
    required WovenRingStyle style,
    required int? highlightedIndex,
  }) {
    return Card(
      elevation: 0,
      color: Colors.white.withValues(alpha: 0.72),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          children: <Widget>[
            Text(
              _summary(segments.length),
              key: const ValueKey<String>('configuration-summary'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF667085)),
            ),
            if (_fillMode == _FillMode.diagnosticGradient ||
                _borderMode == _BorderMode.diagnosticAlternating) ...<Widget>[
              const SizedBox(height: 8),
              const Text(
                'Diagnostic contrast is intentionally exaggerated. Production defaults remain solid and borderless.',
                key: ValueKey<String>('diagnostic-style-note'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF8A4B08),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 24),
            SizedBox.square(
              dimension: 360,
              child: WovenRingChart(
                key: const ValueKey<String>('playground-ring'),
                segments: segments,
                style: style,
                animation: _animation,
                controller: _controller,
                highlightedIndex: highlightedIndex,
                semanticLabel: 'Interactive woven ring preview',
                semanticValue: '${segments.length} visible data entries',
                center: _CenterLabel(
                  value: segments.length.toString(),
                  label: 'segments',
                ),
              ),
            ),
            const SizedBox(height: 24),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 12,
              children: <Widget>[
                FilledButton.icon(
                  key: const ValueKey<String>('replay-button'),
                  onPressed: _controller.replay,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Replay animation'),
                ),
                OutlinedButton.icon(
                  key: const ValueKey<String>('update-data-button'),
                  onPressed: () {
                    setState(() => _alternateData = !_alternateData);
                  },
                  icon: const Icon(Icons.swap_horiz_rounded),
                  label: const Text('Animate data'),
                ),
                OutlinedButton.icon(
                  key: const ValueKey<String>('select-next-button'),
                  onPressed: segments.isEmpty
                      ? null
                      : () {
                          setState(
                            () => _selected = (_selected + 1) % segments.length,
                          );
                        },
                  icon: const Icon(Icons.touch_app_outlined),
                  label: const Text('Select next'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _controlsCard() {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Text(
              'Verification controls',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            _dropdown<_Scenario>(
              key: 'scenario-control',
              label: 'Data case',
              value: _scenario,
              values: _Scenario.values,
              text: _scenarioName,
              onChanged: (value) {
                setState(() {
                  _scenario = value;
                  _selected = 0;
                });
              },
            ),
            const SizedBox(height: 12),
            _dropdown<_FillMode>(
              key: 'fill-control',
              label: 'Fill',
              value: _fillMode,
              values: _FillMode.values,
              text: _fillName,
              onChanged: (value) => setState(() => _fillMode = value),
            ),
            const SizedBox(height: 12),
            _dropdown<_BorderMode>(
              key: 'border-control',
              label: 'Border',
              value: _borderMode,
              values: _BorderMode.values,
              text: _borderName,
              onChanged: (value) => setState(() => _borderMode = value),
            ),
            const SizedBox(height: 12),
            _dropdown<WovenRingAnimation>(
              key: 'animation-control',
              label: 'Animation',
              value: _animation,
              values: WovenRingAnimation.values,
              text: (value) => switch (value) {
                WovenRingAnimation.sweep => 'Sweep',
                WovenRingAnimation.grow => 'Grow',
                WovenRingAnimation.none => 'None',
              },
              onChanged: (value) => setState(() => _animation = value),
            ),
            const SizedBox(height: 12),
            _dropdown<WovenGradientAxis>(
              key: 'gradient-axis-control',
              label: 'Gradient axis',
              value: _gradientAxis,
              values: WovenGradientAxis.values,
              text: (value) => value == WovenGradientAxis.alongSegment
                  ? 'Along each segment'
                  : 'Across the thickness',
              onChanged: (value) => setState(() => _gradientAxis = value),
            ),
            const SizedBox(height: 12),
            _dropdown<WovenSmallValuePolicy>(
              key: 'minimum-policy-control',
              label: 'Small-value policy',
              value: _minimumPolicy,
              values: WovenSmallValuePolicy.values,
              text: (value) => value == WovenSmallValuePolicy.enforce
                  ? 'Enforce minimum'
                  : 'Allow vanish',
              onChanged: (value) => setState(() => _minimumPolicy = value),
            ),
            const SizedBox(height: 8),
            SwitchListTile.adaptive(
              key: const ValueKey<String>('clockwise-control'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Clockwise'),
              subtitle: const Text('Off is a directional mirror'),
              value: _clockwise,
              onChanged: (value) => setState(() => _clockwise = value),
            ),
            SwitchListTile.adaptive(
              key: const ValueKey<String>('gradient-direction-control'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Head-to-tail gradient'),
              value: _gradientDirection == WovenGradientDirection.headToTail,
              onChanged: (value) {
                setState(() {
                  _gradientDirection = value
                      ? WovenGradientDirection.headToTail
                      : WovenGradientDirection.tailToHead;
                });
              },
            ),
            SwitchListTile.adaptive(
              key: const ValueKey<String>('shadow-control'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Subtle head shadow'),
              value: _shadow,
              onChanged: (value) => setState(() => _shadow = value),
            ),
            _slider(
              label: 'Thickness',
              value: _thicknessFraction,
              min: 0.15,
              max: 0.25,
              divisions: 10,
              valueLabel: '${(_thicknessFraction * 100).round()}%',
              onChanged: (value) => setState(() => _thicknessFraction = value),
            ),
            _slider(
              label: 'Overlap',
              value: _overlapFraction,
              min: 0.30,
              max: 0.90,
              divisions: 12,
              valueLabel: '${(_overlapFraction * 100).round()}%',
              onChanged: (value) => setState(() => _overlapFraction = value),
            ),
            _slider(
              label: 'Start angle',
              value: _startDegrees,
              min: -180,
              max: 180,
              divisions: 24,
              valueLabel: '${_startDegrees.round()} degrees',
              onChanged: (value) => setState(() => _startDegrees = value),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStyleMatrix() {
    final List<_MatrixCase> cases = <_MatrixCase>[
      for (final bool clockwise in <bool>[true, false])
        for (final _FillMode fill in <_FillMode>[
          _FillMode.solid,
          _FillMode.gradient,
        ])
          for (final bool bordered in <bool>[false, true])
            _MatrixCase(
              title:
                  '${clockwise ? 'CW' : 'CCW'} | ${fill == _FillMode.solid ? 'solid' : 'gradient'} | ${bordered ? 'border' : 'no border'}',
              segments: _segmentsFor(
                _Scenario.quartet,
                fillMode: fill,
                borderMode: bordered ? _BorderMode.all : _BorderMode.none,
              ),
              style: _style(clockwise: clockwise),
            ),
      _MatrixCase(
        title: 'Diagnostic gradient | high contrast | no border',
        segments: _segmentsFor(
          _Scenario.quartet,
          fillMode: _FillMode.diagnosticGradient,
          borderMode: _BorderMode.none,
        ),
        style: _style(),
      ),
      _MatrixCase(
        title: 'Solid | diagnostic alternating border',
        segments: _segmentsFor(
          _Scenario.quartet,
          fillMode: _FillMode.solid,
          borderMode: _BorderMode.diagnosticAlternating,
        ),
        style: _style(),
      ),
      _MatrixCase(
        title: 'Across-thickness gradient | all borders',
        segments: _segmentsFor(
          _Scenario.quartet,
          fillMode: _FillMode.gradient,
          borderMode: _BorderMode.all,
        ),
        style: _style(gradientAxis: WovenGradientAxis.acrossThickness),
      ),
      _MatrixCase(
        title: 'Mixed fill | mixed border | non-cardinal CCW',
        segments: _segmentsFor(
          _Scenario.extended,
          fillMode: _FillMode.mixed,
          borderMode: _BorderMode.mixed,
        ),
        style: _style(clockwise: false, startDegrees: 22.5),
      ),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'Full solid/gradient, border/no-border, CW/CCW cross-product',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          const Text(
            'All cases are static so seams, cap direction, silhouettes, and gradient resets can be compared directly.',
            style: TextStyle(color: Color(0xFF667085)),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: <Widget>[
              for (var i = 0; i < cases.length; i++)
                _matrixCard(cases[i], index: i),
            ],
          ),
        ],
      ),
    );
  }

  Widget _matrixCard(_MatrixCase item, {required int index}) {
    return SizedBox(
      key: ValueKey<String>('matrix-case-$index'),
      width: 240,
      child: Card(
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: <Widget>[
              SizedBox.square(
                dimension: 174,
                child: WovenRingChart(
                  segments: item.segments,
                  style: item.style,
                  animation: WovenRingAnimation.none,
                  semanticLabel: item.title,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                item.title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStates() {
    final WovenRingStyle base = _style();
    final List<_StateCase> cases = <_StateCase>[
      _StateCase(
        title: 'Empty / no data',
        note: 'Neutral ring, same thickness, no joints',
        ring: WovenRingChart.empty(
          style: base,
          semanticLabel: 'Empty woven ring',
        ),
      ),
      _StateCase(
        title: 'Loading',
        note: 'One neutral 20% segment chasing the track',
        ring: WovenRingChart.loading(
          style: base,
          semanticLabel: 'Loading woven ring',
        ),
      ),
      _StateCase(
        title: 'Single 100% | jointed',
        note: 'Explicit alternate policy',
        ring: WovenRingChart(
          segments: _segmentsFor(
            _Scenario.singleValue,
            fillMode: _FillMode.solid,
            borderMode: _BorderMode.none,
          ),
          style: base.copyWith(
            singleSegmentStyle: WovenSingleSegmentStyle.jointed,
          ),
          animation: WovenRingAnimation.none,
        ),
      ),
      _StateCase(
        title: 'Single 100% | smooth',
        note: 'Default: one value has no boundary to show',
        ring: WovenRingChart(
          segments: _segmentsFor(
            _Scenario.singleValue,
            fillMode: _FillMode.gradient,
            borderMode: _BorderMode.none,
          ),
          style: base,
          animation: WovenRingAnimation.none,
        ),
      ),
      _StateCase(
        title: 'Tiny value | enforced',
        note: 'Legibility wins over exact proportions',
        ring: WovenRingChart(
          segments: _segmentsFor(
            _Scenario.tinyValue,
            fillMode: _FillMode.solid,
            borderMode: _BorderMode.none,
          ),
          style: base.copyWith(smallValuePolicy: WovenSmallValuePolicy.enforce),
          animation: WovenRingAnimation.none,
        ),
      ),
      _StateCase(
        title: 'Tiny value | allowed to vanish',
        note: 'Truthful policy, swallowed values collapse safely',
        ring: WovenRingChart(
          segments: _segmentsFor(
            _Scenario.tinyValue,
            fillMode: _FillMode.solid,
            borderMode: _BorderMode.none,
          ),
          style: base.copyWith(
            smallValuePolicy: WovenSmallValuePolicy.allowVanish,
          ),
          animation: WovenRingAnimation.none,
        ),
      ),
      _StateCase(
        title: 'Selected',
        note: 'One inside border, unchanged silhouette',
        ring: WovenRingChart(
          segments: _segmentsFor(
            _Scenario.quartet,
            fillMode: _FillMode.solid,
            borderMode: _BorderMode.none,
          ),
          style: base,
          highlightedIndex: 2,
          animation: WovenRingAnimation.none,
        ),
      ),
      _StateCase(
        title: 'Optional head shadow',
        note: 'Tight shadow under heads only, never in the hole',
        ring: WovenRingChart(
          segments: _segmentsFor(
            _Scenario.quartet,
            fillMode: _FillMode.solid,
            borderMode: _BorderMode.none,
          ),
          style: base.copyWith(shadow: const WovenShadow()),
          animation: WovenRingAnimation.none,
        ),
      ),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Wrap(
        spacing: 16,
        runSpacing: 16,
        children: <Widget>[
          for (var i = 0; i < cases.length; i++)
            SizedBox(
              key: ValueKey<String>('state-case-$i'),
              width: 270,
              child: Card(
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: <Widget>[
                      SizedBox.square(dimension: 190, child: cases[i].ring),
                      const SizedBox(height: 12),
                      Text(
                        cases[i].title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        cases[i].note,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF667085),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<WovenSegment> _segmentsFor(
    _Scenario scenario, {
    required _FillMode fillMode,
    required _BorderMode borderMode,
    bool alternate = false,
  }) {
    late List<double> values;
    late List<Color> colors;
    switch (scenario) {
      case _Scenario.quartet:
        values = alternate
            ? <double>[18, 31, 23, 28]
            : <double>[25, 25, 25, 25];
        colors = WovenPalette.quartet;
      case _Scenario.extended:
        values = alternate
            ? <double>[6, 14, 8, 12, 9, 15, 7, 11, 10, 8]
            : <double>[10, 9, 11, 8, 12, 10, 9, 11, 8, 12];
        colors = WovenPalette.extended;
      case _Scenario.tinyValue:
        values = alternate
            ? <double>[0.3, 30, 42, 27.7]
            : <double>[0.3, 39.7, 25, 35];
        colors = WovenPalette.quartet;
      case _Scenario.singleValue:
        values = const <double>[100];
        colors = const <Color>[WovenPalette.purple];
    }

    if (alternate && colors.length > 1) {
      colors = <Color>[...colors.skip(1), colors.first];
    }
    return <WovenSegment>[
      for (var i = 0; i < values.length; i++)
        WovenSegment(
          value: values[i],
          fill: _fillFor(colors[i % colors.length], fillMode, i),
          border: _borderFor(borderMode, i),
          semanticLabel: 'Segment ${i + 1}, value ${values[i]}',
        ),
    ];
  }

  WovenFill _fillFor(Color color, _FillMode mode, int index) {
    return switch (mode) {
      _FillMode.solid => WovenFill.solid(color),
      _FillMode.gradient => WovenFill.shaded(color, step: 0.04),
      _FillMode.diagnosticGradient => WovenFill.shaded(color, step: 0.20),
      _FillMode.mixed =>
        index.isOdd
            ? WovenFill.shaded(color, step: 0.04)
            : WovenFill.solid(color),
    };
  }

  WovenBorder? _borderFor(_BorderMode mode, int index) {
    return switch (mode) {
      _BorderMode.none || _BorderMode.selected => null,
      _BorderMode.mixed =>
        index == 1 || index == 5 ? const WovenBorder() : null,
      _BorderMode.all => const WovenBorder(),
      _BorderMode.diagnosticAlternating =>
        index.isOdd ? const WovenBorder(widthFraction: 0.05) : null,
    };
  }

  WovenRingStyle _style({
    bool clockwise = true,
    WovenGradientAxis gradientAxis = WovenGradientAxis.alongSegment,
    WovenGradientDirection gradientDirection =
        WovenGradientDirection.headToTail,
    WovenSmallValuePolicy smallValuePolicy = WovenSmallValuePolicy.enforce,
    double thicknessFraction = 0.20,
    double overlapFraction = 0.50,
    double startDegrees = -90.0,
    bool shadow = false,
  }) {
    return WovenRingStyle(
      clockwise: clockwise,
      gradientAxis: gradientAxis,
      gradientDirection: gradientDirection,
      smallValuePolicy: smallValuePolicy,
      thicknessFraction: thicknessFraction,
      overlapFraction: overlapFraction,
      startAngle: startDegrees * math.pi / 180,
      shadow: shadow ? const WovenShadow() : null,
      surfaceColor: _surface,
    );
  }

  Widget _dropdown<T>({
    required String key,
    required String label,
    required T value,
    required List<T> values,
    required String Function(T value) text,
    required ValueChanged<T> onChanged,
  }) {
    return DropdownButtonFormField<T>(
      key: ValueKey<String>(key),
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
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
    );
  }

  Widget _slider({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String valueLabel,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(left: 8, top: 8),
          child: Text('$label: $valueLabel'),
        ),
        Slider(
          value: value.clamp(min, max).toDouble(),
          min: min,
          max: max,
          divisions: divisions,
          label: valueLabel,
          onChanged: (double next) {
            onChanged(next.clamp(min, max).toDouble());
          },
        ),
      ],
    );
  }

  String _summary(int count) {
    return '$count segments | ${_fillName(_fillMode)} | ${_borderName(_borderMode)} | ${_clockwise ? 'clockwise' : 'counter-clockwise'}';
  }

  String _scenarioName(_Scenario value) => switch (value) {
    _Scenario.quartet => 'Reference 1 | 4 segments',
    _Scenario.extended => 'Reference 2 | 10 segments',
    _Scenario.tinyValue => 'Tiny-value stress case',
    _Scenario.singleValue => 'Single value | 100%',
  };

  String _fillName(_FillMode value) => switch (value) {
    _FillMode.solid => 'Solid',
    _FillMode.gradient => 'Gradient',
    _FillMode.diagnosticGradient => 'Diagnostic gradient (high contrast)',
    _FillMode.mixed => 'Mixed solid + gradient',
  };

  String _borderName(_BorderMode value) => switch (value) {
    _BorderMode.none => 'No border',
    _BorderMode.selected => 'Selected only',
    _BorderMode.mixed => 'Mixed per segment',
    _BorderMode.all => 'All segments',
    _BorderMode.diagnosticAlternating => 'Diagnostic alternating (5%)',
  };
}

class _CenterLabel extends StatelessWidget {
  const _CenterLabel({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            value,
            style: const TextStyle(
              color: _WovenRingChartLabPageState._ink,
              fontSize: 54,
              height: 1,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(color: Color(0xFF667085), fontSize: 16),
          ),
        ],
      ),
    );
  }
}

class _MatrixCase {
  const _MatrixCase({
    required this.title,
    required this.segments,
    required this.style,
  });

  final String title;
  final List<WovenSegment> segments;
  final WovenRingStyle style;
}

class _StateCase {
  const _StateCase({
    required this.title,
    required this.note,
    required this.ring,
  });

  final String title;
  final String note;
  final Widget ring;
}
