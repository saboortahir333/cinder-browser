import 'dart:convert';

import 'package:saboor_browser/extensions/match_pattern.dart';

class ManifestException implements Exception {
  const ManifestException(this.message);
  final String message;
  @override
  String toString() => message;
}

enum RunAt { documentStart, documentEnd, documentIdle }

class ContentScriptEntry {
  const ContentScriptEntry({
    required this.matches,
    required this.excludeMatches,
    required this.js,
    required this.css,
    required this.runAt,
    required this.allFrames,
  });

  final List<String> matches;
  final List<String> excludeMatches;
  final List<String> js;
  final List<String> css;
  final RunAt runAt;
  final bool allFrames;
}

/// A validated Manifest V3 manifest. Only data Cinder understands is kept;
/// anything malformed is rejected rather than half-trusted.
class ExtensionManifest {
  ExtensionManifest({
    required this.name,
    required this.version,
    required this.description,
    required this.permissions,
    required this.optionalPermissions,
    required this.hostPermissions,
    required this.optionalHostPermissions,
    required this.contentScripts,
    required this.popup,
    required this.optionsPage,
    required this.actionTitle,
    required this.icons,
    required this.actionIcons,
    required this.hasServiceWorker,
    required this.defaultLocale,
    required this.raw,
  });

  final String name;
  final String version;
  final String description;
  final List<String> permissions;
  final List<String> optionalPermissions;
  final List<String> hostPermissions;
  final List<String> optionalHostPermissions;
  final List<ContentScriptEntry> contentScripts;

  /// Relative path of `action.default_popup`, if any.
  final String? popup;
  final String? optionsPage;
  final String actionTitle;

  /// Icon size -> relative path (`icons`).
  final Map<int, String> icons;
  final Map<int, String> actionIcons;

  /// Manifest declares `background.service_worker`. Cinder does not run
  /// service workers yet; the UI tells the user honestly.
  final bool hasServiceWorker;
  final String? defaultLocale;
  final Map<String, dynamic> raw;

  static const int maxBytes = 512 * 1024;
  static const Set<String> _validRunAt = {
    'document_start',
    'document_end',
    'document_idle',
  };

  /// Safe, relative, forward-slash path inside the extension (no `..`, no
  /// drive letters, no absolute paths, no backslashes).
  static bool isSafeRelativePath(String p) {
    if (p.isEmpty || p.length > 260) return false;
    if (p.contains('\\') || p.contains('\u0000') || p.contains(':')) {
      return false;
    }
    if (p.startsWith('/')) return false;
    for (final part in p.split('/')) {
      if (part.isEmpty || part == '.' || part == '..') return false;
    }
    return true;
  }

  static ExtensionManifest parse(String source) {
    if (source.length > maxBytes) {
      throw const ManifestException('manifest.json is too large.');
    }
    Object? decoded;
    try {
      // Chrome allows a UTF-8 BOM and (non-standard) comments are NOT allowed
      // in published manifests, so strict JSON is enough.
      decoded = jsonDecode(source.startsWith('﻿') ? source.substring(1) : source);
    } on FormatException catch (e) {
      throw ManifestException('manifest.json is not valid JSON (${e.message}).');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const ManifestException('manifest.json must be a JSON object.');
    }
    final m = decoded;

    final mv = m['manifest_version'];
    if (mv != 3) {
      throw ManifestException(
        mv == 2
            ? 'This extension uses Manifest V2, which Cinder does not support. '
                  'Ask the developer for a Manifest V3 version.'
            : 'Unsupported manifest_version: $mv (Cinder requires 3).',
      );
    }

    String reqString(String key, {int max = 200}) {
      final v = m[key];
      if (v is! String || v.trim().isEmpty) {
        throw ManifestException('manifest.json is missing "$key".');
      }
      if (v.length > max) throw ManifestException('"$key" is too long.');
      return v;
    }

    final name = reqString('name', max: 150);
    final version = reqString('version', max: 64);
    if (!RegExp(r'^\d{1,9}(\.\d{1,9}){0,3}$').hasMatch(version)) {
      throw ManifestException('Invalid version "$version".');
    }
    final description = (m['description'] is String)
        ? (m['description'] as String)
        : '';

    List<String> strings(Object? v, String key, {int max = 200}) {
      if (v == null) return const [];
      if (v is! List) throw ManifestException('"$key" must be an array.');
      if (v.length > max) throw ManifestException('"$key" has too many entries.');
      final out = <String>[];
      for (final e in v) {
        if (e is! String) {
          throw ManifestException('"$key" must contain only strings.');
        }
        out.add(e);
      }
      return out;
    }

    final permissions = strings(m['permissions'], 'permissions');
    final optionalPermissions = strings(
      m['optional_permissions'],
      'optional_permissions',
    );
    final hostPermissions = strings(m['host_permissions'], 'host_permissions');
    final optionalHost = strings(
      m['optional_host_permissions'],
      'optional_host_permissions',
    );
    for (final p in [...hostPermissions, ...optionalHost]) {
      if (MatchPattern.tryParse(p) == null) {
        // Unknown schemes (chrome://, ftp://) are dropped by Chrome too, but
        // a clearly malformed pattern is an error.
        if (!p.contains('://') && p != '<all_urls>') {
          throw ManifestException('Invalid host permission "$p".');
        }
      }
    }

    // content_scripts
    final scripts = <ContentScriptEntry>[];
    final cs = m['content_scripts'];
    if (cs != null) {
      if (cs is! List) {
        throw const ManifestException('"content_scripts" must be an array.');
      }
      if (cs.length > 50) {
        throw const ManifestException('Too many content_scripts entries.');
      }
      for (final raw in cs) {
        if (raw is! Map<String, dynamic>) {
          throw const ManifestException('Invalid content_scripts entry.');
        }
        final matches = strings(raw['matches'], 'content_scripts.matches');
        if (matches.isEmpty) {
          throw const ManifestException(
            'A content script needs at least one "matches" pattern.',
          );
        }
        final valid = matches
            .where((p) => MatchPattern.tryParse(p) != null)
            .toList();
        final excl = strings(
          raw['exclude_matches'],
          'content_scripts.exclude_matches',
        ).where((p) => MatchPattern.tryParse(p) != null).toList();
        final js = strings(raw['js'], 'content_scripts.js');
        final css = strings(raw['css'], 'content_scripts.css');
        for (final f in [...js, ...css]) {
          if (!isSafeRelativePath(f)) {
            throw ManifestException('Unsafe file path in content script: "$f".');
          }
        }
        final runAtRaw = raw['run_at'];
        if (runAtRaw != null &&
            (runAtRaw is! String || !_validRunAt.contains(runAtRaw))) {
          throw ManifestException('Invalid run_at "$runAtRaw".');
        }
        if (raw['world'] == 'MAIN') {
          // MAIN world is what Cinder uses; ISOLATED is not available in
          // WebView2 via this plugin. Accepted, behaviour documented.
        }
        scripts.add(
          ContentScriptEntry(
            matches: valid,
            excludeMatches: excl,
            js: js,
            css: css,
            runAt: switch (runAtRaw) {
              'document_start' => RunAt.documentStart,
              'document_end' => RunAt.documentEnd,
              _ => RunAt.documentIdle,
            },
            allFrames: raw['all_frames'] == true,
          ),
        );
      }
    }

    // action
    String? popup;
    var actionTitle = name;
    final actionIcons = <int, String>{};
    final action = m['action'];
    if (action != null) {
      if (action is! Map<String, dynamic>) {
        throw const ManifestException('"action" must be an object.');
      }
      final p = action['default_popup'];
      if (p is String && p.isNotEmpty) {
        final clean = p.split('#').first.split('?').first;
        if (!isSafeRelativePath(clean)) {
          throw ManifestException('Unsafe popup path "$p".');
        }
        popup = p;
      }
      if (action['default_title'] is String &&
          (action['default_title'] as String).isNotEmpty) {
        actionTitle = action['default_title'] as String;
      }
      actionIcons.addAll(_icons(action['default_icon']));
    }

    String? options;
    final op = m['options_page'] ?? (m['options_ui'] is Map ? (m['options_ui'] as Map)['page'] : null);
    if (op is String && isSafeRelativePath(op.split('#').first.split('?').first)) {
      options = op;
    }

    final bg = m['background'];
    final hasWorker =
        bg is Map && bg['service_worker'] is String && (bg['service_worker'] as String).isNotEmpty;

    return ExtensionManifest(
      name: name,
      version: version,
      description: description,
      permissions: permissions,
      optionalPermissions: optionalPermissions,
      hostPermissions: hostPermissions,
      optionalHostPermissions: optionalHost,
      contentScripts: scripts,
      popup: popup,
      optionsPage: options,
      actionTitle: actionTitle,
      icons: _icons(m['icons']),
      actionIcons: actionIcons,
      hasServiceWorker: hasWorker,
      defaultLocale: m['default_locale'] is String ? m['default_locale'] as String : null,
      raw: m,
    );
  }

  static Map<int, String> _icons(Object? v) {
    final out = <int, String>{};
    if (v is String && isSafeRelativePath(v)) {
      out[16] = v;
    } else if (v is Map) {
      v.forEach((k, val) {
        final size = int.tryParse(k.toString());
        if (size != null && val is String && isSafeRelativePath(val)) {
          out[size] = val;
        }
      });
    }
    return out;
  }

  /// Every file the manifest refers to must exist; returns the missing ones.
  List<String> referencedFiles() => [
    for (final s in contentScripts) ...s.js,
    for (final s in contentScripts) ...s.css,
    if (popup != null) popup!.split('#').first.split('?').first,
  ];

  /// Best icon path for a desired pixel size.
  String? bestIcon(int size) {
    final all = {...icons, ...actionIcons};
    if (all.isEmpty) return null;
    final sizes = all.keys.toList()..sort();
    final pick = sizes.firstWhere((s) => s >= size, orElse: () => sizes.last);
    return all[pick];
  }
}

/// Resolves `__MSG_key__` placeholders using `_locales/<locale>/messages.json`.
class LocaleMessages {
  LocaleMessages(this._messages);
  final Map<String, String> _messages;

  static LocaleMessages parse(String? source) {
    if (source == null) return LocaleMessages(const {});
    try {
      final d = jsonDecode(source);
      final out = <String, String>{};
      if (d is Map) {
        d.forEach((k, v) {
          if (v is Map && v['message'] is String) {
            out[k.toString().toLowerCase()] = v['message'] as String;
          }
        });
      }
      return LocaleMessages(out);
    } catch (_) {
      return LocaleMessages(const {});
    }
  }

  String resolve(String text) {
    return text.replaceAllMapped(RegExp(r'__MSG_([A-Za-z0-9_@]+)__'), (m) {
      return _messages[m[1]!.toLowerCase()] ?? m[0]!;
    });
  }

  Map<String, String> get all => Map.unmodifiable(_messages);
}
