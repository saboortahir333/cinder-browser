import 'dart:math';
import 'dart:ui' show PointMode;

import 'package:flutter/material.dart';

/// A built-in wallpaper that is painted in code: no download, no tracking,
/// instant, resolution-independent, and identical on every machine. Each one
/// layers a base gradient, soft glowing "light blobs", a vignette and a touch
/// of film grain so it reads as a designed image rather than a flat gradient.
class CinderWallpaperSpec {
  const CinderWallpaperSpec({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.top,
    required this.bottom,
    required this.blobs,
    this.isLight = false,
    this.sparks = 0,
    this.seed = 1,
  });

  final String id;
  final String name;
  final String subtitle;
  final Color top;
  final Color bottom;
  final List<LightBlob> blobs;

  /// Light artwork: skips the dark vignette so it stays airy.
  final bool isLight;

  /// Number of tiny glowing specks (embers / stars).
  final int sparks;
  final int seed;
}

class LightBlob {
  const LightBlob(this.x, this.y, this.radius, this.color, this.opacity);

  /// Centre in alignment coordinates (-1..1).
  final double x;
  final double y;

  /// Radius relative to the shorter canvas side.
  final double radius;
  final Color color;
  final double opacity;
}

class CinderWallpapers {
  CinderWallpapers._();

  static const CinderWallpaperSpec ember = CinderWallpaperSpec(
    id: 'ember',
    name: 'Ember',
    subtitle: 'Cinder’s signature: glowing coals in the dark.',
    top: Color(0xFF120A0A),
    bottom: Color(0xFF2A0F0B),
    sparks: 70,
    seed: 11,
    blobs: [
      LightBlob(0.6, 0.85, 1.1, Color(0xFFFF6A2B), 0.9),
      LightBlob(-0.7, 0.45, 0.9, Color(0xFFB3261E), 0.6),
      LightBlob(0.2, -0.6, 0.6, Color(0xFFFFB347), 0.3),
    ],
  );

  static const CinderWallpaperSpec aurora = CinderWallpaperSpec(
    id: 'aurora',
    name: 'Aurora',
    subtitle: 'Northern lights over a polar night.',
    top: Color(0xFF04111F),
    bottom: Color(0xFF07222B),
    sparks: 60,
    seed: 23,
    blobs: [
      LightBlob(-0.5, -0.3, 0.9, Color(0xFF2BFFB0), 0.55),
      LightBlob(0.5, -0.5, 0.9, Color(0xFF7A5CFF), 0.5),
      LightBlob(0.0, 0.7, 1.0, Color(0xFF00B8D9), 0.35),
    ],
  );

  static const CinderWallpaperSpec dusk = CinderWallpaperSpec(
    id: 'dusk',
    name: 'Dusk',
    subtitle: 'The last light of a violet evening.',
    top: Color(0xFF2A1B4D),
    bottom: Color(0xFFE8764C),
    seed: 5,
    blobs: [
      LightBlob(0.0, 0.95, 0.95, Color(0xFFFFD08A), 0.65),
      LightBlob(-0.8, -0.6, 1.0, Color(0xFF5B3FA8), 0.5),
      LightBlob(0.8, 0.3, 0.7, Color(0xFFFF6F91), 0.35),
    ],
  );

  static const CinderWallpaperSpec abyss = CinderWallpaperSpec(
    id: 'abyss',
    name: 'Abyss',
    subtitle: 'Light filtering down into deep water.',
    top: Color(0xFF021A2B),
    bottom: Color(0xFF04293F),
    seed: 31,
    sparks: 30,
    blobs: [
      LightBlob(0.7, -0.6, 1.0, Color(0xFF0FA3B1), 0.45),
      LightBlob(-0.6, 0.7, 1.0, Color(0xFF0B5FA5), 0.5),
      LightBlob(0.0, 0.0, 0.5, Color(0xFF38D0E0), 0.15),
    ],
  );

  static const CinderWallpaperSpec nebula = CinderWallpaperSpec(
    id: 'nebula',
    name: 'Nebula',
    subtitle: 'A stellar nursery in pink and blue.',
    top: Color(0xFF0B0620),
    bottom: Color(0xFF1A0B3B),
    sparks: 90,
    seed: 41,
    blobs: [
      LightBlob(-0.4, -0.2, 0.9, Color(0xFFFF4FD8), 0.5),
      LightBlob(0.6, 0.4, 1.0, Color(0xFF4F7BFF), 0.5),
      LightBlob(0.1, 0.9, 0.8, Color(0xFFA855F7), 0.4),
    ],
  );

  static const CinderWallpaperSpec mistForest = CinderWallpaperSpec(
    id: 'mist-forest',
    name: 'Mist Forest',
    subtitle: 'Green shade and morning haze.',
    top: Color(0xFF0E1F1A),
    bottom: Color(0xFF1F3D31),
    seed: 53,
    blobs: [
      LightBlob(0.5, -0.7, 1.0, Color(0xFFA7F3D0), 0.25),
      LightBlob(-0.6, 0.6, 0.9, Color(0xFF34D399), 0.3),
      LightBlob(0.8, 0.8, 0.6, Color(0xFF065F46), 0.5),
    ],
  );

  static const CinderWallpaperSpec sakura = CinderWallpaperSpec(
    id: 'sakura',
    name: 'Sakura',
    subtitle: 'Soft blossom pinks, light and airy.',
    top: Color(0xFFF6D5E0),
    bottom: Color(0xFFE8B5D0),
    isLight: true,
    seed: 61,
    blobs: [
      LightBlob(-0.5, -0.4, 0.9, Color(0xFFFFFFFF), 0.6),
      LightBlob(0.7, 0.5, 1.0, Color(0xFFFF9EC4), 0.5),
      LightBlob(0.0, 0.9, 0.8, Color(0xFFC9A7FF), 0.4),
    ],
  );

  static const CinderWallpaperSpec goldenHour = CinderWallpaperSpec(
    id: 'golden-hour',
    name: 'Golden Hour',
    subtitle: 'Warm sun low on the horizon.',
    top: Color(0xFFFFC857),
    bottom: Color(0xFFE9724C),
    isLight: true,
    seed: 71,
    blobs: [
      LightBlob(0.7, -0.6, 0.9, Color(0xFFFFF1B8), 0.7),
      LightBlob(-0.7, 0.8, 1.0, Color(0xFFC2410C), 0.5),
    ],
  );

  static const CinderWallpaperSpec neonCity = CinderWallpaperSpec(
    id: 'neon-city',
    name: 'Neon City',
    subtitle: 'Cyan and magenta after midnight.',
    top: Color(0xFF090B1F),
    bottom: Color(0xFF16102E),
    sparks: 40,
    seed: 83,
    blobs: [
      LightBlob(-0.7, 0.7, 0.8, Color(0xFF00E5FF), 0.5),
      LightBlob(0.7, 0.5, 0.9, Color(0xFFFF2E97), 0.55),
      LightBlob(0.0, -0.8, 0.8, Color(0xFF6A5CFF), 0.4),
    ],
  );

  static const CinderWallpaperSpec glacier = CinderWallpaperSpec(
    id: 'glacier',
    name: 'Glacier',
    subtitle: 'Cold, bright and perfectly clear.',
    top: Color(0xFFCFEAF7),
    bottom: Color(0xFF8FC7E6),
    isLight: true,
    seed: 97,
    blobs: [
      LightBlob(0.6, -0.6, 0.9, Color(0xFFFFFFFF), 0.8),
      LightBlob(-0.7, 0.7, 1.0, Color(0xFF5AA9E6), 0.45),
    ],
  );

  static const CinderWallpaperSpec lava = CinderWallpaperSpec(
    id: 'lava',
    name: 'Lava Flow',
    subtitle: 'Molten orange, red and gold.',
    top: Color(0xFF1B0B0B),
    bottom: Color(0xFF2D0A18),
    sparks: 50,
    seed: 101,
    blobs: [
      LightBlob(0.0, 0.5, 0.9, Color(0xFFFF3D00), 0.7),
      LightBlob(-0.7, -0.5, 0.6, Color(0xFFFFB300), 0.45),
      LightBlob(0.8, -0.3, 0.7, Color(0xFFE91E63), 0.5),
    ],
  );

  static const CinderWallpaperSpec cosmic = CinderWallpaperSpec(
    id: 'cosmic',
    name: 'Cosmic Violet',
    subtitle: 'Deep space with violet and teal glow.',
    top: Color(0xFF05010F),
    bottom: Color(0xFF0E0524),
    sparks: 110,
    seed: 113,
    blobs: [
      LightBlob(0.3, -0.3, 1.1, Color(0xFF7C3AED), 0.55),
      LightBlob(-0.7, 0.5, 0.8, Color(0xFF06B6D4), 0.35),
      LightBlob(0.8, 0.8, 0.6, Color(0xFFF472B6), 0.35),
    ],
  );

  static const CinderWallpaperSpec dune = CinderWallpaperSpec(
    id: 'dune',
    name: 'Desert Dune',
    subtitle: 'Sand, sun and long shadows.',
    top: Color(0xFFF2C9A0),
    bottom: Color(0xFFC98B5B),
    isLight: true,
    seed: 127,
    blobs: [
      LightBlob(-0.6, -0.7, 0.9, Color(0xFFFFE9C7), 0.7),
      LightBlob(0.8, 0.7, 1.1, Color(0xFF8C4A2F), 0.5),
    ],
  );

  static const CinderWallpaperSpec orchidNight = CinderWallpaperSpec(
    id: 'orchid-night',
    name: 'Orchid Night',
    subtitle: 'Soft magenta bloom in the dark.',
    top: Color(0xFF1B1033),
    bottom: Color(0xFF2E1A4F),
    sparks: 40,
    seed: 131,
    blobs: [
      LightBlob(0.0, -0.5, 1.0, Color(0xFFC084FC), 0.45),
      LightBlob(0.7, 0.7, 0.8, Color(0xFFF0ABFC), 0.35),
      LightBlob(-0.8, 0.6, 0.7, Color(0xFF6D28D9), 0.4),
    ],
  );

  static const CinderWallpaperSpec peachHaze = CinderWallpaperSpec(
    id: 'peach-haze',
    name: 'Peach Haze',
    subtitle: 'A gentle apricot-to-lilac wash.',
    top: Color(0xFFFFD6C2),
    bottom: Color(0xFFD9B8F5),
    isLight: true,
    seed: 139,
    blobs: [
      LightBlob(-0.6, -0.5, 1.0, Color(0xFFFFFFFF), 0.55),
      LightBlob(0.7, 0.2, 0.9, Color(0xFFFF9F80), 0.45),
      LightBlob(0.0, 0.9, 0.9, Color(0xFFB794F6), 0.45),
    ],
  );

  static const CinderWallpaperSpec tideline = CinderWallpaperSpec(
    id: 'tideline',
    name: 'Tideline',
    subtitle: 'Turquoise shallows meeting deep blue.',
    top: Color(0xFF0A3D62),
    bottom: Color(0xFF3CCFCF),
    seed: 149,
    blobs: [
      LightBlob(0.7, 0.8, 1.0, Color(0xFFB8FFF1), 0.45),
      LightBlob(-0.7, -0.5, 1.0, Color(0xFF0B2A52), 0.6),
    ],
  );

  /// The private-window backdrop. Not offered in the wallpaper library: it is
  /// always used for private windows so they are instantly recognisable.
  static const CinderWallpaperSpec privateWindow = CinderWallpaperSpec(
    id: 'private',
    name: 'Cinder Private',
    subtitle: 'Violet night with a faint ember glow.',
    top: Color(0xFF0E0420),
    bottom: Color(0xFF2A0B4F),
    sparks: 55,
    seed: 7,
    blobs: [
      LightBlob(-0.5, 0.85, 1.1, Color(0xFF7E3FF2), 0.55),
      LightBlob(0.6, -0.5, 0.75, Color(0xFFFF6FB5), 0.28),
      LightBlob(0.3, 0.3, 0.9, Color(0xFF3B1B80), 0.5),
    ],
  );

  /// Everything offered in the library (the private backdrop excluded).
  static const List<CinderWallpaperSpec> library = [
    ember,
    aurora,
    dusk,
    abyss,
    nebula,
    mistForest,
    sakura,
    goldenHour,
    neonCity,
    glacier,
    lava,
    cosmic,
    dune,
    orchidNight,
    peachHaze,
    tideline,
  ];

  static CinderWallpaperSpec? byId(String? id) {
    if (id == 'private') return privateWindow;
    for (final spec in library) {
      if (spec.id == id) return spec;
    }
    return null;
  }

  /// Deterministic "daily rotation": the same artwork all day, a new one each
  /// day, with no network access.
  static CinderWallpaperSpec forDate(DateTime date) {
    final day = DateTime(date.year, date.month, date.day)
        .difference(DateTime(2024))
        .inDays;
    return library[day.abs() % library.length];
  }
}

/// Paints a [CinderWallpaperSpec] to fill its box.
class CinderWallpaper extends StatelessWidget {
  const CinderWallpaper(this.spec, {super.key});

  final CinderWallpaperSpec spec;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _CinderWallpaperPainter(spec),
        size: Size.infinite,
      ),
    );
  }
}

class _CinderWallpaperPainter extends CustomPainter {
  _CinderWallpaperPainter(this.spec);

  final CinderWallpaperSpec spec;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;

    // 1. Base gradient.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [spec.top, spec.bottom],
        ).createShader(rect),
    );

    // 2. Glowing light blobs.
    for (final blob in spec.blobs) {
      canvas.drawRect(
        rect,
        Paint()
          ..shader = RadialGradient(
            center: Alignment(blob.x, blob.y),
            radius: blob.radius,
            colors: [
              blob.color.withValues(alpha: blob.opacity),
              blob.color.withValues(alpha: blob.opacity * 0.35),
              blob.color.withValues(alpha: 0),
            ],
            stops: const [0, 0.45, 1],
          ).createShader(rect),
      );
    }

    // 3. Vignette (dark art only) to pull focus to the middle.
    if (!spec.isLight) {
      canvas.drawRect(
        rect,
        Paint()
          ..shader = RadialGradient(
            center: Alignment.center,
            radius: 1.15,
            colors: const [Color(0x00000000), Color(0x59000000)],
            stops: const [0.55, 1],
          ).createShader(rect),
      );
    }

    final rng = Random(spec.seed);

    // 4. Embers / stars.
    for (var i = 0; i < spec.sparks; i++) {
      final center = Offset(
        rng.nextDouble() * size.width,
        rng.nextDouble() * size.height,
      );
      final r = 0.6 + rng.nextDouble() * 1.8;
      final a = 0.25 + rng.nextDouble() * 0.6;
      canvas.drawCircle(
        center,
        r * 2.6,
        Paint()
          ..color = Colors.white.withValues(alpha: a * 0.12)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
      canvas.drawCircle(
        center,
        r * 0.55,
        Paint()..color = Colors.white.withValues(alpha: a),
      );
    }

    // 5. Film grain: a few thousand faint specks kill gradient banding.
    final grain = Paint()
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    final count = (size.width * size.height / 900).clamp(600, 3200).toInt();
    final points = <Offset>[
      for (var i = 0; i < count; i++)
        Offset(rng.nextDouble() * size.width, rng.nextDouble() * size.height),
    ];
    canvas.drawPoints(
      PointMode.points,
      points,
      grain..color = (spec.isLight ? Colors.black : Colors.white).withValues(
        alpha: 0.035,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant _CinderWallpaperPainter old) =>
      old.spec.id != spec.id;
}
