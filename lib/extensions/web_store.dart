import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:saboor_browser/extensions/extension_manager.dart';
import 'package:saboor_browser/extensions/package_format.dart';

/// Where an extension id comes from.
enum StoreKind { chrome, edge }

class StoreRef {
  const StoreRef(this.kind, this.id);
  final StoreKind kind;
  final String id;

  ExtensionSource get source => kind == StoreKind.chrome
      ? ExtensionSource.chromeWebStore
      : ExtensionSource.edgeAddons;

  /// Accepts a bare 32-letter id or a store detail URL. Returns null for
  /// anything else (other hosts are never accepted).
  static StoreRef? parse(String input) {
    final text = input.trim();
    if (kExtensionId.hasMatch(text)) return StoreRef(StoreKind.chrome, text);
    final uri = Uri.tryParse(text);
    if (uri == null || uri.scheme != 'https') return null;
    final host = uri.host.toLowerCase();
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    String? id;
    for (final s in segments.reversed) {
      if (kExtensionId.hasMatch(s)) {
        id = s;
        break;
      }
    }
    if (id == null) return null;
    if (host == 'chromewebstore.google.com' ||
        (host == 'chrome.google.com' && segments.isNotEmpty && segments.first == 'webstore')) {
      return StoreRef(StoreKind.chrome, id);
    }
    if (host == 'microsoftedge.microsoft.com' && segments.contains('addons')) {
      return StoreRef(StoreKind.edge, id);
    }
    return null;
  }
}

class StoreException implements Exception {
  const StoreException(this.message);
  final String message;
  @override
  String toString() => message;
}

class AvailableUpdate {
  const AvailableUpdate(this.version, this.codebase);
  final String version;
  final Uri codebase;
}

/// Downloads extension packages from the stores' public CRX endpoints.
///
/// Safety rules: HTTPS only, redirects restricted to the store's own domains,
/// a hard size cap and timeouts, no cookies and no user identifiers sent.
class WebStoreClient {
  WebStoreClient({HttpClient Function()? httpFactory})
    : _factory = httpFactory ?? HttpClient.new;

  final HttpClient Function() _factory;

  static const List<String> _allowedHostSuffixes = [
    'google.com',
    'googleusercontent.com',
    'gvt1.com',
    'microsoft.com',
  ];

  static bool isAllowedHost(String host) {
    final h = host.toLowerCase();
    return _allowedHostSuffixes.any((s) => h == s || h.endsWith('.$s'));
  }

  /// Version of Chromium we report. Stores only need a plausible value.
  static const String _prodVersion = '130.0.0.0';

  static Uri downloadUri(StoreRef ref) {
    final x = Uri.encodeQueryComponent('id=${ref.id}&installsource=ondemand&uc');
    return switch (ref.kind) {
      StoreKind.chrome => Uri.parse(
        'https://clients2.google.com/service/update2/crx?response=redirect'
        '&os=win&arch=x64&os_arch=x86_64&prod=chromecrx&prodchannel=&prodversion=$_prodVersion'
        '&lang=en-US&acceptformat=crx3&x=$x',
      ),
      StoreKind.edge => Uri.parse(
        'https://edge.microsoft.com/extensionwebstorebase/v1/crx?response=redirect'
        '&prodversion=$_prodVersion&acceptformat=crx3&x=$x',
      ),
    };
  }

  Future<Uint8List> download(
    Uri start, {
    void Function(int received, int? total)? onProgress,
  }) async {
    var uri = start;
    final client = _factory()
      ..connectionTimeout = const Duration(seconds: 15)
      ..autoUncompress = true
      ..userAgent = 'Cinder'
      ..findProxy = HttpClient.findProxyFromEnvironment;
    try {
      for (var hop = 0; hop < 6; hop++) {
        if (uri.scheme != 'https' || !isAllowedHost(uri.host)) {
          throw const StoreException('The download was blocked: it is not from a trusted store address.');
        }
        final req = await client.getUrl(uri).timeout(const Duration(seconds: 20));
        req.followRedirects = false;
        req.headers.removeAll(HttpHeaders.cookieHeader);
        final res = await req.close().timeout(const Duration(seconds: 30));
        if (res.isRedirect ||
            (res.statusCode >= 300 && res.statusCode < 400 && res.headers.value(HttpHeaders.locationHeader) != null)) {
          final loc = res.headers.value(HttpHeaders.locationHeader)!;
          await res.drain<void>();
          uri = uri.resolve(loc);
          continue;
        }
        if (res.statusCode == 204 || res.statusCode == 404) {
          await res.drain<void>();
          throw const StoreException('The store has no downloadable package for this extension.');
        }
        if (res.statusCode != 200) {
          await res.drain<void>();
          throw StoreException('The store responded with an error (${res.statusCode}).');
        }
        final total = res.contentLength >= 0 ? res.contentLength : null;
        if (total != null && total > PackageLimits.maxDownloadBytes) {
          throw const StoreException('The extension is too large.');
        }
        final out = BytesBuilder(copy: false);
        var received = 0;
        await for (final chunk in res.timeout(const Duration(seconds: 30))) {
          received += chunk.length;
          if (received > PackageLimits.maxDownloadBytes) {
            throw const StoreException('The extension is too large.');
          }
          out.add(chunk);
          onProgress?.call(received, total);
        }
        return out.takeBytes();
      }
      throw const StoreException('Too many redirects.');
    } on SocketException {
      throw const StoreException('Could not reach the store. Check your connection.');
    } on TimeoutException {
      throw const StoreException('The store took too long to respond.');
    } on HandshakeException {
      throw const StoreException('A secure connection to the store could not be made.');
    } finally {
      client.close(force: true);
    }
  }

  Future<Uint8List> downloadExtension(StoreRef ref, {void Function(int, int?)? onProgress}) =>
      download(downloadUri(ref), onProgress: onProgress);

  /// Asks the store whether a newer version exists. Sends only the public
  /// extension id and installed version.
  Future<AvailableUpdate?> checkUpdate(StoreRef ref, String currentVersion) async {
    if (ref.kind != StoreKind.chrome) return null;
    final x = Uri.encodeQueryComponent('id=${ref.id}&v=$currentVersion&uc');
    final uri = Uri.parse(
      'https://clients2.google.com/service/update2/crx?prodversion=$_prodVersion&acceptformat=crx3&x=$x',
    );
    final body = await download(uri);
    return parseUpdateResponse(String.fromCharCodes(body.take(64 * 1024)), ref.id, currentVersion);
  }

  /// Parses a Omaha-style `<gupdate>` response (kept dependency-free).
  static AvailableUpdate? parseUpdateResponse(String xml, String id, String current) {
    final tag = RegExp(r'<updatecheck\b([^>]*)/?>').firstMatch(xml);
    if (tag == null) return null;
    final attrs = tag.group(1)!;
    String? attr(String name) => RegExp('$name="([^"]*)"').firstMatch(attrs)?.group(1);
    final version = attr('version');
    final codebase = attr('codebase');
    final status = attr('status');
    if (status != null && status != 'ok') return null;
    if (version == null || codebase == null) return null;
    if (compareVersions(version, current) <= 0) return null;
    final uri = Uri.tryParse(codebase.replaceAll('&amp;', '&'));
    if (uri == null || uri.scheme != 'https' || !isAllowedHost(uri.host)) return null;
    return AvailableUpdate(version, uri);
  }

  static int compareVersions(String a, String b) {
    final pa = a.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final pb = b.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    for (var i = 0; i < 4; i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x != y) return x.compareTo(y);
    }
    return 0;
  }
}
