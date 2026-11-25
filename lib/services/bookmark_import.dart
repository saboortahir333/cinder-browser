class ImportedBookmark {
  const ImportedBookmark(this.title, this.url);
  final String title;
  final String url;
}

/// Parses the Netscape bookmark HTML file that Chrome, Edge, Firefox, Safari
/// and Brave all export ("Export bookmarks"). Pure text parsing: no HTML
/// engine, no scripts, no network.
class BookmarkImport {
  const BookmarkImport._();

  static const int maxBytes = 20 * 1024 * 1024;
  static const int maxItems = 10000;

  static final RegExp _anchor = RegExp(
    r'<A\s+([^>]*?)>(.*?)</A>',
    caseSensitive: false,
    dotAll: true,
  );
  static final RegExp _href = RegExp(
    r'''HREF\s*=\s*(?:"([^"]*)"|'([^']*)')''',
    caseSensitive: false,
  );

  static List<ImportedBookmark> parse(String html) {
    if (html.length > maxBytes) return const [];
    final out = <ImportedBookmark>[];
    final seen = <String>{};
    for (final m in _anchor.allMatches(html)) {
      final h = _href.firstMatch(m.group(1)!);
      final raw = h?.group(1) ?? h?.group(2);
      if (raw == null) continue;
      final url = _unescape(raw).trim();
      final uri = Uri.tryParse(url);
      // Web addresses only: javascript:, data:, file: and the like are dropped.
      if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https') || uri.host.isEmpty) {
        continue;
      }
      if (!seen.add(url)) continue;
      final title = _unescape(m.group(2)!.replaceAll(RegExp(r'<[^>]*>'), '')).trim();
      out.add(ImportedBookmark(title.isEmpty ? url : title, url));
      if (out.length >= maxItems) break;
    }
    return out;
  }

  static String _unescape(String s) => s
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'");
}
