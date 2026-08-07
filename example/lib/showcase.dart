// The woven_ring_chart showcase.
//
//   cd example && flutter run -t lib/showcase.dart
//
// One scrolling page, deployed to https://omar-hanafy.github.io/woven_ring_chart/
// on every push to main that touches the package or this example.
//
// Every section pairs a chart that is really running with the Dart that
// produced it, because the thing a developer evaluating a package actually
// needs is not a picture: it is the twelve lines that make the picture.
//
// This is deliberately not `main.dart`. pub.dev renders `example/lib/main.dart`
// under its Example tab, and a page of showcase scaffolding is the wrong first
// thing to show someone: that slot belongs to the shortest runnable example
// there is, which is what `main.dart` holds.
import 'package:flutter/material.dart';

import 'package:woven_ring_chart/woven_ring_chart.dart';

import 'src/sections/accessibility.dart';
import 'src/sections/animation.dart';
import 'src/sections/colours.dart';
import 'src/sections/fills.dart';
import 'src/sections/footer.dart';
import 'src/sections/hero.dart';
import 'src/sections/playground.dart';
import 'src/sections/quick_start.dart';
import 'src/sections/states.dart';
import 'src/showcase_theme.dart';

void main() => runApp(const WovenRingChartDemoApp());

class WovenRingChartDemoApp extends StatelessWidget {
  const WovenRingChartDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'woven_ring_chart',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: WovenPalette.purple,
          surface: ShowcaseColors.page,
        ),
        scaffoldBackgroundColor: ShowcaseColors.page,
        useMaterial3: true,
      ),
      home: const ShowcasePage(),
    );
  }
}

/// The whole showcase, top to bottom.
///
/// A [ListView] rather than a [SingleChildScrollView] on purpose: its children
/// are only inflated when they come near the viewport, so each ring plays its
/// entrance as you reach it instead of every ring on the page animating at
/// once into an empty screen.
class ShowcasePage extends StatelessWidget {
  const ShowcasePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Scrollbar(
          child: ListView(
            primary: true,
            children: const <Widget>[
              HeroSection(),
              QuickStartSection(),
              PlaygroundSection(),
              FillsSection(),
              AnimationSection(),
              StatesSection(),
              ColoursSection(),
              AccessibilitySection(),
              FooterSection(),
            ],
          ),
        ),
      ),
    );
  }
}
