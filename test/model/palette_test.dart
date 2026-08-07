// The reference palette, and the cycle that keeps a colour from touching
// itself across the seam.
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woven_ring_chart/woven_ring_chart.dart';

void main() {
  group('WovenPalette.cycle', () {
    const red = Color(0xFFFF0000);
    const green = Color(0xFF00FF00);
    const blue = Color(0xFF0000FF);

    test('handles empty requests and permits one segment', () {
      expect(WovenPalette.cycle(const <Color>[], 4), isEmpty);
      expect(WovenPalette.cycle(const <Color>[red], 0), isEmpty);
      expect(WovenPalette.cycle(const <Color>[red], -1), isEmpty);
      expect(WovenPalette.cycle(const <Color>[red], 1), const <Color>[red]);
    });

    test('deduplicates colors, cycles them, and protects the seam', () {
      final colors = WovenPalette.cycle(const <Color>[
        red,
        red,
        green,
        blue,
        green,
      ], 7);

      expect(colors, hasLength(7));
      expect(colors.take(6), const <Color>[red, green, blue, red, green, blue]);
      for (var i = 0; i < colors.length; i++) {
        expect(colors[i], isNot(colors[(i + 1) % colors.length]));
      }
    });

    test('two colors form a valid even closed cycle', () {
      expect(WovenPalette.cycle(const <Color>[red, green], 6), const <Color>[
        red,
        green,
        red,
        green,
        red,
        green,
      ]);
    });

    test('rejects multiple segments when only one distinct color exists', () {
      expect(
        () => WovenPalette.cycle(const <Color>[red, red], 2),
        throwsArgumentError,
      );
    });

    test('rejects an odd closed cycle with only two distinct colors', () {
      expect(
        () => WovenPalette.cycle(const <Color>[red, green, red], 5),
        throwsArgumentError,
      );
    });
  });
}
