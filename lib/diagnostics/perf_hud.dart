import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:saboor_browser/diagnostics/perf_probe.dart';
import 'package:saboor_browser/diagnostics/win_memory.dart';
import 'package:saboor_browser/models/browser_palette.dart';
import 'package:saboor_browser/ui/chrome/chrome_widgets.dart';

/// Writes [report] as pretty JSON into
/// `Documents\Cinder Performance Reports` and returns the file path.
Future<String> exportPerfReport(Map<String, Object?> report) async {
  final home = Platform.environment['USERPROFILE'];
  final base = home == null
      ? Directory.systemTemp.path
      : '$home${Platform.pathSeparator}Documents';
  final dir = Directory(
    '$base${Platform.pathSeparator}Cinder Performance Reports',
  );
  await dir.create(recursive: true);
  final now = DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  final stamp =
      '${now.year}${two(now.month)}${two(now.day)}-${two(now.hour)}${two(now.minute)}${two(now.second)}';
  final file = File(
    '${dir.path}${Platform.pathSeparator}cinder-perf-$stamp.json',
  );
  await file.writeAsString(const JsonEncoder.withIndent('  ').convert(report));
  return file.path;
}

/// Floating Performance monitor. Opt-in, local-only (see [PerfProbe]).
class PerfHud extends StatefulWidget {
  const PerfHud({
    super.key,
    required this.palette,
    required this.probe,
    required this.benchmarkStatus,
    required this.onClose,
    required this.onRunBenchmark,
    required this.onCancelBenchmark,
    required this.meta,
  });

  final BrowserPalette palette;
  final PerfProbe probe;

  /// Null while idle, otherwise a one-line progress message.
  final ValueNotifier<String?> benchmarkStatus;
  final VoidCallback onClose;
  final VoidCallback onRunBenchmark;
  final VoidCallback onCancelBenchmark;
  final Map<String, Object?> meta;

  @override
  State<PerfHud> createState() => _PerfHudState();
}

class _PerfHudState extends State<PerfHud> {
  String? _exported;
  String? _exportError;

  static const _good = Color(0xFF2E9E5B);
  static const _warn = Color(0xFFE0A100);
  static const _bad = Color(0xFFD9453B);

  Color _frameColor(double p95) {
    if (p95.isNaN) return widget.palette.muted;
    if (p95 <= 16.7) return _good;
    if (p95 <= 33.4) return _warn;
    return _bad;
  }

  String _ms(double v) => v.isNaN ? 'n/a' : '${v.toStringAsFixed(1)} ms';

  Future<void> _export() async {
    try {
      final path = await exportPerfReport(
        widget.probe.buildReport(meta: widget.meta),
      );
      if (mounted) {
        setState(() {
          _exported = path;
          _exportError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _exportError = 'Could not save the report: ${e.runtimeType}';
          _exported = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    return Material(
      elevation: 14,
      color: p.chrome,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: Container(
        width: 360,
        constraints: const BoxConstraints(maxHeight: 620),
        decoration: BoxDecoration(
          border: Border.all(color: p.divider),
          borderRadius: BorderRadius.circular(14),
        ),
        child: ListenableBuilder(
          listenable: Listenable.merge([widget.probe, widget.benchmarkStatus]),
          builder: (context, _) {
            final frames = widget.probe.frameStats;
            final input = widget.probe.inputToFrame;
            final tree = widget.probe.memoryTree;
            final tabs = widget.probe.tabMemory;
            final on = widget.probe.loadSummary(shieldsOn: true);
            final off = widget.probe.loadSummary(shieldsOn: false);
            final busy = widget.benchmarkStatus.value;
            final bench = widget.probe.lastBenchmark;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(p),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _section(p, 'Frames'),
                        if (frames.frames == 0)
                          _note(
                            p,
                            'Waiting for frames. Move the mouse or scroll.',
                          )
                        else ...[
                          _row(
                            p,
                            'p50 / p95 / p99',
                            '${_ms(frames.total.p50)} · ${_ms(frames.total.p95)} · ${_ms(frames.total.p99)}',
                            color: _frameColor(frames.total.p95),
                          ),
                          _row(
                            p,
                            'Build p95 · Raster p95',
                            '${_ms(frames.build.p95)} · ${_ms(frames.raster.p95)}',
                          ),
                          _row(
                            p,
                            'Over 16.7 ms',
                            '${frames.slow} of ${frames.frames} (${frames.slowPercent.toStringAsFixed(1)}%)',
                          ),
                          _row(
                            p,
                            'Over 33 ms · over 700 ms',
                            '${frames.janky} · ${frames.frozen}',
                          ),
                        ],
                        _section(p, 'Input to next frame (build)'),
                        input.isEmpty
                            ? _note(p, 'Click or type to measure.')
                            : _row(
                                p,
                                'p50 / p95',
                                '${_ms(input.p50)} · ${_ms(input.p95)}',
                              ),
                        _section(p, 'Page loads'),
                        if (widget.probe.loads.isEmpty)
                          _note(p, 'Load a page to measure it.')
                        else ...[
                          for (final l in widget.probe.loads.reversed.take(5))
                            _row(
                              p,
                              l.host.isEmpty ? '(blank)' : l.host,
                              '${l.ms} ms  ${l.shieldsOn ? 'shields on' : 'shields off'}',
                            ),
                          _row(
                            p,
                            'Median: on · off',
                            '${on.isEmpty ? 'n/a' : '${on.p50.round()} ms'} · ${off.isEmpty ? 'n/a' : '${off.p50.round()} ms'}',
                          ),
                        ],
                        _section(p, 'Memory'),
                        if (tree == null)
                          _note(
                            p,
                            'Process memory is only available on Windows.',
                          )
                        else ...[
                          _row(
                            p,
                            'Cinder app',
                            formatBytes(tree.app.privateBytes),
                          ),
                          _row(
                            p,
                            'WebView2 (${tree.children.length} processes)',
                            formatBytes(tree.childPrivateBytes),
                          ),
                          _row(
                            p,
                            'Total private',
                            formatBytes(tree.totalPrivateBytes),
                          ),
                        ],
                        if (tabs.isNotEmpty) ...[
                          _note(p, 'Per tab (JS heap · DOM nodes)'),
                          for (final t in tabs)
                            _row(
                              p,
                              t.host.isEmpty ? '(blank)' : t.host,
                              '${formatBytes(t.jsHeapUsedBytes)} · ${t.domNodes}',
                            ),
                        ],
                        _section(p, 'Benchmark'),
                        _note(
                          p,
                          'Loads a few public sites with shields on and off, '
                          'with the cache disabled, and compares the medians.',
                        ),
                        if (busy != null)
                          _note(p, busy, color: p.accent)
                        else if (bench != null) ...[
                          _row(
                            p,
                            'Shields on · off (median)',
                            '${bench.summaryFor(shieldsOn: true).p50.round()} ms · ${bench.summaryFor(shieldsOn: false).p50.round()} ms',
                          ),
                          _row(
                            p,
                            'Shields cost',
                            bench.shieldsCostPercent == null
                                ? 'n/a'
                                : '${bench.shieldsCostPercent! >= 0 ? '+' : ''}${bench.shieldsCostPercent!.toStringAsFixed(1)}%',
                            color: (bench.shieldsCostPercent ?? 0) > 10
                                ? _bad
                                : _good,
                          ),
                        ],
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (busy == null)
                              FilledButton.tonal(
                                onPressed: widget.onRunBenchmark,
                                child: const Text('Run benchmark'),
                              )
                            else
                              OutlinedButton(
                                onPressed: widget.onCancelBenchmark,
                                child: const Text('Cancel'),
                              ),
                            OutlinedButton(
                              onPressed: _export,
                              child: const Text('Export report'),
                            ),
                            TextButton(
                              onPressed: widget.probe.reset,
                              child: const Text('Reset'),
                            ),
                          ],
                        ),
                        if (_exported != null) ...[
                          const SizedBox(height: 8),
                          SelectableText(
                            'Saved: $_exported',
                            style: TextStyle(color: p.muted, fontSize: 11),
                          ),
                        ],
                        if (_exportError != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            _exportError!,
                            style: const TextStyle(color: _bad, fontSize: 11),
                          ),
                        ],
                        const SizedBox(height: 10),
                        Text(
                          'Local only. Nothing is sent anywhere. Reports contain '
                          'timings, host names and memory sizes, never page URLs '
                          'or content.',
                          style: TextStyle(
                            color: p.muted,
                            fontSize: 10.5,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _header(BrowserPalette p) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 10, 6, 2),
    child: Row(
      children: [
        Icon(Icons.speed_rounded, size: 18, color: p.accent),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Performance monitor',
            style: TextStyle(
              color: p.ink,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        IconButton(
          tooltip: 'Close',
          visualDensity: VisualDensity.compact,
          onPressed: widget.onClose,
          icon: Icon(Icons.close_rounded, size: 18, color: p.ink),
        ),
      ],
    ),
  );

  Widget _section(BrowserPalette p, String title) => Padding(
    padding: const EdgeInsets.only(top: 14, bottom: 4),
    child: Text(
      title.toUpperCase(),
      style: TextStyle(
        color: p.muted,
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
      ),
    ),
  );

  Widget _note(BrowserPalette p, String text, {Color? color}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Text(
      text,
      style: TextStyle(color: color ?? p.muted, fontSize: 11.5, height: 1.35),
    ),
  );

  Widget _row(BrowserPalette p, String label, String value, {Color? color}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 2.5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 5,
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: p.ink.withValues(alpha: 0.8),
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 6,
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: color ?? p.ink,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      );
}
