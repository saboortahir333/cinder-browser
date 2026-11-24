import 'dart:io';
import 'dart:typed_data';

import 'package:saboor_browser/extensions/extension_manager.dart';
import 'package:saboor_browser/extensions/package_format.dart';
import 'package:saboor_browser/extensions/permissions.dart';
import 'package:saboor_browser/extensions/web_store.dart';

/// What the user decided in the permission prompt.
class InstallDecision {
  const InstallDecision({required this.grants, this.allowInPrivate = false});
  final ExtensionGrants grants;
  final bool allowInPrivate;
}

typedef ConfirmInstall = Future<InstallDecision?> Function(PendingInstall pending);

/// The user-facing install flows. Every path ends in [ConfirmInstall]: nothing
/// is installed without the user seeing what it can do.
class ExtensionInstaller {
  ExtensionInstaller({ExtensionManager? manager, WebStoreClient? store})
    : manager = manager ?? ExtensionManager.instance,
      store = store ?? WebStoreClient();

  final ExtensionManager manager;
  final WebStoreClient store;

  Future<InstalledExtension?> _finish(PendingInstall pending, ConfirmInstall confirm) async {
    final decision = await confirm(pending);
    if (decision == null) {
      manager.discard(pending);
      return null;
    }
    return manager.commit(
      pending,
      grants: decision.grants,
      allowInPrivate: decision.allowInPrivate,
    );
  }

  /// Install from a store id / URL.
  Future<InstalledExtension?> fromStore(
    String input,
    ConfirmInstall confirm, {
    void Function(int received, int? total)? onProgress,
  }) async {
    final ref = StoreRef.parse(input);
    if (ref == null) {
      throw const ExtensionInstallException(
        'Enter a Chrome Web Store or Microsoft Edge Add-ons link, or a 32-letter extension id.',
      );
    }
    final Uint8List bytes;
    try {
      bytes = await store.downloadExtension(ref, onProgress: onProgress);
    } on StoreException catch (e) {
      throw ExtensionInstallException(e.message);
    }
    final pending = await manager.prepareFromBytes(
      bytes,
      source: ref.source,
      expectedId: ref.id,
    );
    return _finish(pending, confirm);
  }

  /// Install from a local .crx / .zip.
  Future<InstalledExtension?> fromFile(String path, ConfirmInstall confirm) async {
    final f = File(path);
    if (!f.existsSync()) {
      throw const ExtensionInstallException('That file does not exist.');
    }
    if (f.lengthSync() > PackageLimits.maxDownloadBytes) {
      throw const ExtensionInstallException('The file is too large.');
    }
    final lower = path.toLowerCase();
    if (!lower.endsWith('.crx') && !lower.endsWith('.zip')) {
      throw const ExtensionInstallException('Choose a .crx or .zip file.');
    }
    final pending = await manager.prepareFromBytes(
      await f.readAsBytes(),
      source: ExtensionSource.packageFile,
    );
    return _finish(pending, confirm);
  }

  /// Developer mode: load a folder in place.
  Future<InstalledExtension?> fromFolder(String folder, ConfirmInstall confirm) async {
    final pending = await manager.prepareUnpacked(folder);
    return _finish(pending, confirm);
  }

  /// Checks every store-installed extension and returns those updated.
  /// Updates that need new permissions go through [confirm] again.
  Future<List<InstalledExtension>> updateAll(ConfirmInstall confirm) async {
    final updated = <InstalledExtension>[];
    for (final ext in manager.all) {
      if (ext.source != ExtensionSource.chromeWebStore || ext.storeId == null) continue;
      try {
        final ref = StoreRef(StoreKind.chrome, ext.storeId!);
        final available = await store.checkUpdate(ref, ext.version);
        if (available == null) continue;
        final bytes = await store.download(available.codebase);
        final pending = await manager.prepareFromBytes(
          bytes,
          source: ExtensionSource.chromeWebStore,
          expectedId: ext.id,
        );
        // Silent only when nothing new is requested; otherwise ask again.
        final needsConsent = pending.addedPermissions.isNotEmpty || pending.addsHostAccess;
        final InstallDecision? decision = needsConsent
            ? await confirm(pending)
            : InstallDecision(
                grants: ExtensionGrants(
                  permissions: {...ext.grants.permissions},
                  siteAccess: ext.grants.siteAccess,
                  specificSites: {...ext.grants.specificSites},
                ),
                allowInPrivate: ext.allowInPrivate,
              );
        if (decision == null) {
          manager.discard(pending);
          continue;
        }
        updated.add(await manager.commit(
          pending,
          grants: decision.grants,
          allowInPrivate: decision.allowInPrivate,
        ));
      } on Object {
        continue; // one failing extension must not block the rest
      }
    }
    return updated;
  }
}
