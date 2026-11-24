import 'package:saboor_browser/extensions/manifest.dart';
import 'package:saboor_browser/extensions/match_pattern.dart';

enum PermissionRisk { low, medium, high }

class PermissionInfo {
  const PermissionInfo(this.id, this.warning, this.risk, {this.supported = true});
  final String id;

  /// Wording shown in the install prompt (Chrome-style "Read your history").
  final String warning;
  final PermissionRisk risk;

  /// Whether Cinder implements the API. Unsupported permissions are still
  /// shown (so the user is not misled about what the extension asks for) but
  /// are marked as inactive.
  final bool supported;
}

/// The Manifest V3 API permissions Cinder knows about. Anything not listed is
/// treated as unknown: shown as high risk and never granted.
class PermissionCatalog {
  const PermissionCatalog._();

  static const Map<String, PermissionInfo> all = {
    'storage': PermissionInfo(
      'storage',
      'Store its own settings on this device',
      PermissionRisk.low,
    ),
    'activeTab': PermissionInfo(
      'activeTab',
      'Access the current page only when you click its toolbar button',
      PermissionRisk.low,
    ),
    'alarms': PermissionInfo(
      'alarms',
      'Schedule work to run later',
      PermissionRisk.low,
      supported: false,
    ),
    'contextMenus': PermissionInfo(
      'contextMenus',
      'Add items to the right-click menu',
      PermissionRisk.low,
      supported: false,
    ),
    'notifications': PermissionInfo(
      'notifications',
      'Show desktop notifications',
      PermissionRisk.low,
      supported: false,
    ),
    'clipboardWrite': PermissionInfo(
      'clipboardWrite',
      'Copy data to your clipboard',
      PermissionRisk.low,
    ),
    'clipboardRead': PermissionInfo(
      'clipboardRead',
      'Read data you copy and paste',
      PermissionRisk.high,
      supported: false,
    ),
    'scripting': PermissionInfo(
      'scripting',
      'Run code on pages it has access to',
      PermissionRisk.medium,
      supported: false,
    ),
    'tabs': PermissionInfo(
      'tabs',
      'See the address and title of your open tabs',
      PermissionRisk.high,
    ),
    'history': PermissionInfo(
      'history',
      'Read and change your browsing history',
      PermissionRisk.high,
      supported: false,
    ),
    'bookmarks': PermissionInfo(
      'bookmarks',
      'Read and change your bookmarks',
      PermissionRisk.high,
      supported: false,
    ),
    'cookies': PermissionInfo(
      'cookies',
      'Read and change cookies for sites it can access',
      PermissionRisk.high,
      supported: false,
    ),
    'downloads': PermissionInfo(
      'downloads',
      'Manage your downloads',
      PermissionRisk.high,
      supported: false,
    ),
    'webRequest': PermissionInfo(
      'webRequest',
      'Observe the requests pages make',
      PermissionRisk.high,
      supported: false,
    ),
    'declarativeNetRequest': PermissionInfo(
      'declarativeNetRequest',
      'Block or change requests pages make',
      PermissionRisk.high,
      supported: false,
    ),
    'nativeMessaging': PermissionInfo(
      'nativeMessaging',
      'Talk to programs installed on your computer',
      PermissionRisk.high,
      supported: false,
    ),
    'management': PermissionInfo(
      'management',
      'Manage your other extensions',
      PermissionRisk.high,
      supported: false,
    ),
    'proxy': PermissionInfo(
      'proxy',
      'Control how the browser connects to the internet',
      PermissionRisk.high,
      supported: false,
    ),
    'sidePanel': PermissionInfo(
      'sidePanel',
      'Show a side panel',
      PermissionRisk.low,
      supported: false,
    ),
    'unlimitedStorage': PermissionInfo(
      'unlimitedStorage',
      'Store unlimited data',
      PermissionRisk.low,
      supported: false,
    ),
    'offscreen': PermissionInfo(
      'offscreen',
      'Run hidden pages',
      PermissionRisk.medium,
      supported: false,
    ),
  };

  static PermissionInfo infoFor(String id) =>
      all[id] ??
      PermissionInfo(
        id,
        'Use an unrecognised capability ("$id")',
        PermissionRisk.high,
        supported: false,
      );
}

/// How much of the web an extension may touch.
enum SiteAccess {
  /// Runs on every site matching its patterns, no further questions.
  onAllSites,

  /// Only after the user clicks the toolbar button (activeTab-style).
  onClick,

  /// Only on the sites the user listed.
  onSpecificSites,
}

/// What the user has actually granted, which can be less than requested.
class ExtensionGrants {
  ExtensionGrants({
    Set<String>? permissions,
    this.siteAccess = SiteAccess.onAllSites,
    Set<String>? specificSites,
    Set<String>? activeTabOrigins,
  }) : permissions = permissions ?? <String>{},
       specificSites = specificSites ?? <String>{},
       activeTabOrigins = activeTabOrigins ?? <String>{};

  final Set<String> permissions;
  SiteAccess siteAccess;

  /// Match patterns the user allowed when [siteAccess] is onSpecificSites.
  final Set<String> specificSites;

  /// Origins temporarily allowed via "run once" (cleared on restart).
  final Set<String> activeTabOrigins;

  Map<String, dynamic> toJson() => {
    'permissions': permissions.toList()..sort(),
    'siteAccess': siteAccess.name,
    'specificSites': specificSites.toList()..sort(),
  };

  static ExtensionGrants fromJson(Object? json) {
    if (json is! Map) return ExtensionGrants();
    List<String> list(Object? v) =>
        v is List ? v.whereType<String>().take(500).toList() : <String>[];
    final access = SiteAccess.values.where((s) => s.name == json['siteAccess']);
    return ExtensionGrants(
      permissions: list(json['permissions']).toSet(),
      siteAccess: access.isEmpty ? SiteAccess.onAllSites : access.first,
      specificSites: list(json['specificSites'])
          .where((p) => MatchPattern.tryParse(p) != null)
          .toSet(),
    );
  }
}

/// Decides what an extension may do. All checks default to "no".
class PermissionPolicy {
  const PermissionPolicy._();

  /// Grants applied when the user accepts the install prompt: everything the
  /// manifest requests (not the optional ones).
  static ExtensionGrants defaultGrants(ExtensionManifest m) => ExtensionGrants(
    permissions: m.permissions.where(PermissionCatalog.all.containsKey).toSet(),
  );

  /// Summary lines for the install/permissions UI, highest risk first.
  static List<PermissionInfo> describe(ExtensionManifest m) {
    final items = <PermissionInfo>[
      for (final p in m.permissions) PermissionCatalog.infoFor(p),
    ];
    items.sort((a, b) => b.risk.index.compareTo(a.risk.index));
    return items;
  }

  /// Plain-language description of host access.
  static String hostSummary(ExtensionManifest m) {
    final patterns = <String>{
      ...m.hostPermissions,
      for (final s in m.contentScripts) ...s.matches,
    }.map(MatchPattern.tryParse).whereType<MatchPattern>().toList();
    if (patterns.isEmpty) return 'No website access';
    if (patterns.any((p) => p.coversAllSites)) {
      return 'Read and change all your data on all websites';
    }
    final hosts = patterns.map((p) => p.label).toSet().toList()..sort();
    if (hosts.length <= 3) {
      return 'Read and change your data on ${hosts.join(', ')}';
    }
    return 'Read and change your data on ${hosts.length} websites';
  }

  static bool isHighRisk(ExtensionManifest m) =>
      describe(m).any((p) => p.risk == PermissionRisk.high) ||
      m.hostPermissions.any(
        (p) => MatchPattern.tryParse(p)?.coversAllSites ?? false,
      ) ||
      m.contentScripts.any(
        (s) => s.matches.any(
          (p) => MatchPattern.tryParse(p)?.coversAllSites ?? false,
        ),
      );

  static bool hasApi(
    ExtensionManifest m,
    ExtensionGrants g,
    String permission,
  ) {
    final info = PermissionCatalog.all[permission];
    if (info == null || !info.supported) return false;
    return m.permissions.contains(permission) &&
        g.permissions.contains(permission);
  }

  /// May this extension's content scripts run on [url]?
  ///
  /// Requires (1) the page matches a content-script pattern, (2) the extension
  /// declared host access that covers the page, and (3) the user's site-access
  /// choice allows it. Never true for non-web schemes.
  static bool mayRunOn(
    ExtensionManifest m,
    ExtensionGrants g,
    String url,
  ) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    final scheme = uri.scheme.toLowerCase();
    if (!MatchPattern.supportedSchemes.contains(scheme)) return false;
    // The Web Store is off limits to extensions, as in Chrome.
    final host = uri.host.toLowerCase();
    if (host == 'chromewebstore.google.com' ||
        host == 'chrome.google.com' && uri.path.startsWith('/webstore')) {
      return false;
    }
    switch (g.siteAccess) {
      case SiteAccess.onClick:
        return g.activeTabOrigins.contains(originOf(url));
      case SiteAccess.onSpecificSites:
        if (!anyPatternMatches(g.specificSites, url)) return false;
      case SiteAccess.onAllSites:
        break;
    }
    // Content scripts declare their own matches; the declared host
    // permissions bound them too (Chrome treats content-script matches as
    // host permission requests).
    final declared = <String>{
      ...m.hostPermissions,
      for (final s in m.contentScripts) ...s.matches,
    };
    return anyPatternMatches(declared, url);
  }

  static String originOf(String url) {
    final u = Uri.tryParse(url);
    if (u == null || !u.hasScheme) return '';
    final port = u.hasPort ? ':${u.port}' : '';
    return '${u.scheme.toLowerCase()}://${u.host.toLowerCase()}$port';
  }
}
