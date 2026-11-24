import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import 'package:saboor_browser/extensions/manifest.dart';
import 'package:saboor_browser/extensions/package_format.dart';
import 'package:saboor_browser/extensions/permissions.dart';

enum ExtensionSource { chromeWebStore, edgeAddons, packageFile, unpacked, url }

/// An extension that is installed on this device.
class InstalledExtension {
  InstalledExtension({
    required this.id,
    required this.manifest,
    required this.locale,
    required this.contentDir,
    required this.source,
    required this.signed,
    required this.grants,
    this.enabled = true,
    this.allowInPrivate = false,
    this.pinned = true,
    this.storeId,
    this.installedAt,
  });

  final String id;
  ExtensionManifest manifest;
  LocaleMessages locale;

  /// Folder holding manifest.json (a copy owned by Cinder, or the developer's
  /// own folder for unpacked extensions).
  String contentDir;
  final ExtensionSource source;

  /// True when the package carried a valid developer signature.
  final bool signed;
  ExtensionGrants grants;
  bool enabled;
  bool allowInPrivate;
  bool pinned;

  /// Id in the originating store (same as [id] for store installs).
  final String? storeId;
  DateTime? installedAt;

  String get name => locale.resolve(manifest.name);
  String get description => locale.resolve(manifest.description);
  String get version => manifest.version;
  String get actionTitle => locale.resolve(manifest.actionTitle);

  bool get hasPopup => manifest.popup != null;
  bool get isUnpacked => source == ExtensionSource.unpacked;

  /// Absolute path of the best toolbar icon, or null.
  String? iconFile([int size = 32]) {
    final rel = manifest.bestIcon(size);
    if (rel == null) return null;
    final f = File('$contentDir${Platform.pathSeparator}${rel.replaceAll('/', Platform.pathSeparator)}');
    return f.existsSync() ? f.path : null;
  }

  /// True if this extension can run in the current window kind.
  bool activeIn({required bool isPrivate}) =>
      enabled && (!isPrivate || allowInPrivate);

  Map<String, dynamic> metaJson() => {
    'v': 1,
    'id': id,
    'version': manifest.version,
    'source': source.name,
    'signed': signed,
    'enabled': enabled,
    'allowInPrivate': allowInPrivate,
    'pinned': pinned,
    'grants': grants.toJson(),
    'storeId': storeId,
    'installedAt': installedAt?.toIso8601String(),
    'contentDir': contentDir,
  };
}

/// A package that has been downloaded, verified and unpacked but not yet
/// approved by the user.
class PendingInstall {
  PendingInstall({
    required this.id,
    required this.manifest,
    required this.locale,
    required this.stagingDir,
    required this.source,
    required this.signed,
    required this.storeId,
    this.previous,
    this.unpackedPath,
  });

  final String id;
  final ExtensionManifest manifest;
  final LocaleMessages locale;
  final Directory stagingDir;
  final ExtensionSource source;
  final bool signed;
  final String? storeId;
  final InstalledExtension? previous;
  final String? unpackedPath;

  String get name => locale.resolve(manifest.name);
  bool get isUpdate => previous != null;

  /// Permissions requested now that the previous version did not have.
  List<String> get addedPermissions {
    final prev = previous;
    if (prev == null) return manifest.permissions;
    return [
      for (final p in manifest.permissions)
        if (!prev.manifest.permissions.contains(p)) p,
    ];
  }

  bool get addsHostAccess {
    final prev = previous;
    if (prev == null) return true;
    final before = {...prev.manifest.hostPermissions, for (final s in prev.manifest.contentScripts) ...s.matches};
    final after = {...manifest.hostPermissions, for (final s in manifest.contentScripts) ...s.matches};
    return after.difference(before).isNotEmpty;
  }
}

class ExtensionInstallException implements Exception {
  const ExtensionInstallException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Owns the installed-extension list, the install pipeline and per-extension
/// state. All file locations and limits are enforced here, not in the UI.
class ExtensionManager extends ChangeNotifier {
  ExtensionManager._();
  static final ExtensionManager instance = ExtensionManager._();

  /// For tests.
  @visibleForTesting
  ExtensionManager.forTest();

  Directory? _root;
  bool _isPrivate = false;
  final Map<String, InstalledExtension> _byId = {};
  final Random _rand = Random.secure();

  bool get isPrivateWindow => _isPrivate;
  Directory? get root => _root;

  List<InstalledExtension> get all {
    final l = _byId.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return List.unmodifiable(l);
  }

  /// Extensions that are active in this window.
  List<InstalledExtension> get active =>
      all.where((e) => e.activeIn(isPrivate: _isPrivate)).toList();

  InstalledExtension? byId(String id) => _byId[id];

  /// Default location: %LOCALAPPDATA%\Cinder\Extensions\<profile>\ .
  static Directory defaultRoot(String profileId) {
    final base = Platform.environment['LOCALAPPDATA'] ??
        Platform.environment['HOME'] ??
        Directory.systemTemp.path;
    return Directory(
      '$base${Platform.pathSeparator}Cinder${Platform.pathSeparator}Extensions'
      '${Platform.pathSeparator}$profileId',
    );
  }

  Future<void> init({
    required Directory root,
    required bool isPrivate,
  }) async {
    _root = root;
    _isPrivate = isPrivate;
    await root.create(recursive: true);
    // Staging leftovers from a crash are never trusted.
    final staging = Directory('${root.path}${Platform.pathSeparator}.staging');
    if (staging.existsSync()) {
      try {
        staging.deleteSync(recursive: true);
      } catch (_) {}
    }
    _byId.clear();
    await for (final e in root.list(followLinks: false)) {
      if (e is! Directory) continue;
      final id = e.path.split(Platform.pathSeparator).last;
      if (!kExtensionId.hasMatch(id)) continue;
      final ext = await _loadOne(id, e);
      if (ext != null) _byId[id] = ext;
    }
    notifyListeners();
  }

  Future<InstalledExtension?> _loadOne(String id, Directory dir) async {
    try {
      final metaFile = File('${dir.path}${Platform.pathSeparator}meta.json');
      if (!metaFile.existsSync()) return null;
      final meta = jsonDecode(await metaFile.readAsString());
      if (meta is! Map) return null;
      var contentDir = meta['contentDir'];
      if (contentDir is! String) return null;
      final source = ExtensionSource.values.firstWhere(
        (s) => s.name == meta['source'],
        orElse: () => ExtensionSource.packageFile,
      );
      // Cinder-owned copies must live under this extension's own folder.
      if (source != ExtensionSource.unpacked) {
        final expectedPrefix = '${dir.path}${Platform.pathSeparator}';
        if (!contentDir.startsWith(expectedPrefix)) return null;
      }
      final manifestFile = File('$contentDir${Platform.pathSeparator}manifest.json');
      if (!manifestFile.existsSync()) return null;
      final manifest = ExtensionManifest.parse(await manifestFile.readAsString());
      final locale = await _readLocale(contentDir, manifest);
      final grants = ExtensionGrants.fromJson(meta['grants']);
      // Never keep a grant the (possibly updated) manifest does not request.
      grants.permissions.removeWhere((p) => !manifest.permissions.contains(p) && !manifest.optionalPermissions.contains(p));
      return InstalledExtension(
        id: id,
        manifest: manifest,
        locale: locale,
        contentDir: contentDir,
        source: source,
        signed: meta['signed'] == true,
        grants: grants,
        enabled: meta['enabled'] != false,
        allowInPrivate: meta['allowInPrivate'] == true,
        pinned: meta['pinned'] != false,
        storeId: meta['storeId'] as String?,
        installedAt: DateTime.tryParse('${meta['installedAt']}'),
      );
    } catch (e) {
      debugPrint('Extension $id could not be loaded: $e');
      return null;
    }
  }

  static Future<LocaleMessages> _readLocale(String dir, ExtensionManifest m) async {
    final locale = m.defaultLocale;
    if (locale == null || !RegExp(r'^[A-Za-z0-9_]{2,10}$').hasMatch(locale)) {
      return LocaleMessages(const {});
    }
    final f = File('$dir${Platform.pathSeparator}_locales${Platform.pathSeparator}$locale${Platform.pathSeparator}messages.json');
    if (!f.existsSync() || f.lengthSync() > 1024 * 1024) {
      return LocaleMessages(const {});
    }
    return LocaleMessages.parse(await f.readAsString());
  }

  // -------------------------------------------------------------------------
  // Install pipeline
  // -------------------------------------------------------------------------

  Directory _newStaging() {
    final r = _root;
    if (r == null) throw const ExtensionInstallException('Extensions are not ready yet.');
    final token = base64Url
        .encode(List<int>.generate(12, (_) => _rand.nextInt(256)))
        .replaceAll('=', '');
    return Directory('${r.path}${Platform.pathSeparator}.staging${Platform.pathSeparator}$token')
      ..createSync(recursive: true);
  }

  /// Verifies and unpacks [bytes] (a CRX3 or a zip) without installing it.
  Future<PendingInstall> prepareFromBytes(
    Uint8List bytes, {
    required ExtensionSource source,
    String? expectedId,
  }) async {
    if (bytes.length > PackageLimits.maxDownloadBytes) {
      throw const ExtensionInstallException('The extension is too large.');
    }
    final staging = _newStaging();
    try {
      late final Uint8List zip;
      String? id;
      var signed = false;
      if (Crx3.looksLikeCrx(bytes)) {
        final c = await Crx3.open(bytes);
        id = c.id;
        zip = c.zip;
        signed = true;
        if (expectedId != null && expectedId != id) {
          throw const ExtensionInstallException(
            'The downloaded package is signed for a different extension. It was not installed.',
          );
        }
      } else {
        if (expectedId != null) {
          // A store install must always be a signed CRX.
          throw const ExtensionInstallException(
            'The store returned an unsigned package. It was not installed.',
          );
        }
        zip = bytes;
      }
      final contentDir = Directory('${staging.path}${Platform.pathSeparator}c')..createSync();
      final extracted = ZipExtractor.extract(zip, contentDir);
      final manifest = ExtensionManifest.parse(extracted.manifestSource);
      id ??= _idForUnsigned(manifest, null);
      return await _finishPending(
        id: id,
        manifest: manifest,
        staging: staging,
        contentDir: contentDir,
        source: source,
        signed: signed,
        storeId: signed ? id : null,
      );
    } catch (e) {
      _safeDelete(staging);
      if (e is ExtensionInstallException) rethrow;
      throw ExtensionInstallException(e.toString());
    }
  }

  /// Registers a developer folder in place (not copied).
  Future<PendingInstall> prepareUnpacked(String folder) async {
    final dir = Directory(folder);
    if (!dir.existsSync()) {
      throw const ExtensionInstallException('That folder does not exist.');
    }
    final mf = File('${dir.path}${Platform.pathSeparator}manifest.json');
    if (!mf.existsSync()) {
      throw const ExtensionInstallException('There is no manifest.json in that folder.');
    }
    if (mf.lengthSync() > ExtensionManifest.maxBytes) {
      throw const ExtensionInstallException('manifest.json is too large.');
    }
    final staging = _newStaging();
    try {
      final manifest = ExtensionManifest.parse(await mf.readAsString());
      final id = _idForUnsigned(manifest, dir.absolute.path);
      return await _finishPending(
        id: id,
        manifest: manifest,
        staging: staging,
        contentDir: dir,
        source: ExtensionSource.unpacked,
        signed: false,
        storeId: null,
        unpackedPath: dir.absolute.path,
      );
    } catch (e) {
      _safeDelete(staging);
      if (e is ExtensionInstallException) rethrow;
      throw ExtensionInstallException(e.toString());
    }
  }

  String _idForUnsigned(ExtensionManifest m, String? path) {
    final key = m.raw['key'];
    if (key is String && key.isNotEmpty) {
      try {
        return extensionIdFromPublicKey(base64.decode(key));
      } catch (_) {}
    }
    final seed = path != null ? 'unpacked:${path.toLowerCase()}' : 'local:${m.name}';
    return extensionIdFromHash(sha256.convert(utf8.encode(seed)).bytes);
  }

  Future<PendingInstall> _finishPending({
    required String id,
    required ExtensionManifest manifest,
    required Directory staging,
    required Directory contentDir,
    required ExtensionSource source,
    required bool signed,
    required String? storeId,
    String? unpackedPath,
  }) async {
    for (final rel in manifest.referencedFiles()) {
      final f = File('${contentDir.path}${Platform.pathSeparator}${rel.replaceAll('/', Platform.pathSeparator)}');
      if (!f.existsSync()) {
        throw ExtensionInstallException('The extension is missing a file it needs: $rel');
      }
    }
    final locale = await _readLocale(contentDir.path, manifest);
    final previous = _byId[id];
    if (previous != null && previous.source != source && source != ExtensionSource.packageFile) {
      // Allowed (e.g. reinstall from another store), but never silently.
    }
    return PendingInstall(
      id: id,
      manifest: manifest,
      locale: locale,
      stagingDir: staging,
      source: source,
      signed: signed,
      storeId: storeId,
      previous: previous,
      unpackedPath: unpackedPath,
    );
  }

  /// Completes an install the user approved with [grants].
  Future<InstalledExtension> commit(
    PendingInstall pending, {
    required ExtensionGrants grants,
    bool allowInPrivate = false,
  }) async {
    final r = _root!;
    final extDir = Directory('${r.path}${Platform.pathSeparator}${pending.id}')
      ..createSync(recursive: true);
    late String contentDir;
    if (pending.unpackedPath != null) {
      contentDir = pending.unpackedPath!;
    } else {
      final versionDir = Directory(
        '${extDir.path}${Platform.pathSeparator}v${pending.manifest.version}_${DateTime.now().millisecondsSinceEpoch}',
      );
      final from = Directory('${pending.stagingDir.path}${Platform.pathSeparator}c');
      await from.rename(versionDir.path);
      contentDir = versionDir.path;
    }
    final previous = pending.previous;
    final ext = InstalledExtension(
      id: pending.id,
      manifest: pending.manifest,
      locale: pending.locale,
      contentDir: contentDir,
      source: pending.source,
      signed: pending.signed,
      grants: grants,
      enabled: true,
      allowInPrivate: previous?.allowInPrivate ?? allowInPrivate,
      pinned: previous?.pinned ?? true,
      storeId: pending.storeId,
      installedAt: DateTime.now(),
    );
    await _writeMeta(ext);
    _byId[ext.id] = ext;
    _safeDelete(pending.stagingDir);
    // Remove superseded versions only after the new one is recorded.
    if (previous != null && previous.contentDir != contentDir && !previous.isUnpacked) {
      _safeDelete(Directory(previous.contentDir));
    }
    notifyListeners();
    return ext;
  }

  void discard(PendingInstall pending) => _safeDelete(pending.stagingDir);

  Future<void> _writeMeta(InstalledExtension ext) async {
    final r = _root;
    if (r == null) return;
    final dir = Directory('${r.path}${Platform.pathSeparator}${ext.id}')..createSync(recursive: true);
    final target = File('${dir.path}${Platform.pathSeparator}meta.json');
    final tmp = File('${target.path}.tmp');
    await tmp.writeAsString(jsonEncode(ext.metaJson()), flush: true);
    if (target.existsSync()) target.deleteSync();
    await tmp.rename(target.path);
  }

  // -------------------------------------------------------------------------
  // State changes
  // -------------------------------------------------------------------------

  Future<void> update(String id, void Function(InstalledExtension e) change) async {
    final e = _byId[id];
    if (e == null) return;
    change(e);
    await _writeMeta(e);
    notifyListeners();
  }

  Future<void> setEnabled(String id, bool value) => update(id, (e) => e.enabled = value);
  Future<void> setAllowInPrivate(String id, bool value) =>
      update(id, (e) => e.allowInPrivate = value);
  Future<void> setPinned(String id, bool value) => update(id, (e) => e.pinned = value);

  Future<void> setSiteAccess(String id, SiteAccess access) =>
      update(id, (e) => e.grants.siteAccess = access);

  Future<void> addSpecificSite(String id, String pattern) =>
      update(id, (e) => e.grants.specificSites.add(pattern));

  Future<void> removeSpecificSite(String id, String pattern) =>
      update(id, (e) => e.grants.specificSites.remove(pattern));

  Future<void> setPermission(String id, String permission, bool granted) =>
      update(id, (e) {
        final allowed = e.manifest.permissions.contains(permission) ||
            e.manifest.optionalPermissions.contains(permission);
        if (!allowed) return;
        granted ? e.grants.permissions.add(permission) : e.grants.permissions.remove(permission);
      });

  /// "Run once" for the activeTab-style onClick access (not persisted).
  void grantActiveTab(String id, String origin) {
    final e = _byId[id];
    if (e == null || origin.isEmpty) return;
    e.grants.activeTabOrigins.add(origin);
    notifyListeners();
  }

  Future<void> uninstall(String id) async {
    final e = _byId.remove(id);
    final r = _root;
    if (e != null && r != null) {
      _safeDelete(Directory('${r.path}${Platform.pathSeparator}$id'));
    }
    notifyListeners();
  }

  /// Directory for an extension's own data (storage). Never inside the
  /// content folder, so unpacked folders stay clean.
  Directory dataDir(String id) {
    final r = _root!;
    return Directory('${r.path}${Platform.pathSeparator}$id${Platform.pathSeparator}data')
      ..createSync(recursive: true);
  }

  static void _safeDelete(FileSystemEntity e) {
    try {
      if (e.existsSync()) e.deleteSync(recursive: true);
    } catch (_) {}
  }
}
