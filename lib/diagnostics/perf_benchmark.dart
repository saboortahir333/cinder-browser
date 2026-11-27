import 'package:saboor_browser/diagnostics/perf_stats.dart';

/// Loads [url] once with request shielding forced on or off, and returns the
/// time to load in milliseconds, or null if it did not finish in time.
typedef BenchmarkLoad =
    Future<int?> Function(String url, {required bool shieldsOn});

/// Sites used by the built-in benchmark: small, stable, public pages that
/// cover plain HTML, a heavier content site and an ad/tracker-rich page.
const List<String> kBenchmarkUrls = [
  'https://example.com/',
  'https://en.wikipedia.org/wiki/Web_browser',
  'https://news.ycombinator.com/',
  'https://www.bbc.com/news',
];

class BenchmarkCell {
  BenchmarkCell(this.url, this.shieldsOn);

  final String url;
  final bool shieldsOn;
  final List<int> samplesMs = [];
  int timeouts = 0;

  Map<String, Object?> toJson() => {
    // Host only: no path or query in the report.
    'host': Uri.tryParse(url)?.host ?? '',
    'shieldsOn': shieldsOn,
    'samplesMs': samplesMs,
    'timeouts': timeouts,
    'medianMs': summarize(samplesMs).p50.isNaN
        ? null
        : summarize(samplesMs).p50,
  };
}

class BenchmarkResult {
  BenchmarkResult(this.cells, {required this.cancelled});

  final List<BenchmarkCell> cells;
  final bool cancelled;

  StatSummary summaryFor({required bool shieldsOn}) => summarize([
    for (final c in cells)
      if (c.shieldsOn == shieldsOn) ...c.samplesMs,
  ]);

  /// Positive = shields made pages slower, negative = faster.
  double? get shieldsCostPercent {
    final on = summaryFor(shieldsOn: true);
    final off = summaryFor(shieldsOn: false);
    if (on.isEmpty || off.isEmpty) return null;
    return percentChange(off.p50, on.p50);
  }

  Map<String, Object?> toJson() => {
    'cancelled': cancelled,
    'shieldsOnMs': summaryFor(shieldsOn: true).toJson(),
    'shieldsOffMs': summaryFor(shieldsOn: false).toJson(),
    'shieldsCostPercentOfMedian': shieldsCostPercent,
    'cells': [for (final c in cells) c.toJson()],
  };
}

/// Measures page-load time with shields on and off.
///
/// Rounds alternate on/off so slow-network drift and warm DNS hit both modes
/// equally. The caller is responsible for disabling the HTTP cache for the
/// duration, so every load is a cold load.
class PerfBenchmark {
  static Future<BenchmarkResult> run({
    required List<String> urls,
    required BenchmarkLoad load,
    int rounds = 3,
    void Function(String status)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final cells = <BenchmarkCell>[
      for (final u in urls) ...[
        BenchmarkCell(u, true),
        BenchmarkCell(u, false),
      ],
    ];
    BenchmarkCell cell(String url, bool on) =>
        cells.firstWhere((c) => c.url == url && c.shieldsOn == on);

    var cancelled = false;
    for (var round = 1; round <= rounds && !cancelled; round++) {
      for (final on
          in round.isOdd ? const [true, false] : const [false, true]) {
        for (final url in urls) {
          if (isCancelled?.call() ?? false) {
            cancelled = true;
            break;
          }
          final host = Uri.tryParse(url)?.host ?? url;
          onProgress?.call(
            'Round $round/$rounds: $host, shields ${on ? 'on' : 'off'}',
          );
          final ms = await load(url, shieldsOn: on);
          final c = cell(url, on);
          if (ms == null) {
            c.timeouts++;
          } else {
            c.samplesMs.add(ms);
          }
        }
        if (cancelled) break;
      }
    }
    return BenchmarkResult(cells, cancelled: cancelled);
  }
}
