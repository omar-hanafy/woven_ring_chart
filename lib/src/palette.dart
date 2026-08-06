import 'package:flutter/painting.dart';

/// A palette that suits the weave: mid-saturation colours that stay
/// distinct where two of them meet on a cap.
///
/// Nothing in the component reaches for these: a ring paints exactly the
/// colours its snakes carry. They are here so a chart looks right before
/// anyone has picked a palette, and so the examples and tests share one.
class WovenPalette {
  WovenPalette._();

  /// A warm off-white paper, and the default surface colour of a ring.
  ///
  /// A border with no colour of its own resolves to this, which is what turns
  /// two overlapping snakes into one cut out of the other.
  static const Color surface = Color(0xFFFBFAF7);

  /// Mid-saturation blue.
  static const Color blue = Color(0xFF378ADD);

  /// Mid-saturation violet.
  static const Color purple = Color(0xFF7F77DD);

  /// Mid-saturation green.
  static const Color green = Color(0xFF1D9E75);

  /// Warm mid-saturation orange.
  static const Color amber = Color(0xFFEF9F27);

  /// Mid-saturation pink.
  static const Color rose = Color(0xFFD4537E);

  /// Warm mid-saturation red.
  static const Color rust = Color(0xFFD85A30);

  /// The dark anchor among brights.
  ///
  /// One of these in a long palette stops a ring of eight or ten bright
  /// segments from reading as a single vibrating band.
  static const Color navy = Color(0xFF23385C);

  /// The grey of the empty and loading tracks.
  static const Color neutral = Color(0xFFDBD8D1);

  /// Four mid-saturation colours, enough for a ring of four segments.
  static const List<Color> quartet = <Color>[purple, green, amber, rose];

  /// Ten colours for longer rings, with one dark anchor among the brights.
  ///
  /// Ten entries, so a ten segment ring can index it directly. It repeats after
  /// six, which is why the sixth colour is [navy]: the repeat needs somewhere
  /// to land that does not look like a mistake.
  static const List<Color> extended = <Color>[
    blue,
    amber,
    green,
    rose,
    purple,
    navy,
    blue,
    amber,
    green,
    rose,
  ];

  /// Repeats [palette] up to [count] colours, making sure a colour never
  /// touches itself, including across the seam.
  ///
  /// Duplicates in [palette] are dropped before cycling. The last entry is
  /// swapped for another distinct colour when the plain repeat would put the
  /// first colour next to itself where the ring closes.
  ///
  /// Returns an empty list for an empty palette or a non-positive [count].
  /// Throws [ArgumentError] when the palette cannot colour a closed cycle:
  /// more than one snake needs two distinct colours, and an odd number of
  /// snakes above two needs three.
  static List<Color> cycle(List<Color> palette, int count) {
    if (palette.isEmpty || count <= 0) return const <Color>[];
    final List<Color> distinct = <Color>[];
    for (final Color color in palette) {
      if (!distinct.contains(color)) distinct.add(color);
    }
    if (count > 1 && distinct.length < 2) {
      throw ArgumentError.value(
        palette,
        'palette',
        'At least two distinct colors are required for multiple snakes.',
      );
    }
    if (count > 2 && count.isOdd && distinct.length == 2) {
      throw ArgumentError.value(
        palette,
        'palette',
        'An odd closed cycle requires at least three distinct colors.',
      );
    }
    final out = <Color>[
      for (var i = 0; i < count; i++) distinct[i % distinct.length],
    ];
    if (count > 2 && out.last == out.first) {
      for (final Color candidate in distinct) {
        if (candidate != out.first && candidate != out[count - 2]) {
          out[count - 1] = candidate;
          break;
        }
      }
    }
    return out;
  }
}
