import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart';

import 'package:saboor_browser/services/cloud_store.dart';

/// Powerful features a page can ask for.
enum SitePermission {
  camera('Camera', 'use your camera'),
  microphone('Microphone', 'use your microphone'),
  location('Location', 'know your location'),
  notifications('Notifications', 'show notifications'),
  clipboardRead('Clipboard', 'see text and images you copy'),
  sensors('Motion sensors', 'use your device sensors');

  const SitePermission(this.label, this.verb);
  final String label;
  final String verb;

  static SitePermission? fromKind(WebviewPermissionKind kind) => switch (kind) {
    WebviewPermissionKind.camera => SitePermission.camera,
    WebviewPermissionKind.microphone => SitePermission.microphone,
    WebviewPermissionKind.geoLocation => SitePermission.location,
    WebviewPermissionKind.notifications => SitePermission.notifications,
    WebviewPermissionKind.clipboardRead => SitePermission.clipboardRead,
    WebviewPermissionKind.otherSensors => SitePermission.sensors,
    WebviewPermissionKind.unknown => null,
  };
}

enum SiteDecision { allow, block }

/// Answer for one request.
enum PermissionOutcome { allow, deny, askUser }

/// Per-origin permission decisions: persisted (end-to-end encrypted when
/// signed in), always revocable, and never remembered in private windows.
class SitePermissionStore extends ChangeNotifier {
  SitePermissionStore({required this.cloud, required this.isPrivate});

  static const String kind = 'sitepermission';

  final CloudStore cloud;

  /// Private windows keep decisions in memory only.
  final bool isPrivate;
  final Map<String, SiteDecision> _memory = {};

  /// Prompts shown (and dismissed) per origin this run: abuse limiter.
  final Map<String, int> _denyStrikes = {};
  static const int maxStrikes = 3;

  /// `scheme://host[:port]` or null when the address is not a web origin.
  static String? originOf(String url) {
    final u = Uri.tryParse(url);
    if (u == null || (u.scheme != 'https' && u.scheme != 'http') || u.host.isEmpty) {
      return null;
    }
    final port = u.hasPort && u.port != (u.scheme == 'https' ? 443 : 80)
        ? ':${u.port}'
        : '';
    return '${u.scheme}://${u.host.toLowerCase()}$port';
  }

  String _key(String origin, SitePermission p) => '$origin|${p.name}';

  Future<void> load() async {
    if (isPrivate) return;
    await cloud.load(kind);
    notifyListeners();
  }

  SiteDecision? decisionFor(String origin, SitePermission p) {
    final mem = _memory[_key(origin, p)];
    if (mem != null) return mem;
    if (isPrivate) return null;
    final rec = cloud.get(kind, cloud.idFor(kind, _key(origin, p)));
    final d = rec?['decision'];
    return switch (d) {
      'allow' => SiteDecision.allow,
      'block' => SiteDecision.block,
      _ => null,
    };
  }

  /// What to do with an incoming request.
  PermissionOutcome evaluate(String url, SitePermission p, {required bool userInitiated}) {
    final origin = originOf(url);
    if (origin == null) return PermissionOutcome.deny;
    // Powerful features are only meaningful on secure origins.
    final secure = origin.startsWith('https://') || origin.contains('//localhost') || origin.contains('//127.0.0.1');
    if (!secure) return PermissionOutcome.deny;
    switch (decisionFor(origin, p)) {
      case SiteDecision.allow:
        return PermissionOutcome.allow;
      case SiteDecision.block:
        return PermissionOutcome.deny;
      case null:
        break;
    }
    // Sensors are never worth a prompt; pages that spam get silenced.
    if (p == SitePermission.sensors) return PermissionOutcome.deny;
    if ((_denyStrikes[origin] ?? 0) >= maxStrikes) return PermissionOutcome.deny;
    // Notification and location prompts without a user gesture are the classic
    // abuse pattern: refuse them quietly.
    if (!userInitiated && (p == SitePermission.notifications || p == SitePermission.location)) {
      return PermissionOutcome.deny;
    }
    return PermissionOutcome.askUser;
  }

  /// Records the user's answer. [remember] false = this time only.
  void record(String origin, SitePermission p, SiteDecision d, {required bool remember}) {
    if (d == SiteDecision.block) {
      _denyStrikes[origin] = (_denyStrikes[origin] ?? 0) + 1;
    }
    if (!remember) return;
    set(origin, p, d);
  }

  void set(String origin, SitePermission p, SiteDecision d) {
    final k = _key(origin, p);
    if (isPrivate) {
      _memory[k] = d;
    } else {
      cloud.put(kind, cloud.idFor(kind, k), {
        'origin': origin,
        'permission': p.name,
        'decision': d.name,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
    }
    notifyListeners();
  }

  /// Back to "ask again".
  void reset(String origin, SitePermission p) {
    final k = _key(origin, p);
    _memory.remove(k);
    if (!isPrivate) cloud.remove(kind, cloud.idFor(kind, k));
    _denyStrikes.remove(origin);
    notifyListeners();
  }

  void resetOrigin(String origin) {
    for (final p in SitePermission.values) {
      reset(origin, p);
    }
  }

  /// Every stored decision, for the settings screen.
  List<({String origin, SitePermission permission, SiteDecision decision})> all() {
    final out = <({String origin, SitePermission permission, SiteDecision decision})>[];
    void add(String origin, String perm, String decision) {
      final p = SitePermission.values.where((x) => x.name == perm);
      if (p.isEmpty) return;
      out.add((
        origin: origin,
        permission: p.first,
        decision: decision == 'allow' ? SiteDecision.allow : SiteDecision.block,
      ));
    }

    for (final e in _memory.entries) {
      final parts = e.key.split('|');
      add(parts.first, parts.last, e.value.name);
    }
    if (!isPrivate) {
      for (final r in cloud.values(kind)) {
        final o = r['origin'];
        final p = r['permission'];
        final d = r['decision'];
        if (o is String && p is String && d is String) add(o, p, d);
      }
    }
    out.sort((a, b) => a.origin.compareTo(b.origin));
    return out;
  }
}
