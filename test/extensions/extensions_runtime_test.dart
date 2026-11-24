import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:saboor_browser/extensions/content_script_builder.dart';
import 'package:saboor_browser/extensions/extension_manager.dart';
import 'package:saboor_browser/extensions/permissions.dart';
import 'package:saboor_browser/extensions/popup_bridge.dart';
import 'package:saboor_browser/extensions/web_store.dart';

Uint8List _zip(Map<String, String> files) {
  final a = Archive();
  files.forEach((k, v) => a.addFile(ArchiveFile(k, utf8.encode(v).length, utf8.encode(v))));
  return Uint8List.fromList(ZipEncoder().encode(a));
}

const _manifest = '''
{"manifest_version":3,"name":"Demo","version":"1.0.0","permissions":["storage","tabs"],
 "host_permissions":["https://*.example.com/*"],
 "content_scripts":[{"matches":["https://*.example.com/*"],"js":["a.js"],"css":["a.css"]}],
 "action":{"default_popup":"popup.html"}}''';

final _files = {
  'manifest.json': _manifest,
  'a.js': 'document.title="x";',
  'a.css': 'body{color:red}',
  'popup.html': '<p>hi</p>',
};

class _Host implements BridgeHost {
  String? opened;
  bool closed = false;
  Size? resized;
  @override
  ({int id, String url, String title})? activeTab() => (id: 1, url: 'https://a.example.com/', title: 'T');
  @override
  void openTab(String url) => opened = url;
  @override
  void openOptionsPage(InstalledExtension ext) {}
  @override
  void resizePopup(int w, int h) => resized = Size(w.toDouble(), h.toDouble());
  @override
  void closePopup() => closed = true;
  @override
  Future<void> writeClipboard(String text) async {}
}

class Size {
  const Size(this.w, this.h);
  final double w, h;
}

void main() {
  late Directory tmp;
  late ExtensionManager mgr;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('cinder_mgr_test');
    mgr = ExtensionManager.forTest();
    await mgr.init(root: Directory('${tmp.path}/ext'), isPrivate: false);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<InstalledExtension> install() async {
    final p = await mgr.prepareFromBytes(_zip(_files), source: ExtensionSource.packageFile);
    return mgr.commit(p, grants: PermissionPolicy.defaultGrants(p.manifest));
  }

  group('install pipeline', () {
    test('installs, persists and reloads with grants intact', () async {
      final e = await install();
      expect(e.name, 'Demo');
      expect(e.signed, isFalse);
      await mgr.setSiteAccess(e.id, SiteAccess.onClick);
      await mgr.setAllowInPrivate(e.id, true);

      final again = ExtensionManager.forTest();
      await again.init(root: Directory('${tmp.path}/ext'), isPrivate: false);
      final r = again.byId(e.id)!;
      expect(r.grants.siteAccess, SiteAccess.onClick);
      expect(r.allowInPrivate, isTrue);
      expect(r.grants.permissions, containsAll(['storage', 'tabs']));
    });

    test('private windows only run extensions allowed in private', () async {
      final e = await install();
      final priv = ExtensionManager.forTest();
      await priv.init(root: Directory('${tmp.path}/ext'), isPrivate: true);
      expect(priv.active, isEmpty);
      await mgr.setAllowInPrivate(e.id, true);
      await priv.init(root: Directory('${tmp.path}/ext'), isPrivate: true);
      expect(priv.active, hasLength(1));
    });

    test('missing referenced files are rejected', () async {
      final bad = Map.of(_files)..remove('a.js');
      await expectLater(
        mgr.prepareFromBytes(_zip(bad), source: ExtensionSource.packageFile),
        throwsA(isA<ExtensionInstallException>()),
      );
    });

    test('store installs must be signed CRX and match the expected id', () async {
      await expectLater(
        mgr.prepareFromBytes(_zip(_files), source: ExtensionSource.chromeWebStore, expectedId: 'a' * 32),
        throwsA(isA<ExtensionInstallException>()),
      );
    });

    test('update keeps user choices and flags new permissions', () async {
      final e = await install();
      await mgr.setPinned(e.id, false);
      final v2 = Map.of(_files)
        ..['manifest.json'] = _manifest.replaceFirst('"1.0.0"', '"1.1.0"').replaceFirst('"storage","tabs"', '"storage","tabs","history"');
      final p = await mgr.prepareFromBytes(_zip(v2), source: ExtensionSource.packageFile);
      expect(p.isUpdate, isTrue);
      expect(p.addedPermissions, ['history']);
      final upd = await mgr.commit(p, grants: PermissionPolicy.defaultGrants(p.manifest));
      expect(upd.version, '1.1.0');
      expect(upd.pinned, isFalse);
      expect(mgr.all, hasLength(1));
    });

    test('uninstall removes files', () async {
      final e = await install();
      await mgr.uninstall(e.id);
      expect(mgr.all, isEmpty);
      expect(Directory('${tmp.path}/ext/${e.id}').existsSync(), isFalse);
    });

    test('unpacked folders are used in place', () async {
      final dir = Directory('${tmp.path}/dev')..createSync();
      _files.forEach((k, v) => File('${dir.path}/$k').writeAsStringSync(v));
      final p = await mgr.prepareUnpacked(dir.path);
      final e = await mgr.commit(p, grants: PermissionPolicy.defaultGrants(p.manifest));
      expect(e.isUnpacked, isTrue);
      expect(e.contentDir, dir.absolute.path);
      await mgr.uninstall(e.id);
      expect(dir.existsSync(), isTrue, reason: 'never delete a developer folder');
    });
  });

  group('content script builder', () {
    test('produces a gated, per-extension script', () async {
      final e = await install();
      final js = ContentScriptBuilder.build(e)!;
      expect(js, contains('document.title="x";'));
      expect(js, contains('chromewebstore'));
      expect(js, isNot(contains('chrome.webview')));
      expect(js, isNot(contains('postMessage')), reason: 'no privileged bridge in pages');
    });

    test('on-click extensions inject nothing until forced', () async {
      final e = await install();
      await mgr.setSiteAccess(e.id, SiteAccess.onClick);
      expect(ContentScriptBuilder.build(e), isNull);
      expect(ContentScriptBuilder.build(e, force: true), isNotNull);
    });

    test('specific-sites mode adds the user gate', () async {
      final e = await install();
      await mgr.setSiteAccess(e.id, SiteAccess.onSpecificSites);
      expect(ContentScriptBuilder.build(e), isNull, reason: 'no sites chosen');
      await mgr.addSpecificSite(e.id, 'https://shop.example.com/*');
      expect(ContentScriptBuilder.build(e), contains('shop'));
    });
  });

  group('bridge', () {
    late InstalledExtension e;
    late ExtensionBridge bridge;
    late _Host host;

    setUp(() async {
      e = await install();
      host = _Host();
      bridge = ExtensionBridge(ext: e, storage: ExtensionStorage(), host: host);
    });

    Future<Map<String, dynamic>> call(String m, [Map<String, dynamic> a = const {}]) async =>
        jsonDecode(await bridge.handle(jsonEncode({'cinderExt': true, 'id': 1, 'method': m, 'args': a})))
            as Map<String, dynamic>;

    test('storage round trip', () async {
      expect((await call('storage.set', {'area': 'local', 'items': {'k': 1}}))['ok'], isTrue);
      final r = await call('storage.get', {'area': 'local', 'keys': ['k', 'z']});
      expect(r['result'], {'k': 1});
      await call('storage.remove', {'area': 'local', 'keys': 'k'});
      expect((await call('storage.get', {'area': 'local', 'keys': null}))['result'], isEmpty);
    });

    test('rejects malformed and unknown requests', () async {
      expect((await call('nope'))['ok'], isFalse);
      expect((await call('storage.get', {'area': 'managed'}))['ok'], isFalse);
      expect(jsonDecode(await bridge.handle('not json'))['ok'], isFalse);
      expect(jsonDecode(await bridge.handle({'cinderExt': true, 'id': 'x', 'method': 'storage.get'}))['ok'], isFalse);
      expect(jsonDecode(await bridge.handle({'method': 'storage.get', 'id': 1}))['ok'], isFalse);
    });

    test('enforces permissions', () async {
      await mgr.update(e.id, (x) => x.grants.permissions.remove('storage'));
      expect((await call('storage.get', {'area': 'local'}))['ok'], isFalse);
      expect((await call('clipboard.writeText', {'text': 'x'}))['ok'], isFalse);
    });

    test('tabs.query hides url without permission', () async {
      final r = (await call('tabs.query'))['result'] as List;
      expect((r.first as Map).containsKey('url'), isTrue, reason: 'has tabs permission');
      await mgr.update(e.id, (x) => x.grants.permissions.remove('tabs'));
      final r2 = (await call('tabs.query'))['result'] as List;
      expect((r2.first as Map).containsKey('url'), isFalse);
    });

    test('tabs.create only opens web addresses; popup size is clamped', () async {
      expect((await call('tabs.create', {'url': 'javascript:alert(1)'}))['ok'], isFalse);
      expect((await call('tabs.create', {'url': 'file:///c:/x'}))['ok'], isFalse);
      expect((await call('tabs.create', {'url': 'https://example.com'}))['ok'], isTrue);
      expect(host.opened, 'https://example.com');
      await call('popup.resize', {'width': 99999, 'height': 1});
      expect(host.resized!.w, 800);
      expect(host.resized!.h, 60);
    });

    test('storage quota and message size limit', () async {
      final chunk = 'x' * (900 * 1024);
      var ok = 0;
      for (var i = 0; i < 14; i++) {
        final r = await call('storage.set', {'area': 'local', 'items': {'k$i': chunk}});
        if (r['ok'] == true) ok++;
      }
      expect(ok, inInclusiveRange(10, 12), reason: '10 MB cap');
      final huge = await call('storage.set', {'area': 'local', 'items': {'z': 'x' * (2 * 1024 * 1024)}});
      expect(huge['ok'], isFalse);
    });
  });

  group('web store', () {
    test('parses ids and store URLs; rejects other hosts', () {
      final id = 'a' * 32;
      expect(StoreRef.parse(id)!.id, id);
      expect(StoreRef.parse('https://chromewebstore.google.com/detail/name/$id')!.kind, StoreKind.chrome);
      expect(StoreRef.parse('https://chrome.google.com/webstore/detail/name/$id')!.id, id);
      expect(StoreRef.parse('https://microsoftedge.microsoft.com/addons/detail/name/$id')!.kind, StoreKind.edge);
      expect(StoreRef.parse('https://evil.com/detail/name/$id'), isNull);
      expect(StoreRef.parse('http://chromewebstore.google.com/detail/n/$id'), isNull);
      expect(StoreRef.parse('hello'), isNull);
    });

    test('download hosts are allow-listed', () {
      expect(WebStoreClient.isAllowedHost('clients2.googleusercontent.com'), isTrue);
      expect(WebStoreClient.isAllowedHost('evilgoogle.com'), isFalse);
      expect(WebStoreClient.isAllowedHost('google.com.evil.com'), isFalse);
    });

    test('update response parsing', () {
      const xml = '<gupdate><app appid="x"><updatecheck codebase="https://clients2.googleusercontent.com/crx/a.crx" version="2.0.1" status="ok"/></app></gupdate>';
      expect(WebStoreClient.parseUpdateResponse(xml, 'x', '2.0.0')!.version, '2.0.1');
      expect(WebStoreClient.parseUpdateResponse(xml, 'x', '2.0.1'), isNull);
      expect(
        WebStoreClient.parseUpdateResponse(xml.replaceFirst('clients2.googleusercontent.com', 'evil.com'), 'x', '1.0'),
        isNull,
      );
      expect(WebStoreClient.compareVersions('1.10', '1.9'), greaterThan(0));
    });
  });
}
