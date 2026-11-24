import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart';

import 'package:saboor_browser/extensions/content_script_builder.dart';
import 'package:saboor_browser/extensions/extension_manager.dart';
import 'package:saboor_browser/extensions/permissions.dart';
import 'package:saboor_browser/extensions/popup_bridge.dart';

/// Connects installed extensions to browser tabs.
class ExtensionRuntime {
  ExtensionRuntime._() {
    ExtensionManager.instance.addListener(_onChanged);
  }
  static final ExtensionRuntime instance = ExtensionRuntime._();

  final Map<WebviewController, List<ScriptID>> _attached = {};
  final Map<String, ExtensionStorage> _storage = {};
  Timer? _debounce;

  void _onChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), () {
      for (final c in _attached.keys.toList()) {
        unawaited(_sync(c));
      }
    });
  }

  /// Registers content scripts on a tab's WebView. They apply to every
  /// document the tab loads from now on.
  Future<void> attach(WebviewController controller) async {
    _attached.putIfAbsent(controller, () => []);
    await _sync(controller);
  }

  void detach(WebviewController controller) => _attached.remove(controller);

  Future<void> _sync(WebviewController c) async {
    final old = _attached[c];
    if (old == null) return;
    final fresh = <ScriptID>[];
    try {
      for (final id in old) {
        await c.removeScriptToExecuteOnDocumentCreated(id);
      }
      final mgr = ExtensionManager.instance;
      for (final ext in mgr.active) {
        final js = ContentScriptBuilder.build(ext);
        if (js == null) continue;
        final id = await c.addScriptToExecuteOnDocumentCreated(js);
        if (id != null) fresh.add(id);
      }
    } catch (e) {
      debugPrint('ExtensionRuntime sync failed: $e');
    }
    if (_attached.containsKey(c)) _attached[c] = fresh;
  }

  /// "Run on click": the user pressed the toolbar button of an extension whose
  /// site access is "on click". Grants the current origin for this session
  /// and injects its content scripts into the current page immediately.
  Future<void> runOnce(
    WebviewController c,
    InstalledExtension ext,
    String pageUrl,
  ) async {
    final origin = PermissionPolicy.originOf(pageUrl);
    if (origin.isEmpty) return;
    if (!PermissionPolicy.mayRunOn(
      ext.manifest,
      ExtensionGrants(permissions: ext.grants.permissions, activeTabOrigins: {origin}),
      pageUrl,
    )) {
      return;
    }
    ExtensionManager.instance.grantActiveTab(ext.id, origin);
    final js = ContentScriptBuilder.build(ext, force: true);
    if (js != null) await c.executeScript(js);
  }

  ExtensionStorage storageFor(InstalledExtension ext) {
    return _storage.putIfAbsent(ext.id, () {
      final mgr = ExtensionManager.instance;
      return ExtensionStorage(
        file: mgr.isPrivateWindow
            ? null
            : File('${mgr.dataDir(ext.id).path}${Platform.pathSeparator}storage.json'),
      );
    });
  }

  void forget(String id) => _storage.remove(id)?.flush();
}

/// A popup (or options page) shown from the toolbar.
class ExtensionPopupSession implements BridgeHost {
  ExtensionPopupSession({
    required this.ext,
    required this.onOpenTab,
    required this.onClose,
    required this.activeTabInfo,
    this.relativePath,
  });

  final InstalledExtension ext;
  final void Function(String url) onOpenTab;
  final VoidCallback onClose;
  final ({int id, String url, String title})? Function() activeTabInfo;
  final String? relativePath;

  final WebviewController controller = WebviewController();
  final ValueNotifier<Size> size = ValueNotifier(const Size(360, 440));
  final ValueNotifier<bool> ready = ValueNotifier(false);
  StreamSubscription<dynamic>? _msg;
  StreamSubscription<String>? _url;
  late final ExtensionBridge _bridge;
  bool _disposed = false;
  String _currentUrl = '';

  Future<void> start() async {
    _bridge = ExtensionBridge(
      ext: ext,
      storage: ExtensionRuntime.instance.storageFor(ext),
      host: this,
    );
    final host = extensionHost(ext.id);
    await controller.initialize();
    await controller.setDefaultContextMenusEnabled(false);
    await controller.setPopupWindowPolicy(WebviewPopupWindowPolicy.deny);
    await controller.addVirtualHostNameMapping(
      host,
      ext.contentDir,
      WebviewHostResourceAccessKind.denyCors,
    );
    await controller.addScriptToExecuteOnDocumentCreated(ExtensionPageShim.script(ext));
    _url = controller.url.listen((u) {
      _currentUrl = u;
      final uri = Uri.tryParse(u);
      // An extension page must stay on its own origin; anything else goes to a
      // regular tab and the popup is closed.
      if (uri != null && uri.host != host && u.isNotEmpty && u != 'about:blank') {
        unawaited(controller.stop());
        if (uri.scheme == 'http' || uri.scheme == 'https') onOpenTab(u);
        onClose();
      }
    });
    _msg = controller.webMessage.listen((m) async {
      // Only answer while the page really is on the extension's origin.
      if (Uri.tryParse(_currentUrl)?.host != host) return;
      final reply = await _bridge.handle(m);
      if (!_disposed) {
        try {
          await controller.postWebMessage(reply);
        } catch (_) {}
      }
    });
    final path = relativePath ?? ext.manifest.popup ?? '';
    await controller.loadUrl('https://$host/$path');
    ready.value = true;
  }

  // BridgeHost
  @override
  ({int id, String url, String title})? activeTab() => activeTabInfo();
  @override
  void openTab(String url) => onOpenTab(url);
  @override
  void openOptionsPage(InstalledExtension e) {
    final page = e.manifest.optionsPage;
    if (page != null) onOpenTab('https://${extensionHost(e.id)}/$page');
  }

  @override
  void resizePopup(int width, int height) {
    if (relativePath != null) return; // options pages keep their own size
    size.value = Size(width.toDouble(), height.toDouble());
  }

  @override
  void closePopup() => onClose();
  @override
  Future<void> writeClipboard(String text) => Clipboard.setData(ClipboardData(text: text));

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _msg?.cancel();
    await _url?.cancel();
    try {
      await controller.removeVirtualHostNameMapping(extensionHost(ext.id));
    } catch (_) {}
    await controller.dispose();
    size.dispose();
    ready.dispose();
  }
}
