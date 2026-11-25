import 'package:flutter_test/flutter_test.dart';
import 'package:saboor_browser/services/app_services.dart';
import 'package:saboor_browser/services/bookmark_import.dart';
import 'package:saboor_browser/services/update_service.dart';

void main() {
  group('LaunchOptions.startUrl', () {
    test('accepts one http(s) address', () {
      expect(LaunchOptions.parse(['https://example.com/a?b=1']).startUrl, 'https://example.com/a?b=1');
      expect(LaunchOptions.parse(['--profile=work', 'http://a.test']).startUrl, 'http://a.test');
    });
    test('rejects other schemes and flags', () {
      for (final bad in ['javascript:alert(1)', 'file:///c:/x', 'data:text/html,hi', 'ftp://x/y', 'chrome://settings', '--private']) {
        expect(LaunchOptions.parse([bad]).startUrl, isNull, reason: bad);
      }
      expect(LaunchOptions.parse(['https://' + 'a' * 5000]).startUrl, isNull);
    });
  });

  group('UpdateService.parse', () {
    String rel(String tag, {String? url, bool pre = false}) =>
        '{"tag_name":"$tag","prerelease":$pre,"draft":false,"body":"notes",'
        '"html_url":"${url ?? 'https://github.com/saboortahir333/cinder-browser/releases/tag/$tag'}"}';
    test('newer stable release is reported', () {
      final u = UpdateService.parse(rel('v1.2.0'), current: '1.0.0');
      expect(u?.version, '1.2.0');
    });
    test('same, older, prerelease and foreign urls are ignored', () {
      expect(UpdateService.parse(rel('v1.0.0'), current: '1.0.0'), isNull);
      expect(UpdateService.parse(rel('v0.9'), current: '1.0.0'), isNull);
      expect(UpdateService.parse(rel('v2.0.0', pre: true), current: '1.0.0'), isNull);
      expect(UpdateService.parse(rel('v2.0.0', url: 'https://evil.example/x'), current: '1.0.0'), isNull);
      expect(UpdateService.parse('not json'), isNull);
      expect(UpdateService.parse(rel('v2.0.0-evil'), current: '1.0.0'), isNull);
    });
  });

  group('BookmarkImport', () {
    const html = '''<!DOCTYPE NETSCAPE-Bookmark-file-1>
<DL><p>
<DT><H3>Folder</H3><DL><p>
<DT><A HREF="https://example.com/?a=1&amp;b=2" ADD_DATE="1">Example &amp; Co</A>
<DT><A HREF='http://a.test/'><b>Bold</b> title</A>
<DT><A HREF="javascript:alert(1)">bad</A>
<DT><A HREF="file:///c:/secret">bad</A>
<DT><A HREF="https://example.com/?a=1&amp;b=2">dup</A>
</DL><p></DL>''';
    test('keeps web links, decodes entities, drops unsafe and duplicates', () {
      final r = BookmarkImport.parse(html);
      expect(r.map((b) => b.url), ['https://example.com/?a=1&b=2', 'http://a.test/']);
      expect(r.first.title, 'Example & Co');
      expect(r.last.title, 'Bold title');
    });
    test('empty input', () => expect(BookmarkImport.parse(''), isEmpty));
  });
}
