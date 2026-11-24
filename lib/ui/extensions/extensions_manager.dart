import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'package:saboor_browser/extensions/extension_installer.dart';
import 'package:saboor_browser/extensions/extension_manager.dart';
import 'package:saboor_browser/extensions/match_pattern.dart';
import 'package:saboor_browser/extensions/permissions.dart';
import 'package:saboor_browser/models/browser_palette.dart';
import 'package:saboor_browser/ui/chrome/chrome_widgets.dart';
import 'package:saboor_browser/ui/extensions/install_prompt.dart';

/// Opens the Extensions manager.
Future<void> showExtensionsManager(
  BuildContext context,
  BrowserPalette palette, {
  required bool isPrivateWindow,
  required void Function(String url) openUrl,
  required void Function(InstalledExtension ext) openOptions,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: palette.chrome,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860, maxHeight: 680),
        child: ExtensionsManagerView(
          palette: palette,
          isPrivateWindow: isPrivateWindow,
          openUrl: openUrl,
          openOptions: openOptions,
          onClose: () => Navigator.pop(ctx),
        ),
      ),
    ),
  );
}

class ExtensionsManagerView extends StatefulWidget {
  const ExtensionsManagerView({
    super.key,
    required this.palette,
    required this.isPrivateWindow,
    required this.openUrl,
    required this.openOptions,
    required this.onClose,
  });

  final BrowserPalette palette;
  final bool isPrivateWindow;
  final void Function(String url) openUrl;
  final void Function(InstalledExtension ext) openOptions;
  final VoidCallback onClose;

  @override
  State<ExtensionsManagerView> createState() => _ExtensionsManagerViewState();
}

class _ExtensionsManagerViewState extends State<ExtensionsManagerView> {
  final ExtensionManager _mgr = ExtensionManager.instance;
  late final ExtensionInstaller _installer = ExtensionInstaller();
  final TextEditingController _storeInput = TextEditingController();
  final Set<String> _expanded = {};
  final TextEditingController _siteInput = TextEditingController();
  String? _status;
  bool _statusIsError = false;
  bool _busy = false;
  double? _progress;

  BrowserPalette get p => widget.palette;

  @override
  void initState() {
    super.initState();
    _mgr.addListener(_changed);
  }

  @override
  void dispose() {
    _mgr.removeListener(_changed);
    _storeInput.dispose();
    _siteInput.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _say(String text, {bool error = false}) {
    setState(() {
      _status = text;
      _statusIsError = error;
    });
  }

  Future<InstallDecision?> _confirm(PendingInstall pending) => showInstallPrompt(
    context,
    p,
    pending,
    isPrivateWindow: widget.isPrivateWindow,
  );

  Future<void> _run(String doing, Future<InstalledExtension?> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _progress = null;
    });
    _say(doing);
    try {
      final ext = await action();
      if (!mounted) return;
      if (ext == null) {
        _say('Cancelled.');
      } else {
        _say('Added “${ext.name}”.');
        _expanded.add(ext.id);
      }
    } on ExtensionInstallException catch (e) {
      if (mounted) _say(e.message, error: true);
    } catch (e) {
      if (mounted) _say('Could not install: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _fromStore() async {
    final text = _storeInput.text.trim();
    if (text.isEmpty) return;
    await _run('Downloading…', () async {
      final ext = await _installer.fromStore(
        text,
        _confirm,
        onProgress: (r, t) {
          if (mounted && t != null && t > 0) setState(() => _progress = r / t);
        },
      );
      if (ext != null) _storeInput.clear();
      return ext;
    });
  }

  Future<void> _fromFile() async {
    final f = await FilePicker.pickFile(
      dialogTitle: 'Choose an extension package',
      type: FileType.custom,
      allowedExtensions: const ['crx', 'zip'],
    );
    final path = f?.path;
    if (path == null) return;
    await _run('Reading package…', () => _installer.fromFile(path, _confirm));
  }

  Future<void> _fromFolder() async {
    final dir = await FilePicker.getDirectoryPath(dialogTitle: 'Select unpacked extension folder');
    if (dir == null) return;
    await _run('Loading folder…', () => _installer.fromFolder(dir, _confirm));
  }

  Future<void> _checkUpdates() async {
    if (_busy) return;
    setState(() => _busy = true);
    _say('Checking for updates…');
    try {
      final updated = await _installer.updateAll(_confirm);
      if (mounted) {
        _say(updated.isEmpty
            ? 'Your extensions are up to date.'
            : 'Updated ${updated.map((e) => e.name).join(', ')}.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(InstalledExtension e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: p.chrome,
        title: Text('Remove “${e.name}”?'),
        content: Text(
          e.isUnpacked
              ? 'Cinder will forget this extension. The folder on your computer is not deleted.'
              : 'Its files and saved data will be deleted from this device.',
        ),
        actions: [
          TextButton(autofocus: true, onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok == true) {
      await _mgr.uninstall(e.id);
      _say('Removed “${e.name}”.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = _mgr.all;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.extension_rounded, color: p.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text('Extensions', style: TextStyle(color: p.ink, fontSize: 21, fontWeight: FontWeight.w700)),
                ),
              ),
              IconButton(tooltip: 'Close', onPressed: widget.onClose, icon: const Icon(Icons.close_rounded)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Cinder runs Manifest V3 extensions: content scripts, toolbar popups and options pages. '
            'Background service workers are not supported yet.',
            style: TextStyle(color: p.muted, fontSize: 12.5),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _storeInput,
                  enabled: !_busy,
                  textInputAction: TextInputAction.go,
                  onSubmitted: (_) => _fromStore(),
                  decoration: const InputDecoration(
                    hintText: 'Paste a Chrome Web Store or Edge Add-ons link, or an extension id',
                    isDense: true,
                    prefixIcon: Icon(Icons.link_rounded, size: 18),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(onPressed: _busy ? null : _fromStore, child: const Text('Add')),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _busy ? null : _fromFile,
                icon: const Icon(Icons.archive_outlined, size: 18),
                label: const Text('Install from file…'),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : _fromFolder,
                icon: const Icon(Icons.folder_open_outlined, size: 18),
                label: const Text('Load unpacked…'),
              ),
              OutlinedButton.icon(
                onPressed: _busy || list.isEmpty ? null : _checkUpdates,
                icon: const Icon(Icons.system_update_alt_rounded, size: 18),
                label: const Text('Check for updates'),
              ),
              TextButton.icon(
                onPressed: () => widget.openUrl('https://chromewebstore.google.com/category/extensions'),
                icon: const Icon(Icons.storefront_outlined, size: 18),
                label: const Text('Browse Chrome Web Store'),
              ),
            ],
          ),
          if (_progress != null) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(value: _progress, minHeight: 3),
          ],
          if (_status != null)
            Semantics(
              liveRegion: true,
              child: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  _status!,
                  style: TextStyle(
                    color: _statusIsError ? const Color(0xFFD70022) : p.muted,
                    fontSize: 12.5,
                    fontWeight: _statusIsError ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ),
          const Divider(height: 26),
          Expanded(
            child: list.isEmpty
                ? _empty()
                : ListView.separated(
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, i) => _card(list[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _empty() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.extension_outlined, size: 44, color: p.muted),
        const SizedBox(height: 12),
        Text('No extensions yet', style: TextStyle(color: p.ink, fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Text(
          'Paste a store link above to add one. Every extension shows what it can do before it is installed.',
          textAlign: TextAlign.center,
          style: TextStyle(color: p.muted, fontSize: 12.5),
        ),
      ],
    ),
  );

  Widget _icon(InstalledExtension e, double size) {
    final f = e.iconFile(size.round() * 2);
    if (f != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.2),
        child: Image.file(File(f), width: size, height: size, fit: BoxFit.contain,
            errorBuilder: (_, _, _) => SiteGlyph(host: e.name, size: size)),
      );
    }
    return SiteGlyph(host: e.name, size: size);
  }

  Widget _chip(String text, {Color? color}) => Container(
    margin: const EdgeInsets.only(left: 6),
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: (color ?? p.muted).withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(text, style: TextStyle(color: color ?? p.muted, fontSize: 10.5, fontWeight: FontWeight.w600)),
  );

  Widget _card(InstalledExtension e) {
    final open = _expanded.contains(e.id);
    return Container(
      decoration: BoxDecoration(
        color: p.raised,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.soft),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => open ? _expanded.remove(e.id) : _expanded.add(e.id)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  _icon(e, 40),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(e.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: p.ink, fontSize: 14.5, fontWeight: FontWeight.w700)),
                            ),
                            const SizedBox(width: 6),
                            Text('v${e.version}', style: TextStyle(color: p.muted, fontSize: 11.5)),
                            if (e.isUnpacked) _chip('Developer'),
                            if (!e.signed && !e.isUnpacked) _chip('Unsigned', color: const Color(0xFFB36B00)),
                            if (e.manifest.hasServiceWorker) _chip('Limited', color: const Color(0xFFB36B00)),
                          ],
                        ),
                        if (e.description.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text(e.description,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: p.muted, fontSize: 12.5)),
                          ),
                      ],
                    ),
                  ),
                  Semantics(
                    label: 'Enable ${e.name}',
                    child: Switch(value: e.enabled, onChanged: (v) => _mgr.setEnabled(e.id, v)),
                  ),
                  Icon(open ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: p.muted),
                ],
              ),
            ),
          ),
          if (open) _details(e),
        ],
      ),
    );
  }

  Widget _section(String title) => Padding(
    padding: const EdgeInsets.only(top: 14, bottom: 6),
    child: Semantics(
      header: true,
      child: Text(title, style: TextStyle(color: p.ink, fontWeight: FontWeight.w700, fontSize: 13)),
    ),
  );

  Widget _details(InstalledExtension e) {
    final hasHosts = e.manifest.contentScripts.isNotEmpty || e.manifest.hostPermissions.isNotEmpty;
    final perms = PermissionPolicy.describe(e.manifest);
    final optional = e.manifest.optionalPermissions.where(PermissionCatalog.all.containsKey).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 1),
          if (hasHosts) ...[
            _section('Site access'),
            Text(PermissionPolicy.hostSummary(e.manifest), style: TextStyle(color: p.muted, fontSize: 12)),
            const SizedBox(height: 8),
            SegmentedButton<SiteAccess>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: SiteAccess.onAllSites, label: Text('On all sites')),
                ButtonSegment(value: SiteAccess.onClick, label: Text('On click')),
                ButtonSegment(value: SiteAccess.onSpecificSites, label: Text('On specific sites')),
              ],
              selected: {e.grants.siteAccess},
              onSelectionChanged: (s) => _mgr.setSiteAccess(e.id, s.first),
            ),
            if (e.grants.siteAccess == SiteAccess.onClick)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Runs only after you click its toolbar button on a page.',
                    style: TextStyle(color: p.muted, fontSize: 11.5)),
              ),
            if (e.grants.siteAccess == SiteAccess.onSpecificSites) _specificSites(e),
          ],
          _section('Options'),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Show in toolbar'),
            value: e.pinned,
            onChanged: (v) => _mgr.setPinned(e.id, v),
          ),
          if (!widget.isPrivateWindow)
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('Allow in private windows'),
              subtitle: const Text('It will be able to see what you do in private windows.'),
              value: e.allowInPrivate,
              onChanged: (v) => _mgr.setAllowInPrivate(e.id, v),
            ),
          _section('Permissions'),
          if (perms.isEmpty && optional.isEmpty)
            Text('This extension asks for no special permissions.', style: TextStyle(color: p.muted, fontSize: 12)),
          for (final perm in perms)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Icon(riskIcon(perm.risk), size: 16, color: riskColor(perm.risk, p)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(perm.warning, style: TextStyle(color: p.ink, fontSize: 12.5))),
                  if (!perm.supported) Text('not supported yet', style: TextStyle(color: p.muted, fontSize: 11)),
                ],
              ),
            ),
          for (final id in optional)
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(PermissionCatalog.infoFor(id).warning, style: const TextStyle(fontSize: 12.5)),
              subtitle: const Text('Optional'),
              value: e.grants.permissions.contains(id),
              onChanged: (v) => _mgr.setPermission(e.id, id, v),
            ),
          _section('Details'),
          SelectableText(
            'Source: ${sourceLabel(e.source)}\n'
            'Id: ${e.id}\n'
            '${e.signed ? 'Signature: verified' : 'Signature: none'}'
            '${e.installedAt != null ? '\nInstalled: ${e.installedAt!.toLocal().toString().split('.').first}' : ''}',
            style: TextStyle(color: p.muted, fontSize: 11.5, height: 1.5),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              if (e.manifest.optionsPage != null)
                OutlinedButton(onPressed: () => widget.openOptions(e), child: const Text('Extension options')),
              const Spacer(),
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: const Color(0xFFD70022)),
                onPressed: () => _remove(e),
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                label: const Text('Remove'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _specificSites(InstalledExtension e) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final s in e.grants.specificSites)
                InputChip(
                  label: Text(s),
                  onDeleted: () => _mgr.removeSpecificSite(e.id, s),
                  deleteButtonTooltipMessage: 'Remove $s',
                ),
              if (e.grants.specificSites.isEmpty)
                Text('No sites yet — it will not run anywhere.', style: TextStyle(color: p.muted, fontSize: 11.5)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _siteInput,
                  decoration: const InputDecoration(hintText: 'https://example.com/*', isDense: true),
                  onSubmitted: (_) => _addSite(e),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(onPressed: () => _addSite(e), child: const Text('Add site')),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _addSite(InstalledExtension e) async {
    var text = _siteInput.text.trim();
    if (text.isEmpty) return;
    if (!text.contains('://')) text = 'https://$text';
    if (!text.substring(text.indexOf('://') + 3).contains('/')) text = '$text/*';
    if (MatchPattern.tryParse(text) == null) {
      _say('“$text” is not a valid site pattern. Example: https://example.com/*', error: true);
      return;
    }
    await _mgr.addSpecificSite(e.id, text);
    _siteInput.clear();
  }
}
