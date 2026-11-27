import 'dart:async';

import 'package:saboor_browser/rendering/cdp_connection.dart';
import 'package:saboor_browser/rendering/page_target_finder.dart';

/// One DevTools connection for the window plus a cache of which engine target
/// belongs to which tab, shared by every [CompatPageView].
class CompatRenderService {
  CompatRenderService({
    required this.port,
    Future<CdpTransport?> Function(int port)? connect,
  }) : _connect = connect ?? CdpConnection.connect;

  final int port;
  final Future<CdpTransport?> Function(int port) _connect;

  CdpTransport? _transport;
  Future<CdpTransport?>? _connecting;
  final Map<String, String> _targets = {};
  bool _disposed = false;

  /// The open connection, (re)connecting when needed; null if unreachable.
  Future<CdpTransport?> transport() async {
    if (_disposed) return null;
    final current = _transport;
    if (current != null && current.isOpen) return current;
    return _connecting ??= _open();
  }

  Future<CdpTransport?> _open() async {
    try {
      final t = await _connect(port);
      if (_disposed) {
        unawaited(t?.close());
        return null;
      }
      _transport = t;
      _targets.clear(); // ids from a dead connection are not trustworthy
      return t;
    } catch (_) {
      return null;
    } finally {
      _connecting = null; // a failed attempt must not block the next one
    }
  }

  /// The engine target for [tabId]. A cached id is reused while it still
  /// exists; otherwise the tab is marked (via [mark]) and located again.
  Future<String?> targetFor({
    required String tabId,
    required String url,
    required Future<void> Function(String marker) mark,
  }) async {
    final t = await transport();
    if (t == null) return null;
    final cached = _targets[tabId];
    if (cached != null && await targetExists(t, cached)) return cached;
    final marker = 'cinder-tab:$tabId';
    final found = await findPageTarget(
      t,
      marker: marker,
      mark: () => mark(marker),
      url: url,
    );
    if (found != null) {
      _targets[tabId] = found;
    } else {
      _targets.remove(tabId);
    }
    return found;
  }

  /// Forget a tab (it closed, or its target went away).
  void forget(String tabId) => _targets.remove(tabId);

  Future<void> dispose() async {
    _disposed = true;
    _targets.clear();
    final t = _transport;
    _transport = null;
    try {
      await t?.close();
    } catch (_) {}
  }
}
