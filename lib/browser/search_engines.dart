/// A search provider. Templates are HTTPS-only and contain exactly one `%s`.
class SearchEngine {
  const SearchEngine({
    required this.id,
    required this.name,
    required this.template,
    this.isCustom = false,
  });

  final String id;
  final String name;
  final String template;
  final bool isCustom;

  /// Builds the results URL. The query is percent-encoded so it can never
  /// break out of the query string or inject extra parameters.
  Uri buildUri(String query) {
    final clean = SearchEngine.sanitizeQuery(query);
    return Uri.parse(template.replaceFirst('%s', Uri.encodeQueryComponent(clean)));
  }

  static const int maxQueryLength = 2048;

  /// Removes control / bidi / zero-width characters and caps the length.
  static String sanitizeQuery(String raw) {
    final buffer = StringBuffer();
    for (final rune in raw.runes) {
      if (_isInvisible(rune)) continue;
      buffer.writeCharCode(rune);
    }
    var out = buffer.toString().trim();
    if (out.length > maxQueryLength) out = out.substring(0, maxQueryLength);
    return out;
  }

  static bool _isInvisible(int r) =>
      r < 0x20 ||
      (r >= 0x7F && r <= 0x9F) ||
      (r >= 0x200B && r <= 0x200F) ||
      (r >= 0x202A && r <= 0x202E) ||
      (r >= 0x2066 && r <= 0x2069) ||
      r == 0xFEFF ||
      r == 0x2028 ||
      r == 0x2029;

  /// Validates a user-supplied template. Returns an error message or null.
  static String? validateTemplate(String template) {
    if (template.length > 512) return 'Address is too long.';
    if ('%s'.allMatches(template).length != 1) {
      return 'Use exactly one %s where the search text goes.';
    }
    final probe = Uri.tryParse(template.replaceFirst('%s', 'test'));
    if (probe == null || probe.scheme != 'https') {
      return 'Search engines must use https://.';
    }
    if (probe.host.isEmpty || probe.userInfo.isNotEmpty) {
      return 'Enter a valid https:// address without a username or password.';
    }
    // The query text must land in the query string, never in host or path
    // segments where it could redirect the request elsewhere.
    final marker = template.indexOf('%s');
    final queryStart = template.indexOf('?');
    if (queryStart < 0 || marker < queryStart) {
      return 'The %s placeholder must be in the query part (after "?").';
    }
    return null;
  }
}

class SearchEngines {
  SearchEngines._();

  static const SearchEngine google = SearchEngine(
    id: 'google',
    name: 'Google',
    template: 'https://www.google.com/search?q=%s',
  );
  static const SearchEngine duckDuckGo = SearchEngine(
    id: 'duckduckgo',
    name: 'DuckDuckGo',
    template: 'https://duckduckgo.com/?q=%s',
  );
  static const SearchEngine bing = SearchEngine(
    id: 'bing',
    name: 'Bing',
    template: 'https://www.bing.com/search?q=%s',
  );
  static const SearchEngine brave = SearchEngine(
    id: 'brave',
    name: 'Brave Search',
    template: 'https://search.brave.com/search?q=%s',
  );
  static const SearchEngine startpage = SearchEngine(
    id: 'startpage',
    name: 'Startpage',
    template: 'https://www.startpage.com/do/search?q=%s',
  );
  static const SearchEngine ecosia = SearchEngine(
    id: 'ecosia',
    name: 'Ecosia',
    template: 'https://www.ecosia.org/search?q=%s',
  );

  static const List<SearchEngine> builtIn = [
    google,
    duckDuckGo,
    bing,
    brave,
    startpage,
    ecosia,
  ];

  static const SearchEngine defaultEngine = google;

  static SearchEngine byId(String? id, {SearchEngine? custom}) {
    if (id == 'custom' && custom != null) return custom;
    for (final engine in builtIn) {
      if (engine.id == id) return engine;
    }
    return defaultEngine;
  }

  /// Rebuilds a custom engine from stored data, re-validating it so a
  /// tampered cloud record can never smuggle in an unsafe template.
  static SearchEngine? customFromStored(String? name, String? template) {
    if (template == null || SearchEngine.validateTemplate(template) != null) {
      return null;
    }
    final label = (name ?? '').trim();
    return SearchEngine(
      id: 'custom',
      name: label.isEmpty || label.length > 40 ? 'Custom' : label,
      template: template,
      isCustom: true,
    );
  }
}
