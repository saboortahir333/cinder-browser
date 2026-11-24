import 'package:flutter_test/flutter_test.dart';
import 'package:saboor_browser/browser/search_engines.dart';
import 'package:saboor_browser/browser/url_policy.dart';

void main() {
  const engine = SearchEngines.duckDuckGo;
  NavDecision omni(String s) => UrlPolicy.resolveOmnibox(s, engine);
  NavDecision check(String s, [NavSource src = NavSource.link]) =>
      UrlPolicy.checkNavigation(s, src);

  group('omnibox resolution', () {
    test('bare domains default to https', () {
      final d = omni('example.com/path?x=1');
      expect(d.kind, NavKind.web);
      expect(d.url, 'https://example.com/path?x=1');
    });

    test('localhost and private addresses default to http without warning spam', () {
      expect(omni('localhost:3000').url, 'http://localhost:3000');
      expect(omni('192.168.1.10/admin').url, 'http://192.168.1.10/admin');
      expect(omni('127.0.0.1:8080').kind, NavKind.web);
    });

    test('explicit http is allowed but flagged', () {
      final d = omni('http://example.com');
      expect(d.kind, NavKind.web);
      expect(d.warnings, contains(NavWarning.insecureHttp));
    });

    test('plain words become a search', () {
      final d = omni('how to bake bread');
      expect(d.kind, NavKind.search);
      expect(d.url, 'https://duckduckgo.com/?q=how+to+bake+bread');
    });

    test('search text cannot inject extra parameters or hosts', () {
      final d = omni('cats&evil=1#frag http://evil.example');
      expect(d.kind, NavKind.search);
      expect(d.uri!.host, 'duckduckgo.com');
      expect(d.uri!.queryParameters.keys, ['q']);
      expect(d.uri!.fragment, isEmpty);
    });

    test('file extensions are not mistaken for hosts', () {
      expect(omni('notes.txt something').kind, NavKind.search);
      expect(omni('hello').kind, NavKind.search);
    });
  });

  group('scheme allowlist (default deny)', () {
    test('code-execution and content-smuggling schemes are blocked', () {
      for (final s in [
        'javascript:alert(1)',
        'JaVaScRiPt:alert(1)',
        'javascript: alert(1)',
        'data:text/html,<script>alert(1)</script>',
        'vbscript:msgbox(1)',
        'blob:https://example.com/uuid',
        'filesystem:https://example.com/temporary/x',
      ]) {
        expect(omni(s).isBlocked, isTrue, reason: s);
        expect(check(s).isBlocked, isTrue, reason: s);
      }
    });

    test('Windows protocol-handler abuse is blocked', () {
      for (final s in [
        'ms-msdt:/id PCWDiagnostic /skip force /param "IT_RebrowseForFile=?"',
        'search-ms:query=foo&crumb=location:\\\\evil\\share',
        'ms-officecmd:{"x":1}',
        'calculator:',
        'mailto:a@b.c',
        'ftp://example.com/file',
        'chrome://settings',
        'edge://flags',
        'ssh://host',
      ]) {
        expect(check(s).isBlocked, isTrue, reason: s);
      }
    });

    test('whitespace / control / bidi tricks do not bypass the filter', () {
      for (final s in [
        'java\tscript:alert(1)',
        'java\nscript:alert(1)',
        '\u0000javascript:alert(1)',
        '\u202Ejavascript:alert(1)',
        'java\u200Bscript:alert(1)',
        ' \u0001 javascript:alert(1)',
      ]) {
        expect(check(s).isBlocked, isTrue, reason: s.codeUnits.toString());
        expect(omni(s).kind, isNot(NavKind.web), reason: s.codeUnits.toString());
      }
    });

    test('file: only from the address bar', () {
      expect(check('file:///C:/Users/a/b.html').isBlocked, isTrue);
      expect(check('file:///C:/a.html', NavSource.restore).isBlocked, isTrue);
      expect(check('file:///C:/a.html', NavSource.omnibox).kind, NavKind.localFile);
    });

    test('view-source only wraps http(s) and never comes from stored data', () {
      expect(check('view-source:https://example.com', NavSource.browser).kind, NavKind.viewSource);
      expect(check('view-source:https://example.com', NavSource.omnibox).kind, NavKind.viewSource);
      expect(check('view-source:javascript:alert(1)', NavSource.browser).isBlocked, isTrue);
      expect(check('view-source:file:///C:/a', NavSource.browser).isBlocked, isTrue);
      expect(check('view-source:https://example.com', NavSource.restore).isBlocked, isTrue);
      // A page-supplied link may never open a source view.
      expect(check('view-source:https://example.com', NavSource.link).isBlocked, isTrue);
    });

    test('about:blank is the only about: page', () {
      expect(check('about:blank').kind, NavKind.blank);
      expect(check('about:config').isBlocked, isTrue);
    });
  });

  group('phishing defences', () {
    test('userinfo impersonation is blocked', () {
      expect(check('https://paypal.com@evil.example/login').isBlocked, isTrue);
      expect(check('https://user:pw@example.com').isBlocked, isTrue);
    });

    test('bad ports and hosts are rejected', () {
      expect(check('https://example.com:99999').isBlocked, isTrue);
      expect(check('https://').isBlocked, isTrue);
      expect(check('https://exa mple.com').isBlocked, isTrue);
    });

    test('mixed-script hostnames are flagged as confusable', () {
      final d = check('https://p\u0430ypal.com'); // Cyrillic a
      expect(d.warnings, contains(NavWarning.internationalizedHost));
      expect(d.warnings, contains(NavWarning.confusableHost));
    });

    test('legitimate IDN is flagged as IDN but not confusable', () {
      final d = check('https://münchen.de');
      expect(d.warnings, contains(NavWarning.internationalizedHost));
      expect(d.warnings, isNot(contains(NavWarning.confusableHost)));
    });

    test('displayHost shows punycode for non-ASCII hosts', () {
      expect(UrlPolicy.displayHost('münchen.de'), 'xn--mnchen-3ya.de');
      expect(UrlPolicy.displayHost('bücher.example'), 'xn--bcher-kva.example');
      expect(UrlPolicy.displayHost('Example.COM'), 'example.com');
    });

    test('oversized input is refused', () {
      expect(check('https://example.com/${'a' * 9000}').isBlocked, isTrue);
      expect(omni('a' * 9000).isBlocked, isTrue);
    });
  });

  group('search engine templates', () {
    test('built-in engines are valid', () {
      for (final e in SearchEngines.builtIn) {
        expect(SearchEngine.validateTemplate(e.template), isNull, reason: e.id);
      }
    });

    test('unsafe custom templates are rejected', () {
      for (final t in [
        'http://insecure.example/?q=%s',
        'https://%s.evil.example/?q=1',
        'https://evil.example/%s?x=1',
        'https://u:p@evil.example/?q=%s',
        'https://evil.example/?q=%s&b=%s',
        'https://evil.example/?q=',
        'javascript:alert(%s)',
      ]) {
        expect(SearchEngine.validateTemplate(t), isNotNull, reason: t);
      }
      expect(SearchEngine.validateTemplate('https://s.example/find?query=%s'), isNull);
    });

    test('tampered stored custom engine falls back to default', () {
      expect(SearchEngines.customFromStored('x', 'http://evil/?q=%s'), isNull);
      expect(SearchEngines.byId('custom', custom: null), SearchEngines.defaultEngine);
      expect(SearchEngines.byId('nonsense'), SearchEngines.defaultEngine);
    });
  });
}
