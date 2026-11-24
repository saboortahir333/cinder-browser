import 'package:saboor_browser/browser/session_model.dart';
import 'package:saboor_browser/browser/url_policy.dart';
import 'package:saboor_browser/services/app_services.dart';
import 'package:saboor_browser/services/cloud_store.dart';

/// Browsing and search history.
///
/// Memory-first and end-to-end encrypted: records are AES-GCM encrypted on the
/// device and keyed by an HMAC of the URL, so the server learns neither the
/// pages nor which pages repeat. Guests keep history in memory only.
class HistoryService {
  HistoryService._();
  static final HistoryService instance = HistoryService._();

  static const String _history = 'history';
  static const String _search = 'search';
  static const int maxEntries = 10000;
  static const int maxSearches = 2000;
  static const int _maxUrlLength = 2048;

  final Set<String> _loaded = {};

  CloudStore get _cloud => AppServices.cloud;

  /// Forces the next fetch to re-read from the cloud (after sign-in/out).
  void reset() => _loaded.clear();

  Future<void> _ensureLoaded(String kind, int limit) async {
    if (_loaded.contains(kind)) return;
    _loaded.add(kind);
    await _cloud.load(kind, limit: limit);
  }

  /// Records a page visit (http/https only).
  Future<void> recordVisit(String url, String title, {bool isPqc = false}) async {
    if (url.isEmpty || url.length > _maxUrlLength) return;
    final decision = UrlPolicy.checkNavigation(url, NavSource.restore);
    if (decision.isBlocked || decision.kind != NavKind.web) return;
    final id = _cloud.idFor(_history, decision.url);
    final previous = _cloud.get(_history, id);
    final count = previous?['visit_count'];
    final cleanTitle = TabSnapshot.sanitizeTitle(title);
    _cloud.put(_history, id, {
      'url': decision.url,
      'title': cleanTitle.isEmpty ? decision.url : cleanTitle,
      'last_visited_at': DateTime.now().toUtc().toIso8601String(),
      'visit_count': (count is int ? count : 0) + 1,
      'is_pqc_verified': isPqc,
    });
    _prune(_history, maxEntries, 'last_visited_at');
  }

  Future<void> recordSearch(String queryText) async {
    final clean = queryText.trim();
    if (clean.isEmpty || clean.length > 512) return;
    final id = _cloud.idFor(_search, clean.toLowerCase());
    _cloud.put(_search, id, {
      'query_text': clean,
      'searched_at': DateTime.now().toUtc().toIso8601String(),
    });
    _prune(_search, maxSearches, 'searched_at');
  }

  Future<List<Map<String, dynamic>>> fetchBrowsingHistory({int limit = 50}) async {
    await _ensureLoaded(_history, 1000);
    return _sorted(_history, 'last_visited_at', limit);
  }

  Future<List<Map<String, dynamic>>> fetchSearchHistory({int limit = 30}) async {
    await _ensureLoaded(_search, 500);
    return _sorted(_search, 'searched_at', limit);
  }

  /// Deletes all history and searches, locally and in the cloud.
  Future<void> clearHistory() async {
    await _cloud.clearKind(_history);
    await _cloud.clearKind(_search);
  }

  Future<void> updatePqcStatus(String url, {required bool isPqcVerified}) async {
    final decision = UrlPolicy.checkNavigation(url, NavSource.restore);
    if (decision.isBlocked) return;
    final id = _cloud.idFor(_history, decision.url);
    final record = _cloud.get(_history, id);
    if (record == null) return;
    _cloud.put(_history, id, {...record, 'is_pqc_verified': isPqcVerified});
  }

  List<Map<String, dynamic>> _sorted(String kind, String timeKey, int limit) {
    final rows = _cloud.values(kind).toList()
      ..sort(
        (a, b) => (b[timeKey]?.toString() ?? '').compareTo(
          a[timeKey]?.toString() ?? '',
        ),
      );
    return rows.take(limit).toList();
  }

  void _prune(String kind, int max, String timeKey) {
    final rows = _cloud.values(kind);
    if (rows.length <= max) return;
    final sorted = _sorted(kind, timeKey, rows.length);
    // Drop the oldest 5% in one go so pruning is not triggered every visit.
    final drop = sorted.reversed.take((max * 0.05).ceil());
    for (final row in drop) {
      final natural = (kind == _history ? row['url'] : row['query_text'])
          ?.toString();
      if (natural == null) continue;
      _cloud.remove(
        kind,
        _cloud.idFor(kind, kind == _search ? natural.toLowerCase() : natural),
      );
    }
  }
}
