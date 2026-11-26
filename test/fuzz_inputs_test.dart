import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:saboor_browser/browser/url_policy.dart';
import 'package:saboor_browser/security/page_messages.dart';
import 'package:saboor_browser/security/request_policy.dart';

/// Seeded fuzz-style tests: thousands of hostile inputs must never throw, and
/// must never produce an unsafe result. Run on every CI build. The Rust side
/// has a cargo-fuzz target in rust/fuzz.
String _junk(Random r, {int max = 60}) {
  const pool = [
    'http://', 'https://', 'javascript:', 'file:///', 'data:', 'blob:', 'vbscript:',
    '@', '%00', '%', '\u202e', '\u200b', '..', '/', '\\', '?', '#', ':', '[', ']',
    'xn--', 'localhost', '127.0.0.1', '0x7f.1', '999.1.1.1', 'a', 'b', 'é', '例', ' ', '\n',
    '<script>', '"', "'", '.com', '.', '-',
  ];
  final n = r.nextInt(max);
  return List.generate(n, (_) => pool[r.nextInt(pool.length)]).join();
}

void main() {
  final r = Random(1337);

  test('UrlPolicy never throws and never allows dangerous schemes', () {
    for (var i = 0; i < 5000; i++) {
      final s = _junk(r);
      for (final src in NavSource.values) {
        final d = UrlPolicy.checkNavigation(s, src);
        if (!d.isBlocked && d.uri != null) {
          final scheme = d.uri!.scheme;
          expect(
            const ['http', 'https', 'about', 'file', 'view-source', 'cinder'].contains(scheme),
            isTrue,
            reason: 'allowed "$s" as $scheme',
          );
          expect(scheme == 'javascript' || scheme == 'vbscript' || scheme == 'data', isFalse);
        }
      }
    }
  });

  test('RequestPolicy never throws and only upgrades to https', () {
    final policy = RequestPolicy(matcher: (u, s, t) => u.length % 7 == 0, malwareHosts: {'evil.test'});
    for (var i = 0; i < 5000; i++) {
      final d = policy.decide(
        url: _junk(r),
        documentUrl: _junk(r),
        resourceType: ['Document', 'Script', 'Image', '', 'x'][r.nextInt(5)],
      );
      if (d is UpgradeRequest) {
        expect(d.httpsUrl.startsWith('https://'), isTrue, reason: d.httpsUrl);
      }
    }
  });

  test('PageMessages rejects everything except a well-formed context message', () {
    const web = 'https://example.com/';
    for (var i = 0; i < 5000; i++) {
      final raw = r.nextBool()
          ? _junk(r, max: 200)
          : jsonEncode({
              'cinderContext': r.nextBool(),
              'x': [1, -5, 1e308, 'a', null, double.nan][r.nextInt(6)],
              'y': r.nextInt(100),
              'link': _junk(r),
              'image': _junk(r),
              'selection': _junk(r, max: 400),
              'editable': r.nextBool(),
            }, toEncodable: (o) => o.toString());
      final m = PageMessages.parseContext(raw, senderUrl: web);
      if (m != null) {
        expect(m.link.isEmpty || m.link.startsWith('http'), isTrue);
        expect(m.image.isEmpty || m.image.startsWith('http'), isTrue);
        expect(m.selection.length <= PageMessages.maxSelection, isTrue);
      }
    }
  });

  test('context messages are ignored from non-web senders', () {
    final ok = jsonEncode({'cinderContext': true, 'x': 1, 'y': 2});
    expect(PageMessages.parseContext(ok, senderUrl: 'https://example.com/'), isNotNull);
    for (final s in [
      'about:blank',
      'file:///c:/x.html',
      'https://abc.extension.cinder.local/popup.html',
      '',
      'javascript:alert(1)',
    ]) {
      expect(PageMessages.parseContext(ok, senderUrl: s), isNull, reason: s);
    }
  });

  test('oversized and non-string payloads are rejected', () {
    final huge = jsonEncode({'cinderContext': true, 'x': 1, 'y': 2, 'selection': 'a' * 100000});
    expect(PageMessages.parseContext(huge, senderUrl: 'https://a.com/'), isNull);
    expect(PageMessages.parseContext(42, senderUrl: 'https://a.com/'), isNull);
    expect(PageMessages.parseContext(null, senderUrl: 'https://a.com/'), isNull);
    expect(PageMessages.parseContext([1, 2], senderUrl: 'https://a.com/'), isNull);
  });

  test('javascript: and file: links in a context message are dropped', () {
    final m = PageMessages.parseContext(
      jsonEncode({'cinderContext': true, 'x': 1, 'y': 2, 'link': 'javascript:alert(1)', 'image': 'file:///c:/a.png'}),
      senderUrl: 'https://a.com/',
    )!;
    expect(m.link, '');
    expect(m.image, '');
  });
}
