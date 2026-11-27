import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import 'package:saboor_browser/rendering/cdp_connection.dart';

/// Draws one page from the browser engine's own screen frames instead of from
/// `Windows.Graphics.Capture`.
///
/// The default renderer copies the engine's composition surface into a Flutter
/// texture. On machines where that capture produces nothing (Remote Desktop
/// sessions, software-only GPUs, some virtual machines) the page is loaded and
/// running but the texture stays blank. The engine can always hand out its own
/// rendered frames over DevTools (`Page.startScreencast`), so this session
/// shows those and sends mouse / keyboard input back the same way.
///
/// If the engine pushes no screencast frame at all, it falls back to polling
/// `Page.captureScreenshot`, which works wherever the page can be rendered.
class ScreencastSession extends ChangeNotifier {
  ScreencastSession(
    this._t,
    this.targetId, {
    this.quality = 72,
    this.firstFrameTimeout = const Duration(seconds: 2),
    this.pollInterval = const Duration(milliseconds: 90),
  });

  final CdpTransport _t;
  final String targetId;
  final int quality;
  final Duration firstFrameTimeout;
  final Duration pollInterval;

  String? _session;
  StreamSubscription<CdpEvent>? _sub;
  Timer? _firstFrameTimer;
  Timer? _metricsTimer;
  bool _stopped = false;
  bool _polling = false;
  bool _decoding = false;
  Uint8List? _queued;

  ui.Image? _image;
  int _frames = 0;
  String? _error;
  bool _lost = false;
  int _maxWidth = 0;
  int _maxHeight = 0;

  /// CSS-pixel size of the page viewport, for mapping pointer positions.
  ui.Size _cssSize = ui.Size.zero;

  /// The newest decoded frame. Owned by the session; do not dispose.
  ui.Image? get image => _image;
  int get framesReceived => _frames;
  String? get error => _error;

  /// True when the target went away (tab closed, renderer crashed).
  bool get lost => _lost;
  bool get isPolling => _polling;
  ui.Size get cssSize => _cssSize;

  /// Attaches to the target and starts streaming frames, sized for a view of
  /// [maxWidth] x [maxHeight] device pixels.
  Future<void> start({required int maxWidth, required int maxHeight}) async {
    _maxWidth = maxWidth;
    _maxHeight = maxHeight;
    try {
      final a = await _t.send('Target.attachToTarget', {
        'targetId': targetId,
        'flatten': true,
      });
      final session = a['sessionId'] as String?;
      if (session == null) throw StateError('no session for target');
      _session = session;
      _sub = _t.events.listen(_onEvent, onDone: _onClosed);
      await _startScreencast();
      await _refreshMetrics();
      _metricsTimer = Timer.periodic(
        const Duration(milliseconds: 1500),
        (_) => unawaited(_refreshMetrics()),
      );
      _firstFrameTimer = Timer(firstFrameTimeout, () {
        if (_frames == 0 && !_stopped) _beginPolling();
      });
    } catch (e) {
      _error = '$e';
      notifyListeners();
    }
  }

  Future<void> _startScreencast() async {
    await _t.send('Page.startScreencast', {
      'format': 'jpeg',
      'quality': quality,
      'maxWidth': _maxWidth,
      'maxHeight': _maxHeight,
      'everyNthFrame': 1,
    }, _session);
  }

  /// The view changed size: ask for frames at the new size.
  Future<void> resize({required int maxWidth, required int maxHeight}) async {
    if (_stopped || _session == null) return;
    if (maxWidth == _maxWidth && maxHeight == _maxHeight) return;
    _maxWidth = maxWidth;
    _maxHeight = maxHeight;
    if (_polling) return; // screenshots are taken at the live view size
    try {
      await _t.send('Page.stopScreencast', null, _session);
      await _startScreencast();
    } catch (_) {}
  }

  void _onEvent(CdpEvent e) {
    if (_stopped) return;
    if (e.method == 'Target.detachedFromTarget' &&
        e.params['sessionId'] == _session) {
      _lost = true;
      notifyListeners();
      return;
    }
    if (e.sessionId != _session) return;
    if (e.method == 'Page.screencastFrame') {
      final data = e.params['data'];
      final ackId = e.params['sessionId'];
      if (ackId is int) {
        // Always acknowledge, even when a frame is dropped, or the engine
        // stops sending.
        unawaited(
          _t
              .send('Page.screencastFrameAck', {'sessionId': ackId}, _session)
              .then((_) {}, onError: (_) {}),
        );
      }
      if (data is String) {
        final meta = e.params['metadata'];
        if (meta is Map && _cssSize == ui.Size.zero) {
          final w = (meta['deviceWidth'] as num?)?.toDouble() ?? 0;
          final h = (meta['deviceHeight'] as num?)?.toDouble() ?? 0;
          if (w > 0 && h > 0) _cssSize = ui.Size(w, h);
        }
        _ingest(base64Decode(data));
      }
    }
  }

  void _onClosed() {
    if (_stopped) return;
    _lost = true;
    notifyListeners();
  }

  void _ingest(Uint8List bytes) {
    _frames++;
    if (_decoding) {
      _queued = bytes; // keep only the newest while a decode is running
      return;
    }
    unawaited(_decode(bytes));
  }

  Future<void> _decode(Uint8List bytes) async {
    _decoding = true;
    try {
      var next = bytes;
      while (true) {
        ui.Codec? codec;
        try {
          codec = await ui.instantiateImageCodec(next);
          final frame = await codec.getNextFrame();
          if (_stopped) {
            frame.image.dispose();
            return;
          }
          final old = _image;
          _image = frame.image;
          old?.dispose();
          notifyListeners();
        } catch (_) {
          // A corrupt frame is skipped; the next one replaces it.
        } finally {
          codec?.dispose();
        }
        final queued = _queued;
        if (queued == null) break;
        _queued = null;
        next = queued;
      }
    } finally {
      _decoding = false;
    }
  }

  Future<void> _refreshMetrics() async {
    if (_stopped || _session == null) return;
    try {
      final m = await _t.send('Page.getLayoutMetrics', null, _session);
      final v = m['cssVisualViewport'] ?? m['visualViewport'];
      if (v is Map) {
        final w = (v['clientWidth'] as num?)?.toDouble() ?? 0;
        final h = (v['clientHeight'] as num?)?.toDouble() ?? 0;
        if (w > 0 && h > 0) _cssSize = ui.Size(w, h);
      }
    } catch (_) {}
  }

  void _beginPolling() {
    if (_polling || _stopped) return;
    _polling = true;
    notifyListeners();
    unawaited(_pollLoop());
  }

  Future<void> _pollLoop() async {
    while (!_stopped && !_lost) {
      try {
        final r = await _t.send('Page.captureScreenshot', {
          'format': 'jpeg',
          'quality': quality,
          'fromSurface': true,
        }, _session);
        final data = r['data'];
        if (data is String) _ingest(base64Decode(data));
      } catch (e) {
        if (_stopped) return;
        if (!_t.isOpen) {
          _onClosed();
          return;
        }
      }
      await Future<void>.delayed(pollInterval);
    }
  }

  // --- input -------------------------------------------------------------

  Future<void> _input(String method, Map<String, dynamic> params) async {
    final s = _session;
    if (s == null || _stopped) return;
    try {
      await _t.send(method, params, s);
    } catch (_) {}
  }

  /// [x],[y] are CSS pixels inside the page viewport.
  Future<void> mouse({
    required String type, // mousePressed | mouseReleased | mouseMoved
    required double x,
    required double y,
    String button = 'none',
    int buttons = 0,
    int clickCount = 0,
    int modifiers = 0,
  }) => _input('Input.dispatchMouseEvent', {
    'type': type,
    'x': x,
    'y': y,
    'button': button,
    'buttons': buttons,
    'clickCount': clickCount,
    'modifiers': modifiers,
  });

  Future<void> wheel({
    required double x,
    required double y,
    required double deltaX,
    required double deltaY,
    int modifiers = 0,
  }) => _input('Input.dispatchMouseEvent', {
    'type': 'mouseWheel',
    'x': x,
    'y': y,
    'deltaX': deltaX,
    'deltaY': deltaY,
    'modifiers': modifiers,
  });

  Future<void> key(Map<String, dynamic> params) =>
      _input('Input.dispatchKeyEvent', params);

  Future<void> insertText(String text) =>
      _input('Input.insertText', {'text': text});

  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    _firstFrameTimer?.cancel();
    _metricsTimer?.cancel();
    // Events are already ignored once _stopped is set, so there is no need to
    // wait for the subscription to finish cancelling before shutting down.
    unawaited(_sub?.cancel());
    final s = _session;
    if (s != null && _t.isOpen) {
      try {
        await _t.send('Page.stopScreencast', null, s);
      } catch (_) {}
      try {
        await _t.send('Target.detachFromTarget', {'sessionId': s});
      } catch (_) {}
    }
    _image?.dispose();
    _image = null;
  }

  @override
  void dispose() {
    unawaited(stop());
    super.dispose();
  }
}
