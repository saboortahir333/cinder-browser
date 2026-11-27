import 'dart:math' as math;

/// Percentile of an ascending-sorted list, with linear interpolation.
/// Returns NaN for an empty list.
double percentile(List<double> sortedAscending, double p) {
  if (sortedAscending.isEmpty) return double.nan;
  if (sortedAscending.length == 1) return sortedAscending.first;
  final clamped = p.clamp(0, 100).toDouble();
  final rank = (clamped / 100) * (sortedAscending.length - 1);
  final lo = rank.floor();
  final hi = rank.ceil();
  if (lo == hi) return sortedAscending[lo];
  return sortedAscending[lo] +
      (sortedAscending[hi] - sortedAscending[lo]) * (rank - lo);
}

double? _round2(double v) => v.isNaN ? null : (v * 100).roundToDouble() / 100;

/// Distribution summary of a list of measurements (milliseconds, bytes, ...).
class StatSummary {
  const StatSummary({
    required this.count,
    required this.min,
    required this.max,
    required this.mean,
    required this.p50,
    required this.p90,
    required this.p95,
    required this.p99,
  });

  static const StatSummary empty = StatSummary(
    count: 0,
    min: double.nan,
    max: double.nan,
    mean: double.nan,
    p50: double.nan,
    p90: double.nan,
    p95: double.nan,
    p99: double.nan,
  );

  final int count;
  final double min;
  final double max;
  final double mean;
  final double p50;
  final double p90;
  final double p95;
  final double p99;

  bool get isEmpty => count == 0;

  /// JSON-safe: NaN (no data) becomes null, values are rounded to 0.01.
  Map<String, Object?> toJson() => {
    'count': count,
    'min': _round2(min),
    'max': _round2(max),
    'mean': _round2(mean),
    'p50': _round2(p50),
    'p90': _round2(p90),
    'p95': _round2(p95),
    'p99': _round2(p99),
  };
}

StatSummary summarize(Iterable<num> values) {
  final sorted = values.map((v) => v.toDouble()).toList()..sort();
  if (sorted.isEmpty) return StatSummary.empty;
  final sum = sorted.fold<double>(0, (a, b) => a + b);
  return StatSummary(
    count: sorted.length,
    min: sorted.first,
    max: sorted.last,
    mean: sum / sorted.length,
    p50: percentile(sorted, 50),
    p90: percentile(sorted, 90),
    p95: percentile(sorted, 95),
    p99: percentile(sorted, 99),
  );
}

/// Relative change of [after] versus [before], in percent. Null when either is
/// missing or [before] is zero.
double? percentChange(double before, double after) {
  if (before.isNaN || after.isNaN || before == 0) return null;
  return _round2(((after - before) / before) * 100);
}

/// Largest of two values; kept here so callers do not import dart:math.
double maxOf(double a, double b) => math.max(a, b);
