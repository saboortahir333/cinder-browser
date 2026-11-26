import 'package:flutter_test/flutter_test.dart';
import 'package:saboor_browser/security/request_policy.dart';

void main() {
  RequestPolicy p() => RequestPolicy(
    matcher: (u, s, t) => u.contains('ads.example'),
    malwareHosts: {'evil.test', 'bad.example.net'},
  );

  RequestDecision doc(RequestPolicy policy, String url) =>
      policy.decide(url: url, documentUrl: '', resourceType: 'Document');

  test('upgrades http documents, not loopback or intranet', () {
    final policy = p();
    final d = doc(policy, 'http://example.org/a?b=1');
    expect(d, isA<UpgradeRequest>());
    expect((d as UpgradeRequest).httpsUrl, 'https://example.org/a?b=1');
    for (final u in [
      'http://localhost:3000/',
      'http://127.0.0.1/',
      'http://192.168.1.5/',
      'http://printer/',
      'http://nas.local/',
    ]) {
      expect(doc(policy, u), isA<AllowRequest>(), reason: u);
    }
  });

  test('explicit port is kept, user opt-out respected', () {
    final policy = p();
    final d = doc(policy, 'http://example.org:8080/');
    expect((d as UpgradeRequest).httpsUrl, 'https://example.org:8080/');
    policy.insecureOk.add('example.org');
    expect(doc(policy, 'http://example.org/'), isA<AllowRequest>());
  });

  test('trackers blocked as subresources, never as the page itself', () {
    final policy = p();
    RequestDecision script() => policy.decide(
      url: 'https://ads.example/x.js',
      documentUrl: 'https://news.org/',
      resourceType: 'Script',
    );
    expect(script(), isA<BlockRequest>());
    expect(doc(policy, 'https://ads.example/'), isA<AllowRequest>());
    policy.shieldsOff.add('news.org');
    expect(script(), isA<AllowRequest>());
  });

  test('malware hosts and subdomains are warned', () {
    final policy = p();
    expect(doc(policy, 'https://evil.test/'), isA<WarnRequest>());
    expect(doc(policy, 'https://x.y.evil.test/'), isA<WarnRequest>());
    expect(doc(policy, 'https://notevil.test/'), isA<AllowRequest>());
  });

  test('internal and malformed requests pass untouched', () {
    final policy = p();
    expect(doc(policy, 'https://abc.extension.cinder.local/popup.html'), isA<AllowRequest>());
    expect(doc(policy, ':::'), isA<AllowRequest>());
    expect(doc(policy, 'data:text/plain,hi'), isA<AllowRequest>());
  });
}
