import 'package:saboor_browser/browser/url_policy.dart';

/// A tab as saved for session restore / "reopen closed tab".
class TabSnapshot {
  const TabSnapshot({
    required this.url,
    required this.title,
    this.pinned = false,
    this.groupId,
  });

  final String url;
  final String title;
  final bool pinned;

  /// Tab-group id (see [TabGroupModel]); null when ungrouped.
  final String? groupId;

  Map<String, dynamic> toJson() => {
    'url': url,
    'title': title,
    'pinned': pinned,
    if (groupId != null) 'group': groupId,
  };

  /// Strictly validates untrusted data (cloud record, tampering, older
  /// builds). Returns null when the entry must be dropped.
  static TabSnapshot? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final url = raw['url'];
    if (url is! String) return null;
    final decision = UrlPolicy.checkNavigation(url, NavSource.restore);
    if (decision.isBlocked ||
        (decision.kind != NavKind.web && decision.kind != NavKind.blank)) {
      return null;
    }
    final title = raw['title'];
    final group = raw['group'];
    return TabSnapshot(
      url: decision.kind == NavKind.blank ? '' : decision.url,
      title: sanitizeTitle(title is String ? title : ''),
      pinned: raw['pinned'] == true,
      groupId: group is String && _idRe.hasMatch(group) ? group : null,
    );
  }

  static final RegExp _idRe = RegExp(r'^[A-Za-z0-9_-]{1,40}$');

  /// Titles come from web pages: cap length, strip control/bidi characters.
  static String sanitizeTitle(String raw) {
    final b = StringBuffer();
    for (final r in raw.runes) {
      final bad =
          r < 0x20 ||
          (r >= 0x7F && r <= 0x9F) ||
          (r >= 0x200B && r <= 0x200F) ||
          (r >= 0x202A && r <= 0x202E) ||
          (r >= 0x2066 && r <= 0x2069) ||
          r == 0xFEFF;
      if (!bad) b.writeCharCode(r);
    }
    final out = b.toString().trim();
    return out.length > 200 ? out.substring(0, 200) : out;
  }
}

/// A named, coloured group of tabs (Chrome-style tab groups).
class TabGroupSnapshot {
  const TabGroupSnapshot({
    required this.id,
    required this.name,
    required this.colorIndex,
  });

  static const int colorCount = 8;
  static const int maxGroups = 50;
  static final RegExp idPattern = RegExp(r'^[A-Za-z0-9_-]{1,40}$');

  final String id;
  final String name;
  final int colorIndex;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'color': colorIndex};

  static TabGroupSnapshot? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    if (id is! String || !idPattern.hasMatch(id)) return null;
    final name = raw['name'];
    final color = raw['color'];
    var clean = TabSnapshot.sanitizeTitle(name is String ? name : '');
    if (clean.length > 40) clean = clean.substring(0, 40);
    return TabGroupSnapshot(
      id: id,
      name: clean,
      colorIndex: color is int ? color.clamp(0, colorCount - 1) : 0,
    );
  }
}

class SessionSnapshot {
  const SessionSnapshot({
    required this.tabs,
    required this.activeIndex,
    this.groups = const [],
  });

  static const int schemaVersion = 1;
  static const int maxTabs = 200;

  final List<TabSnapshot> tabs;
  final int activeIndex;
  final List<TabGroupSnapshot> groups;

  bool get isEmpty => tabs.isEmpty;

  Map<String, dynamic> toJson() => {
    'v': schemaVersion,
    'active': activeIndex,
    'tabs': [for (final t in tabs) t.toJson()],
    'groups': [for (final g in groups) g.toJson()],
  };

  static SessionSnapshot? tryFromJson(Map<String, dynamic>? json) {
    if (json == null || json['v'] != schemaVersion) return null;
    final rawTabs = json['tabs'];
    if (rawTabs is! List) return null;
    final tabs = <TabSnapshot>[];
    for (final raw in rawTabs.take(maxTabs)) {
      final tab = TabSnapshot.tryFromJson(raw);
      if (tab != null) tabs.add(tab);
    }
    if (tabs.isEmpty) return null;
    final groups = <TabGroupSnapshot>[];
    final rawGroups = json['groups'];
    if (rawGroups is List) {
      for (final raw in rawGroups.take(TabGroupSnapshot.maxGroups)) {
        final g = TabGroupSnapshot.tryFromJson(raw);
        if (g != null && !groups.any((x) => x.id == g.id)) groups.add(g);
      }
    }
    final known = groups.map((g) => g.id).toSet();
    final cleanedTabs = [
      for (final t in tabs)
        if (t.groupId != null && !known.contains(t.groupId))
          TabSnapshot(url: t.url, title: t.title, pinned: t.pinned)
        else
          t,
    ];
    final active = json['active'];
    final index = active is int ? active.clamp(0, cleanedTabs.length - 1) : 0;
    return SessionSnapshot(tabs: cleanedTabs, activeIndex: index, groups: groups);
  }
}

/// Most-recently-closed tabs for Ctrl+Shift+T.
class ClosedTabStack {
  ClosedTabStack({this.capacity = 25});

  final int capacity;
  final List<TabSnapshot> _items = [];

  int get length => _items.length;
  bool get isNotEmpty => _items.isNotEmpty;
  List<TabSnapshot> get items => List.unmodifiable(_items.reversed);

  /// Blank new-tab pages are not worth restoring.
  void push(TabSnapshot tab) {
    if (tab.url.isEmpty) return;
    _items.add(tab);
    if (_items.length > capacity) _items.removeAt(0);
  }

  TabSnapshot? pop() => _items.isEmpty ? null : _items.removeLast();

  void clear() => _items.clear();
}
