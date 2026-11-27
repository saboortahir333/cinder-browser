import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:saboor_browser/rendering/compat_input.dart';
import 'package:saboor_browser/rendering/compat_service.dart';
import 'package:saboor_browser/rendering/screencast_session.dart';

/// Shows one tab by streaming the browser engine's own frames and sending
/// pointer / keyboard input back over DevTools. It is meant to sit on top of
/// the normal `Webview` (which stays mounted underneath so the engine keeps
/// the right size) on machines where the normal frame capture is blank.
///
/// Only the visible tab streams: switching tabs replaces this widget, which
/// stops the previous tab's stream.
class CompatPageView extends StatefulWidget {
  const CompatPageView({
    super.key,
    required this.service,
    required this.tabId,
    required this.url,
    required this.mark,
    required this.background,
    required this.foreground,
    this.onEngaged,
  });

  final CompatRenderService service;
  final String tabId;
  final String url;

  /// Runs `window.name = marker` inside this tab's page.
  final Future<void> Function(String marker) mark;
  final Color background;
  final Color foreground;

  /// Called with true when streaming starts and false when it ends, so the
  /// caller can throttle the now-hidden default renderer.
  final ValueChanged<bool>? onEngaged;

  @override
  State<CompatPageView> createState() => _CompatPageViewState();
}

class _CompatPageViewState extends State<CompatPageView> {
  static const int _maxRestarts = 3;

  final FocusNode _focus = FocusNode(debugLabel: 'compat page');
  ScreencastSession? _session;
  String? _failure;
  bool _starting = false;
  int _restarts = 0;
  Size _size = Size.zero;
  double _dpr = 1;
  Timer? _resizeTimer;
  Timer? _restartTimer;
  bool _disposed = false;

  // Click counting and button tracking.
  int _clickCount = 0;
  DateTime _lastDownAt = DateTime.fromMillisecondsSinceEpoch(0);
  Offset _lastDownPos = Offset.zero;
  final Map<int, String> _pressed = {};

  // Hover / drag moves are coalesced so slow round trips never queue up.
  ({Offset local, int buttons})? _pendingMove;
  bool _moveInFlight = false;

  @override
  void dispose() {
    _disposed = true;
    _resizeTimer?.cancel();
    _restartTimer?.cancel();
    _endSession();
    _focus.dispose();
    super.dispose();
  }

  void _endSession() {
    final s = _session;
    _session = null;
    if (s != null) {
      s.removeListener(_onSession);
      s.dispose();
      widget.onEngaged?.call(false);
    }
  }

  // --- starting / restarting -------------------------------------------------

  Future<void> _start() async {
    if (_starting || _disposed) return;
    _starting = true;
    if (_failure != null && mounted) setState(() => _failure = null);
    ScreencastSession? session;
    try {
      final t = await widget.service.transport();
      if (t == null) {
        throw StateError('Could not reach the browser engine.');
      }
      final target = await widget.service.targetFor(
        tabId: widget.tabId,
        url: widget.url,
        mark: widget.mark,
      );
      if (target == null) {
        throw StateError('Could not find this tab in the browser engine.');
      }
      if (_disposed) return;
      session = ScreencastSession(t, target);
      await session.start(
        maxWidth: _px(_size.width),
        maxHeight: _px(_size.height),
      );
      if (_disposed) {
        session.dispose();
        return;
      }
      final error = session.error;
      if (error != null) {
        widget.service.forget(widget.tabId);
        session.dispose();
        throw StateError(error);
      }
      session.addListener(_onSession);
      setState(() => _session = session);
      widget.onEngaged?.call(true);
      session = null; // owned by the state now
    } catch (e) {
      session?.dispose();
      if (mounted) {
        setState(
          () => _failure = '$e'.replaceFirst(RegExp(r'^[A-Za-z ]*: '), ''),
        );
      }
    } finally {
      _starting = false;
    }
  }

  int _px(double logical) => (logical * _dpr).round().clamp(1, 4096);

  void _onSession() {
    final s = _session;
    if (s == null || _disposed || !s.lost) return;
    // This runs inside the session's own notifyListeners(); disposing it here
    // is forbidden, so the clean-up happens right after it returns.
    scheduleMicrotask(() => _handleLost(s));
  }

  void _handleLost(ScreencastSession lost) {
    if (_disposed || !identical(_session, lost)) return;
    // The engine target went away (renderer crash, tab re-created): drop the
    // cached id and attach again a moment later.
    widget.service.forget(widget.tabId);
    _endSession();
    if (_restarts >= _maxRestarts) {
      if (mounted) {
        setState(() => _failure = 'The page connection was lost.');
      }
      return;
    }
    _restarts++;
    if (mounted) setState(() {});
    _restartTimer?.cancel();
    _restartTimer = Timer(const Duration(milliseconds: 400), _start);
  }

  void _retry() {
    _restarts = 0;
    _start();
  }

  void _noteSize(Size size, double dpr) {
    if (size == _size && dpr == _dpr) return;
    final first = _size == Size.zero;
    _size = size;
    _dpr = dpr;
    if (first) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _start());
      return;
    }
    _resizeTimer?.cancel();
    _resizeTimer = Timer(const Duration(milliseconds: 250), () {
      _session?.resize(
        maxWidth: _px(_size.width),
        maxHeight: _px(_size.height),
      );
    });
  }

  // --- pointer ---------------------------------------------------------------

  /// Widget-local logical pixels -> page CSS pixels (accounts for page zoom).
  Offset _css(Offset local) {
    final css = _session?.cssSize ?? Size.zero;
    if (css.isEmpty || _size.isEmpty) return local;
    return Offset(
      local.dx * css.width / _size.width,
      local.dy * css.height / _size.height,
    );
  }

  double get _scale {
    final css = _session?.cssSize ?? Size.zero;
    return css.isEmpty || _size.isEmpty ? 1 : css.width / _size.width;
  }

  void _onDown(PointerDownEvent e) {
    _focus.requestFocus();
    final s = _session;
    if (s == null) return;
    final now = DateTime.now();
    final near = (e.localPosition - _lastDownPos).distance < 5;
    _clickCount = near && now.difference(_lastDownAt).inMilliseconds < 500
        ? _clickCount + 1
        : 1;
    _lastDownAt = now;
    _lastDownPos = e.localPosition;

    final buttons = e.kind == PointerDeviceKind.mouse ? e.buttons : 1;
    final button = cdpButtonName(buttons);
    _pressed[e.pointer] = button;
    final p = _css(e.localPosition);
    unawaited(
      s.mouse(
        type: 'mousePressed',
        x: p.dx,
        y: p.dy,
        button: button,
        buttons: buttons,
        clickCount: _clickCount,
        modifiers: currentCdpModifiers(),
      ),
    );
  }

  void _onUp(PointerUpEvent e) {
    final s = _session;
    final button = _pressed.remove(e.pointer);
    if (s == null || button == null) return;
    final p = _css(e.localPosition);
    unawaited(
      s.mouse(
        type: 'mouseReleased',
        x: p.dx,
        y: p.dy,
        button: button,
        buttons: 0,
        clickCount: _clickCount,
        modifiers: currentCdpModifiers(),
      ),
    );
  }

  void _onCancel(PointerCancelEvent e) {
    final s = _session;
    final button = _pressed.remove(e.pointer);
    if (s == null || button == null) return;
    final p = _css(e.localPosition);
    unawaited(s.mouse(type: 'mouseReleased', x: p.dx, y: p.dy, button: button));
  }

  void _onMove(PointerEvent e) {
    if (_session == null) return;
    _pendingMove = (local: e.localPosition, buttons: e.buttons);
    if (_moveInFlight) return;
    _moveInFlight = true;
    unawaited(_pumpMoves());
  }

  Future<void> _pumpMoves() async {
    try {
      while (_pendingMove != null && !_disposed) {
        final m = _pendingMove!;
        _pendingMove = null;
        final s = _session;
        if (s == null) break;
        final p = _css(m.local);
        await s.mouse(
          type: 'mouseMoved',
          x: p.dx,
          y: p.dy,
          button: m.buttons == 0 ? 'none' : cdpButtonName(m.buttons),
          buttons: m.buttons,
          modifiers: currentCdpModifiers(),
        );
      }
    } finally {
      _moveInFlight = false;
    }
  }

  void _onSignal(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    // Claim the scroll so no scrollable above this view also moves.
    GestureBinding.instance.pointerSignalResolver.register(e, (event) {
      final s = _session;
      if (s == null) return;
      final scroll = event as PointerScrollEvent;
      final p = _css(scroll.localPosition);
      final k = _scale;
      unawaited(
        s.wheel(
          x: p.dx,
          y: p.dy,
          deltaX: scroll.scrollDelta.dx * k,
          deltaY: scroll.scrollDelta.dy * k,
          modifiers: currentCdpModifiers(),
        ),
      );
    });
  }

  void _onPanZoom(PointerPanZoomUpdateEvent e) {
    final s = _session;
    if (s == null) return;
    final p = _css(e.localPosition);
    final k = _scale;
    // Touchpad fingers move opposite to the content they scroll.
    unawaited(
      s.wheel(
        x: p.dx,
        y: p.dy,
        deltaX: -e.panDelta.dx * k,
        deltaY: -e.panDelta.dy * k,
        modifiers: currentCdpModifiers(),
      ),
    );
  }

  // --- keyboard --------------------------------------------------------------

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final s = _session;
    if (s == null) return KeyEventResult.ignored;
    final forward = forwardKey(event, modifiers: currentCdpModifiers());
    switch (forward) {
      case KeySend(:final events):
        for (final params in events) {
          unawaited(s.key(params));
        }
        return KeyEventResult.handled;
      case KeyPaste():
        unawaited(_paste());
        return KeyEventResult.handled;
      case KeyIgnore():
        return KeyEventResult.ignored;
    }
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) return;
    await _session?.insertText(text);
  }

  // --- build -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final dpr = View.of(context).devicePixelRatio;
    return LayoutBuilder(
      builder: (context, constraints) {
        _noteSize(constraints.biggest, dpr);
        return Focus(
          focusNode: _focus,
          onKeyEvent: _onKey,
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: _onDown,
            onPointerUp: _onUp,
            onPointerCancel: _onCancel,
            onPointerMove: _onMove,
            onPointerHover: _onMove,
            onPointerSignal: _onSignal,
            onPointerPanZoomUpdate: _onPanZoom,
            child: ColoredBox(
              color: widget.background,
              child: SizedBox.expand(child: _content()),
            ),
          ),
        );
      },
    );
  }

  Widget _content() {
    final s = _session;
    if (s != null) {
      return ListenableBuilder(
        listenable: s,
        builder: (context, _) {
          final image = s.image;
          if (image == null) return _status('Getting the first frame…');
          return RawImage(
            image: image,
            fit: BoxFit.fill,
            filterQuality: FilterQuality.low,
          );
        },
      );
    }
    final failure = _failure;
    if (failure != null) {
      return _status(
        "Compatibility view couldn't start: $failure",
        retry: true,
      );
    }
    return _status('Starting compatibility view…', busy: true);
  }

  Widget _status(String text, {bool retry = false, bool busy = false}) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (busy)
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                color: widget.foreground.withValues(alpha: 0.6),
              ),
            ),
          if (busy) const SizedBox(height: 14),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: widget.foreground.withValues(alpha: 0.8),
              fontSize: 13,
            ),
          ),
          if (retry) ...[
            const SizedBox(height: 12),
            FilledButton(onPressed: _retry, child: const Text('Try again')),
          ],
        ],
      ),
    );
  }
}
