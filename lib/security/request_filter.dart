import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:saboor_browser/security/request_policy.dart';

/// Applies [RequestPolicy] to every request the browser makes.
///
/// WebView2 (through `webview_flutter_windows`) has no request-interception
/// API, so this talks to the engine's own DevTools Protocol on the loopback
/// port the runner opened for this window (`--cinder-devtools-port`):
/// browser-level target auto-attach, then `Fetch.enable` per page/frame.
///
/// Security note: that port accepts connections from any local process, as
/// every Chromium remote-debugging port does. It is bound to 127.0.0.1 on a
/// random ephemeral port that differs per launch; see docs/threat-model.md.
class RequestFilter {
  RequestFilter({required this.port, required this.policy});

  final int port;
  final RequestPolicy policy;

  WebSocket? _ws;
  int _nextId = 0;
  final Map<int, Completer<Map<String, dynamic>>> _pending = {};
  final Set<String> _sessions = {};
  final Map<String, String> _sessionUrl = {};
  bool _closed = false;

  /// Blocked sub-resource counts per page host (shown in the site panel).
  final Map<String, int> blockedByHost = {};
  final ValueNotifier<int> blockedTotal = ValueNotifier<int>(0);

  bool get connected => _ws != null && !_closed;

  Future<bool> start() async {
    if (port == 0) return false;
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
      final req = await client.getUrl(Uri.parse('http://127.0.0.1:$port/json/version'));
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      client.close();
      final wsUrl = (jsonDecode(body) as Map)['webSocketDebuggerUrl'];
      if (wsUrl is! String) return false;
      // Only ever our own loopback endpoint.
      final u = Uri.parse(wsUrl);
      if (u.host != '127.0.0.1' && u.host != 'localhost') return false;
      _ws = await WebSocket.connect(wsUrl);
      _ws!.listen(_onMessage, onDone: _onDone, onError: (_) => _onDone());
      await _send('Target.setDiscoverTargets', {'discover': true});
      await _send('Target.setAutoAttach', {
        'autoAttach': true,
        'waitForDebuggerOnStart': true,
        'flatten': true,
      });
      // Pages that already exist.
      final targets = await _send('Target.getTargets');
      for (final t in (targets['targetInfos'] as List? ?? const [])) {
        if (t is Map && t['type'] == 'page' && t['attached'] != true) {
          unawaited(_send('Target.attachToTarget', {'targetId': t['targetId'], 'flatten': true})
              .catchError((_) => <String, dynamic>{}));
        }
      }
      return true;
    } catch (_) {
      _onDone();
      return false;
    }
  }

  void dispose() {
    _closed = true;
    _ws?.close();
    _ws = null;
    for (final c in _pending.values) {
      if (!c.isCompleted) c.complete(const {});
    }
    _pending.clear();
  }

  void _onDone() {
    _closed = true;
    _ws = null;
  }

  Future<Map<String, dynamic>> _send(String method, [Map<String, dynamic>? params, String? sessionId]) {
    final ws = _ws;
    if (ws == null) return Future.value(const {});
    final id = ++_nextId;
    final c = Completer<Map<String, dynamic>>();
    _pending[id] = c;
    ws.add(jsonEncode({
      'id': id,
      'method': method,
      if (params != null) 'params': params,
      if (sessionId != null) 'sessionId': sessionId,
    }));
    return c.future.timeout(const Duration(seconds: 10), onTimeout: () {
      _pending.remove(id);
      return const <String, dynamic>{};
    });
  }

  void _onMessage(dynamic data) {
    if (data is! String || data.length > 8 * 1024 * 1024) return;
    Map<String, dynamic> m;
    try {
      m = jsonDecode(data) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final id = m['id'];
    if (id is int) {
      final c = _pending.remove(id);
      if (c != null && !c.isCompleted) {
        final r = m['result'];
        c.complete(r is Map<String, dynamic> ? r : const {});
      }
      return;
    }
    final params = m['params'];
    if (params is! Map<String, dynamic>) return;
    switch (m['method']) {
      case 'Target.attachedToTarget':
        unawaited(_onAttached(params));
      case 'Target.detachedFromTarget':
        final s = params['sessionId'];
        if (s is String) {
          _sessions.remove(s);
          _sessionUrl.remove(s);
        }
      case 'Fetch.requestPaused':
        final s = m['sessionId'];
        if (s is String) _onPaused(s, params);
    }
  }

  Future<void> _onAttached(Map<String, dynamic> p) async {
    final session = p['sessionId'];
    final info = p['targetInfo'];
    if (session is! String || info is! Map) return;
    final type = info['type'];
    final url = '${info['url'] ?? ''}';
    final waiting = p['waitingForDebugger'] == true;
    if ((type == 'page' || type == 'iframe') && !url.startsWith('devtools://')) {
      _sessions.add(session);
      _sessionUrl[session] = url;
      await _send('Fetch.enable', {
        'patterns': [
          {'urlPattern': '*', 'requestStage': 'Request'},
        ],
      }, session);
      // Nested out-of-process frames.
      await _send('Target.setAutoAttach', {
        'autoAttach': true,
        'waitForDebuggerOnStart': true,
        'flatten': true,
      }, session);
    }
    // Never leave a target frozen, whatever its type.
    if (waiting) await _send('Runtime.runIfWaitingForDebugger', null, session);
  }

  void _onPaused(String session, Map<String, dynamic> p) {
    final requestId = p['requestId'];
    final request = p['request'];
    if (requestId is! String || request is! Map) return;
    final url = '${request['url'] ?? ''}';
    final type = '${p['resourceType'] ?? 'Other'}';
    final headers = request['headers'];
    var documentUrl = _sessionUrl[session] ?? '';
    if (type != 'Document' && headers is Map) {
      final ref = headers['Referer'] ?? headers['referer'];
      if (ref is String && ref.isNotEmpty) documentUrl = ref;
    }
    if (type == 'Document' && p['frameId'] != null) {
      // Navigation: remember it as the page URL for later sub-requests.
      _sessionUrl[session] = url;
    }

    RequestDecision d;
    try {
      d = policy.decide(url: url, documentUrl: documentUrl, resourceType: type);
    } catch (_) {
      d = const AllowRequest();
    }

    switch (d) {
      case AllowRequest():
        unawaited(_send('Fetch.continueRequest', {'requestId': requestId}, session));
      case BlockRequest():
        final host = Uri.tryParse(documentUrl)?.host ?? '';
        blockedByHost[host] = (blockedByHost[host] ?? 0) + 1;
        blockedTotal.value++;
        unawaited(_send('Fetch.failRequest', {'requestId': requestId, 'errorReason': 'BlockedByClient'}, session));
      case UpgradeRequest(:final httpsUrl):
        unawaited(_send('Fetch.fulfillRequest', {
          'requestId': requestId,
          'responseCode': 307,
          'responseHeaders': [
            {'name': 'Location', 'value': httpsUrl},
            {'name': 'Cache-Control', 'value': 'no-store'},
          ],
        }, session));
      case WarnRequest(:final kind, :final host):
        unawaited(_send('Fetch.fulfillRequest', {
          'requestId': requestId,
          'responseCode': 200,
          'responseHeaders': [
            {'name': 'Content-Type', 'value': 'text/html; charset=utf-8'},
            {'name': 'Cache-Control', 'value': 'no-store'},
          ],
          'body': base64Encode(utf8.encode(warningPage(kind, host, url))),
        }, session));
    }
  }

  /// Self-contained interstitial. No scripts, no external resources.
  static String warningPage(String kind, String host, String url) {
    String esc(String s) => const HtmlEscape().convert(s);
    return '<!doctype html><meta charset="utf-8"><title>Deceptive site blocked</title>'
        '<meta name="viewport" content="width=device-width,initial-scale=1">'
        '<style>body{font:16px system-ui,sans-serif;background:#1b1115;color:#f4e9ea;'
        'display:grid;place-items:center;min-height:100vh;margin:0}main{max-width:560px;padding:32px}'
        'h1{color:#ff8a80;font-size:26px}code{background:#00000055;padding:2px 6px;border-radius:4px}</style>'
        '<main><h1>Deceptive site blocked</h1>'
        '<p><code>${esc(host)}</code> is on a list of sites that distribute malware or run scams. '
        'Cinder stopped the page from loading to protect you.</p>'
        '<p>Close this tab, or go back to where you came from.</p>'
        '<p style="font-size:13px;opacity:.7">Source: abuse.ch URLhaus host list. '
        'You can turn this protection off for a site from the lock icon in the address bar.</p></main>';
  }
}
