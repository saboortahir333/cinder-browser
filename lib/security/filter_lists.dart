import 'dart:convert';
import 'dart:io';

import 'package:saboor_browser/src/rust/api/adblock_engine.dart' as rust;

/// Downloads, caches and loads the filter lists used for tracker/ad blocking
/// and the malware host list.
///
/// * Lists are fetched over HTTPS from their publishers and cached under
///   `%LOCALAPPDATA%\Cinder\filters`; they are refreshed weekly.
/// * Lists are not bundled with the app (EasyList/EasyPrivacy are CC BY-SA /
///   GPL; URLhaus is CC0). A tiny built-in list keeps blocking working offline.
/// * Fetching a list reveals only "a Cinder user downloaded this public file".
class FilterLists {
  FilterLists({HttpClient? http, Directory? cacheDir})
      : _http = http,
        _cacheDir = cacheDir;

  final HttpClient? _http;
  final Directory? _cacheDir;

  static const Duration maxAge = Duration(days: 7);
  static const int maxBytes = 30 * 1024 * 1024;

  static const Map<String, String> adLists = {
    'easylist.txt': 'https://easylist.to/easylist/easylist.txt',
    'easyprivacy.txt': 'https://easylist.to/easylist/easyprivacy.txt',
  };
  static const String malwareFile = 'urlhaus-hosts.txt';
  static const String malwareUrl = 'https://urlhaus.abuse.ch/downloads/hostfile/';

  /// Always available, even offline and on first run.
  static const String builtIn = '''
||doubleclick.net^
||googlesyndication.com^
||googleadservices.com^
||google-analytics.com^
||googletagmanager.com^\$third-party
||adservice.google.com^
||facebook.net^\$third-party
||connect.facebook.net^\$third-party
||scorecardresearch.com^
||hotjar.com^\$third-party
||adnxs.com^
||taboola.com^\$third-party
||outbrain.com^\$third-party
||criteo.com^
||amazon-adsystem.com^
||quantserve.com^
''';

  Directory get _dir {
    final base = _cacheDir ??
        Directory('${Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path}\\Cinder\\filters');
    return base;
  }

  /// Loads whatever is cached (plus built-ins) into the Rust engine and returns
  /// the malware host set. Never throws: filtering degrades, browsing does not.
  Future<Set<String>> loadCached() async {
    try {
      final texts = <String>[builtIn];
      for (final name in adLists.keys) {
        final f = File('${_dir.path}\\$name');
        if (await f.exists()) texts.add(await f.readAsString());
      }
      await rust.adblockLoad(lists: texts);
    } catch (_) {}
    return _readMalware();
  }

  /// Fetches stale lists. Returns true when anything changed.
  Future<bool> refreshIfStale() async {
    var changed = false;
    try {
      await _dir.create(recursive: true);
    } catch (_) {
      return false;
    }
    final jobs = {...adLists, malwareFile: malwareUrl};
    for (final e in jobs.entries) {
      final f = File('${_dir.path}\\${e.key}');
      try {
        if (await f.exists() && DateTime.now().difference(await f.lastModified()) < maxAge) {
          continue;
        }
        final body = await _download(e.value);
        if (body == null || body.isEmpty) continue;
        final tmp = File('${f.path}.tmp');
        await tmp.writeAsString(body);
        await tmp.rename(f.path);
        changed = true;
      } catch (_) {}
    }
    return changed;
  }

  Future<String?> _download(String url) async {
    final u = Uri.parse(url);
    if (u.scheme != 'https') return null;
    final client = _http ?? HttpClient();
    client.connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.getUrl(u);
      req.headers.set('User-Agent', 'CinderBrowser-FilterUpdate');
      final res = await req.close().timeout(const Duration(seconds: 60));
      if (res.statusCode != 200) {
        await res.drain<void>();
        return null;
      }
      final bytes = <int>[];
      await for (final chunk in res) {
        bytes.addAll(chunk);
        if (bytes.length > maxBytes) return null;
      }
      return utf8.decode(bytes, allowMalformed: true);
    } finally {
      if (_http == null) client.close();
    }
  }

  Future<Set<String>> _readMalware() async {
    try {
      final f = File('${_dir.path}\\$malwareFile');
      if (!await f.exists()) return {};
      return parseHostFile(await f.readAsString());
    } catch (_) {
      return {};
    }
  }

  /// Parses a hosts-format file ("127.0.0.1 host") into lowercase hosts.
  static Set<String> parseHostFile(String text) {
    final out = <String>{};
    for (final raw in const LineSplitter().convert(text)) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final parts = line.split(RegExp(r'\s+'));
      if (parts.length < 2) continue;
      final host = parts[1].toLowerCase();
      if (host.length <= 253 && RegExp(r'^[a-z0-9.-]+$').hasMatch(host) && host != 'localhost') {
        out.add(host);
      }
    }
    return out;
  }
}
