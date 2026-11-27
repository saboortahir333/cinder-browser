import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'package:saboor_browser/diagnostics/cdp_memory.dart';
import 'package:saboor_browser/diagnostics/perf_benchmark.dart';
import 'package:saboor_browser/diagnostics/perf_stats.dart';
import 'package:saboor_browser/diagnostics/win_memory.dart';

/// One finished page load.
class LoadSample {
  const LoadSample({
    required this.host,
    required this.shieldsOn,
    required this.ms,
    required this.at,
  });

  /// Host name only. Paths, queries and credentials are never stored.
  final String host;
  final bool shieldsOn;
  final int ms;
  final DateTime at;

  Map<String, Object?> toJson() => {
    'host': host,
    'shieldsOn': shieldsOn,
    'ms': ms,
    'at': at.toUtc().toIso8601String(),
  };
}

/// Frame-time statistics over the rolling window.
class FrameStats {
  const FrameStats({
    required this.total,
    required this.build,
    required this.raster,
    required this.frames,
    required this.slow,
    required this.janky,
    required this.frozen,
  });

  static const FrameStats empty = FrameStats(
    total: StatSummary.empty,
    build: StatSummary.empty,
    raster: StatSummary.empty,
    frames: 0,
    slow: 0,
    janky: 0,
    frozen: 0,
  );

  /// Build + raster, in milliseconds.
  final StatSummary total;
  final StatSummary build;
  final StatSummary raster;

  /// Frames seen since the probe started (not just the window).
  final int frames;

  /// Frames over 16.7 ms (missed a 60 Hz deadline), over 33.4 ms, and over
  /// 700 ms (Flutter's "frozen" threshold).
  final int slow;
  final int janky;
  final int frozen;

  double get slowPercent => frames == 0 ? 0 : slow * 100 / frames;

  Map<String, Object?> toJson() => {
    'framesSeen': frames,
    'totalMs': total.toJson(),
    'buildMs': build.toJson(),
    'rasterMs': raster.toJson(),
    'slowOver16_7ms': slow,
    'jankyOver33_4ms': janky,
    'frozenOver700ms': frozen,
    'slowPercent': (slowPercent * 100).roundToDouble() / 100,
  };
}

class _PendingLoad {
  _PendingLoad(this.shieldsOn);
  final bool shieldsOn;
  final Stopwatch watch = Stopwatch()..start();
}

/// Local-only performance probe.
///
/// Privacy: it collects nothing until [start] is called (the Performance
/// monitor is opt-in), is never started for private windows, keeps everything
/// in memory, and sends nothing anywhere. A report only leaves memory when the
/// user exports it to a file.
class PerfProbe extends ChangeNotifier {
  PerfProbe({this.maxFrames = 1200, this.maxLoads = 200});

  static final PerfProbe instance = PerfProbe();

  final int maxFrames;
  final int maxLoads;

  static const double _slowMs = 16.7;
  static const double _jankyMs = 33.4;
  static const double _frozenMs = 700;
  static const Duration _maxInputWait = Duration(milliseconds: 500);

  /// Loopback DevTools port of this window (0 = unknown). Set by the shell.
  int devtoolsPort = 0;

  bool _active = false;
  bool get active => _active;

  final Queue<double> _total = Queue();
  final Queue<double> _build = Queue();
  final Queue<double> _raster = Queue();
  final Queue<double> _input = Queue();
  int _frames = 0;
  int _slow = 0;
  int _janky = 0;
  int _frozen = 0;

  final Map<String, _PendingLoad> _pending = {};
  final Map<String, Completer<LoadSample>> _waiters = {};
  final List<LoadSample> _loads = [];

  Stopwatch? _inputWatch;
  Timer? _tick;
  Timer? _memoryTimer;
  bool _memoryBusy = false;

  MemoryTree? _tree;
  List<TabMemory> _tabs = const [];
  DateTime? _memoryAt;

  BenchmarkResult? lastBenchmark;

  void setBenchmark(BenchmarkResult? result) {
    lastBenchmark = result;
    notifyListeners();
  }

  // ----- lifecycle ---------------------------------------------------------

  void start() {
    if (_active) return;
    _active = true;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
    HardwareKeyboard.instance.addHandler(_onKey);
    _tick = Timer.periodic(const Duration(milliseconds: 500), (_) {
      notifyListeners();
    });
    _memoryTimer = Timer.periodic(
      const Duration(seconds: 4),
      (_) => unawaited(sampleMemory()),
    );
    unawaited(sampleMemory());
    notifyListeners();
  }

  void stop() {
    if (!_active) return;
    _active = false;
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
    HardwareKeyboard.instance.removeHandler(_onKey);
    _tick?.cancel();
    _memoryTimer?.cancel();
    _tick = null;
    _memoryTimer = null;
    _pending.clear();
    notifyListeners();
  }

  /// Clears measurements but keeps the probe running.
  void reset() {
    _total.clear();
    _build.clear();
    _raster.clear();
    _input.clear();
    _frames = _slow = _janky = _frozen = 0;
    _loads.clear();
    lastBenchmark = null;
    notifyListeners();
  }

  @visibleForTesting
  void debugSetActive(bool value) => _active = value;

  // ----- frames ------------------------------------------------------------

  void _onTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      ingestFrame(
        buildMs: t.buildDuration.inMicroseconds / 1000,
        rasterMs: t.rasterDuration.inMicroseconds / 1000,
      );
    }
  }

  /// Records one frame. Public so tests can feed synthetic frames.
  void ingestFrame({required double buildMs, required double rasterMs}) {
    final total = buildMs + rasterMs;
    _push(_total, total, maxFrames);
    _push(_build, buildMs, maxFrames);
    _push(_raster, rasterMs, maxFrames);
    _frames++;
    if (total > _slowMs) _slow++;
    if (total > _jankyMs) _janky++;
    if (total > _frozenMs) _frozen++;
  }

  FrameStats get frameStats => _frames == 0
      ? FrameStats.empty
      : FrameStats(
          total: summarize(_total),
          build: summarize(_build),
          raster: summarize(_raster),
          frames: _frames,
          slow: _slow,
          janky: _janky,
          frozen: _frozen,
        );

  // ----- input to next frame ----------------------------------------------

  void _onPointer(PointerEvent e) {
    if (e is PointerDownEvent) _markInput();
  }

  bool _onKey(KeyEvent e) {
    if (e is KeyDownEvent) _markInput();
    return false; // never consume the event
  }

  /// Measures time from an input event to the end of the next frame build.
  /// (Raster and display time are reported separately in the frame stats.)
  void _markInput() {
    if (_inputWatch != null) return;
    final watch = Stopwatch()..start();
    _inputWatch = watch;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _inputWatch = null;
      if (watch.elapsed <= _maxInputWait) {
        recordInputLatency(watch.elapsedMicroseconds / 1000);
      }
    });
    SchedulerBinding.instance.scheduleFrame();
  }

  void recordInputLatency(double ms) => _push(_input, ms, 400);

  StatSummary get inputToFrame => summarize(_input);

  // ----- page loads --------------------------------------------------------

  /// Call when a page starts loading. A second call before the first finishes
  /// is ignored, so redirects count as one load.
  void loadStarted(String tabId, {required bool shieldsOn}) {
    if (!_active) return;
    _pending.putIfAbsent(tabId, () => _PendingLoad(shieldsOn));
  }

  /// Call when the load completes. [url] is reduced to its host immediately.
  void loadFinished(String tabId, String url) {
    final p = _pending.remove(tabId);
    if (p == null) return;
    p.watch.stop();
    final sample = LoadSample(
      host: hostOf(url),
      shieldsOn: p.shieldsOn,
      ms: p.watch.elapsedMilliseconds,
      at: DateTime.now(),
    );
    // Blank pages (about:blank) settle the tab between benchmark loads and are
    // not real page loads, so they are not listed or summarised.
    if (sample.host.isNotEmpty) {
      _loads.add(sample);
      if (_loads.length > maxLoads) _loads.removeAt(0);
    }
    _waiters.remove(tabId)?.complete(sample);
    notifyListeners();
  }

  /// Completes with the next finished load of [tabId], or null on timeout.
  Future<LoadSample?> expectLoad(String tabId, {Duration? timeout}) {
    final c = _waiters.putIfAbsent(tabId, () => Completer<LoadSample>());
    return c.future
        .then<LoadSample?>((s) => s)
        .timeout(
          timeout ?? const Duration(seconds: 30),
          onTimeout: () {
            _waiters.remove(tabId);
            _pending.remove(tabId);
            return null;
          },
        );
  }

  List<LoadSample> get loads => List.unmodifiable(_loads);

  StatSummary loadSummary({required bool shieldsOn}) => summarize([
    for (final l in _loads)
      if (l.shieldsOn == shieldsOn) l.ms,
  ]);

  static String hostOf(String url) => Uri.tryParse(url)?.host ?? '';

  // ----- memory ------------------------------------------------------------

  MemoryTree? get memoryTree => _tree;
  List<TabMemory> get tabMemory => _tabs;

  Future<void> sampleMemory() async {
    if (_memoryBusy) return;
    _memoryBusy = true;
    try {
      _tree = WinMemory.snapshot();
      _tabs = await CdpMemory.sample(devtoolsPort);
      _memoryAt = DateTime.now();
    } finally {
      _memoryBusy = false;
    }
    notifyListeners();
  }

  // ----- report ------------------------------------------------------------

  /// A privacy-safe report: statistics, hosts and byte counts only. Never
  /// full URLs, titles or page content.
  Map<String, Object?> buildReport({Map<String, Object?> meta = const {}}) => {
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
    'meta': {
      'platform': Platform.operatingSystemVersion,
      'processors': Platform.numberOfProcessors,
      ...meta,
    },
    'frames': frameStats.toJson(),
    'inputToFrameBuildMs': inputToFrame.toJson(),
    'pageLoads': {
      'shieldsOnMs': loadSummary(shieldsOn: true).toJson(),
      'shieldsOffMs': loadSummary(shieldsOn: false).toJson(),
      'samples': [for (final l in _loads) l.toJson()],
    },
    'memory': {
      'sampledAt': _memoryAt?.toUtc().toIso8601String(),
      'processes': _tree?.toJson(),
      'tabs': [for (final t in _tabs) t.toJson()],
    },
    if (lastBenchmark != null) 'benchmark': lastBenchmark!.toJson(),
  };

  static void _push(Queue<double> q, double v, int cap) {
    q.addLast(v);
    while (q.length > cap) {
      q.removeFirst();
    }
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
