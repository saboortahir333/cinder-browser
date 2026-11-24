import 'package:flutter/material.dart';

import 'package:saboor_browser/extensions/extension_installer.dart';
import 'package:saboor_browser/extensions/extension_manager.dart';
import 'package:saboor_browser/extensions/permissions.dart';
import 'package:saboor_browser/models/browser_palette.dart';

String sourceLabel(ExtensionSource s) => switch (s) {
  ExtensionSource.chromeWebStore => 'Chrome Web Store',
  ExtensionSource.edgeAddons => 'Microsoft Edge Add-ons',
  ExtensionSource.packageFile => 'Package file',
  ExtensionSource.unpacked => 'Unpacked folder (developer)',
  ExtensionSource.url => 'Web address',
};

Color riskColor(PermissionRisk r, BrowserPalette p) => switch (r) {
  PermissionRisk.high => const Color(0xFFD70022),
  PermissionRisk.medium => const Color(0xFFB36B00),
  PermissionRisk.low => p.muted,
};

IconData riskIcon(PermissionRisk r) => switch (r) {
  PermissionRisk.high => Icons.warning_amber_rounded,
  PermissionRisk.medium => Icons.info_outline_rounded,
  PermissionRisk.low => Icons.check_circle_outline_rounded,
};

/// The Chrome-style "Add extension?" prompt. Returns null if cancelled.
Future<InstallDecision?> showInstallPrompt(
  BuildContext context,
  BrowserPalette palette,
  PendingInstall pending, {
  required bool isPrivateWindow,
}) {
  return showDialog<InstallDecision>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _InstallPrompt(
      palette: palette,
      pending: pending,
      isPrivateWindow: isPrivateWindow,
    ),
  );
}

class _InstallPrompt extends StatefulWidget {
  const _InstallPrompt({
    required this.palette,
    required this.pending,
    required this.isPrivateWindow,
  });

  final BrowserPalette palette;
  final PendingInstall pending;
  final bool isPrivateWindow;

  @override
  State<_InstallPrompt> createState() => _InstallPromptState();
}

class _InstallPromptState extends State<_InstallPrompt> {
  bool _allowPrivate = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final pe = widget.pending;
    final m = pe.manifest;
    final perms = PermissionPolicy.describe(m);
    final host = PermissionPolicy.hostSummary(m);
    final highRisk = PermissionPolicy.isHighRisk(m);

    TextStyle muted([double size = 12.5]) => TextStyle(color: p.muted, fontSize: size, height: 1.4);

    Widget line(IconData icon, Color color, String text, {String? note}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color, semanticLabel: null),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(text, style: TextStyle(color: p.ink, fontSize: 13.5, height: 1.35)),
                if (note != null) Text(note, style: muted(11.5)),
              ],
            ),
          ),
        ],
      ),
    );

    return AlertDialog(
      backgroundColor: p.chrome,
      surfaceTintColor: Colors.transparent,
      scrollable: true,
      title: Semantics(
        header: true,
        child: Text(
          pe.isUpdate ? 'Update “${pe.name}”?' : 'Add “${pe.name}”?',
          style: TextStyle(color: p.ink, fontWeight: FontWeight.w700),
        ),
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Version ${m.version} · ${sourceLabel(pe.source)}',
              style: muted(),
            ),
            const SizedBox(height: 6),
            if (pe.signed)
              line(Icons.verified_outlined, const Color(0xFF058B00),
                  'Package signature verified',
                  note: 'It is signed by the key that defines its id.')
            else
              line(Icons.gpp_maybe_outlined, const Color(0xFFB36B00),
                  'Not signed',
                  note: 'Only install extensions from people you trust.'),
            const Divider(height: 22),
            Text(
              pe.isUpdate ? 'This update asks for:' : 'This extension can:',
              style: TextStyle(color: p.ink, fontWeight: FontWeight.w700, fontSize: 13.5),
            ),
            const SizedBox(height: 4),
            line(
              host.startsWith('No') ? Icons.public_off_outlined : Icons.language_rounded,
              host.contains('all websites') ? riskColor(PermissionRisk.high, p) : p.muted,
              host,
            ),
            for (final perm in perms)
              line(
                riskIcon(perm.risk),
                riskColor(perm.risk, p),
                perm.warning,
                note: perm.supported ? null : 'Not supported in Cinder yet — this has no effect.',
              ),
            if (pe.isUpdate && pe.addedPermissions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'New since the last version: ${pe.addedPermissions.join(', ')}',
                  style: muted(),
                ),
              ),
            if (m.hasServiceWorker) ...[
              const Divider(height: 22),
              line(
                Icons.build_circle_outlined,
                const Color(0xFFB36B00),
                'Limited compatibility',
                note: 'This extension relies on a background service worker, which Cinder does not run yet. '
                    'Features that need it may not work.',
              ),
            ],
            if (!widget.isPrivateWindow) ...[
              const Divider(height: 22),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
                value: _allowPrivate,
                onChanged: (v) => setState(() => _allowPrivate = v ?? false),
                title: Text('Allow in private windows', style: TextStyle(color: p.ink, fontSize: 13.5)),
                subtitle: Text(
                  'It will be able to see what you do in private windows.',
                  style: muted(11.5),
                ),
              ),
            ],
            if (highRisk && !pe.isUpdate)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'This extension asks for broad access. You can limit it to specific sites or to '
                  '“on click” later in Extensions.',
                  style: muted(11.5),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          autofocus: true,
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final grants = pe.isUpdate && pe.previous != null
                ? (ExtensionGrants(
                    permissions: PermissionPolicy.defaultGrants(m).permissions,
                    siteAccess: pe.previous!.grants.siteAccess,
                    specificSites: {...pe.previous!.grants.specificSites},
                  ))
                : PermissionPolicy.defaultGrants(m);
            Navigator.pop(
              context,
              InstallDecision(grants: grants, allowInPrivate: _allowPrivate),
            );
          },
          child: Text(pe.isUpdate ? 'Update' : 'Add extension'),
        ),
      ],
    );
  }
}
