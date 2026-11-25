import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:saboor_browser/extensions/web_store.dart' show WebStoreClient;
import 'package:saboor_browser/utils/app_info.dart';

class UpdateInfo {
  const UpdateInfo(this.version, this.pageUrl, this.notes);
  final String version;
  final String pageUrl;
  final String notes;
}

/// Looks for a newer Cinder release on GitHub. It only *tells* the user and
/// links to the release page: nothing is downloaded or run automatically, so a
/// compromised response can at worst show a link to this project's own
/// releases page (the URL is validated).
class UpdateService {
  const UpdateService({HttpClient Function()? httpFactory}) : _factory = httpFactory;
  final HttpClient Function()? _factory;

  static final Uri _api = Uri.parse(
    'https://api.github.com/repos/$kRepoOwner/$kRepoName/releases/latest',
  );

  /// Returns the newer release, or null when up to date / unreachable.
  Future<UpdateInfo?> check() async {
    final client = (_factory ?? HttpClient.new)()
      ..connectionTimeout = const Duration(seconds: 8)
      ..userAgent = 'Cinder/$kAppVersion';
    try {
      final req = await client.getUrl(_api).timeout(const Duration(seconds: 10));
      req.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      final res = await req.close().timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) {
        await res.drain<void>();
        return null;
      }
      final body = await res
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 10));
      if (body.length > 512 * 1024) return null;
      return parse(body);
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  static UpdateInfo? parse(String body, {String current = kAppVersion}) {
    try {
      final j = jsonDecode(body);
      if (j is! Map) return null;
      if (j['draft'] == true || j['prerelease'] == true) return null;
      final tag = (j['tag_name'] as String? ?? '').replaceFirst(RegExp('^[vV]'), '');
      if (!RegExp(r'^\d{1,4}(\.\d{1,4}){0,3}$').hasMatch(tag)) return null;
      if (WebStoreClient.compareVersions(tag, current) <= 0) return null;
      final url = j['html_url'] as String? ?? '';
      if (!url.startsWith('https://github.com/$kRepoOwner/$kRepoName/releases/')) {
        return null;
      }
      var notes = (j['body'] as String? ?? '').trim();
      if (notes.length > 600) notes = '${notes.substring(0, 600)}…';
      return UpdateInfo(tag, url, notes);
    } catch (_) {
      return null;
    }
  }
}
