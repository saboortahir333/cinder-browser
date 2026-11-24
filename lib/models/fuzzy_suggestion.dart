
enum FuzzySuggestionType {
  bookmark,
  history,
  searchHistory,
  webSearch,
  url,
}

class FuzzySuggestion {
  FuzzySuggestion({
    required this.title,
    required this.url,
    required this.type,
    required this.score,
  });

  final String title;
  final String url;
  final FuzzySuggestionType type;
  final int score;
}

class FuzzySearchEngine {
  static List<FuzzySuggestion> getSuggestions({
    required String query,
    required List<Map<String, dynamic>> bookmarks,
    required List<Map<String, dynamic>> history,
    required List<Map<String, dynamic>> searchHistory,
  }) {
    final clean = query.trim().toLowerCase();
    if (clean.isEmpty) return [];

    final results = <FuzzySuggestion>[];
    final seenUrls = <String>{};

    int calculateScore(String text, String targetUrl) {
      final t = text.toLowerCase();
      final u = targetUrl.toLowerCase();
      final cleanUrl = u.replaceAll(RegExp(r'^https?://(www\.)?'), '');

      if (t == clean || u == clean || cleanUrl == clean) return 1000;
      if (t.startsWith(clean) || u.startsWith(clean) || cleanUrl.startsWith(clean)) {
        return 500;
      }

      final words = t.split(RegExp(r'[\s\.\-_]+'));
      for (final w in words) {
        if (w.startsWith(clean)) return 350;
      }

      final urlWords = cleanUrl.split(RegExp(r'[\s\.\-_/\?]+'));
      for (final w in urlWords) {
        if (w.startsWith(clean)) return 300;
      }

      if (t.contains(clean) || u.contains(clean)) return 150;

      if (clean.length >= 2 && _isSubsequence(clean, t)) return 80;
      if (clean.length >= 2 && _isSubsequence(clean, cleanUrl)) return 70;

      return 0;
    }

    // 1. Search Bookmarks
    for (final bm in bookmarks) {
      final title = bm['title']?.toString() ?? '';
      final url = bm['url']?.toString() ?? '';
      if (url.isEmpty) continue;

      final score = calculateScore(title, url);
      if (score > 0) {
        seenUrls.add(url.toLowerCase());
        results.add(
          FuzzySuggestion(
            title: title.isEmpty ? url : title,
            url: url,
            type: FuzzySuggestionType.bookmark,
            score: score + 120,
          ),
        );
      }
    }

    // 2. Search History
    for (final h in history) {
      final title = h['title']?.toString() ?? '';
      final url = h['url']?.toString() ?? '';
      if (url.isEmpty || seenUrls.contains(url.toLowerCase())) continue;

      final score = calculateScore(title, url);
      if (score > 0) {
        seenUrls.add(url.toLowerCase());
        results.add(
          FuzzySuggestion(
            title: title.isEmpty ? url : title,
            url: url,
            type: FuzzySuggestionType.history,
            score: score + 60,
          ),
        );
      }
    }

    // 3. Search Past Queries
    for (final s in searchHistory) {
      final text = s['query_text']?.toString() ?? '';
      if (text.isEmpty) continue;
      final score = calculateScore(text, text);
      if (score > 0) {
        final targetUrl =
            'https://www.google.com/search?q=${Uri.encodeComponent(text)}';
        if (seenUrls.contains(targetUrl.toLowerCase())) continue;
        seenUrls.add(targetUrl.toLowerCase());
        results.add(
          FuzzySuggestion(
            title: text,
            url: targetUrl,
            type: FuzzySuggestionType.searchHistory,
            score: score + 40,
          ),
        );
      }
    }

    // 4. Popular Web Domains (Chrome/Firefox/Opera style domain completion)
    final popularSites = [
      {'title': 'YouTube', 'url': 'https://youtube.com'},
      {'title': 'GitHub', 'url': 'https://github.com'},
      {'title': 'Google', 'url': 'https://google.com'},
      {'title': 'Wikipedia', 'url': 'https://wikipedia.org'},
      {'title': 'Reddit', 'url': 'https://reddit.com'},
      {'title': 'ChatGPT', 'url': 'https://chatgpt.com'},
      {'title': 'Stack Overflow', 'url': 'https://stackoverflow.com'},
      {'title': 'Twitter / X', 'url': 'https://x.com'},
      {'title': 'Speedtest', 'url': 'https://speedtest.net'},
      {'title': 'DuckDuckGo', 'url': 'https://duckduckgo.com'},
    ];

    for (final site in popularSites) {
      final title = site['title']!;
      final url = site['url']!;
      if (seenUrls.contains(url.toLowerCase())) continue;

      final score = calculateScore(title, url);
      if (score > 0) {
        seenUrls.add(url.toLowerCase());
        results.add(
          FuzzySuggestion(
            title: title,
            url: url,
            type: FuzzySuggestionType.url,
            score: score + 30,
          ),
        );
      }
    }

    // 5. Default Google Web Search option
    results.add(
      FuzzySuggestion(
        title: 'Search Google for "$clean"',
        url: 'https://www.google.com/search?q=${Uri.encodeComponent(clean)}',
        type: FuzzySuggestionType.webSearch,
        score: 10,
      ),
    );

    results.sort((a, b) => b.score.compareTo(a.score));

    return results.take(7).toList();
  }

  static bool _isSubsequence(String sub, String str) {
    int i = 0;
    for (int j = 0; j < str.length && i < sub.length; j++) {
      if (sub[i] == str[j]) i++;
    }
    return i == sub.length;
  }
}
