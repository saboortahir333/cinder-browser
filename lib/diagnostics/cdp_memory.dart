import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// JS heap and DOM size of one open page.
class TabMemory {
  const TabMemory({
    required this.targetId,
    required this.host,
    required this.jsHeapUsedBytes,
    required this.jsHeapTotalBytes,
    required this.domNodes,
    required this.documents,
  });

  final String targetId;

  /// Host name only. The full URL is never kept (it can contain secrets).
  final String host;
  final int jsHeapUsedBytes;
  final int jsHeapTotalBytes;
  final int domNodes;
  final int documents;

  Map<String, Object?> toJson() => {
    'host': host,
    'jsHeapUsedBytes': jsHeapUsedBytes,
    'jsHeapTotalBytes': jsHeapTotalBytes,
    'domNodes': domNodes,
    'documents': documents,
  };
}

/// Per-tab memory straight from the engine, using a short-lived second client
/// on the loopback DevTools port the app already opened. Read-only: it only
/// calls `Performance.getMetrics`.
class CdpMemory {
  CdpMemory._();

  static Future<List<TabMemory>> sample(
    int port, {
    Duration timeout = const Duration(seconds: 4),
  }) async {
    if (port <= 0) return const [];
    WebSocket? ws;
    try {
      final http = HttpClient()..connectionTimeout = const Duration(seconds: 2);
      final req = await http.getUrl(
        Uri.parse('http://127.0.0.1:$port/json/version'),
      );
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      http.close();
      final wsUrl = (jsonDecode(body) as Map)['webSocketDebuggerUrl'];
      if (wsUrl is! String) return const [];
      final uri = Uri.parse(wsUrl);
      if (uri.host != '127.0.0.1' && uri.host != 'localhost') return const [];

      ws = await WebSocket.connect(wsUrl).timeout(timeout);
      final client = _Client(ws);
      return await _collect(client).timeout(timeout, onTimeout: () => const []);
    } catch (_) {
      return const [];
    } finally {
      await ws?.close();
    }
  }

  static Future<List<TabMemory>> _collect(_Client c) async {
    final targets = await c.send('Target.getTargets');
    final infos = (targets['targetInfos'] as List?) ?? const [];
    final out = <TabMemory>[];
    for (final t in infos) {
      if (t is! Map || t['type'] != 'page') continue;
      final url = '${t['url'] ?? ''}';
      if (url.startsWith('devtools://')) continue;
      final targetId = '${t['targetId']}';
      final attach = await c.send('Target.attachToTarget', {
        'targetId': targetId,
        'flatten': true,
      });
      final session = attach['sessionId'];
      if (session is! String) continue;
      try {
        await c.send('Performance.enable', null, session);
        final res = await c.send('Performance.getMetrics', null, session);
        final metrics = <String, num>{};
        for (final m in (res['metrics'] as List?) ?? const []) {
          if (m is Map && m['name'] is String && m['value'] is num) {
            metrics[m['name'] as String] = m['value'] as num;
          }
        }
        out.add(
          TabMemory(
            targetId: targetId,
            host: Uri.tryParse(url)?.host ?? '',
            jsHeapUsedBytes: (metrics['JSHeapUsedSize'] ?? 0).toInt(),
            jsHeapTotalBytes: (metrics['JSHeapTotalSize'] ?? 0).toInt(),
            domNodes: (metrics['Nodes'] ?? 0).toInt(),
            documents: (metrics['Documents'] ?? 0).toInt(),
          ),
        );
        await c.send('Performance.disable', null, session);
      } finally {
        await c.send('Target.detachFromTarget', {'sessionId': session});
      }
    }
    return out;
  }
}

class _Client {
  _Client(this._ws) {
    _ws.listen((data) {
      if (data is! String) return;
      try {
        final m = jsonDecode(data);
        if (m is Map && m['id'] is int) {
          final c = _pending.remove(m['id'] as int);
          final r = m['result'];
          c?.complete(r is Map<String, dynamic> ? r : const {});
        }
      } catch (_) {}
    });
  }

  final WebSocket _ws;
  int _id = 0;
  final Map<int, Completer<Map<String, dynamic>>> _pending = {};

  Future<Map<String, dynamic>> send(
    String method, [
    Map<String, dynamic>? params,
    String? sessionId,
  ]) {
    final id = ++_id;
    final c = Completer<Map<String, dynamic>>();
    _pending[id] = c;
    _ws.add(
      jsonEncode({
        'id': id,
        'method': method,
        if (params != null) 'params': params,
        if (sessionId != null) 'sessionId': sessionId,
      }),
    );
    return c.future.timeout(
      const Duration(seconds: 3),
      onTimeout: () {
        _pending.remove(id);
        return const <String, dynamic>{};
      },
    );
  }
}
