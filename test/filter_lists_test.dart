import 'package:flutter_test/flutter_test.dart';
import 'package:saboor_browser/security/filter_lists.dart';
import 'package:saboor_browser/security/request_filter.dart';

void main() {
  test('host file parsing keeps only valid hosts', () {
    final s = FilterLists.parseHostFile(
      '# comment\n127.0.0.1 localhost\n127.0.0.1 Evil.Example.com\n0.0.0.0 bad_host!\n\nnonsense\n127.0.0.1 a.b-c.net\n',
    );
    expect(s, {'evil.example.com', 'a.b-c.net'});
  });

  test('warning page escapes the host', () {
    final html = RequestFilter.warningPage('malware', '<script>x</script>', 'https://x');
    expect(html.contains('<script>'), isFalse);
    expect(html.contains('&lt;script&gt;'), isTrue);
  });
}
