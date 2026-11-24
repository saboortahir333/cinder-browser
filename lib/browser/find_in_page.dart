import 'dart:convert';

/// Find-in-page implemented with the CSS Custom Highlight API: matches are
/// highlighted without touching the page's DOM, and the user's query is only
/// ever embedded as a JSON string literal (no injection into the script).
class FindInPage {
  FindInPage._();

  static const int maxQueryLength = 200;
  static const int maxMatches = 5000;

  /// Searches and activates match number [index] (0-based, wraps).
  /// Resolves to a JSON string: {"count":N,"index":I}.
  static String searchScript(
    String query, {
    int index = 0,
    bool caseSensitive = false,
  }) {
    final q = jsonEncode(_clean(query));
    final i = index < 0 ? 0 : index;
    return '''
(function () {
  var query = $q, idx = $i, cs = ${caseSensitive ? 'true' : 'false'};
  var MAX = $maxMatches;
  try {
    if (!window.CSS || !CSS.highlights || typeof Highlight === 'undefined') {
      return JSON.stringify({count: -1, index: 0});
    }
    CSS.highlights.delete('cinder-find');
    CSS.highlights.delete('cinder-find-active');
    if (!query) return JSON.stringify({count: 0, index: 0});
    if (!window.__cinderFindSheet) {
      var sheet = new CSSStyleSheet();
      sheet.replaceSync('::highlight(cinder-find){background:#ffe58a;color:#000}' +
        '::highlight(cinder-find-active){background:#ff9632;color:#000}');
      document.adoptedStyleSheets = document.adoptedStyleSheets.concat([sheet]);
      window.__cinderFindSheet = sheet;
    }
    var needle = cs ? query : query.toLowerCase();
    var ranges = [];
    var walker = document.createTreeWalker(document.body || document.documentElement,
      NodeFilter.SHOW_TEXT, {
        acceptNode: function (n) {
          var p = n.parentElement;
          if (!p) return NodeFilter.FILTER_REJECT;
          var tag = p.tagName;
          if (tag === 'SCRIPT' || tag === 'STYLE' || tag === 'NOSCRIPT' || tag === 'TEMPLATE')
            return NodeFilter.FILTER_REJECT;
          if (p.checkVisibility && !p.checkVisibility()) return NodeFilter.FILTER_REJECT;
          return NodeFilter.FILTER_ACCEPT;
        }
      });
    var node;
    while ((node = walker.nextNode()) && ranges.length < MAX) {
      var text = cs ? node.nodeValue : node.nodeValue.toLowerCase();
      var from = 0, at;
      while ((at = text.indexOf(needle, from)) !== -1 && ranges.length < MAX) {
        var r = new Range();
        r.setStart(node, at);
        r.setEnd(node, at + needle.length);
        ranges.push(r);
        from = at + Math.max(needle.length, 1);
      }
    }
    if (!ranges.length) return JSON.stringify({count: 0, index: 0});
    idx = ((idx % ranges.length) + ranges.length) % ranges.length;
    CSS.highlights.set('cinder-find', new Highlight(...ranges));
    CSS.highlights.set('cinder-find-active', new Highlight(ranges[idx]));
    var el = ranges[idx].startContainer.parentElement;
    if (el && el.scrollIntoView) el.scrollIntoView({block: 'center', inline: 'nearest'});
    return JSON.stringify({count: ranges.length, index: idx});
  } catch (e) {
    return JSON.stringify({count: -1, index: 0});
  }
})()
''';
  }

  static const String clearScript = '''
(function () {
  try {
    if (window.CSS && CSS.highlights) {
      CSS.highlights.delete('cinder-find');
      CSS.highlights.delete('cinder-find-active');
    }
  } catch (e) {}
  return '';
})()
''';

  /// Parses the page's reply defensively: the page can alter globals, so the
  /// result is treated as untrusted and clamped.
  static FindResult parse(Object? raw) {
    try {
      var value = raw;
      if (value is String) value = jsonDecode(value);
      if (value is String) value = jsonDecode(value);
      if (value is Map) {
        final count = value['count'];
        final index = value['index'];
        if (count is int && index is int) {
          if (count < 0) return const FindResult.unsupported();
          final c = count.clamp(0, maxMatches);
          return FindResult(c, c == 0 ? 0 : index.clamp(0, c - 1));
        }
      }
    } catch (_) {}
    return const FindResult.unsupported();
  }

  static String _clean(String raw) {
    final b = StringBuffer();
    for (final r in raw.runes) {
      if (r < 0x20 || (r >= 0x7F && r <= 0x9F)) continue;
      b.writeCharCode(r);
    }
    final s = b.toString();
    return s.length > maxQueryLength ? s.substring(0, maxQueryLength) : s;
  }
}

class FindResult {
  const FindResult(this.count, this.index) : supported = true;
  const FindResult.unsupported() : count = 0, index = 0, supported = false;

  final int count;
  final int index;
  final bool supported;

  String get label => !supported
      ? 'Find is unavailable on this page'
      : count == 0
      ? 'No matches'
      : '${index + 1} of $count';
}
