/// Chrome-compatible zoom steps and per-site zoom memory.
class PageZoom {
  PageZoom._();

  static const List<double> steps = [
    0.25, 0.33, 0.5, 0.67, 0.75, 0.8, 0.9, 1.0,
    1.1, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0, 4.0, 5.0,
  ];
  static const double min = 0.25;
  static const double max = 5.0;

  static double clamp(double v) =>
      v.isNaN ? 1.0 : v.clamp(min, max).toDouble();

  static double zoomIn(double current) {
    for (final s in steps) {
      if (s > current + 0.001) return s;
    }
    return steps.last;
  }

  static double zoomOut(double current) {
    for (final s in steps.reversed) {
      if (s < current - 0.001) return s;
    }
    return steps.first;
  }

  static String label(double zoom) => '${(zoom * 100).round()}%';
}

/// Remembers a zoom level per host (not per full URL, like Chrome).
class SiteZoomMemory {
  SiteZoomMemory([Map<String, double>? initial]) {
    if (initial != null) _levels.addAll(initial);
  }

  static const int maxSites = 500;
  final Map<String, double> _levels = {};

  double levelFor(String host) => _levels[_key(host)] ?? 1.0;

  /// Stores the level; 100% removes the entry so the map stays small.
  void set(String host, double zoom) {
    final key = _key(host);
    if (key.isEmpty) return;
    final z = PageZoom.clamp(zoom);
    if ((z - 1.0).abs() < 0.001) {
      _levels.remove(key);
      return;
    }
    _levels.remove(key);
    _levels[key] = z;
    while (_levels.length > maxSites) {
      _levels.remove(_levels.keys.first);
    }
  }

  Map<String, dynamic> toJson() => {'levels': Map<String, double>.of(_levels)};

  static SiteZoomMemory fromJson(Map<String, dynamic>? json) {
    final memory = SiteZoomMemory();
    final raw = json?['levels'];
    if (raw is Map) {
      for (final entry in raw.entries) {
        final key = entry.key;
        final value = entry.value;
        if (key is String && value is num && key.length <= 253) {
          memory.set(key, value.toDouble());
        }
      }
    }
    return memory;
  }

  static String _key(String host) => host.trim().toLowerCase();
}
