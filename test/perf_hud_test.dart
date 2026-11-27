import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saboor_browser/diagnostics/perf_benchmark.dart';
import 'package:saboor_browser/diagnostics/perf_hud.dart';
import 'package:saboor_browser/diagnostics/perf_probe.dart';
import 'package:saboor_browser/models/browser_palette.dart';

Widget _hud(PerfProbe probe, ValueNotifier<String?> status) => MaterialApp(
  home: Scaffold(
    body: Align(
      alignment: Alignment.bottomRight,
      child: PerfHud(
        palette: kPalettes.first,
        probe: probe,
        benchmarkStatus: status,
        onClose: () {},
        onRunBenchmark: () {},
        onCancelBenchmark: () {},
        meta: const {'app': 'test'},
      ),
    ),
  ),
);

void main() {
  testWidgets('empty state tells the user how to get data', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final probe = PerfProbe();
    final status = ValueNotifier<String?>(null);
    await tester.pumpWidget(_hud(probe, status));

    expect(find.text('Performance monitor'), findsOneWidget);
    expect(find.textContaining('Waiting for frames'), findsOneWidget);
    expect(find.text('Run benchmark'), findsOneWidget);
    expect(find.text('Export report'), findsOneWidget);
    expect(find.textContaining('Nothing is sent anywhere'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows frame stats, loads and a benchmark without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final probe = PerfProbe()..debugSetActive(true);
    for (var i = 0; i < 50; i++) {
      probe.ingestFrame(buildMs: 4 + (i % 5).toDouble(), rasterMs: 5);
    }
    probe.ingestFrame(buildMs: 40, rasterMs: 30); // one janky frame
    probe.recordInputLatency(9);
    for (final on in [true, false, true]) {
      probe.loadStarted('t', shieldsOn: on);
      probe.loadFinished('t', 'https://example.com/path');
    }
    final bench = await PerfBenchmark.run(
      urls: const ['https://a.test/'],
      rounds: 2,
      load: (url, {required shieldsOn}) async => shieldsOn ? 130 : 100,
    );
    probe.setBenchmark(bench);

    final status = ValueNotifier<String?>(null);
    await tester.pumpWidget(_hud(probe, status));

    expect(find.textContaining('p50 / p95 / p99'), findsOneWidget);
    expect(find.text('example.com'), findsWidgets);
    expect(find.textContaining('Shields cost'), findsOneWidget);
    expect(find.text('+30.0%'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows progress and a Cancel button while benchmarking', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final probe = PerfProbe();
    final status = ValueNotifier<String?>('Round 1/3: example.com, shields on');
    await tester.pumpWidget(_hud(probe, status));

    expect(find.textContaining('Round 1/3'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Run benchmark'), findsNothing);
  });

  testWidgets('fits a small window by scrolling instead of overflowing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(700, 420);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final probe = PerfProbe();
    final status = ValueNotifier<String?>(null);
    await tester.pumpWidget(_hud(probe, status));
    expect(tester.takeException(), isNull);
  });
}
