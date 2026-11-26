import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:saboor_browser/security/site_permissions.dart';
import 'package:saboor_browser/services/cloud_store.dart';

class _Keys implements VaultKeySource {
  @override
  String? userId = 'u';
  @override
  Uint8List? masterKey = Uint8List(32);
  @override
  Future<void> invalidateKey() async {}
}

class _Api implements RecordApi {
  @override
  dynamic noSuchMethod(Invocation i) async => <RecordRow>[];
}

SitePermissionStore _store({bool isPrivate = false}) => SitePermissionStore(
  cloud: CloudStore(api: _Api(), keys: _Keys(), profileId: 'default', autoFlush: false),
  isPrivate: isPrivate,
);

void main() {
  test('originOf normalises and rejects non-web', () {
    expect(SitePermissionStore.originOf('https://Example.com/a?b'), 'https://example.com');
    expect(SitePermissionStore.originOf('https://example.com:8443/'), 'https://example.com:8443');
    expect(SitePermissionStore.originOf('file:///c:/x'), isNull);
    expect(SitePermissionStore.originOf('about:blank'), isNull);
  });

  test('insecure origins are denied, secure ones asked', () {
    final s = _store();
    expect(s.evaluate('http://example.com', SitePermission.camera, userInitiated: true), PermissionOutcome.deny);
    expect(s.evaluate('https://example.com', SitePermission.camera, userInitiated: true), PermissionOutcome.askUser);
  });

  test('remembered decisions win and are revocable', () {
    final s = _store();
    s.record('https://a.com', SitePermission.camera, SiteDecision.allow, remember: true);
    expect(s.evaluate('https://a.com/x', SitePermission.camera, userInitiated: false), PermissionOutcome.allow);
    s.reset('https://a.com', SitePermission.camera);
    expect(s.evaluate('https://a.com', SitePermission.camera, userInitiated: true), PermissionOutcome.askUser);
  });

  test('sensors denied, gestureless notifications/location denied', () {
    final s = _store();
    expect(s.evaluate('https://a.com', SitePermission.sensors, userInitiated: true), PermissionOutcome.deny);
    expect(s.evaluate('https://a.com', SitePermission.notifications, userInitiated: false), PermissionOutcome.deny);
    expect(s.evaluate('https://a.com', SitePermission.location, userInitiated: false), PermissionOutcome.deny);
  });

  test('repeated blocks silence a site', () {
    final s = _store();
    for (var i = 0; i < SitePermissionStore.maxStrikes; i++) {
      s.record('https://a.com', SitePermission.microphone, SiteDecision.block, remember: false);
    }
    expect(s.evaluate('https://a.com', SitePermission.microphone, userInitiated: true), PermissionOutcome.deny);
  });

  test('private windows keep decisions in memory only', () {
    final s = _store(isPrivate: true);
    s.set('https://a.com', SitePermission.camera, SiteDecision.block);
    expect(s.all(), hasLength(1));
    expect(s.cloud.values(SitePermissionStore.kind), isEmpty);
  });
}
