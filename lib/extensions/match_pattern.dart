/// WebExtensions match patterns (`https://*.example.com/path/*`, `<all_urls>`).
///
/// This is security-critical: a host pattern that matches too much hands an
/// extension access to sites the user never approved. The rules follow
/// Chromium's `URLPattern` for the schemes Cinder supports (http, https, file).
library;

class MatchPattern {
  MatchPattern._({
    required this.source,
    required this.schemes,
    required this.host,
    required this.matchSubdomains,
    required this.port,
    required this.path,
    required this.allUrls,
  });

  final String source;

  /// Allowed schemes (lower case).
  final Set<String> schemes;

  /// Host to match, lower case, no leading `*.`. Empty means "any host".
  final String host;
  final bool matchSubdomains;

  /// `null` = any port.
  final int? port;

  /// Glob path (may contain `*`), always starting with `/`.
  final String path;
  final bool allUrls;

  static const Set<String> supportedSchemes = {'http', 'https', 'file'};

  static final Map<String, MatchPattern?> _cache = {};

  /// Parses [pattern]; returns null when it is not a valid, supported pattern.
  static MatchPattern? tryParse(String pattern) {
    if (_cache.containsKey(pattern)) return _cache[pattern];
    final parsed = _parse(pattern);
    if (_cache.length > 2048) _cache.clear();
    _cache[pattern] = parsed;
    return parsed;
  }

  static MatchPattern? _parse(String pattern) {
    if (pattern.isEmpty || pattern.length > 2048) return null;
    if (pattern == '<all_urls>') {
      return MatchPattern._(
        source: pattern,
        schemes: supportedSchemes,
        host: '',
        matchSubdomains: false,
        port: null,
        path: '/*',
        allUrls: true,
      );
    }
    final sep = pattern.indexOf('://');
    if (sep <= 0) return null;
    final scheme = pattern.substring(0, sep).toLowerCase();
    final rest = pattern.substring(sep + 3);
    final Set<String> schemes;
    if (scheme == '*') {
      schemes = {'http', 'https'};
    } else if (supportedSchemes.contains(scheme)) {
      schemes = {scheme};
    } else {
      return null;
    }

    final slash = rest.indexOf('/');
    if (slash < 0) return null; // the path is mandatory
    var hostPart = rest.substring(0, slash);
    final path = rest.substring(slash);

    if (scheme == 'file') {
      if (hostPart.isNotEmpty) return null;
      return MatchPattern._(
        source: pattern,
        schemes: schemes,
        host: '',
        matchSubdomains: false,
        port: null,
        path: path,
        allUrls: false,
      );
    }
    if (hostPart.isEmpty || hostPart.contains('@')) return null;

    int? port;
    final colon = hostPart.lastIndexOf(':');
    if (colon >= 0 && !hostPart.endsWith(']')) {
      final p = hostPart.substring(colon + 1);
      hostPart = hostPart.substring(0, colon);
      if (p != '*') {
        port = int.tryParse(p);
        if (port == null || port < 0 || port > 65535) return null;
      }
    }

    var subdomains = false;
    var host = hostPart.toLowerCase();
    if (host == '*') {
      host = '';
    } else if (host.startsWith('*.')) {
      subdomains = true;
      host = host.substring(2);
      if (host.isEmpty) return null;
    }
    // A wildcard anywhere else (`foo*.com`, `a.*.com`) is not allowed.
    if (host.contains('*')) return null;
    if (host.endsWith('.')) host = host.substring(0, host.length - 1);
    if (host.contains('..')) return null;

    return MatchPattern._(
      source: pattern,
      schemes: schemes,
      host: host,
      matchSubdomains: subdomains,
      port: port,
      path: path,
      allUrls: false,
    );
  }

  /// True when the pattern covers every web address (`<all_urls>`, `*://*/*`).
  bool get coversAllSites => allUrls || (host.isEmpty && path == '/*');

  RegExp? _pathRegex;

  bool matches(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) return false;
    final scheme = uri.scheme.toLowerCase();
    if (!schemes.contains(scheme)) return false;

    if (scheme != 'file') {
      var h = uri.host.toLowerCase();
      if (h.endsWith('.')) h = h.substring(0, h.length - 1);
      if (h.isEmpty) return false;
      if (host.isNotEmpty) {
        final ok = matchSubdomains
            ? (h == host || h.endsWith('.$host'))
            : h == host;
        if (!ok) return false;
      }
      if (port != null) {
        final effective = uri.hasPort
            ? uri.port
            : (scheme == 'https' ? 443 : 80);
        if (effective != port) return false;
      }
    }
    final target = '${uri.path.isEmpty ? '/' : uri.path}'
        '${uri.hasQuery ? '?${uri.query}' : ''}';
    return (_pathRegex ??= _globToRegex(path)).hasMatch(target);
  }

  static RegExp _globToRegex(String glob) {
    final buf = StringBuffer('^');
    for (final rune in glob.runes) {
      final ch = String.fromCharCode(rune);
      buf.write(ch == '*' ? '.*' : RegExp.escape(ch));
    }
    buf.write(r'$');
    return RegExp(buf.toString(), dotAll: true);
  }

  /// Does this pattern grant at least what [other] asks for? Used to check an
  /// extension only injects where the user granted access.
  bool covers(MatchPattern other) {
    if (coversAllSites) return other.schemes.every(schemes.contains);
    if (!other.schemes.every(schemes.contains)) return false;
    if (host.isNotEmpty) {
      if (other.host.isEmpty) return false;
      final ok = matchSubdomains
          ? (other.host == host || other.host.endsWith('.$host'))
          : (other.host == host && !other.matchSubdomains);
      if (!ok) return false;
    }
    if (port != null && other.port != port) return false;
    return path == '/*' || path == other.path;
  }

  /// Human label such as "all websites" or "example.com".
  String get label {
    if (coversAllSites) return 'all websites';
    if (schemes.length == 1 && schemes.first == 'file') {
      return 'local files';
    }
    final h = host.isEmpty ? 'any site' : host;
    return matchSubdomains ? '$h and its subdomains' : h;
  }

  /// JavaScript regular expression source (anchored) equivalent to this
  /// pattern, used by injected bootstrap code so the page-side runner matches
  /// exactly what Dart would. Built only from escaped literals.
  String toJsRegexSource() {
    String esc(String s) =>
        s.replaceAllMapped(RegExp(r'[.*+?^${}()|\[\]\\/]'), (m) => '\\${m[0]}');
    final scheme = schemes.length == 1
        ? esc(schemes.first)
        : '(?:${schemes.map(esc).join('|')})';
    final b = StringBuffer('^$scheme:\\/\\/');
    if (!schemes.contains('file') || schemes.length > 1) {
      if (host.isEmpty) {
        b.write('[^\\/:?#]+');
      } else if (matchSubdomains) {
        b.write('(?:[^\\/:?#]+\\.)?${esc(host)}');
      } else {
        b.write(esc(host));
      }
      b.write(port == null ? '(?::\\d+)?' : '(?::$port)?');
    }
    final pathSrc = path.split('*').map(esc).join('[\\s\\S]*');
    b.write(pathSrc);
    b.write(r'(?:[#].*)?$');
    return b.toString();
  }
}

/// True if any of [patterns] matches [url].
bool anyPatternMatches(Iterable<String> patterns, String url) {
  for (final p in patterns) {
    final m = MatchPattern.tryParse(p);
    if (m != null && m.matches(url)) return true;
  }
  return false;
}
