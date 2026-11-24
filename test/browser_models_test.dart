import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:saboor_browser/browser/find_in_page.dart';
import 'package:saboor_browser/browser/page_zoom.dart';
import 'package:saboor_browser/browser/session_model.dart';

void main() {
  group('session restore validation', () {
    test('round-trips a normal session', () {
      const s = SessionSnapshot(
        activeIndex: 1,
        groups: [TabGroupSnapshot(id: 'g1', name: 'Work', colorIndex: 1)],
        tabs: [
          TabSnapshot(url: 'https://a.example/', title: 'A', pinned: true),
          TabSnapshot(url: 'https://b.example/x?y=1', title: 'B', groupId: 'g1'),
        ],
      );
      final back = SessionSnapshot.tryFromJson(
        jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>,
      )!;
      expect(back.activeIndex, 1);
      expect(back.tabs[0].pinned, isTrue);
      expect(back.tabs[1].groupId, 'g1');
      expect(back.tabs[1].url, 'https://b.example/x?y=1');
    });

    test('tampered cloud data cannot smuggle in dangerous URLs', () {
      final evil = {
        'v': 1,
        'active': 0,
        'tabs': [
          {'url': 'javascript:alert(document.cookie)', 'title': 'x'},
          {'url': 'data:text/html,<script>1</script>', 'title': 'x'},
          {'url': 'file:///C:/Windows/win.ini', 'title': 'x'},
          {'url': 'view-source:https://a.example', 'title': 'x'},
          {'url': 'ms-msdt:/id PCWDiagnostic', 'title': 'x'},
          {'url': 'https://paypal.com@evil.example', 'title': 'x'},
          {'url': 42, 'title': 'x'},
          'not even a map',
          {'url': 'https://ok.example/', 'title': 'fine'},
        ],
      };
      final s = SessionSnapshot.tryFromJson(evil)!;
      expect(s.tabs.map((t) => t.url), ['https://ok.example/']);
    });

    test('rejects wrong version, empty or malformed sessions', () {
      expect(SessionSnapshot.tryFromJson(null), isNull);
      expect(SessionSnapshot.tryFromJson({'v': 2, 'tabs': []}), isNull);
      expect(SessionSnapshot.tryFromJson({'v': 1, 'tabs': 'x'}), isNull);
      expect(SessionSnapshot.tryFromJson({'v': 1, 'tabs': []}), isNull);
    });

    test('caps tab count and clamps the active index', () {
      final many = {
        'v': 1,
        'active': 99999,
        'tabs': [
          for (var i = 0; i < 1000; i++) {'url': 'https://e.example/$i', 'title': 't'},
        ],
      };
      final s = SessionSnapshot.tryFromJson(many)!;
      expect(s.tabs.length, SessionSnapshot.maxTabs);
      expect(s.activeIndex, SessionSnapshot.maxTabs - 1);
    });

    test('titles are stripped of control and bidi characters and capped', () {
      final t = TabSnapshot.tryFromJson({
        'url': 'https://a.example',
        'title': 'Pay\u202Epal\u0000 \u200Bsecure${'x' * 500}',
      })!;
      expect(t.title.contains('\u202E'), isFalse);
      expect(t.title.contains('\u0000'), isFalse);
      expect(t.title.length, lessThanOrEqualTo(200));
    });

    test('groups are validated and dangling group references removed', () {
      final s = SessionSnapshot.tryFromJson({
        'v': 1,
        'active': 0,
        'groups': [
          {'id': 'g1', 'name': 'Work\u202E', 'color': 99},
          {'id': '../bad', 'name': 'x', 'color': 1},
          {'id': 'g1', 'name': 'dup', 'color': 2},
        ],
        'tabs': [
          {'url': 'https://a.example', 'title': 'a', 'group': 'g1'},
          {'url': 'https://b.example', 'title': 'b', 'group': 'ghost'},
        ],
      })!;
      expect(s.groups.length, 1);
      expect(s.groups.single.colorIndex, TabGroupSnapshot.colorCount - 1);
      expect(s.groups.single.name.contains('\u202E'), isFalse);
      expect(s.tabs[0].groupId, 'g1');
      expect(s.tabs[1].groupId, isNull);
    });

    test('bad group ids are dropped', () {
      final t = TabSnapshot.tryFromJson({
        'url': 'https://a.example',
        'title': 't',
        'group': '<script>',
      })!;
      expect(t.groupId, isNull);
    });
  });

  group('closed tab stack', () {
    test('reopens in reverse order, skips blanks, is bounded', () {
      final stack = ClosedTabStack(capacity: 3);
      stack.push(const TabSnapshot(url: '', title: 'blank'));
      for (var i = 1; i <= 5; i++) {
        stack.push(TabSnapshot(url: 'https://e.example/$i', title: '$i'));
      }
      expect(stack.length, 3);
      expect(stack.pop()!.title, '5');
      expect(stack.pop()!.title, '4');
      expect(stack.pop()!.title, '3');
      expect(stack.pop(), isNull);
    });
  });

  group('zoom', () {
    test('steps through Chrome-style levels and stays in range', () {
      expect(PageZoom.zoomIn(1.0), 1.1);
      expect(PageZoom.zoomOut(1.0), 0.9);
      expect(PageZoom.zoomIn(5.0), 5.0);
      expect(PageZoom.zoomOut(0.25), 0.25);
      expect(PageZoom.clamp(double.nan), 1.0);
      expect(PageZoom.clamp(99), 5.0);
      expect(PageZoom.clamp(-3), 0.25);
    });

    test('remembers per host, forgets at 100%, ignores tampered data', () {
      final m = SiteZoomMemory();
      m.set('Example.com', 1.5);
      expect(m.levelFor('example.com'), 1.5);
      m.set('example.com', 1.0);
      expect(m.levelFor('example.com'), 1.0);
      final loaded = SiteZoomMemory.fromJson({
        'levels': {'a.example': 2.0, 'b.example': 9999, 'c.example': 'x', 3: 1.2},
      });
      expect(loaded.levelFor('a.example'), 2.0);
      expect(loaded.levelFor('b.example'), 5.0);
      expect(loaded.levelFor('c.example'), 1.0);
    });

    test('memory is bounded', () {
      final m = SiteZoomMemory();
      for (var i = 0; i < SiteZoomMemory.maxSites + 50; i++) {
        m.set('h$i.example', 1.5);
      }
      expect((m.toJson()['levels'] as Map).length, SiteZoomMemory.maxSites);
    });
  });

  group('find in page', () {
    test('query is embedded as an inert JSON literal', () {
      const hostile = '"; alert(1); ("</script><img src=x onerror=alert(2)>\\';
      final script = FindInPage.searchScript(hostile);
      expect(script.contains(jsonEncode(hostile)), isTrue);
      // The raw, unescaped breakout sequence must not appear.
      expect(script.contains('"; alert(1); ("'), isFalse);
    });

    test('control characters and excessive length are removed', () {
      final script = FindInPage.searchScript('a\u0000b${'z' * 1000}');
      expect(script.contains('\\u0000'), isFalse);
      expect(script.length, lessThan(5000));
    });

    test('page replies are parsed defensively', () {
      expect(FindInPage.parse('{"count":3,"index":1}').label, '2 of 3');
      expect(FindInPage.parse('{"count":0,"index":0}').label, 'No matches');
      expect(FindInPage.parse('{"count":-1,"index":0}').supported, isFalse);
      expect(FindInPage.parse('garbage').supported, isFalse);
      expect(FindInPage.parse(null).supported, isFalse);
      expect(FindInPage.parse({'count': 999999, 'index': 999999}).count, FindInPage.maxMatches);
      expect(FindInPage.parse('{"count":2,"index":50}').index, 1);
    });
  });
}
