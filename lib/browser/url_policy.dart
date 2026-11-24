import 'package:saboor_browser/browser/search_engines.dart';

/// Where a navigation request came from. Trust drops from top to bottom.
enum NavSource {
  /// The user typed it in the address bar.
  omnibox,

  /// Cinder's own UI acting on a value it fully controls (e.g. "View source"
  /// for the current tab). Never use this for page-supplied values.
  browser,

  /// A link, context-menu action or page-supplied value (untrusted).
  link,

  /// Read back from a saved session / cloud record (untrusted: could be
  /// tampered with or written by an older, buggier build).
  restore,
}

enum NavKind { web, search, viewSource, localFile, blank, blocked }

class NavDecision {
  const NavDecision._(
    this.kind, {
    this.uri,
    this.reason,
    this.warnings = const [],
    this.originalQuery,
  });

  const NavDecision.allow(
    NavKind kind,
    Uri uri, {
    List<NavWarning> warnings = const [],
    String? originalQuery,
  }) : this._(kind, uri: uri, warnings: warnings, originalQuery: originalQuery);

  const NavDecision.blocked(String reason)
    : this._(NavKind.blocked, reason: reason);

  final NavKind kind;
  final Uri? uri;

  /// Human-readable explanation when [kind] is [NavKind.blocked].
  final String? reason;
  final List<NavWarning> warnings;

  /// For search decisions: the sanitised query text.
  final String? originalQuery;

  bool get isBlocked => kind == NavKind.blocked;
  String get url => uri?.toString() ?? '';
}

enum NavWarning {
  /// Plain http:// - traffic is not encrypted.
  insecureHttp,

  /// Non-ASCII hostname; show the punycode form to the user.
  internationalizedHost,

  /// Mixed-script label (e.g. Latin + Cyrillic): classic homograph attack.
  confusableHost,
}

/// The single choke point that decides whether an address may be loaded.
/// Default-deny: only an explicit allowlist of schemes ever reaches WebView2.
class UrlPolicy {
  UrlPolicy._();

  static const int maxUrlLength = 8192;

  static final RegExp _schemeRe = RegExp(r'^([a-zA-Z][a-zA-Z0-9+.\-]*):');
  static final RegExp _hostPortRe = RegExp(
    r'^(?:\[[0-9a-fA-F:.]+\]|[^\s/:@?#\[\]]+):\d{1,5}(?:[/?#]|$)',
  );
  static final RegExp _ipv4Re = RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$');

  /// Resolves text typed into the address bar.
  static NavDecision resolveOmnibox(String input, SearchEngine engine) {
    final cleaned = _stripInvisible(input).trim();
    if (cleaned.isEmpty) return const NavDecision.blocked('Nothing to open.');
    if (cleaned.length > maxUrlLength) {
      return const NavDecision.blocked('That address is too long.');
    }
    if (cleaned == 'about:blank') {
      return NavDecision.allow(NavKind.blank, Uri.parse('about:blank'));
    }

    final hasSpace = RegExp(r'\s').hasMatch(cleaned);
    final scheme = _schemeRe.firstMatch(cleaned)?.group(1)?.toLowerCase();
    final isHostPort = _hostPortRe.hasMatch(cleaned);

    // "javascript:alert(1)", "data:text/html,...", "ms-msdt:..." and friends.
    if (scheme != null && !isHostPort && !hasSpace) {
      return checkNavigation(cleaned, NavSource.omnibox);
    }
    if (scheme != null && !isHostPort && hasSpace) {
      // "javascript: alert(1)" with a space is still an attack, not a search.
      if (_dangerousSchemes.contains(scheme)) {
        return NavDecision.blocked(_blockedReason(scheme));
      }
    }

    if (!hasSpace && _looksLikeHost(cleaned)) {
      final withScheme = _hasExplicitSlashes(cleaned)
          ? cleaned
          : '${_defaultSchemeFor(cleaned)}://$cleaned';
      return checkNavigation(withScheme, NavSource.omnibox);
    }

    final query = SearchEngine.sanitizeQuery(cleaned);
    if (query.isEmpty) return const NavDecision.blocked('Nothing to search.');
    return NavDecision.allow(
      NavKind.search,
      engine.buildUri(query),
      originalQuery: query,
    );
  }

  /// Validates an absolute URL from any source and normalises it.
  static NavDecision checkNavigation(String raw, NavSource source) {
    final cleaned = _stripInvisible(raw).trim();
    if (cleaned.isEmpty) return const NavDecision.blocked('Empty address.');
    if (cleaned.length > maxUrlLength) {
      return const NavDecision.blocked('That address is too long.');
    }
    if (cleaned == 'about:blank') {
      return NavDecision.allow(NavKind.blank, Uri.parse('about:blank'));
    }

    final scheme = _schemeRe.firstMatch(cleaned)?.group(1)?.toLowerCase();
    if (scheme == null) return const NavDecision.blocked('Not a web address.');

    if (scheme == 'view-source') {
      // Only wraps http(s), and only when the user (or Cinder's own menu)
      // asked for it - never from page content or stored data.
      if (source == NavSource.restore || source == NavSource.link) {
        return const NavDecision.blocked('Source view cannot be opened here.');
      }
      final inner = cleaned.substring('view-source:'.length);
      final innerDecision = checkNavigation(inner, NavSource.link);
      if (innerDecision.isBlocked ||
          (innerDecision.kind != NavKind.web)) {
        return const NavDecision.blocked('Cannot view source of that address.');
      }
      return NavDecision.allow(
        NavKind.viewSource,
        Uri.parse('view-source:${innerDecision.uri}'),
        warnings: innerDecision.warnings,
      );
    }

    if (scheme == 'file') {
      if (source != NavSource.omnibox) {
        return const NavDecision.blocked(
          'Web pages cannot open local files.',
        );
      }
      final uri = Uri.tryParse(cleaned);
      if (uri == null) return const NavDecision.blocked('Invalid file address.');
      return NavDecision.allow(NavKind.localFile, uri);
    }

    if (scheme != 'http' && scheme != 'https') {
      return NavDecision.blocked(_blockedReason(scheme));
    }

    var uri = Uri.tryParse(cleaned);
    if (uri == null || !uri.hasAuthority || uri.host.isEmpty) {
      return const NavDecision.blocked('Invalid web address.');
    }
    // Dart percent-encodes non-ASCII / odd characters in the host, so decode
    // before analysing it. Undecodable hosts are rejected outright.
    String decodedHost;
    try {
      decodedHost = Uri.decodeComponent(uri.host);
    } catch (_) {
      return const NavDecision.blocked('Invalid host name.');
    }
    if (uri.userInfo.isNotEmpty) {
      return const NavDecision.blocked(
        'Addresses containing a username or password are blocked because they are commonly used to impersonate sites.',
      );
    }
    if (uri.hasPort && (uri.port < 1 || uri.port > 65535)) {
      return const NavDecision.blocked('Invalid port.');
    }
    final host = decodedHost.toLowerCase();
    if (!_isValidHost(host)) {
      return const NavDecision.blocked('Invalid host name.');
    }

    final warnings = <NavWarning>[];
    if (scheme == 'http') warnings.add(NavWarning.insecureHttp);
    final isNonAscii = host.runes.any((r) => r > 0x7F);
    if (isNonAscii) {
      warnings.add(NavWarning.internationalizedHost);
      if (_hasConfusableLabel(host)) warnings.add(NavWarning.confusableHost);
    }
    // Always hand WebView2 a canonical ASCII (punycode) host.
    if (isNonAscii || uri.host.contains('%')) {
      uri = uri.replace(host: displayHost(host));
    }
    return NavDecision.allow(NavKind.web, uri, warnings: warnings);
  }

  /// The host as it should be shown in the UI. Confusable / non-ASCII hosts
  /// are shown in punycode so look-alike characters cannot fool the user.
  static String displayHost(String host) {
    final lower = host.toLowerCase();
    if (!lower.runes.any((r) => r > 0x7F)) return lower;
    return lower.split('.').map(_toAsciiLabel).join('.');
  }

  // -- internals ------------------------------------------------------------

  static const Set<String> _dangerousSchemes = {
    'javascript',
    'data',
    'vbscript',
    'blob',
    'filesystem',
  };

  static String _blockedReason(String scheme) {
    if (_dangerousSchemes.contains(scheme)) {
      return 'Cinder blocks "$scheme:" addresses because they can run code or hide content.';
    }
    return 'Cinder does not open "$scheme:" links.';
  }

  static bool _hasExplicitSlashes(String s) => s.contains('://');

  static String _defaultSchemeFor(String input) {
    final hostPart = input.split(RegExp(r'[/?#]')).first;
    final host = hostPart.replaceFirst(RegExp(r':\d+$'), '').toLowerCase();
    if (_isLocalHost(host)) return 'http';
    return 'https';
  }

  static bool _isLocalHost(String host) {
    if (host == 'localhost' || host.endsWith('.localhost')) return true;
    if (host == '[::1]' || host.startsWith('[')) return true;
    final m = _ipv4Re.firstMatch(host);
    if (m == null) return false;
    final a = int.parse(m.group(1)!);
    final b = int.parse(m.group(2)!);
    return a == 127 ||
        a == 10 ||
        (a == 192 && b == 168) ||
        (a == 172 && b >= 16 && b <= 31);
  }

  static bool _looksLikeHost(String s) {
    final hostPart = s.split(RegExp(r'[/?#]')).first;
    if (hostPart.isEmpty) return false;
    final noPort = hostPart.replaceFirst(RegExp(r':\d{1,5}$'), '');
    final hostName = noPort.startsWith('http') && noPort.contains('://')
        ? noPort.split('://').last
        : noPort;
    if (hostName == 'localhost') return true;
    if (hostName.startsWith('[') && hostName.endsWith(']')) return true;
    if (_ipv4Re.hasMatch(hostName)) return true;
    if (!hostName.contains('.')) return false;
    final labels = hostName.split('.');
    final tld = labels.last;
    return labels.every((l) => l.isNotEmpty) &&
        (RegExp(r'^[a-zA-Z]{2,}$').hasMatch(tld) ||
            RegExp(r'^xn--[a-zA-Z0-9\-]+$').hasMatch(tld) ||
            tld.runes.any((r) => r > 0x7F));
  }

  static bool _isValidHost(String host) {
    if (host.length > 253) return false;
    if (host.startsWith('[')) return true; // IPv6 literal, parsed by Uri
    // Reject characters that never belong in a host (spaces, backslash, etc.).
    if (RegExp(r'[\s\\/@#?<>"{}|^`]').hasMatch(host)) return false;
    for (final label in host.split('.')) {
      if (label.isEmpty && host != '.') return false;
      if (label.length > 63) return false;
    }
    return true;
  }

  static bool _hasConfusableLabel(String host) {
    for (final label in host.split('.')) {
      final scripts = <_Script>{};
      for (final r in label.runes) {
        final s = _scriptOf(r);
        if (s != _Script.common) scripts.add(s);
      }
      if (scripts.length > 1) return true;
    }
    return false;
  }

  static _Script _scriptOf(int r) {
    if ((r >= 0x30 && r <= 0x39) || r == 0x2D || r == 0x5F) return _Script.common;
    if ((r >= 0x41 && r <= 0x5A) ||
        (r >= 0x61 && r <= 0x7A) ||
        (r >= 0xC0 && r <= 0x24F)) {
      return _Script.latin;
    }
    if (r >= 0x370 && r <= 0x3FF) return _Script.greek;
    if (r >= 0x400 && r <= 0x52F) return _Script.cyrillic;
    if (r >= 0x530 && r <= 0x58F) return _Script.armenian;
    if (r >= 0x590 && r <= 0x5FF) return _Script.hebrew;
    if (r >= 0x600 && r <= 0x6FF) return _Script.arabic;
    if (r >= 0x3040 && r <= 0x30FF) return _Script.kana;
    if (r >= 0x4E00 && r <= 0x9FFF) return _Script.han;
    return _Script.other;
  }

  static String _stripInvisible(String raw) {
    final b = StringBuffer();
    for (final r in raw.runes) {
      final invisible =
          r < 0x20 ||
          (r >= 0x7F && r <= 0x9F) ||
          (r >= 0x200B && r <= 0x200F) ||
          (r >= 0x202A && r <= 0x202E) ||
          (r >= 0x2066 && r <= 0x2069) ||
          r == 0xFEFF ||
          r == 0x2028 ||
          r == 0x2029;
      if (!invisible) b.writeCharCode(r);
    }
    return b.toString();
  }

  // RFC 3492 Punycode (encode only) for safe display of IDN hosts.
  static String _toAsciiLabel(String label) {
    if (!label.runes.any((r) => r > 0x7F)) return label;
    return 'xn--${_punycodeEncode(label.runes.toList())}';
  }

  static String _punycodeEncode(List<int> input) {
    const base = 36, tMin = 1, tMax = 26, skew = 38, damp = 700;
    var n = 128, delta = 0, bias = 72;
    final out = StringBuffer();
    for (final c in input) {
      if (c < 128) out.writeCharCode(c);
    }
    final basicCount = out.length;
    var handled = basicCount;
    if (basicCount > 0) out.write('-');

    String digit(int d) =>
        String.fromCharCode(d < 26 ? d + 97 : d - 26 + 48);

    int adapt(int delta, int numPoints, bool first) {
      delta = first ? delta ~/ damp : delta ~/ 2;
      delta += delta ~/ numPoints;
      var k = 0;
      while (delta > ((base - tMin) * tMax) ~/ 2) {
        delta ~/= base - tMin;
        k += base;
      }
      return k + (((base - tMin + 1) * delta) ~/ (delta + skew));
    }

    while (handled < input.length) {
      var m = 0x7FFFFFFF;
      for (final c in input) {
        if (c >= n && c < m) m = c;
      }
      delta += (m - n) * (handled + 1);
      n = m;
      for (final c in input) {
        if (c < n) delta++;
        if (c == n) {
          var q = delta;
          for (var k = base; ; k += base) {
            final t = k <= bias ? tMin : (k >= bias + tMax ? tMax : k - bias);
            if (q < t) break;
            out.write(digit(t + (q - t) % (base - t)));
            q = (q - t) ~/ (base - t);
          }
          out.write(digit(q));
          bias = adapt(delta, handled + 1, handled == basicCount);
          delta = 0;
          handled++;
        }
      }
      delta++;
      n++;
    }
    return out.toString();
  }
}

enum _Script {
  common,
  latin,
  greek,
  cyrillic,
  armenian,
  hebrew,
  arabic,
  kana,
  han,
  other,
}
