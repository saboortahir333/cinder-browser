import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:saboor_browser/diagnostics/perf_probe.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('frame statistics', () {
    test('counts slow, janky and frozen frames', () {
      final p = PerfProbe();
      p.ingestFrame(buildMs: 4, rasterMs: 4); // 8 ms: fine
      p.ingestFrame(buildMs: 10, rasterMs: 10); // 20 ms: slow
      p.ingestFrame(buildMs: 20, rasterMs: 20); // 40 ms: slow + janky
      p.ingestFrame(buildMs: 400, rasterMs: 400); // 800 ms: all three
      final s = p.frameStats;
      expect(s.frames, 4);
      expect(s.slow, 3);
      expect(s.janky, 2);
      expect(s.frozen, 1);
      expect(s.slowPercent, 75);
      expect(s.total.max, 800);
    });

    test('keeps only the rolling window but counts every frame', () {
      final p = PerfProbe(maxFrames: 10);
      for (var i = 0; i < 25; i++) {
        p.ingestFrame(buildMs: 1, rasterMs: 1);
      }
      expect(p.frameStats.frames, 25);
      expect(p.frameStats.total.count, 10);
    });

    test('empty probe reports no frames', () {
      expect(PerfProbe().frameStats.frames, 0);
    });
  });

  group('page loads', () {
    test('records host only and the shield state', () async {
      final p = PerfProbe()..debugSetActive(true);
      p.loadStarted('t1', shieldsOn: true);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      p.loadFinished('t1', 'https://user:pw@example.com/a/b?token=SECRET#frag');
      expect(p.loads, hasLength(1));
      expect(p.loads.single.host, 'example.com');
      expect(p.loads.single.shieldsOn, isTrue);
      expect(p.loads.single.ms, greaterThanOrEqualTo(15));
      final json = jsonEncode(p.buildReport());
      expect(json, isNot(contains('SECRET')));
      expect(json, isNot(contains('user:pw')));
      expect(json, isNot(contains('/a/b')));
    });

    test('collects nothing while inactive (opt-in only)', () {
      final p = PerfProbe();
      p.loadStarted('t1', shieldsOn: true);
      p.loadFinished('t1', 'https://example.com/');
      expect(p.loads, isEmpty);
    });

    test('a redirect during a load does not restart the clock', () async {
      final p = PerfProbe()..debugSetActive(true);
      p.loadStarted('t1', shieldsOn: false);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      p.loadStarted('t1', shieldsOn: false); // redirect
      p.loadFinished('t1', 'https://example.com/');
      expect(p.loads.single.ms, greaterThanOrEqualTo(25));
    });

    test('summaries split by shield state', () {
      final p = PerfProbe()..debugSetActive(true);
      for (final on in [true, true, false]) {
        p.loadStarted('t', shieldsOn: on);
        p.loadFinished('t', 'https://example.com/');
      }
      expect(p.loadSummary(shieldsOn: true).count, 2);
      expect(p.loadSummary(shieldsOn: false).count, 1);
    });

    test('expectLoad completes with the next finished load', () async {
      final p = PerfProbe()..debugSetActive(true);
      p.loadStarted('t9', shieldsOn: true);
      final future = p.expectLoad('t9');
      p.loadFinished('t9', 'https://example.org/');
      final sample = await future;
      expect(sample, isNotNull);
      expect(sample!.host, 'example.org');
    });

    test('expectLoad times out with null', () async {
      final p = PerfProbe()..debugSetActive(true);
      final sample = await p.expectLoad(
        'nothing',
        timeout: const Duration(milliseconds: 30),
      );
      expect(sample, isNull);
    });
  });

  group('report', () {
    test('is valid JSON with no NaN and has the expected sections', () {
      final p = PerfProbe();
      final report = p.buildReport(meta: {'version': '1.1.0'});
      final text = jsonEncode(report); // would throw on NaN/Infinity
      expect(text, contains('"frames"'));
      expect(text, contains('"pageLoads"'));
      expect(text, contains('"memory"'));
      expect((report['meta'] as Map)['version'], '1.1.0');
    });

    test('input latency feeds its own summary', () {
      final p = PerfProbe();
      p.recordInputLatency(8);
      p.recordInputLatency(12);
      expect(p.inputToFrame.count, 2);
      expect(p.inputToFrame.max, 12);
    });
  });
}
