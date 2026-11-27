import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saboor_browser/rendering/cdp_connection.dart';
import 'package:saboor_browser/rendering/compat_mode.dart';
import 'package:saboor_browser/rendering/compat_page_view.dart';
import 'package:saboor_browser/rendering/compat_service.dart';

/// A 1x1 PNG, standing in for a screencast frame.
const _png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

class Call {
  Call(this.method, this.params, this.session);
  final String method;
  final Map<String, dynamic>? params;
  final String? session;
}

class FakeCdp implements CdpTransport {
  final calls = <Call>[];
  final _events = StreamController<CdpEvent>.broadcast();
  bool hasTarget = true;
  bool open = true;
  int _sessions = 0;

  Iterable<Call> of(String method) => calls.where((c) => c.method == method);

  String get screencastSession => of('Page.startScreencast').last.session!;

  void emit(String method, Map<String, dynamic> params, {String? session}) =>
      _events.add(CdpEvent(method, params, session));

  @override
  Future<Map<String, dynamic>> send(
    String method, [
    Map<String, dynamic>? params,
    String? sessionId,
  ]) async {
    calls.add(Call(method, params, sessionId));
    switch (method) {
      case 'Target.getTargets':
        return {
          'targetInfos': hasTarget
              ? [
                  {'targetId': 'T1', 'type': 'page', 'url': 'https://x.test/'},
                  {
                    'targetId': 'DT',
                    'type': 'page',
                    'url': 'devtools://devtools/x',
                  },
                ]
              : <Object>[],
        };
      case 'Target.getTargetInfo':
        return hasTarget ? {'targetInfo': {}} : {};
      case 'Target.attachToTarget':
        return {'sessionId': 'S${++_sessions}'};
      case 'Runtime.evaluate':
        return {
          'result': {'value': 'cinder-tab:tab1'},
        };
      case 'Page.getLayoutMetrics':
        return {
          'cssVisualViewport': {'clientWidth': 500.0, 'clientHeight': 250.0},
        };
      default:
        return {};
    }
  }

  @override
  Stream<CdpEvent> get events => _events.stream;
  @override
  bool get isOpen => open;
  @override
  Future<void> close() async => open = false;
}

Widget _app(
  CompatRenderService service, {
  List<String>? marks,
  List<bool>? engaged,
}) => MaterialApp(
  home: Scaffold(
    body: CompatPageView(
      service: service,
      tabId: 'tab1',
      url: 'https://x.test/',
      mark: (m) async => marks?.add(m),
      background: Colors.black,
      foreground: Colors.white,
      onEngaged: engaged?.add,
    ),
  ),
);

/// Lets the fake's futures, the post-frame start and any timers run.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void _bigWindow(WidgetTester tester) {
  tester.view.physicalSize = const Size(1000, 500);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 3));
}

void main() {
  group('CompatPageView', () {
    testWidgets('marks the tab, finds it and streams frames into the view', (
      tester,
    ) async {
      _bigWindow(tester);
      final fake = FakeCdp();
      final service = CompatRenderService(port: 1, connect: (_) async => fake);
      final marks = <String>[];
      final engaged = <bool>[];
      await tester.pumpWidget(_app(service, marks: marks, engaged: engaged));
      expect(find.text('Starting compatibility view…'), findsOneWidget);
      await _settle(tester);

      expect(marks, ['cinder-tab:tab1']);
      final start = fake.of('Page.startScreencast').single;
      expect(start.params!['maxWidth'], 1000);
      expect(start.params!['maxHeight'], 500);
      expect(engaged, [true]);
      expect(find.text('Getting the first frame…'), findsOneWidget);

      // The engine pushes a frame: it is decoded, shown, and acknowledged.
      fake.emit('Page.screencastFrame', {
        'data': _png,
        'sessionId': 7,
        'metadata': {'deviceWidth': 500, 'deviceHeight': 250},
      }, session: fake.screencastSession);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump();
      expect(find.byType(RawImage), findsOneWidget);
      expect(fake.of('Page.screencastFrameAck').single.params!['sessionId'], 7);

      await _unmount(tester);
      expect(engaged, [true, false]);
      expect(
        fake.calls.map((c) => c.method).toList(),
        contains('Page.stopScreencast'),
      );
    });

    testWidgets('a click lands at the right page position (page zoom)', (
      tester,
    ) async {
      _bigWindow(tester);
      final fake = FakeCdp();
      final service = CompatRenderService(port: 1, connect: (_) async => fake);
      await tester.pumpWidget(_app(service));
      await _settle(tester);

      // The page's CSS viewport is 500x250 but the view is 1000x500 logical
      // px (a 200% page zoom): a click at (200, 100) is CSS (100, 50).
      await tester.tapAt(const Offset(200, 100));
      await tester.pump();

      final press = fake
          .of('Input.dispatchMouseEvent')
          .firstWhere((c) => c.params!['type'] == 'mousePressed');
      expect(press.params!['x'], closeTo(100, 0.01));
      expect(press.params!['y'], closeTo(50, 0.01));
      expect(press.params!['button'], 'left');
      expect(press.params!['clickCount'], 1);
      expect(press.session, fake.screencastSession);
      expect(
        fake
            .of('Input.dispatchMouseEvent')
            .any((c) => c.params!['type'] == 'mouseReleased'),
        isTrue,
      );
      await _unmount(tester);
    });

    testWidgets('the wheel scrolls the page, scaled to page pixels', (
      tester,
    ) async {
      _bigWindow(tester);
      final fake = FakeCdp();
      final service = CompatRenderService(port: 1, connect: (_) async => fake);
      await tester.pumpWidget(_app(service));
      await _settle(tester);

      final mouse = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(mouse.hover(const Offset(200, 200)));
      await tester.sendEventToBinding(mouse.scroll(const Offset(0, 100)));

      final wheel = fake
          .of('Input.dispatchMouseEvent')
          .firstWhere((c) => c.params!['type'] == 'mouseWheel');
      expect(wheel.params!['x'], closeTo(100, 0.01));
      expect(wheel.params!['y'], closeTo(100, 0.01));
      expect(wheel.params!['deltaY'], closeTo(50, 0.01));
      await _unmount(tester);
    });

    testWidgets('typing reaches the page; Ctrl+V pastes the clipboard', (
      tester,
    ) async {
      _bigWindow(tester);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async =>
            call.method == 'Clipboard.getData' ? {'text': 'pasted text'} : null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final fake = FakeCdp();
      final service = CompatRenderService(port: 1, connect: (_) async => fake);
      await tester.pumpWidget(_app(service));
      await _settle(tester);

      await tester.tapAt(const Offset(200, 100)); // focuses the view
      await tester.pump();

      await simulateKeyDownEvent(LogicalKeyboardKey.keyA, character: 'a');
      await simulateKeyUpEvent(LogicalKeyboardKey.keyA);
      final keys = fake.of('Input.dispatchKeyEvent').toList();
      expect(keys.first.params!['type'], 'keyDown');
      expect(keys.first.params!['text'], 'a');
      expect(keys.last.params!['type'], 'keyUp');

      // An app shortcut (Ctrl+T) is not swallowed by the page view.
      final before = fake.of('Input.dispatchKeyEvent').length;
      await simulateKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await simulateKeyDownEvent(LogicalKeyboardKey.keyT);
      await simulateKeyUpEvent(LogicalKeyboardKey.keyT);
      expect(fake.of('Input.dispatchKeyEvent').length, before);

      // Ctrl+V inserts the clipboard text.
      await simulateKeyDownEvent(LogicalKeyboardKey.keyV);
      await tester.pump();
      await simulateKeyUpEvent(LogicalKeyboardKey.keyV);
      await simulateKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(fake.of('Input.insertText').single.params!['text'], 'pasted text');
      await _unmount(tester);
    });

    testWidgets('says so, and can retry, when the tab cannot be found', (
      tester,
    ) async {
      _bigWindow(tester);
      final fake = FakeCdp()..hasTarget = false;
      final service = CompatRenderService(port: 1, connect: (_) async => fake);
      await tester.pumpWidget(_app(service));
      await _settle(tester);

      expect(
        find.textContaining("Compatibility view couldn't start"),
        findsOneWidget,
      );
      expect(find.textContaining('Could not find this tab'), findsOneWidget);
      expect(fake.of('Page.startScreencast'), isEmpty);

      fake.hasTarget = true;
      await tester.tap(find.text('Try again'));
      await _settle(tester);
      expect(fake.of('Page.startScreencast'), hasLength(1));
      expect(find.text('Getting the first frame…'), findsOneWidget);
      await _unmount(tester);
    });

    testWidgets('says so when the browser engine cannot be reached', (
      tester,
    ) async {
      _bigWindow(tester);
      final service = CompatRenderService(port: 1, connect: (_) async => null);
      await tester.pumpWidget(_app(service));
      await _settle(tester);
      expect(find.textContaining('Could not reach'), findsOneWidget);
      await _unmount(tester);
    });

    testWidgets('re-attaches when the engine target goes away', (tester) async {
      _bigWindow(tester);
      final fake = FakeCdp();
      final service = CompatRenderService(port: 1, connect: (_) async => fake);
      await tester.pumpWidget(_app(service));
      await _settle(tester);
      expect(fake.of('Page.startScreencast'), hasLength(1));

      fake.emit('Target.detachedFromTarget', {
        'sessionId': fake.screencastSession,
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await _settle(tester);
      expect(fake.of('Page.startScreencast'), hasLength(2));
      await _unmount(tester);
    });
  });

  group('compat mode decision', () {
    bool decide(
      CompatPreference p, {
      bool remote = false,
      bool soft = false,
      bool attach = true,
    }) => shouldUseCompat(
      p,
      remoteSession: remote,
      softwareGpu: soft,
      canAttach: attach,
    );

    test('auto turns on only where capture is known to fail', () {
      expect(decide(CompatPreference.auto), isFalse);
      expect(decide(CompatPreference.auto, remote: true), isTrue);
      expect(decide(CompatPreference.auto, soft: true), isTrue);
    });

    test('the user preference overrides detection', () {
      expect(decide(CompatPreference.on), isTrue);
      expect(decide(CompatPreference.off, remote: true, soft: true), isFalse);
    });

    test('without a DevTools port it can never be used', () {
      expect(decide(CompatPreference.on, attach: false), isFalse);
      expect(
        decide(CompatPreference.auto, remote: true, attach: false),
        isFalse,
      );
    });

    test('parses and stores the preference', () {
      expect(CompatPreference.parse(null), CompatPreference.auto);
      expect(CompatPreference.parse('garbage'), CompatPreference.auto);
      expect(CompatPreference.parse('on'), CompatPreference.on);
      expect(CompatPreference.parse('off'), CompatPreference.off);
      for (final p in CompatPreference.values) {
        expect(CompatPreference.parse(p.storageValue), p);
      }
    });

    test('detects the forced software-rendering switch', () {
      expect(softwareRenderingRequested({'CINDER_DISABLE_GPU': '1'}), isTrue);
      expect(softwareRenderingRequested({'CINDER_DISABLE_GPU': '0'}), isFalse);
      expect(softwareRenderingRequested(const {}), isFalse);
    });

    test('remote-session detection runs against the real Win32 API', () {
      // True inside Remote Desktop, false on a local console; either way it
      // must answer without throwing.
      expect(isRemoteSession(), isA<bool>());
    });
  });

  group('CompatRenderService', () {
    test('reuses a live target and re-finds a dead one', () async {
      final fake = FakeCdp();
      final service = CompatRenderService(port: 1, connect: (_) async => fake);
      var marks = 0;
      Future<void> mark(String _) async => marks++;

      expect(await service.targetFor(tabId: 'tab1', url: '', mark: mark), 'T1');
      expect(marks, 1);
      // Cached and still alive: no second scan.
      expect(await service.targetFor(tabId: 'tab1', url: '', mark: mark), 'T1');
      expect(marks, 1);

      // The target vanished: it is searched for again.
      fake.hasTarget = false;
      expect(
        await service.targetFor(tabId: 'tab1', url: '', mark: mark),
        isNull,
      );
      expect(marks, 2);
    });

    test('a failed connection does not wedge later attempts', () async {
      var attempts = 0;
      final fake = FakeCdp();
      final service = CompatRenderService(
        port: 1,
        connect: (_) async {
          attempts++;
          if (attempts == 1) throw StateError('engine not ready');
          return fake;
        },
      );
      expect(await service.transport(), isNull);
      expect(await service.transport(), same(fake));
    });
  });
}
