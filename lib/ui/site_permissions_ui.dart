import 'package:flutter/material.dart';

import 'package:saboor_browser/models/browser_palette.dart';
import 'package:saboor_browser/security/site_permissions.dart';

IconData permissionIcon(SitePermission p) => switch (p) {
  SitePermission.camera => Icons.videocam_outlined,
  SitePermission.microphone => Icons.mic_none_rounded,
  SitePermission.location => Icons.location_on_outlined,
  SitePermission.notifications => Icons.notifications_none_rounded,
  SitePermission.clipboardRead => Icons.content_paste_rounded,
  SitePermission.sensors => Icons.sensors_rounded,
};

String hostLabel(String origin) =>
    Uri.tryParse(origin)?.authority ?? origin;

/// "example.com wants to use your camera". Returns null when dismissed
/// (treated as "not now": denied this time, nothing remembered).
Future<({SiteDecision decision, bool remember})?> showPermissionPrompt(
  BuildContext context,
  BrowserPalette p,
  String origin,
  SitePermission permission, {
  required bool isPrivate,
}) {
  return showDialog<({SiteDecision decision, bool remember})>(
    context: context,
    builder: (ctx) {
      var remember = !isPrivate;
      return StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          backgroundColor: p.chrome,
          surfaceTintColor: Colors.transparent,
          icon: Icon(permissionIcon(permission), color: p.accent, size: 30),
          title: Text(
            '${hostLabel(origin)} wants to ${permission.verb}',
            textAlign: TextAlign.center,
            style: TextStyle(color: p.ink, fontSize: 17, fontWeight: FontWeight.w700),
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Only allow this if you trust the site. You can change it later by '
                  'clicking the icon at the left of the address bar.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: p.muted, fontSize: 12.5),
                ),
                if (!isPrivate)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: remember,
                    onChanged: (v) => setState(() => remember = v ?? false),
                    title: Text('Remember my choice for this site', style: TextStyle(color: p.ink, fontSize: 13)),
                  ),
              ],
            ),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            OutlinedButton(
              autofocus: true,
              onPressed: () => Navigator.pop(ctx, (decision: SiteDecision.block, remember: remember)),
              child: const Text('Block'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, (decision: SiteDecision.allow, remember: remember)),
              child: const Text('Allow'),
            ),
          ],
        ),
      );
    },
  );
}

/// Permissions for one site, opened from the address bar's lock icon.
Future<void> showSiteInfoDialog(
  BuildContext context,
  BrowserPalette p,
  SitePermissionStore store,
  String origin,
  String connectionMessage,
) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: p.chrome,
      surfaceTintColor: Colors.transparent,
      title: Semantics(
        header: true,
        child: Text(hostLabel(origin), style: TextStyle(color: p.ink, fontWeight: FontWeight.w700)),
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: ListenableBuilder(
          listenable: store,
          builder: (context, _) => SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(connectionMessage, style: TextStyle(color: p.muted, fontSize: 12.5, height: 1.4)),
                const Divider(height: 24),
                Text('Permissions', style: TextStyle(color: p.ink, fontWeight: FontWeight.w700)),
                if (store.isPrivate)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('Private window: choices are forgotten when it closes.',
                        style: TextStyle(color: p.muted, fontSize: 11.5)),
                  ),
                const SizedBox(height: 6),
                for (final perm in SitePermission.values)
                  _PermissionRow(palette: p, store: store, origin: origin, permission: perm),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => store.resetOrigin(origin), child: const Text('Reset all')),
        TextButton(autofocus: true, onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
      ],
    ),
  );
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.palette,
    required this.store,
    required this.origin,
    required this.permission,
  });

  final BrowserPalette palette;
  final SitePermissionStore store;
  final String origin;
  final SitePermission permission;

  @override
  Widget build(BuildContext context) {
    final d = store.decisionFor(origin, permission);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(permissionIcon(permission), size: 18, color: palette.muted),
          const SizedBox(width: 10),
          Expanded(child: Text(permission.label, style: TextStyle(color: palette.ink, fontSize: 13.5))),
          Semantics(
            label: '${permission.label} permission for ${hostLabel(origin)}',
            child: DropdownButton<SiteDecision?>(
              value: d,
              underline: const SizedBox.shrink(),
              isDense: true,
              dropdownColor: palette.chrome,
              items: const [
                DropdownMenuItem(value: null, child: Text('Ask')),
                DropdownMenuItem(value: SiteDecision.allow, child: Text('Allow')),
                DropdownMenuItem(value: SiteDecision.block, child: Text('Block')),
              ],
              onChanged: (v) => v == null
                  ? store.reset(origin, permission)
                  : store.set(origin, permission, v),
            ),
          ),
        ],
      ),
    );
  }
}

/// All stored decisions across sites (Settings → Site permissions).
Future<void> showSitePermissionsManager(
  BuildContext context,
  BrowserPalette p,
  SitePermissionStore store,
) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: p.chrome,
      surfaceTintColor: Colors.transparent,
      title: Semantics(
        header: true,
        child: Text('Site permissions', style: TextStyle(color: p.ink, fontWeight: FontWeight.w700)),
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 420),
        child: ListenableBuilder(
          listenable: store,
          builder: (context, _) {
            final rows = store.all();
            if (rows.isEmpty) {
              return Padding(
                padding: const EdgeInsets.all(12),
                child: Text('No saved choices yet. Sites ask before using your camera, microphone, location or notifications.',
                    style: TextStyle(color: p.muted)),
              );
            }
            return ListView.builder(
              shrinkWrap: true,
              itemCount: rows.length,
              itemBuilder: (context, i) {
                final r = rows[i];
                return ListTile(
                  dense: true,
                  leading: Icon(permissionIcon(r.permission), color: p.muted),
                  title: Text(hostLabel(r.origin), style: TextStyle(color: p.ink)),
                  subtitle: Text(
                    '${r.permission.label}: ${r.decision == SiteDecision.allow ? 'Allowed' : 'Blocked'}',
                    style: TextStyle(color: r.decision == SiteDecision.allow ? p.accent : p.muted),
                  ),
                  trailing: IconButton(
                    tooltip: 'Remove this choice (ask again)',
                    icon: const Icon(Icons.delete_outline_rounded),
                    onPressed: () => store.reset(r.origin, r.permission),
                  ),
                );
              },
            );
          },
        ),
      ),
      actions: [TextButton(autofocus: true, onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
    ),
  );
}
