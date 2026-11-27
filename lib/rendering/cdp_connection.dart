import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// One DevTools-protocol event (a message without an `id`).
class CdpEvent {
  const CdpEvent(this.method, this.params, this.sessionId);

  final String method;
  final Map<String, dynamic> params;
  final String? sessionId;
}

/// A DevTools-protocol error reply.
class CdpException implements Exception {
  CdpException(this.method, this.message);

  final String method;
  final String message;

  @override
  String toString() => 'CdpException($method): $message';
}

/// What the compatibility renderer needs from a DevTools connection. Kept as
/// an interface so it can be faked in widget tests.
abstract class CdpTransport {
  /// Sends [method]; completes with the `result`, or throws [CdpException]
  /// (protocol error) / [TimeoutException] / [StateError] (closed).
  Future<Map<String, dynamic>> send(
    String method, [
    Map<String, dynamic>? params,
    String? sessionId,
  ]);

  Stream<CdpEvent> get events;

  bool get isOpen;

  Future<void> close();
}

/// A browser-level DevTools websocket on this window's loopback port.
///
/// Only ever connects to 127.0.0.1: the port comes from the runner
/// (`--cinder-devtools-port`) and the websocket address the engine reports is
/// checked before use, exactly as `RequestFilter` does.
class CdpConnection implements CdpTransport {
  CdpConnection._(this._ws) {
    _ws.listen(_onMessage, onDone: _onDone, onError: (_) => _onDone());
  }

  final WebSocket _ws;
  int _nextId = 0;
  bool _closed = false;
  final Map<int, Completer<Map<String, dynamic>>> _pending = {};
  final StreamController<CdpEvent> _events = StreamController.broadcast();

  /// Connects to the browser endpoint on [port], or returns null.
  static Future<CdpConnection?> connect(int port) async {
    if (port <= 0) return null;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    try {
      final req = await client.getUrl(
        Uri.parse('http://127.0.0.1:$port/json/version'),
      );
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      final wsUrl = (jsonDecode(body) as Map)['webSocketDebuggerUrl'];
      if (wsUrl is! String) return null;
      final u = Uri.parse(wsUrl);
      if (u.host != '127.0.0.1' && u.host != 'localhost') return null;
      return CdpConnection._(await WebSocket.connect(wsUrl));
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  @override
  bool get isOpen => !_closed;

  @override
  Stream<CdpEvent> get events => _events.stream;

  @override
  Future<Map<String, dynamic>> send(
    String method, [
    Map<String, dynamic>? params,
    String? sessionId,
  ]) {
    if (_closed) return Future.error(StateError('DevTools connection closed'));
    final id = ++_nextId;
    final c = Completer<Map<String, dynamic>>();
    _pending[id] = c;
    _ws.add(
      jsonEncode({
        'id': id,
        'method': method,
        'params': ?params,
        'sessionId': ?sessionId,
      }),
    );
    return c.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        _pending.remove(id);
        throw TimeoutException('$method timed out');
      },
    );
  }

  void _onMessage(dynamic data) {
    // Screencast frames are large; allow generous but bounded messages.
    if (data is! String || data.length > 32 * 1024 * 1024) return;
    Map<String, dynamic> m;
    try {
      m = jsonDecode(data) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final id = m['id'];
    if (id is int) {
      final c = _pending.remove(id);
      if (c == null || c.isCompleted) return;
      final error = m['error'];
      if (error is Map) {
        c.completeError(CdpException('#$id', '${error['message']}'));
      } else {
        final r = m['result'];
        c.complete(r is Map<String, dynamic> ? r : const {});
      }
      return;
    }
    final method = m['method'];
    final params = m['params'];
    if (method is String) {
      _events.add(
        CdpEvent(
          method,
          params is Map<String, dynamic> ? params : const {},
          m['sessionId'] as String?,
        ),
      );
    }
  }

  void _onDone() {
    _closed = true;
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(StateError('connection closed'));
    }
    _pending.clear();
    if (!_events.isClosed) unawaited(_events.close());
  }

  @override
  Future<void> close() async {
    _closed = true;
    await _ws.close();
  }
}
