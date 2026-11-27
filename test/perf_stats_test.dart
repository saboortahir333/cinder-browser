import 'package:flutter_test/flutter_test.dart';
import 'package:saboor_browser/diagnostics/perf_benchmark.dart';
import 'package:saboor_browser/diagnostics/perf_stats.dart';

void main() {
  group('percentile', () {
    test('interpolates between neighbours', () {
      final v = [for (var i = 1; i <= 100; i++) i.toDouble()];
      expect(percentile(v, 50), closeTo(50.5, 1e-9));
      expect(percentile(v, 95), closeTo(95.05, 1e-9));
      expect(percentile(v, 0), 1);
      expect(percentile(v, 100), 100);
    });

    test('handles tiny and empty lists', () {
      expect(percentile(const [], 50).isNaN, isTrue);
      expect(percentile(const [7.0], 99), 7);
    });

    test('clamps out-of-range percentiles', () {
      expect(percentile(const [1.0, 2.0, 3.0], 150), 3);
      expect(percentile(const [1.0, 2.0, 3.0], -5), 1);
    });
  });

  group('summarize', () {
    test('computes the distribution', () {
      final s = summarize([4, 1, 3, 2, 5]);
      expect(s.count, 5);
      expect(s.min, 1);
      expect(s.max, 5);
      expect(s.mean, 3);
      expect(s.p50, 3);
    });

    test('empty summary serialises to nulls, never NaN', () {
      final json = summarize(const <num>[]).toJson();
      expect(json['count'], 0);
      expect(json['p95'], isNull);
      expect(json['mean'], isNull);
    });
  });

  group('percentChange', () {
    test('signed relative change', () {
      expect(percentChange(100, 125), 25);
      expect(percentChange(200, 150), -25);
    });

    test('null when there is nothing to compare', () {
      expect(percentChange(0, 10), isNull);
      expect(percentChange(double.nan, 10), isNull);
    });
  });

  group('PerfBenchmark', () {
    test('alternates shield modes and tallies timeouts', () async {
      final order = <String>[];
      final result = await PerfBenchmark.run(
        urls: const ['https://a.test/', 'https://b.test/'],
        rounds: 2,
        load: (url, {required shieldsOn}) async {
          order.add('${Uri.parse(url).host}:${shieldsOn ? 'on' : 'off'}');
          if (url.contains('b.test') && !shieldsOn) return null; // timeout
          return shieldsOn ? 120 : 100;
        },
      );
      // Round 1 runs shields on, round 2 runs shields off first.
      expect(order.take(4), [
        'a.test:on',
        'b.test:on',
        'a.test:off',
        'b.test:off',
      ]);
      expect(order.skip(4).first, 'a.test:off');
      expect(result.summaryFor(shieldsOn: true).p50, 120);
      expect(result.summaryFor(shieldsOn: false).p50, 100);
      expect(result.shieldsCostPercent, 20);
      final bOff = result.cells.firstWhere(
        (c) => c.url.contains('b.test') && !c.shieldsOn,
      );
      expect(bOff.timeouts, 2);
      expect(bOff.samplesMs, isEmpty);
    });

    test('stops when cancelled', () async {
      var calls = 0;
      final result = await PerfBenchmark.run(
        urls: const ['https://a.test/'],
        rounds: 5,
        isCancelled: () => calls >= 2,
        load: (url, {required shieldsOn}) async {
          calls++;
          return 50;
        },
      );
      expect(result.cancelled, isTrue);
      expect(calls, 2);
    });

    test('report contains hosts only, never paths or queries', () async {
      final result = await PerfBenchmark.run(
        urls: const ['https://a.test/private/path?token=SECRET'],
        rounds: 1,
        load: (url, {required shieldsOn}) async => 10,
      );
      final text = result.toJson().toString();
      expect(text, contains('a.test'));
      expect(text, isNot(contains('SECRET')));
      expect(text, isNot(contains('/private/path')));
    });
  });
}
