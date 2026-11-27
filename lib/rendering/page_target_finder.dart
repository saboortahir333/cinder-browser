import 'dart:async';

import 'package:saboor_browser/rendering/cdp_connection.dart';

/// Finds the DevTools target that belongs to one Cinder tab.
///
/// The plugin gives no mapping from a `WebviewController` to its DevTools
/// target, and several tabs can show the same address, so matching on the URL
/// alone is unreliable. Instead the tab is *marked*: [mark] runs a script in
/// the tab's own page that prefixes `window.name` with `marker|` (keeping the
/// page's own value after the bar), then every page target is asked for its
/// `window.name` and the one that starts with [marker] wins. The page's
/// original `window.name` is put back as soon as the tab is found, so sites
/// that use it are not affected. Once a target id is known it is cached by the
/// caller, so marking is only needed again if the target goes away.
Future<String?> findPageTarget(
  CdpTransport transport, {
  required String marker,
  required Future<void> Function() mark,
  String? url,
}) async {
  try {
    await mark();
  } catch (_) {
    // Fall through: the URL fallback below may still find a single match.
  }

  final infos = await _pageTargets(transport);

  for (final info in infos) {
    final id = info['targetId'] as String?;
    if (id == null) continue;
    final name = await _windowName(transport, id);
    if (name != null && (name == marker || name.startsWith('$marker|'))) {
      await _restoreName(transport, id, marker);
      return id;
    }
  }

  if (url != null && url.isNotEmpty) {
    final same = [
      for (final i in infos)
        if (i['url'] == url) i['targetId'] as String?,
    ].whereType<String>().toList();
    if (same.length == 1) return same.single;
  }
  return null;
}

/// Whether [targetId] still exists (cheap check before reusing a cached id).
Future<bool> targetExists(CdpTransport transport, String targetId) async {
  try {
    final r = await transport.send('Target.getTargetInfo', {
      'targetId': targetId,
    });
    return r['targetInfo'] is Map;
  } catch (_) {
    return false;
  }
}

Future<List<Map<String, dynamic>>> _pageTargets(CdpTransport t) async {
  final r = await t.send('Target.getTargets');
  final out = <Map<String, dynamic>>[];
  for (final raw in (r['targetInfos'] as List? ?? const [])) {
    if (raw is! Map) continue;
    final info = raw.cast<String, dynamic>();
    final url = '${info['url'] ?? ''}';
    if (info['type'] != 'page') continue;
    // Cinder's own docked DevTools frontend is never a tab.
    if (url.startsWith('devtools://') || url.contains('inspector.html')) {
      continue;
    }
    out.add(info);
  }
  return out;
}

/// Removes the `marker|` prefix again, leaving the page's own window.name.
Future<void> _restoreName(
  CdpTransport t,
  String targetId,
  String marker,
) async {
  String? session;
  try {
    final a = await t.send('Target.attachToTarget', {
      'targetId': targetId,
      'flatten': true,
    });
    session = a['sessionId'] as String?;
    if (session == null) return;
    // The marker is a fixed internal string ("cinder-tab:<id>"), never page
    // or user input.
    await t.send('Runtime.evaluate', {
      'expression':
          "(function(m){if(window.name===m){window.name='';}"
          "else if(window.name.indexOf(m+'|')===0){"
          'window.name=window.name.slice(m.length+1);}})(\'$marker\')',
      'returnByValue': true,
    }, session);
  } catch (_) {
    // Best effort: the marker is harmless if it stays.
  } finally {
    if (session != null) {
      unawaited(
        t
            .send('Target.detachFromTarget', {'sessionId': session})
            .then((_) {}, onError: (_) {}),
      );
    }
  }
}

Future<String?> _windowName(CdpTransport t, String targetId) async {
  String? session;
  try {
    final a = await t.send('Target.attachToTarget', {
      'targetId': targetId,
      'flatten': true,
    });
    session = a['sessionId'] as String?;
    if (session == null) return null;
    final r = await t.send('Runtime.evaluate', {
      'expression': 'window.name',
      'returnByValue': true,
    }, session);
    final value = (r['result'] as Map?)?['value'];
    return value is String ? value : null;
  } catch (_) {
    return null;
  } finally {
    if (session != null) {
      unawaited(
        t
            .send('Target.detachFromTarget', {'sessionId': session})
            .then((_) {}, onError: (_) {}),
      );
    }
  }
}
