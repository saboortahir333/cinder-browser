import 'package:saboor_browser/browser/session_model.dart';
import 'package:saboor_browser/browser/url_policy.dart';
import 'package:saboor_browser/services/app_services.dart';

/// Bookmarks: memory-first, end-to-end encrypted cloud sync. Guests keep
/// bookmarks for the current run only.
class BookmarkService {
  BookmarkService._();
  static final BookmarkService instance = BookmarkService._();

  static const String _kind = 'bookmark';
  static const int maxBookmarks = 10000;

  bool _loaded = false;

  /// Forces the next fetch to re-read from the cloud (after sign-in/out).
  void reset() => _loaded = false;

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    await AppServices.cloud.load(_kind, limit: 2000);
  }

  Future<void> addBookmark(String url, String title) async {
    final decision = UrlPolicy.checkNavigation(url, NavSource.restore);
    if (decision.isBlocked || decision.kind != NavKind.web) return;
    final cloud = AppServices.cloud;
    if (cloud.values(_kind).length >= maxBookmarks) return;
    final id = cloud.idFor(_kind, decision.url);
    if (cloud.contains(_kind, id)) return; // already bookmarked
    final cleanTitle = TabSnapshot.sanitizeTitle(title);
    cloud.put(_kind, id, {
      'url': decision.url,
      'title': cleanTitle.isEmpty ? decision.url : cleanTitle,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<void> removeBookmark(String url) async {
    final decision = UrlPolicy.checkNavigation(url, NavSource.restore);
    final cloud = AppServices.cloud;
    cloud.remove(_kind, cloud.idFor(_kind, decision.isBlocked ? url : decision.url));
  }

  /// All bookmarks, newest first.
  Future<List<Map<String, dynamic>>> fetchBookmarks({int limit = 200}) async {
    await _ensureLoaded();
    final rows = AppServices.cloud.values(_kind).toList()
      ..sort(
        (a, b) => (b['created_at']?.toString() ?? '').compareTo(
          a['created_at']?.toString() ?? '',
        ),
      );
    return rows.take(limit).toList();
  }
}
