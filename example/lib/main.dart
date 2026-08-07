// The smallest thing that draws a woven ring.
//
// This file is deliberately the whole of it. pub.dev renders it under the
// Example tab, so it is the first code most people ever see of this package,
// and it should be something you can read in one go and paste straight into an
// app.
//
// The showcase - every option, side by side with the code that produces it -
// is a separate entrypoint, and is what the live demo runs:
//
//   flutter run -t lib/showcase.dart
//   https://omar-hanafy.github.io/woven_ring_chart/
import 'package:flutter/material.dart';

import 'package:woven_ring_chart/woven_ring_chart.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: WovenRingChart(
            segments: <WovenSegment>[
              WovenSegment.solid(37, WovenPalette.purple),
              WovenSegment.solid(19, WovenPalette.green),
              WovenSegment.solid(29, WovenPalette.amber),
              WovenSegment.solid(15, WovenPalette.rose),
            ],
            center: const Text('100'),
            semanticLabel: 'Spending by category',
          ),
        ),
      ),
    );
  }
}
