import 'dart:ui' show ColorSpace;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woven_ring_chart/woven_ring_chart.dart';

const _fill = WovenFill.solid(WovenPalette.blue);
const _white = Color(0xffffffff);
const _black = Color(0xff000000);
const _red = Color(0xffff0000);

void main() {
  test('mixed retained border keeps surface contribution through fades', () {
    final first = WovenBorder.lerp(
      const WovenBorder(),
      const WovenBorder(color: _red),
      0.25,
      fill: _fill,
      surfaceColor: _white,
    );
    final second = WovenBorder.lerp(
      first,
      const WovenBorder(),
      0.5,
      fill: _fill,
      surfaceColor: _white,
    )!;
    final expected = Color.lerp(_black, _red, 0.125);
    expect(second.resolve(_fill, _black), expected);
    for (final fading in <WovenBorder>[
      WovenBorder.lerp(null, second, 0.25)!,
      WovenBorder.lerp(second, null, 0.75)!,
    ]) {
      expect(fading.resolve(_fill, _black), expected);
      expect(fading.resolvedOpacity, 0.25);
    }
  });

  test('pure darker-fill retargets retain the current fill derivation', () {
    const nextFill = WovenFill.gradient(
      head: Color(0xfffac080),
      tail: Color(0xff805020),
    );
    const border = WovenBorder.darkerFill();
    var retained = border;
    for (var i = 0; i < 100; i++) {
      retained = WovenBorder.lerp(
        retained,
        border,
        0.2,
        fill: _fill,
        surfaceColor: _white,
      )!;
    }
    expect(
      retained.resolve(nextFill, _black),
      border.resolve(nextFill, _black),
    );
  });

  test('mixed fill and surface contributions remain live after retarget', () {
    const nextFill = WovenFill.solid(Color(0xff8090a0));
    const dark = WovenBorder.darkerFill();
    final first = WovenBorder.lerp(
      dark,
      const WovenBorder(),
      0.25,
      fill: _fill,
      surfaceColor: _white,
    );
    final retained = WovenBorder.lerp(
      first,
      const WovenBorder(color: _red),
      0.5,
      fill: _fill,
      surfaceColor: _white,
    )!;
    _expectColorNear(
      retained.resolve(nextFill, _black),
      Color.lerp(
        Color.lerp(dark.resolve(nextFill, _black), _black, 0.25),
        _red,
        0.5,
      )!,
    );
  });

  test(
    'derived snapshots have value equality distinct from explicit color',
    () {
      WovenBorder snapshot() => WovenBorder.lerp(
        const WovenBorder(),
        const WovenBorder(color: _white),
        0.5,
        fill: _fill,
        surfaceColor: _white,
      )!;
      final a = snapshot();
      final b = snapshot();
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a.color, _white);
      expect(a, isNot(const WovenBorder(color: _white)));
      expect(
        a.resolve(_fill, _black),
        const Color(0xff808080).withValues(red: 0.5, green: 0.5, blue: 0.5),
      );
    },
  );

  test('P3 surface contributions retain channels and live alpha', () {
    const surface = Color.from(
      alpha: 0.6,
      red: 0.2,
      green: 0.8,
      blue: 0.3,
      colorSpace: ColorSpace.displayP3,
    );
    const nextSurface = Color.from(
      alpha: 0.3,
      red: 0.7,
      green: 0.2,
      blue: 0.6,
      colorSpace: ColorSpace.displayP3,
    );
    const explicit = Color.from(
      alpha: 0.8,
      red: 0.9,
      green: 0.5,
      blue: 0.1,
      colorSpace: ColorSpace.displayP3,
    );
    final first = WovenBorder.lerp(
      const WovenBorder(),
      const WovenBorder(color: explicit),
      0.25,
      fill: _fill,
      surfaceColor: surface,
    );
    final retained = WovenBorder.lerp(
      first,
      const WovenBorder(),
      0.5,
      fill: _fill,
      surfaceColor: surface,
    )!;
    _expectColorNear(
      retained.resolve(_fill, nextSurface),
      Color.lerp(nextSurface, explicit, 0.125)!,
    );
  });

  test('mixed-gamut retargets keep each exact Color.lerp sample', () {
    const p3 = Color.from(
      alpha: 0.7,
      red: 0.9,
      green: 0.2,
      blue: 0.6,
      colorSpace: ColorSpace.displayP3,
    );
    const borders = <WovenBorder>[
      WovenBorder(),
      WovenBorder.darkerFill(),
      WovenBorder(color: p3),
      WovenBorder(color: _red),
    ];
    var retained = borders.first;
    for (var i = 0; i < 20; i++) {
      final next = borders[(i + 1) % borders.length];
      final surface = i.isEven ? _white : p3;
      final expected = Color.lerp(
        retained.resolve(_fill, surface),
        next.resolve(_fill, surface),
        0.37,
      );
      retained = WovenBorder.lerp(
        retained,
        next,
        0.37,
        fill: _fill,
        surfaceColor: surface,
      )!;
      expect(retained.color, expected);
      expect(retained.resolve(_fill, surface), expected);
    }
  });

  test(
    'default fill and extrapolated samples preserve Color.lerp behavior',
    () {
      const borders = <WovenBorder>[
        WovenBorder(),
        WovenBorder.darkerFill(),
        WovenBorder(color: _red),
      ];
      const defaultFill = WovenFill.solid(_white);
      for (final a in borders) {
        for (final b in borders) {
          for (final t in <double>[-2, -0.25, 0, 1, 1.25, 3]) {
            final expected = Color.lerp(
              a.resolve(defaultFill, _white),
              b.resolve(defaultFill, _white),
              t,
            );
            final retained = WovenBorder.lerp(a, b, t, surfaceColor: _white)!;
            expect(retained.color, expected, reason: 'sample t=$t');
            expect(
              retained.resolve(defaultFill, _white),
              expected,
              reason: 'resolve t=$t',
            );
          }
        }
      }
    },
  );

  test('derived retarget work remains bounded after 6000 updates', () {
    final surface = _CountingColor();
    var retained = const WovenBorder();
    for (var i = 0; i < 6000; i++) {
      retained = WovenBorder.lerp(
        retained,
        i.isEven ? const WovenBorder(color: _red) : const WovenBorder(),
        0.1,
        fill: _fill,
        surfaceColor: _white,
      )!;
    }
    surface.reads = 0;
    final resolved = retained.resolve(_fill, surface);
    expect(resolved.a, 1);
    expect(
      surface.reads,
      lessThan(64),
      reason: 'resolve must not visit a source once per previous retarget',
    );
  });
}

void _expectColorNear(Color actual, Color expected) {
  expect(actual.colorSpace, expected.colorSpace);
  expect(actual.a, closeTo(expected.a, 1e-12));
  expect(actual.r, closeTo(expected.r, 1e-12));
  expect(actual.g, closeTo(expected.g, 1e-12));
  expect(actual.b, closeTo(expected.b, 1e-12));
}

class _CountingColor extends Color {
  _CountingColor() : super(0xff000000);

  int reads = 0;

  @override
  double get a {
    reads++;
    return super.a;
  }

  @override
  double get r {
    reads++;
    return super.r;
  }

  @override
  double get g {
    reads++;
    return super.g;
  }

  @override
  double get b {
    reads++;
    return super.b;
  }
}
