// Ten segments, every one gradient-filled and bordered, animating continuously.
//
//   cd example && flutter run -t lib/ten_segments.dart
//
// One screen, one chart. The entrance replays on a timer and the data reshuffles
// between it, so every animated path the chart has - the sweep reveal and the
// data transition - is on screen without touching a control.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:woven_ring_chart/woven_ring_chart.dart';

void main() => runApp(const TenSegmentsApp());

const Color _surface = Color(0xFFFBFAF7);
const Color _ink = Color(0xFF202532);

/// Deterministic, so what is on screen can be checked against the data rather
/// than against whatever a random generator happened to produce.
const List<List<double>> _dataSets = <List<double>>[
  <double>[10, 10, 10, 10, 10, 10, 10, 10, 10, 10],
  <double>[18, 6, 13, 9, 15, 5, 11, 8, 7, 8],
  <double>[6, 14, 8, 12, 7, 16, 9, 11, 10, 7],
  <double>[12, 9, 11, 8, 13, 10, 7, 12, 9, 9],
];

class TenSegmentsApp extends StatelessWidget {
  const TenSegmentsApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Ten segments',
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: WovenPalette.blue,
        surface: _surface,
      ),
      scaffoldBackgroundColor: _surface,
      useMaterial3: true,
    ),
    home: const TenSegmentsScreen(),
  );
}

class TenSegmentsScreen extends StatefulWidget {
  const TenSegmentsScreen({super.key});

  @override
  State<TenSegmentsScreen> createState() => _TenSegmentsScreenState();
}

class _TenSegmentsScreenState extends State<TenSegmentsScreen> {
  final WovenRingChartController _controller = WovenRingChartController();
  Timer? _shuffle;
  Timer? _replay;
  int _set = 0;
  int _cycles = 0;
  bool _running = true;

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    _shuffle = Timer.periodic(const Duration(milliseconds: 2200), (_) {
      setState(() {
        _set = (_set + 1) % _dataSets.length;
        _cycles++;
      });
    });
    _replay = Timer.periodic(const Duration(seconds: 11), (_) {
      _controller.replay();
    });
  }

  void _stop() {
    _shuffle?.cancel();
    _replay?.cancel();
    _shuffle = null;
    _replay = null;
  }

  @override
  void dispose() {
    _stop();
    _controller.dispose();
    super.dispose();
  }

  List<WovenSegment> get _segments {
    final List<double> values = _dataSets[_set];
    return <WovenSegment>[
      for (var i = 0; i < values.length; i++)
        WovenSegment(
          value: values[i],
          // Every segment gradient-filled...
          fill: WovenFill.shaded(WovenPalette.extended[i], step: 0.04),
          // ...and every segment bordered.
          border: const WovenBorder(),
          semanticLabel: 'Segment ${i + 1}',
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final List<WovenSegment> segments = _segments;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Text(
                'Ten segments, all gradient, all bordered, animating',
                key: ValueKey<String>('headline'),
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: _ink,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'sweep animation every 11s, data transition every 2.2s',
                style: TextStyle(
                  fontSize: 13,
                  color: _ink.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 28),
              SizedBox.square(
                dimension: 460,
                child: WovenRingChart(
                  key: const ValueKey<String>('ten-segment-ring'),
                  segments: segments,
                  style: const WovenRingStyle(surfaceColor: _surface),
                  animation: WovenRingAnimation.sweep,
                  controller: _controller,
                  semanticLabel: 'Ten segment woven ring',
                  semanticValue: '${segments.length} segments',
                  center: _Centre(
                    value: '${segments.length}',
                    label: 'segments',
                    note: 'set ${_set + 1} of ${_dataSets.length}',
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Wrap(
                spacing: 12,
                children: <Widget>[
                  FilledButton.icon(
                    key: const ValueKey<String>('replay'),
                    onPressed: _controller.replay,
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Replay animation'),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey<String>('shuffle'),
                    onPressed: () => setState(() {
                      _set = (_set + 1) % _dataSets.length;
                      _cycles++;
                    }),
                    icon: const Icon(Icons.swap_horiz_rounded),
                    label: const Text('Next data'),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey<String>('toggle'),
                    onPressed: () => setState(() {
                      _running = !_running;
                      if (_running) {
                        _start();
                      } else {
                        _stop();
                      }
                    }),
                    icon: Icon(
                      _running
                          ? Icons.pause_rounded
                          : Icons.play_circle_outline_rounded,
                    ),
                    label: Text(_running ? 'Pause' : 'Resume'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'transitions: $_cycles',
                key: const ValueKey<String>('cycle-count'),
                style: TextStyle(
                  fontSize: 12,
                  color: _ink.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Centre extends StatelessWidget {
  const _Centre({required this.value, required this.label, required this.note});

  final String value;
  final String label;
  final String note;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      Text(
        value,
        style: const TextStyle(
          fontSize: 46,
          fontWeight: FontWeight.w700,
          color: _ink,
          height: 1.0,
        ),
      ),
      const SizedBox(height: 2),
      Text(label, style: TextStyle(color: _ink.withValues(alpha: 0.65))),
      const SizedBox(height: 6),
      Text(
        note,
        style: TextStyle(fontSize: 11, color: _ink.withValues(alpha: 0.45)),
      ),
    ],
  );
}
