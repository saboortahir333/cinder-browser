import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saboor_browser/rendering/cdp_connection.dart';
import 'package:saboor_browser/rendering/compat_input.dart';
import 'package:saboor_browser/rendering/page_target_finder.dart';
import 'package:saboor_browser/rendering/screencast_session.dart';

/// Real headless Chrome speaking the same DevTools protocol WebView2 exposes.
/// Skipped when Chrome isn't installed.
String? _chromePath() {
  const candidates = [
    r'C:\Program Files\Google\Chrome\Application\chrome.exe',
    r'C:\Program Files (x86)\Google\Chrome\Application\chrome.exe',
    '/usr/bin/google-chrome',
    '/usr/bin/chromium',
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  ];
  for (final c in candidates) {
    if (File(c).existsSync()) return c;
  }
  return null;
}

const _pageHtml = '''<!doctype html><meta charset="utf-8">
<body style="margin:0;background:#e05a00">
<button id="b" style="position:absolute;left:100px;top:100px;width:200px;height:80px"
  onclick="document.title='clicked'">go</button>
<input id="i" style="position:absolute;left:100px;top:250px;width:300px;height:30px">
<div style="height:3000px"></div>''';

/// Hides screencast so the polling fallback is the only way frames can arrive.
class _NoScreencast implements CdpTransport {
  _NoScreencast(this.inner);
  final CdpTransport inner;

  @override
  Future<Map<String, dynamic>> send(
    String method, [
    Map<String, dynamic>? params,
    String? sessionId,
  ]) {
    if (method == 'Page.startScreencast') return Future.value(const {});
    return inner.send(method, params, sessionId);
  }

  @override
  Stream<CdpEvent> get events => inner.events;
  @override
  bool get isOpen => inner.isOpen;
  @override
  Future<void> close() => inner.close();
}

KeyDownEvent _down(
  PhysicalKeyboardKey p,
  LogicalKeyboardKey l, [
  String? character,
]) => KeyDownEvent(
  physicalKey: p,
  logicalKey: l,
  character: character,
  timeStamp: Duration.zero,
);

void main() {
  final chrome = _chromePath();
  late Process proc;
  late Directory tmp;
  late CdpConnection cdp;
  late String pageTarget;
  late String pageSession;

  Future<dynamic> eval(String expr) async {
    final r = await cdp.send('Runtime.evaluate', {
      'expression': expr,
      'returnByValue': true,
    }, pageSession);
    return (r['result'] as Map)['value'];
  }

  /// Polls until [ok] holds (page-side effects of input are asynchronous).
  Future<void> until(
    FutureOr<bool> Function() ok, {
    Duration timeout = const Duration(seconds: 8),
    String? what,
  }) async {
    final end = DateTime.now().add(timeout);
    while (!await ok()) {
      if (DateTime.now().isAfter(end)) {
        fail('timed out waiting for ${what ?? 'condition'}');
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  setUpAll(() async {
    if (chrome == null) return;
    // The widget-test binding answers every HTTP request with 400; this test
    // talks to a real browser on loopback.
    HttpOverrides.global = null;
    tmp = Directory.systemTemp.createTempSync('cinder_cast_');
    final html = File('${tmp.path}${Platform.pathSeparator}page.html')
      ..writeAsStringSync(_pageHtml);
    final port = 9300 + Random().nextInt(500);
    proc = await Process.start(chrome, [
      '--headless=new',
      '--remote-debugging-port=$port',
      '--user-data-dir=${tmp.path}${Platform.pathSeparator}profile',
      '--no-first-run',
      '--no-default-browser-check',
      '--window-size=800,600',
      'about:blank',
    ]);
    unawaited(proc.stdout.drain<void>());
    unawaited(proc.stderr.drain<void>());

    CdpConnection? c;
    for (var i = 0; i < 60 && c == null; i++) {
      c = await CdpConnection.connect(port);
      if (c == null) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    }
    cdp = c!;

    final targets = await cdp.send('Target.getTargets');
    pageTarget =
        (targets['targetInfos'] as List).cast<Map>().firstWhere(
              (t) => t['type'] == 'page',
            )['targetId']
            as String;
    pageSession =
        (await cdp.send('Target.attachToTarget', {
              'targetId': pageTarget,
              'flatten': true,
            }))['sessionId']
            as String;
    await cdp.send('Page.enable', null, pageSession);
    await cdp.send('Page.navigate', {'url': html.uri.toString()}, pageSession);
    await until(
      () async =>
          await eval(
            'document.readyState === "complete" && !!document.getElementById("b")',
          ) ==
          true,
      what: 'the test page to load',
      timeout: const Duration(seconds: 15),
    );
  });

  tearDownAll(() async {
    if (chrome == null) return;
    try {
      await cdp.close();
    } catch (_) {}
    proc.kill();
    await proc.exitCode.timeout(const Duration(seconds: 5), onTimeout: () => 0);
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  // Skipped (not failed) when Chrome isn't installed.
  final skip = chrome == null;

  testWidgets('streams real page frames that show the page', (tester) async {
    await tester.runAsync(() async {
      final s = ScreencastSession(cdp, pageTarget);
      await s.start(maxWidth: 800, maxHeight: 600);
      await until(() => s.image != null, what: 'first decoded frame');
      expect(s.error, isNull);
      expect(s.image!.width, greaterThan(100));
      expect(s.framesReceived, greaterThan(0));

      // The page background is #e05a00: sample a pixel away from the controls.
      final img = s.image!;
      final data = await img.toByteData();
      final i = ((img.height - 20) * img.width + (img.width - 20)) * 4;
      expect(data!.getUint8(i), greaterThan(190), reason: 'red channel');
      expect(data.getUint8(i + 1), inInclusiveRange(50, 130));
      expect(data.getUint8(i + 2), lessThan(60));

      expect(s.cssSize.width, greaterThan(100));
      await s.stop();
    });
  }, skip: skip);

  testWidgets('mouse clicks reach the page', (tester) async {
    await tester.runAsync(() async {
      await eval("document.title='start'");
      final s = ScreencastSession(cdp, pageTarget);
      await s.start(maxWidth: 800, maxHeight: 600);
      await s.mouse(type: 'mouseMoved', x: 150, y: 130);
      await s.mouse(
        type: 'mousePressed',
        x: 150,
        y: 130,
        button: 'left',
        buttons: 1,
        clickCount: 1,
      );
      await s.mouse(
        type: 'mouseReleased',
        x: 150,
        y: 130,
        button: 'left',
        clickCount: 1,
      );
      await until(
        () async => await eval('document.title') == 'clicked',
        what: 'the click to land',
      );
      await s.stop();
    });
  }, skip: skip);

  testWidgets('keys built from real Flutter key events reach a field', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await eval("document.getElementById('i').value=''");
      final s = ScreencastSession(cdp, pageTarget);
      await s.start(maxWidth: 800, maxHeight: 600);
      // Focus the input with a real click.
      await s.mouse(
        type: 'mousePressed',
        x: 200,
        y: 265,
        button: 'left',
        buttons: 1,
        clickCount: 1,
      );
      await s.mouse(
        type: 'mouseReleased',
        x: 200,
        y: 265,
        button: 'left',
        clickCount: 1,
      );

      Future<void> press(
        PhysicalKeyboardKey p,
        LogicalKeyboardKey l,
        String? ch,
      ) async {
        final up = KeyUpEvent(
          physicalKey: p,
          logicalKey: l,
          timeStamp: Duration.zero,
        );
        for (final ev in [_down(p, l, ch), up]) {
          final f = forwardKey(ev, modifiers: 0);
          if (f is KeySend) {
            for (final params in f.events) {
              await s.key(params);
            }
          }
        }
      }

      await press(PhysicalKeyboardKey.keyH, LogicalKeyboardKey.keyH, 'h');
      await press(PhysicalKeyboardKey.keyI, LogicalKeyboardKey.keyI, 'i');
      await press(PhysicalKeyboardKey.digit5, LogicalKeyboardKey.digit5, '5');
      await press(
        PhysicalKeyboardKey.backspace,
        LogicalKeyboardKey.backspace,
        null,
      );
      await until(
        () async => await eval("document.getElementById('i').value") == 'hi',
        what: 'typed text (with Backspace)',
      );

      // insertText is how paste and IME text are delivered.
      await s.insertText('!!');
      await until(
        () async => await eval("document.getElementById('i').value") == 'hi!!',
        what: 'inserted text',
      );
      await s.stop();
    });
  }, skip: skip);

  testWidgets('the wheel scrolls the page', (tester) async {
    await tester.runAsync(() async {
      await eval('window.scrollTo(0,0)');
      final s = ScreencastSession(cdp, pageTarget);
      await s.start(maxWidth: 800, maxHeight: 600);
      await s.wheel(x: 600, y: 400, deltaX: 0, deltaY: 300);
      await until(
        () async => ((await eval('window.scrollY')) as num) > 0,
        what: 'the page to scroll',
      );
      await s.stop();
    });
  }, skip: skip);

  testWidgets('falls back to screenshots when no screencast frame arrives', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final s = ScreencastSession(
        _NoScreencast(cdp),
        pageTarget,
        firstFrameTimeout: const Duration(milliseconds: 200),
      );
      await s.start(maxWidth: 800, maxHeight: 600);
      await until(() => s.image != null, what: 'a polled frame');
      expect(s.isPolling, isTrue);
      expect(s.image!.width, greaterThan(100));
      await s.stop();
    });
  }, skip: skip);

  testWidgets('finds the right tab among several by its marker', (
    tester,
  ) async {
    await tester.runAsync(() async {
      // A second tab that must NOT be picked.
      final other =
          (await cdp.send('Target.createTarget', {'url': 'about:blank'}))['targetId']
              as String;

      final found = await findPageTarget(
        cdp,
        marker: 'cinder-tab:abc',
        // Same effect as WebviewController.executeScript on the real tab.
        mark: () async => eval("window.name='cinder-tab:abc'"),
      );
      expect(found, pageTarget);
      expect(found, isNot(other));
      expect(await targetExists(cdp, pageTarget), isTrue);
      expect(await targetExists(cdp, 'no-such-target'), isFalse);

      // No marker anywhere and no URL hint: nothing is guessed.
      final none = await findPageTarget(
        cdp,
        marker: 'cinder-tab:missing',
        mark: () async {},
      );
      expect(none, isNull);

      await cdp.send('Target.closeTarget', {'targetId': other});
    });
  }, skip: skip);

  testWidgets("marking a tab leaves the page's own window.name intact", (
    tester,
  ) async {
    await tester.runAsync(() async {
      await eval("window.name='hello'");
      const marker = 'cinder-tab:keep';
      final found = await findPageTarget(
        cdp,
        marker: marker,
        // The same script the app runs through WebviewController.
        mark: () async => eval(
          "if(!window.name.startsWith('$marker|'))"
          "window.name='$marker|'+window.name;",
        ),
      );
      expect(found, pageTarget);
      await until(
        () async => await eval('window.name') == 'hello',
        what: 'the original window.name to be restored',
      );
      // Marking twice (e.g. a retry) must not stack prefixes.
      await findPageTarget(
        cdp,
        marker: marker,
        mark: () async => eval(
          "if(!window.name.startsWith('$marker|'))"
          "window.name='$marker|'+window.name;",
        ),
      );
      await until(
        () async => await eval('window.name') == 'hello',
        what: 'the name to be restored after a second find',
      );
    });
  }, skip: skip);

  test('only editing shortcuts are forwarded; the browser keeps the rest', () {
    // Ctrl+T / Ctrl+L belong to the browser.
    expect(
      forwardKey(
        _down(PhysicalKeyboardKey.keyT, LogicalKeyboardKey.keyT),
        modifiers: 2,
      ),
      isA<KeyIgnore>(),
    );
    // F12 belongs to the browser.
    expect(
      forwardKey(
        _down(PhysicalKeyboardKey.f12, LogicalKeyboardKey.f12),
        modifiers: 0,
      ),
      isA<KeyIgnore>(),
    );
    // Ctrl+C is an editing command for the page.
    final copy = forwardKey(
      _down(PhysicalKeyboardKey.keyC, LogicalKeyboardKey.keyC),
      modifiers: 2,
    );
    expect(copy, isA<KeySend>());
    expect((copy as KeySend).events.single['commands'], ['copy']);
    // Ctrl+V goes through the clipboard.
    expect(
      forwardKey(
        _down(PhysicalKeyboardKey.keyV, LogicalKeyboardKey.keyV),
        modifiers: 2,
      ),
      isA<KeyPaste>(),
    );
    // Enter carries a carriage return so forms react.
    final enter =
        forwardKey(
              _down(PhysicalKeyboardKey.enter, LogicalKeyboardKey.enter),
              modifiers: 0,
            )
            as KeySend;
    expect(enter.events.single['text'], '\r');
    expect(enter.events.single['windowsVirtualKeyCode'], 13);
    // A bare Shift press is not sent.
    expect(
      forwardKey(
        _down(PhysicalKeyboardKey.shiftLeft, LogicalKeyboardKey.shiftLeft),
        modifiers: 8,
      ),
      isA<KeyIgnore>(),
    );
    expect(cdpButtonName(1), 'left');
    expect(cdpButtonName(2), 'right');
    expect(cdpButtonName(4), 'middle');
    expect(cdpButtonName(0), 'none');
    expect(
      cdpModifiers(alt: true, ctrl: true, meta: false, shift: true),
      1 | 2 | 8,
    );
  });
}
