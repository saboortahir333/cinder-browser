import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:saboor_browser/extensions/extension_manager.dart';
import 'package:saboor_browser/extensions/extension_runtime.dart';
import 'package:saboor_browser/extensions/permissions.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart';

Future<T> until<T>(Future<T?> Function() f, {int secs = 20}) async {
  final end = DateTime.now().add(Duration(seconds: secs));
  while (DateTime.now().isBefore(end)) {
    final v = await f();
    if (v != null && v != false) return v;
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  throw TimeoutException('condition not met');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('real WebView2: content script, CSS, popup bridge', (tester) async {
    final tmp = Directory.systemTemp.createTempSync('cinder_e2e');
    final mgr = ExtensionManager.instance;
    await mgr.init(root: Directory('${tmp.path}/ext'), isPrivate: false);
    final pending = await mgr.prepareUnpacked(Directory('integration_test/fixtures/sample_ext').absolute.path);
    final ext = await mgr.commit(pending, grants: PermissionPolicy.defaultGrants(pending.manifest));

    // --- content script on a matching page, not on a non-matching one ---
    final tab = WebviewController();
    await tab.initialize();
    await ExtensionRuntime.instance.attach(tab);
    final site = Directory('integration_test/fixtures/site').absolute.path;
    await tab.addVirtualHostNameMapping('a.cinder-test.example', site, WebviewHostResourceAccessKind.allow);
    await tab.addVirtualHostNameMapping('other.invalid-test.example', site, WebviewHostResourceAccessKind.allow);

    await tab.loadUrl('https://a.cinder-test.example/index.html');
    final ran = await until(() async {
      final r = await tab.executeScript('window.__cinderExtRan || ""');
      return (r?.toString().replaceAll('"', '') ?? '').isEmpty ? null : r.toString().replaceAll('"', '');
    });
    expect(ran, ext.id, reason: 'content script ran on matching host');
    final title = await until(() async {
      final r = (await tab.executeScript('document.title')).toString().replaceAll('"', '');
      return r.startsWith('patched:') ? r : null;
    });
    expect(title, 'patched:Hello');
    final bg = (await tab.executeScript('getComputedStyle(document.body).backgroundColor')).toString();
    expect(bg, contains('1, 2, 3'), reason: 'extension CSS applied');

    await tab.loadUrl('https://other.invalid-test.example/index.html');
    await Future<void>.delayed(const Duration(seconds: 2));
    final other = (await tab.executeScript('String(window.__cinderExtRan)')).toString();
    expect(other, contains('undefined'), reason: 'no injection on non-matching host');

    // --- site access "on click": nothing injected on load ---
    await mgr.setSiteAccess(ext.id, SiteAccess.onClick);
    await Future<void>.delayed(const Duration(seconds: 1));
    await tab.loadUrl('https://a.cinder-test.example/index.html');
    await Future<void>.delayed(const Duration(seconds: 2));
    expect((await tab.executeScript('String(window.__cinderExtRan)')).toString(), contains('undefined'));
    await ExtensionRuntime.instance.runOnce(tab, mgr.byId(ext.id)!, 'https://a.cinder-test.example/index.html');
    final after = await until(() async {
      final r = (await tab.executeScript('String(window.__cinderExtRan)')).toString().replaceAll('"', '');
      return r == 'undefined' ? null : r;
    });
    expect(after, ext.id, reason: 'runs after toolbar click');
    await mgr.setSiteAccess(ext.id, SiteAccess.onAllSites);

    // --- popup + storage bridge ---
    final session = ExtensionPopupSession(
      ext: mgr.byId(ext.id)!,
      onOpenTab: (_) {},
      onClose: () {},
      activeTabInfo: () => (id: 1, url: 'https://a.cinder-test.example/', title: 'T'),
    );
    await session.start();
    final done = await until(() async {
      final r = (await session.controller.executeScript('window.__popupDone || ""')).toString().replaceAll('"', '');
      return r.isEmpty ? null : r;
    });
    expect(done, 'stored:42', reason: 'chrome.storage round trip through the bridge');
    // The popup page must refuse to be navigated off its origin.
    final host = (await session.controller.executeScript('location.host')).toString().replaceAll('"', '');
    expect(host.endsWith('.extension.cinder.local'), isTrue);
    await session.dispose();
    await tab.dispose();
    tmp.deleteSync(recursive: true);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
