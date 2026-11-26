import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsService;
import 'package:flutter/services.dart';
import 'package:saboor_browser/ui/chrome/chrome_widgets.dart';
import 'package:saboor_browser/ui/start/start_widgets.dart';
import 'package:saboor_browser/ui/wallpapers/cinder_wallpapers.dart';
import 'package:saboor_browser/src/rust/frb_generated.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart';
import 'package:saboor_browser/models/browser_palette.dart';
import 'package:saboor_browser/models/browser_wallpaper.dart';
import 'package:saboor_browser/models/download_item.dart';
import 'package:saboor_browser/models/fuzzy_suggestion.dart';
import 'package:saboor_browser/browser/find_in_page.dart';
import 'package:saboor_browser/browser/page_zoom.dart';
import 'package:saboor_browser/browser/search_engines.dart';
import 'package:saboor_browser/browser/session_model.dart';
import 'package:saboor_browser/browser/url_policy.dart';
import 'package:saboor_browser/security/secure_storage.dart';
import 'package:saboor_browser/services/account_service.dart';
import 'package:saboor_browser/services/app_services.dart';
import 'package:saboor_browser/services/bookmark_service.dart';
import 'package:saboor_browser/services/prefs_store.dart';
import 'package:saboor_browser/services/profile_paths.dart';
import 'package:saboor_browser/ui/account_dialog.dart';
import 'package:saboor_browser/ui/search_engine_dialog.dart';
import 'package:saboor_browser/services/download_service.dart';
import 'package:saboor_browser/extensions/extension_manager.dart';
import 'package:saboor_browser/services/bookmark_import.dart';
import 'package:saboor_browser/services/update_service.dart';
import 'package:saboor_browser/utils/app_info.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:saboor_browser/extensions/extension_runtime.dart';
import 'package:saboor_browser/extensions/permissions.dart';
import 'package:saboor_browser/ui/extensions/extensions_manager.dart';
import 'package:saboor_browser/services/history_service.dart';
import 'package:saboor_browser/services/settings_sync_service.dart';
import 'package:saboor_browser/utils/constants.dart';
import 'package:saboor_browser/security/site_permissions.dart';
import 'package:saboor_browser/ui/site_permissions_ui.dart';
import 'package:saboor_browser/security/filter_lists.dart';
import 'package:saboor_browser/security/request_filter.dart';
import 'package:saboor_browser/security/request_policy.dart';
import 'package:saboor_browser/security/page_messages.dart';
import 'package:saboor_browser/src/rust/api/adblock_engine.dart' as rust_adblock;

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  AppServices.launch = LaunchOptions.parse(args);
  await RustLib.init();
  await Supabase.initialize(
    url: supabaseUrl,
    publishableKey: supabaseAnonKey,
    authOptions: FlutterAuthClientOptions(
      // The session (refresh token) lives in the OS secret store, never in a
      // plaintext preferences file. Private windows never persist a session.
      localStorage: AppServices.launch.isPrivate
          ? const EmptyLocalStorage()
          : SecureSupabaseStorage(
              const OsSecretStore(),
              profileId: AppServices.launch.profileId,
            ),
      // We never use web deep links for auth; ignore any that arrive.
      detectSessionInUri: false,
    ),
  );
  await _configureEngineProfile();
  await AccountService.instance.restore();
  runApp(const SaboorBrowserApp());
}

String? _privateProfileDir;
RandomAccessFile? _privateProfileLock;

/// Chooses where WebView2 keeps its cookies/cache. This is the only
/// user-related data that must live on disk (the engine requires it):
///  - private window: a random temp folder, locked while open, deleted on exit
///  - named profile: %LOCALAPPDATA%\Cinder\Profiles\<id>\WebView2
///  - default profile: the plugin's default folder
Future<void> _configureEngineProfile() async {
  if (defaultTargetPlatform != TargetPlatform.windows) return;
  final launch = AppServices.launch;
  String? dir;
  try {
    if (launch.isPrivate) {
      final temp = Directory.systemTemp.path;
      unawaited(ProfilePaths.sweepStalePrivateDirs(temp));
      dir = '$temp${Platform.pathSeparator}${ProfilePaths.newPrivateDirName()}';
      await Directory(dir).create(recursive: true);
      _privateProfileDir = dir;
      _privateProfileLock = ProfilePaths.acquireLock(dir);
    } else {
      final local = Platform.environment['LOCALAPPDATA'];
      if (local != null) {
        dir = ProfilePaths.namedProfileDir(launch.profileId, local);
        if (dir != null) await Directory(dir).create(recursive: true);
      }
    }
    if (dir != null) {
      await WebviewController.initializeEnvironment(userDataPath: dir);
    }
  } catch (error) {
    // Never fall back to the shared default profile for a private window.
    debugPrint('engine profile setup failed: ${error.runtimeType}');
    if (launch.isPrivate) rethrow;
  }
}

/// Best-effort removal of the private window's engine profile on exit.
Future<void> _cleanUpPrivateProfile() async {
  final dir = _privateProfileDir;
  if (dir == null) return;
  try {
    _privateProfileLock?.closeSync();
  } catch (_) {}
  _privateProfileLock = null;
  await ProfilePaths.deletePrivateDir(dir, Directory.systemTemp.path);
}

enum _BrowserContextAction {
  newTab,
  addShortcut,
  reload,
  duplicateTab,
  closeTab,
  closeOtherTabs,
  open,
  openInNewTab,
  copyAddress,
  removeBookmark,
  addBookmark,
  back,
  forward,
  viewSource,
  inspect,
  openImage,
  copyImageAddress,
  copy,
  cut,
  paste,
  selectAll,
  searchSelection,
  print,
  pasteAndGo,
  toggleBookmarksBar,
  showBookmarks,
  showHistory,
  showDownloads,
  customize,
  pinTab,
  unpinTab,
  newGroup,
  removeFromGroup,
  renameGroup,
  sleepTab,
  reopenClosedTab,
}

class SaboorBrowserApp extends StatefulWidget {
  const SaboorBrowserApp({super.key});

  @override
  State<SaboorBrowserApp> createState() => _SaboorBrowserAppState();
}

class _SaboorBrowserAppState extends State<SaboorBrowserApp>
    with WidgetsBindingObserver {
  final PrefsStore _prefs = PrefsStore.instance;
  BrowserPalette _palette = AppServices.launch.isPrivate
      ? kPrivatePalette
      : kPalettes.first;

  @override
  void initState() {
    super.initState();
    unawaited(_loadPalette());
    // Re-apply the saved theme when the account's cloud settings arrive.
    _prefs.addListener(_onPrefsChanged);
    WidgetsBinding.instance.addObserver(this);
  }

  // Windows high-contrast / theme changes arrive here.
  @override
  void didChangeAccessibilityFeatures() {
    if (mounted) setState(() {});
  }

  @override
  void didChangePlatformBrightness() {
    if (mounted) setState(() {});
  }

  void _onPrefsChanged() => unawaited(_loadPalette());

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _prefs.removeListener(_onPrefsChanged);
    super.dispose();
  }

  Future<void> _loadPalette() async {
    try {
      final id = await _prefs.getString('appearance.palette');
      _applyPaletteId(id);

      // Cloud sync load
      final cloudId = await SettingsSyncService.instance.fetchSetting(
        'appearance.palette',
      );
      if (cloudId != null && cloudId != id) {
        _applyPaletteId(cloudId);
        await _prefs.setString('appearance.palette', cloudId);
      }
    } catch (_) {}
  }

  void _applyPaletteId(String? id) {
    // Private windows always use their own violet theme, whatever is saved.
    if (id == null || AppServices.launch.isPrivate) return;
    final stored = kPalettes.where((palette) => palette.id == id);
    if (stored.isNotEmpty && mounted) {
      setState(() => _palette = stored.first);
    }
  }

  Future<void> _selectPalette(BrowserPalette palette) async {
    if (AppServices.launch.isPrivate) return;
    setState(() => _palette = palette);
    try {
      await _prefs.setString('appearance.palette', palette.id);
      unawaited(
        SettingsSyncService.instance.saveSetting(
          'appearance.palette',
          palette.id,
        ),
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final dispatcher = WidgetsBinding.instance.platformDispatcher;
    final palette = effectivePalette(
      _palette,
      isPrivate: AppServices.launch.isPrivate,
      highContrast: dispatcher.accessibilityFeatures.highContrast,
      platformBrightness: dispatcher.platformBrightness,
    );
    return _buildApp(palette);
  }

  Widget _buildApp(BrowserPalette _palette) {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: _palette.accent,
          brightness: _palette.isDark ? Brightness.dark : Brightness.light,
        ).copyWith(
          primary: _palette.accent,
          surface: _palette.chrome,
          onSurface: _palette.ink,
          secondary: _palette.accent,
        );
    return MaterialApp(
      title: 'Cinder',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: scheme,
        scaffoldBackgroundColor: _palette.chrome,
        useMaterial3: true,
        visualDensity: VisualDensity.compact,
        fontFamily: 'Segoe UI Variable Text',
        fontFamilyFallback: const ['Segoe UI', 'Inter'],
        splashFactory: NoSplash.splashFactory,
        iconButtonTheme: IconButtonThemeData(
          style: IconButton.styleFrom(
            foregroundColor: _palette.ink,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: _palette.accent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: _palette.accent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: _palette.raised,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: _palette.accent, width: 1.6),
          ),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: _palette.chrome,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        popupMenuTheme: PopupMenuThemeData(
          color: _palette.chrome,
          elevation: 8,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        tooltipTheme: TooltipThemeData(
          decoration: BoxDecoration(
            color: _palette.ink,
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: TextStyle(color: _palette.chrome, fontSize: 12),
        ),
      ),
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        // Respect the system text size, but keep the fixed-height browser
        // chrome from breaking at extreme settings.
        return MediaQuery(
          data: mq.copyWith(
            textScaler: mq.textScaler.clamp(
              minScaleFactor: 1.0,
              maxScaleFactor: 1.5,
            ),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: BrowserShell(palette: _palette, onPaletteSelected: _selectPalette),
    );
  }
}

class _BrowserTab {
  _BrowserTab({this.pendingUrl, this.sleeping = false})
    : id = '${DateTime.now().microsecondsSinceEpoch}-${_sequence++}',
      controller = WebviewController();

  static int _sequence = 0;

  final String id;
  WebviewController controller;

  /// Pinned tabs sort to the front and are shown compactly.
  bool pinned = false;

  /// Id of the tab group this tab belongs to, if any.
  String? groupId;

  /// A sleeping tab has no live WebView2 (its memory is released) and only
  /// remembers its address; it is woken when selected.
  bool sleeping;

  /// Address to load when a restored / sleeping tab is woken.
  String? pendingUrl;

  /// Current page zoom (1.0 = 100%).
  double zoom = 1.0;

  DateTime lastActive = DateTime.now();

  /// The address to remember for this tab (live URL, else the pending one).
  String get savedUrl => url.isNotEmpty ? url : (pendingUrl ?? '');
  StreamSubscription<String>? urlSubscription;
  StreamSubscription<String>? titleSubscription;
  StreamSubscription<LoadingState>? loadingSubscription;
  StreamSubscription<HistoryChanged>? historySubscription;
  StreamSubscription<WebErrorStatus>? errorSubscription;
  StreamSubscription<WebviewDownloadEvent>? downloadSubscription;
  StreamSubscription<dynamic>? webMessageSubscription;
  Future<void>? initialization;
  String url = '';
  String title = 'New tab';
  String? error;
  bool isLoading = false;
  bool isInitialized = false;
  bool canGoBack = false;
  bool canGoForward = false;

  Future<void> dispose() async {
    ExtensionRuntime.instance.detach(controller);
    await _cancelSubscriptions();
    await controller.dispose();
  }

  Future<void> _cancelSubscriptions() async {
    await urlSubscription?.cancel();
    await titleSubscription?.cancel();
    await loadingSubscription?.cancel();
    await historySubscription?.cancel();
    await errorSubscription?.cancel();
    await downloadSubscription?.cancel();
    await webMessageSubscription?.cancel();
    urlSubscription = null;
    titleSubscription = null;
    loadingSubscription = null;
    historySubscription = null;
    errorSubscription = null;
    downloadSubscription = null;
    webMessageSubscription = null;
  }

  /// Releases the WebView2 (renderer process memory) but keeps the tab's
  /// address and title so it can be woken later.
  Future<void> sleep() async {
    if (sleeping) return;
    pendingUrl = savedUrl;
    await _cancelSubscriptions();
    final old = controller;
    controller = WebviewController();
    initialization = null;
    isInitialized = false;
    isLoading = false;
    canGoBack = false;
    canGoForward = false;
    sleeping = true;
    await old.dispose();
  }

  TabSnapshot toSnapshot() => TabSnapshot(
    url: savedUrl,
    title: title,
    pinned: pinned,
    groupId: groupId,
  );
}

class BrowserShell extends StatefulWidget {
  const BrowserShell({
    super.key,
    required this.palette,
    required this.onPaletteSelected,
  });

  final BrowserPalette palette;
  final ValueChanged<BrowserPalette> onPaletteSelected;

  @override
  State<BrowserShell> createState() => _BrowserShellState();
}

class _BrowserShellState extends State<BrowserShell>
    with WidgetsBindingObserver {
  /// Device-local registry of unpacked extension folders (paths are
  /// inherently per-device, so this is the one local preference we keep).

  /// Everything else (theme, wallpaper, shortcuts, flags): memory + cloud.
  final PrefsStore _prefs = PrefsStore.instance;
  final TextEditingController _urlController = TextEditingController();
  final FocusNode _urlFocusNode = FocusNode();
  final List<_BrowserTab> _tabs = [];

  int _activeTabIndex = 0;

  // --- Tabs, session, zoom, find (all state is in memory; persistence goes
  // through the encrypted cloud store and is skipped in private windows) ---
  final ClosedTabStack _closedTabs = ClosedTabStack();
  final Map<String, TabGroupSnapshot> _groups = {};
  SiteZoomMemory _siteZoom = SiteZoomMemory();
  Timer? _sessionSaveTimer;
  Timer? _sleepTimer;
  bool _sessionRestoreAttempted = false;
  bool _findOpen = false;
  final TextEditingController _findController = TextEditingController();
  final FocusNode _findFocusNode = FocusNode();
  FindResult _findResult = const FindResult(0, 0);
  bool get _isPrivate => AppServices.launch.isPrivate;
  bool get _persists => !_isPrivate && AppServices.cloud.isSyncing;

  late final SitePermissionStore _sitePerms = SitePermissionStore(
    cloud: AppServices.cloud,
    isPrivate: _isPrivate,
  );

  /// Serialises prompts: one dialog at a time, later requests reuse its answer.
  Future<void> _permissionQueue = Future.value();

  Future<WebviewPermissionDecision> _onPermissionRequested(
    String url,
    WebviewPermissionKind kind,
    bool userInitiated,
  ) async {
    final perm = SitePermission.fromKind(kind);
    if (perm == null) return WebviewPermissionDecision.deny;
    final origin = SitePermissionStore.originOf(url);
    if (origin == null) return WebviewPermissionDecision.deny;
    final completer = Completer<WebviewPermissionDecision>();
    _permissionQueue = _permissionQueue.then((_) async {
      // Re-evaluate inside the queue: an earlier prompt may have settled it.
      final outcome = _sitePerms.evaluate(url, perm, userInitiated: userInitiated);
      if (outcome != PermissionOutcome.askUser || !mounted) {
        completer.complete(outcome == PermissionOutcome.allow
            ? WebviewPermissionDecision.allow
            : WebviewPermissionDecision.deny);
        return;
      }
      final answer = await showPermissionPrompt(
        context,
        _palette,
        origin,
        perm,
        isPrivate: _isPrivate,
      );
      if (answer == null) {
        completer.complete(WebviewPermissionDecision.deny);
        return;
      }
      _sitePerms.record(origin, perm, answer.decision, remember: answer.remember);
      completer.complete(answer.decision == SiteDecision.allow
          ? WebviewPermissionDecision.allow
          : WebviewPermissionDecision.deny);
    });
    return completer.future;
  }

  final RequestPolicy _requestPolicy = RequestPolicy();
  RequestFilter? _requestFilter;
  final FilterLists _filterLists = FilterLists();
  final Completer<void> _webviewUp = Completer<void>();
  final Completer<void> _shieldsReady = Completer<void>();

  /// Starts HTTPS-only, tracker blocking and the deceptive-site list once the
  /// first WebView exists (its DevTools port is what the filter attaches to).
  Future<void> _startShields() async {
    try {
      _requestPolicy.httpsOnly = await PrefsStore.instance.getBool('shield_https_only') ?? true;
      _requestPolicy.blockTrackers = await PrefsStore.instance.getBool('shield_trackers') ?? true;
      _requestPolicy.blockMalware = await PrefsStore.instance.getBool('shield_malware') ?? true;
      _requestPolicy.malwareHosts = await _filterLists.loadCached();
      _requestPolicy.matcher = (url, src, type) =>
          rust_adblock.adblockShouldBlock(url: url, sourceUrl: src, requestType: type);
      final port = AppServices.launch.devToolsPort;
      if (port != 0) {
        await _webviewUp.future.timeout(const Duration(seconds: 10), onTimeout: () {});
        final f = RequestFilter(port: port, policy: _requestPolicy);
        if (await f.start()) {
          _requestFilter = f;
        }
      }
      if (!_shieldsReady.isCompleted) _shieldsReady.complete();
      if (await _filterLists.refreshIfStale() && mounted) {
        _requestPolicy.malwareHosts = await _filterLists.loadCached();
      }
    } catch (_) {
      // Shields degrade silently; browsing keeps working.
    } finally {
      if (!_shieldsReady.isCompleted) _shieldsReady.complete();
    }
  }

  bool _shieldsOnFor(String url) {
    final h = Uri.tryParse(url)?.host.toLowerCase() ?? '';
    return !_requestPolicy.shieldsOff.contains(h);
  }

  void _setShieldsFor(String url, bool on) {
    final h = Uri.tryParse(url)?.host.toLowerCase() ?? '';
    if (h.isEmpty) return;
    if (on) {
      _requestPolicy.shieldsOff.remove(h);
    } else {
      _requestPolicy.shieldsOff.add(h);
    }
    _activeTab?.controller.reload();
  }

  Future<void> _showShieldsSettingsDialog() => showShieldsSettings(
    context,
    _palette,
    httpsOnly: _requestPolicy.httpsOnly,
    trackers: _requestPolicy.blockTrackers,
    malware: _requestPolicy.blockMalware,
    onChanged: (h, t, m) {
      _requestPolicy.httpsOnly = h;
      _requestPolicy.blockTrackers = t;
      _requestPolicy.blockMalware = m;
      unawaited(PrefsStore.instance.setBool('shield_https_only', h));
      unawaited(PrefsStore.instance.setBool('shield_trackers', t));
      unawaited(PrefsStore.instance.setBool('shield_malware', m));
    },
  );

  /// An HTTPS-only upgrade failed to load: let the user decide about HTTP.
  Future<void> _offerInsecureFallback(_BrowserTab tab) async {
    final u = Uri.tryParse(tab.url);
    if (u == null || u.scheme != 'https') return;
    final host = u.host.toLowerCase();
    if (!_requestPolicy.upgraded.contains(host) || _requestPolicy.insecureOk.contains(host)) return;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _palette.chrome,
        surfaceTintColor: Colors.transparent,
        title: Text('No secure connection to $host',
            style: TextStyle(color: _palette.ink, fontWeight: FontWeight.w700)),
        content: Text(
          'This site does not seem to support HTTPS. Opening it over HTTP means anyone on '
          'your network could read or change what you see and send. Do not enter passwords or payment details.',
          style: TextStyle(color: _palette.muted),
        ),
        actions: [
          TextButton(autofocus: true, onPressed: () => Navigator.pop(ctx, false), child: const Text('Go back')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Continue to HTTP')),
        ],
      ),
    );
    if (go == true) {
      _requestPolicy.insecureOk.add(host);
      unawaited(tab.controller.loadUrl(u.replace(scheme: 'http').toString()));
    }
  }

  void _showSiteInfo(_BrowserTab tab) {
    final origin = SitePermissionStore.originOf(tab.url);
    if (origin == null) return;
    unawaited(showSiteInfoDialog(
      context,
      _palette,
      _sitePerms,
      origin,
      _connectionSecurityMessage(tab),
      shieldsOn: _shieldsOnFor(tab.url),
      onShieldsChanged: (on) => _setShieldsFor(tab.url, on),
      blockedCount: _requestFilter?.blockedByHost[Uri.tryParse(tab.url)?.host ?? ''] ?? 0,
    ));
  }

  static const Duration _autoSleepAfter = Duration(minutes: 30);
  DateTime _backgroundDate = _dateOnly(DateTime.now());
  String? _wallpaperUrl;
  String? _wallpaperFilePath;
  Color? _wallpaperColor;
  String _wallpaperCategory = 'All';
  String _wallpaperName = 'Daily rotation';
  String? _wallpaperProcedural;
  Timer? _midnightTimer;
  String? _webviewRuntimeError;

  // Bookmarks state
  // _bookmarks: full list for the bar/dialog
  // _bookmarkedUrls: fast O(1) in-memory set — no Supabase call on navigation
  List<Map<String, dynamic>> _bookmarks = [];
  final Set<String> _bookmarkedUrls = {};
  bool _showBookmarksBar = true;
  bool _currentPageBookmarked = false;

  // Coalesce rapid stream-triggered setState calls into a single frame rebuild.
  // Without this, url+title+loading+history subscriptions each call setState
  // independently — 4+ rebuilds per page load = visible jank.
  bool _pendingRebuild = false;

  // Focus node that catches keyboard shortcuts at the shell level
  final FocusNode _shellFocusNode = FocusNode();

  // Fuzzy suggestions state
  List<FuzzySuggestion> _fuzzySuggestions = [];
  int _selectedSuggestionIndex = -1;
  bool _showSuggestions = false;
  List<Map<String, dynamic>> _historyCache = [];
  List<Map<String, dynamic>> _searchHistoryCache = [];
  final LayerLink _addressBarLayerLink = LayerLink();

  static const List<(String, String)> _kDefaultShortcuts = [
    ('Wikipedia', 'https://www.wikipedia.org'),
    ('GitHub', 'https://github.com'),
    ('Flutter', 'https://flutter.dev'),
    ('Rust', 'https://www.rust-lang.org'),
    ('YouTube', 'https://www.youtube.com'),
    ('Reddit', 'https://www.reddit.com'),
    ('Supabase', 'https://supabase.com'),
    ('X', 'https://x.com'),
  ];
  List<(String, String)> _homeShortcuts = List.of(_kDefaultShortcuts);
  final Set<String> _pinnedShortcutUrls = {};

  BrowserPalette get _palette => widget.palette;

  _BrowserTab? get _activeTab =>
      _tabs.isEmpty ? null : _tabs[_activeTabIndex.clamp(0, _tabs.length - 1)];


  final Set<String> _favoriteThemes = {'sky'};
  final Set<String> _favoriteWallpapers = {'alpine', 'coast'};

  List<BrowserWallpaper> get _filteredWallpapers {
    if (_wallpaperCategory == 'Favorites') {
      return kWallpapers
          .where((wallpaper) => _favoriteWallpapers.contains(wallpaper.id))
          .toList();
    }
    return _wallpaperCategory == 'All'
        ? kWallpapers
        : kWallpapers
              .where((wallpaper) => wallpaper.category == _wallpaperCategory)
              .toList();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scheduleMidnightRefresh();
    unawaited(_loadWallpaper());
    unawaited(
      _createTab(
        url: AppServices.launch.startUrl,
        source: NavSource.link,
      ),
    );
    unawaited(_scheduleUpdateCheck());
    unawaited(_loadBookmarks());
    unawaited(_loadBookmarksBarPref());
    unawaited(_loadShortcuts());
    unawaited(_loadHistoryCache());
    unawaited(_initExtensions());
    unawaited(_sitePerms.load());
    unawaited(_startShields());
    // Fetch download history from Supabase (Zero local SQLite / disk cache)
    unawaited(DownloadService.instance.initialize());

    _urlController.addListener(_onUrlTextChanged);
    _urlFocusNode.addListener(_onUrlFocusChanged);

    AppServices.account.addListener(_onAccountChanged);
    _sleepTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => unawaited(_sleepIdleTabs()),
    );
    unawaited(_onAccountChanged());
  }

  AccountState? _lastAccountState;

  /// Reacts to sign-in / unlock / sign-out.
  Future<void> _onAccountChanged() async {
    final state = AppServices.account.state;
    if (state == _lastAccountState) return;
    _lastAccountState = state;
    if (state == AccountState.unlocked) {
      // Start from a clean slate so guest data and account data never mix.
      AppServices.cloud.wipe();
      HistoryService.instance.reset();
      BookmarkService.instance.reset();
      await PrefsStore.instance.load();
      await _loadCloudPreferences();
      await _reloadAccountData();
      await _restoreSession();
    } else if (state == AccountState.guest) {
      // Signed out: forget everything that belonged to the account.
      AppServices.cloud.wipe();
      PrefsStore.instance.clearMemory();
      HistoryService.instance.reset();
      BookmarkService.instance.reset();
      DownloadService.instance.clearMemory();
      _historyCache = [];
      _searchHistoryCache = [];
      _bookmarks = [];
      _bookmarkedUrls.clear();
      _sessionSaveTimer?.cancel();
      _closedTabs.clear();
      _groups.clear();
      _siteZoom = SiteZoomMemory();
      AppServices.searchEngine = SearchEngines.defaultEngine;
      _sessionRestoreAttempted = false;
    }
    if (mounted) setState(() {});
  }

  /// Re-reads everything that depends on the account after sign-in/unlock.
  Future<void> _reloadAccountData() async {
    await Future.wait([
      _loadBookmarks(),
      _loadBookmarksBarPref(),
      _loadShortcuts(),
      _loadWallpaper(),
      _loadHistoryCache(),
      DownloadService.instance.fetchHistoryFromCloud(),
      _sitePerms.load(),
    ]);
  }

  Future<void> _loadCloudPreferences() async {
    final cloud = AppServices.cloud;
    await cloud.load('setting');
    await cloud.load('zoom');
    await cloud.load('profile');
    if (!mounted) return;
    final prefs = cloud.get('setting', 'search');
    if (prefs != null) {
      final custom = SearchEngines.customFromStored(
        prefs['customName'] as String?,
        prefs['customTemplate'] as String?,
      );
      AppServices.searchEngine = SearchEngines.byId(
        prefs['engine'] as String?,
        custom: custom,
      );
    }
    final zoomRecord = cloud.get('zoom', 'sites');
    if (zoomRecord != null) _siteZoom = SiteZoomMemory.fromJson(zoomRecord);
  }

  /// Restores the previous session into sleeping tabs (so 50 saved tabs do
  /// not start 50 renderers) when the window only has the blank start tab.
  Future<void> _restoreSession() async {
    if (_isPrivate || _sessionRestoreAttempted) return;
    _sessionRestoreAttempted = true;
    await AppServices.cloud.load('session');
    final snapshot = SessionSnapshot.tryFromJson(
      AppServices.cloud.get('session', 'current'),
    );
    if (!mounted || snapshot == null) return;
    final onlyBlank = _tabs.length == 1 && _tabs.first.savedUrl.isEmpty;
    if (!onlyBlank) return;

    final restored = <_BrowserTab>[];
    _groups
      ..clear()
      ..addEntries(snapshot.groups.map((g) => MapEntry(g.id, g)));
    for (var i = 0; i < snapshot.tabs.length; i++) {
      final s = snapshot.tabs[i];
      final tab = _BrowserTab(
        pendingUrl: s.url.isEmpty ? null : s.url,
        sleeping: s.url.isNotEmpty,
      )
        ..title = s.title.isEmpty ? _tabTitle(s.url) : s.title
        ..pinned = s.pinned
        ..groupId = s.groupId;
      restored.add(tab);
    }
    final old = _tabs.toList();
    setState(() {
      _tabs
        ..clear()
        ..addAll(restored);
      _activeTabIndex = snapshot.activeIndex.clamp(0, _tabs.length - 1);
      _urlController.text = _activeTab?.savedUrl ?? '';
    });
    for (final tab in old) {
      unawaited(tab.dispose());
    }
    final active = _activeTab;
    if (active != null) await _wakeTab(active);
  }

  void _scheduleSessionSave() {
    if (!_persists) return;
    _sessionSaveTimer?.cancel();
    _sessionSaveTimer = Timer(const Duration(seconds: 2), _saveSessionNow);
  }

  void _saveSessionNow() {
    if (!_persists || _tabs.isEmpty) return;
    final snapshot = SessionSnapshot(
      tabs: [for (final t in _tabs) t.toSnapshot()],
      activeIndex: _activeTabIndex.clamp(0, _tabs.length - 1),
      groups: _groups.values.toList(),
    );
    AppServices.cloud.put('session', 'current', snapshot.toJson());
  }

  void _saveZoomMemory() {
    if (!_persists) return;
    AppServices.cloud.put('zoom', 'sites', _siteZoom.toJson());
  }

  /// Puts long-idle background tabs to sleep to free renderer memory.
  Future<void> _sleepIdleTabs() async {
    final now = DateTime.now();
    for (final tab in _tabs.toList()) {
      if (identical(tab, _activeTab) ||
          tab.sleeping ||
          tab.pinned ||
          tab.isLoading ||
          tab.savedUrl.isEmpty) {
        continue;
      }
      if (now.difference(tab.lastActive) >= _autoSleepAfter) {
        await tab.sleep();
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _wakeTab(_BrowserTab tab) async {
    if (!tab.sleeping) return;
    final url = tab.pendingUrl;
    tab.sleeping = false;
    tab.pendingUrl = null;
    tab.initialization = _initializeTab(tab);
    if (mounted) setState(() {});
    await tab.initialization;
    if (url != null && url.isNotEmpty && tab.isInitialized) {
      final decision = UrlPolicy.checkNavigation(url, NavSource.restore);
      if (!decision.isBlocked) {
        try {
          await tab.controller.loadUrl(decision.url);
        } catch (error) {
          tab.error = 'Unable to load page.';
          if (mounted) setState(() {});
        }
      }
    }
  }

  Future<void> _loadHistoryCache() async {
    try {
      final h = await HistoryService.instance.fetchBrowsingHistory(limit: 150);
      final s = await HistoryService.instance.fetchSearchHistory(limit: 50);
      if (!mounted) return;
      _historyCache = h;
      _searchHistoryCache = s;
    } catch (_) {}
  }

  void _onUrlTextChanged() {
    final query = _urlController.text;
    if (!_urlFocusNode.hasFocus || query.trim().isEmpty) {
      if (_showSuggestions) {
        setState(() {
          _showSuggestions = false;
          _fuzzySuggestions.clear();
          _selectedSuggestionIndex = -1;
        });
      }
      return;
    }

    final suggestions = FuzzySearchEngine.getSuggestions(
      query: query,
      bookmarks: _bookmarks,
      history: _historyCache,
      searchHistory: _searchHistoryCache,
    );

    setState(() {
      _fuzzySuggestions = suggestions;
      _showSuggestions = suggestions.isNotEmpty;
      _selectedSuggestionIndex = -1;
    });
  }

  void _onUrlFocusChanged() {
    if (!_urlFocusNode.hasFocus) {
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted && !_urlFocusNode.hasFocus) {
          setState(() {
            _showSuggestions = false;
          });
        }
      });
    } else {
      _onUrlTextChanged();
    }
  }

  void _selectFuzzySuggestion(FuzzySuggestion suggestion) {
    setState(() {
      _showSuggestions = false;
      _urlController.text = suggestion.url;
    });
    unawaited(_navigate(suggestion.url));
  }

  Future<void> _loadBookmarks() async {
    final items = await BookmarkService.instance.fetchBookmarks();
    if (!mounted) return;
    setState(() {
      _bookmarks = items;
      // Rebuild the O(1) URL set for instant bookmark status checks
      _bookmarkedUrls
        ..clear()
        ..addAll(
          items
              .map((m) => m['url']?.toString() ?? '')
              .where((u) => u.isNotEmpty),
        );
      // Sync star icon for the current page without any extra network call
      final currentUrl = _activeTab?.url ?? '';
      _currentPageBookmarked =
          currentUrl.isNotEmpty && _bookmarkedUrls.contains(currentUrl);
    });
  }

  Future<void> _loadBookmarksBarPref() async {
    try {
      final val = await _prefs.getBool('appearance.showBookmarksBar');
      if (mounted && val != null) setState(() => _showBookmarksBar = val);

      final cloudVal = await SettingsSyncService.instance.fetchSetting(
        'appearance.showBookmarksBar',
      );
      if (cloudVal != null && mounted) {
        final parsed = cloudVal == 'true';
        if (parsed != _showBookmarksBar) {
          setState(() => _showBookmarksBar = parsed);
          await _prefs.setBool('appearance.showBookmarksBar', parsed);
        }
      }
    } catch (_) {}
  }

  Future<void> _toggleBookmarksBar() async {
    final newValue = !_showBookmarksBar;
    setState(() => _showBookmarksBar = newValue);
    try {
      await _prefs.setBool('appearance.showBookmarksBar', newValue);
      unawaited(
        SettingsSyncService.instance.saveSetting(
          'appearance.showBookmarksBar',
          newValue.toString(),
        ),
      );
    } catch (_) {}
  }

  Future<void> _toggleBookmark() async {
    final tab = _activeTab;
    if (tab == null || tab.url.isEmpty) return;
    final url = tab.url;
    final title = tab.title;
    if (_currentPageBookmarked) {
      // Optimistic update first — feels instant to user
      setState(() {
        _currentPageBookmarked = false;
        _bookmarkedUrls.remove(url);
        _bookmarks.removeWhere((m) => m['url'] == url);
      });
      await BookmarkService.instance.removeBookmark(url);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Bookmark removed'),
            backgroundColor: _palette.raised,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } else {
      final newBm = <String, dynamic>{
        'url': url,
        'title': title.isEmpty ? url : title,
        'created_at': DateTime.now().toIso8601String(),
      };
      // Optimistic update first
      setState(() {
        _currentPageBookmarked = true;
        _bookmarkedUrls.add(url);
        _bookmarks.insert(0, newBm);
      });
      await BookmarkService.instance.addBookmark(url, title);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Bookmark saved'),
            backgroundColor: _palette.raised,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
    // Background sync to get server-confirmed state
    unawaited(_loadBookmarks());
  }

  /// Instantly checks bookmark status from in-memory set — zero network calls.
  void _updateBookmarkStatus(String url) {
    final bookmarked = url.isNotEmpty && _bookmarkedUrls.contains(url);
    if (bookmarked != _currentPageBookmarked) {
      setState(() => _currentPageBookmarked = bookmarked);
    }
  }

  /// Schedule a coalesced setState — multiple calls within the same frame
  /// collapse into a single rebuild instead of N separate rebuilds.
  void _scheduleRebuild() {
    if (_pendingRebuild) return;
    _pendingRebuild = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pendingRebuild = false;
      if (mounted) setState(() {});
    });
  }

  Future<void> _loadShortcuts() async {
    try {
      final jsonStr = await _prefs.getString('cinder_home.shortcuts');
      final pinnedList = await _prefs.getStringList('cinder_home.pinned');
      if (pinnedList != null && pinnedList.isNotEmpty) {
        _pinnedShortcutUrls.addAll(pinnedList);
      }
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final decoded = jsonDecode(jsonStr);
        if (decoded is List) {
          final list = <(String, String)>[];
          for (final item in decoded) {
            if (item is Map) {
              final name = item['name']?.toString() ?? '';
              final url = item['url']?.toString() ?? '';
              if (name.isNotEmpty && url.isNotEmpty) {
                list.add((name, url));
              }
            }
          }
          if (list.isNotEmpty && mounted) {
            setState(() {
              _homeShortcuts = list;
            });
            return;
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _saveShortcuts() async {
    try {
      final list = _homeShortcuts
          .map((s) => {'name': s.$1, 'url': s.$2})
          .toList();
      await _prefs.setString('cinder_home.shortcuts', jsonEncode(list));
      await _prefs.setStringList(
        'cinder_home.pinned',
        _pinnedShortcutUrls.toList(),
      );
    } catch (_) {}
  }

  void _togglePinShortcut(String url) {
    setState(() {
      if (_pinnedShortcutUrls.contains(url)) {
        _pinnedShortcutUrls.remove(url);
      } else {
        _pinnedShortcutUrls.add(url);
      }
    });
    unawaited(_saveShortcuts());
  }

  void _removeShortcut(int index) {
    if (index >= 0 && index < _homeShortcuts.length) {
      final removed = _homeShortcuts[index];
      setState(() {
        _homeShortcuts.removeAt(index);
        _pinnedShortcutUrls.remove(removed.$2);
      });
      unawaited(_saveShortcuts());
    }
  }

  Future<void> _showEditShortcutDialog({int? editIndex}) async {
    final isEditing =
        editIndex != null &&
        editIndex >= 0 &&
        editIndex < _homeShortcuts.length;
    final current = isEditing ? _homeShortcuts[editIndex] : null;

    final nameController = TextEditingController(text: current?.$1 ?? '');
    final urlController = TextEditingController(
      text: current?.$2 ?? 'https://',
    );

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _palette.chrome,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          isEditing ? 'Edit Shortcut' : 'Add Shortcut',
          style: TextStyle(color: _palette.ink, fontWeight: FontWeight.w600),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              autofocus: true,
              style: TextStyle(color: _palette.ink),
              decoration: InputDecoration(
                labelText: 'Name',
                labelStyle: TextStyle(color: _palette.muted),
                hintText: 'e.g. GitHub',
                hintStyle: TextStyle(color: _palette.muted.withOpacity(0.5)),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: _palette.accent),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: urlController,
              style: TextStyle(color: _palette.ink),
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                labelText: 'URL',
                labelStyle: TextStyle(color: _palette.muted),
                hintText: 'https://github.com',
                hintStyle: TextStyle(color: _palette.muted.withOpacity(0.5)),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: _palette.accent),
                ),
              ),
              onSubmitted: (_) {
                if (nameController.text.trim().isNotEmpty &&
                    urlController.text.trim().isNotEmpty) {
                  Navigator.pop(dialogContext, true);
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text('Cancel', style: TextStyle(color: _palette.muted)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _palette.accent),
            onPressed: () {
              if (nameController.text.trim().isNotEmpty &&
                  urlController.text.trim().isNotEmpty) {
                Navigator.pop(dialogContext, true);
              }
            },
            child: Text(isEditing ? 'Save' : 'Add'),
          ),
        ],
      ),
    );

    if (result == true) {
      final name = nameController.text.trim();
      var url = urlController.text.trim();
      if (!url.startsWith('http://') && !url.startsWith('https://')) {
        url = 'https://$url';
      }
      setState(() {
        if (isEditing) {
          final oldUrl = _homeShortcuts[editIndex].$2;
          final wasPinned = _pinnedShortcutUrls.remove(oldUrl);
          _homeShortcuts[editIndex] = (name, url);
          if (wasPinned) _pinnedShortcutUrls.add(url);
        } else {
          _homeShortcuts.add((name, url));
        }
      });
      unawaited(_saveShortcuts());
    }

    nameController.dispose();
    urlController.dispose();
  }

  Future<void> _loadWallpaper() async {
    try {
      final url = await _prefs.getString('appearance.wallpaperUrl');
      final filePath = await _prefs.getString(
        'appearance.wallpaperFilePath',
      );
      final colorValue = await _prefs.getInt('appearance.wallpaperColor');
      final name = await _prefs.getString('appearance.wallpaperName');
      final procedural = await _prefs.getString('appearance.wallpaperProcedural');
      if (!mounted) return;
      setState(() {
        _wallpaperUrl = url;
        _wallpaperFilePath = filePath;
        _wallpaperProcedural = procedural;
        _wallpaperColor = colorValue == null ? null : Color(colorValue);
        _wallpaperName =
            url == null &&
                filePath == null &&
                colorValue == null &&
                procedural == null
            ? 'Daily rotation'
            : (name ?? 'Custom image');
      });

      // Cloud sync load
      final cloudUrl = await SettingsSyncService.instance.fetchSetting(
        'appearance.wallpaperUrl',
      );
      final cloudName = await SettingsSyncService.instance.fetchSetting(
        'appearance.wallpaperName',
      );
      if (cloudUrl != null &&
          cloudUrl.isNotEmpty &&
          mounted &&
          cloudUrl != _wallpaperUrl) {
        setState(() {
          _wallpaperUrl = cloudUrl;
          _wallpaperName = cloudName ?? 'Custom image';
        });
        await _prefs.setString('appearance.wallpaperUrl', cloudUrl);
        if (cloudName != null) {
          await _prefs.setString('appearance.wallpaperName', cloudName);
        }
      }
    } catch (_) {}
  }

  Future<void> _selectWallpaper({
    String? url,
    String? filePath,
    Color? solidColor,
    String? procedural,
    required String name,
  }) async {
    setState(() {
      _wallpaperProcedural = procedural;
      _wallpaperUrl = url;
      _wallpaperFilePath = filePath;
      _wallpaperColor = solidColor;
      _wallpaperName = name;
    });
    try {
      await _prefs.remove('appearance.wallpaperUrl');
      await _prefs.remove('appearance.wallpaperFilePath');
      await _prefs.remove('appearance.wallpaperColor');
      await _prefs.remove('appearance.wallpaperName');
      await _prefs.remove('appearance.wallpaperProcedural');
      if (procedural != null) {
        await _prefs.setString('appearance.wallpaperProcedural', procedural);
        unawaited(
          SettingsSyncService.instance.saveSetting(
            'appearance.wallpaperProcedural',
            procedural,
          ),
        );
      } else {
        unawaited(
          SettingsSyncService.instance.saveSetting(
            'appearance.wallpaperProcedural',
            '',
          ),
        );
      }
      if (url != null) {
        await _prefs.setString('appearance.wallpaperUrl', url);
        unawaited(
          SettingsSyncService.instance.saveSetting(
            'appearance.wallpaperUrl',
            url,
          ),
        );
      } else {
        unawaited(
          SettingsSyncService.instance.saveSetting(
            'appearance.wallpaperUrl',
            '',
          ),
        );
      }
      if (filePath != null) {
        await _prefs.setString('appearance.wallpaperFilePath', filePath);
      }
      if (solidColor != null) {
        await _prefs.setInt(
          'appearance.wallpaperColor',
          solidColor.toARGB32(),
        );
      }
      if (url != null ||
          filePath != null ||
          solidColor != null ||
          procedural != null) {
        await _prefs.setString('appearance.wallpaperName', name);
        unawaited(
          SettingsSyncService.instance.saveSetting(
            'appearance.wallpaperName',
            name,
          ),
        );
      }
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // Updates, bookmark import, default browser, About
  // ---------------------------------------------------------------------------
  Timer? _updateTimer;

  Future<void> _scheduleUpdateCheck() async {
    if (_isPrivate) return;
    // Once a day, a few seconds after start, never blocking the UI.
    _updateTimer = Timer(const Duration(seconds: 8), () => unawaited(_dailyUpdateCheck()));
  }

  Future<void> _dailyUpdateCheck() async {
    if (!mounted) return;
    final last = DateTime.tryParse(
      await PrefsStore.instance.getString('updates.lastCheck') ?? '',
    );
    if (last != null && DateTime.now().difference(last) < const Duration(hours: 24)) {
      return;
    }
    await PrefsStore.instance.setString(
      'updates.lastCheck',
      DateTime.now().toUtc().toIso8601String(),
    );
    await _checkForUpdates(manual: false);
  }

  Future<void> _checkForUpdates({required bool manual}) async {
    final info = await const UpdateService().check();
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (info == null) {
      if (manual) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Cinder is up to date.')),
        );
      }
      return;
    }
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 15),
        content: Text('Cinder ${info.version} is available.'),
        action: SnackBarAction(
          label: "What's new",
          onPressed: () => unawaited(_createTab(url: info.pageUrl)),
        ),
      ),
    );
  }

  Future<void> _importBookmarks() async {
    final picked = await FilePicker.pickFile(
      dialogTitle: 'Choose a bookmarks file exported from Chrome, Edge or Firefox',
      type: FileType.custom,
      allowedExtensions: const ['html', 'htm'],
    );
    final path = picked?.path;
    if (path == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final file = File(path);
      if (file.lengthSync() > BookmarkImport.maxBytes) {
        messenger.showSnackBar(const SnackBar(content: Text('That file is too large.')));
        return;
      }
      final items = BookmarkImport.parse(await file.readAsString());
      for (final b in items) {
        await BookmarkService.instance.addBookmark(b.url, b.title);
      }
      await _loadBookmarks();
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            items.isEmpty
                ? 'No bookmarks were found in that file.'
                : 'Imported ${items.length} bookmark${items.length == 1 ? '' : 's'}.',
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Could not read that file.')),
        );
      }
    }
  }

  /// Windows does not let apps set the default browser themselves; open the
  /// Default apps page where the user picks Cinder.
  Future<void> _openDefaultAppsSettings() async {
    await launchUrl(Uri.parse('ms-settings:defaultapps'));
  }

  void _showAbout() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _palette.chrome,
        title: Text('Cinder $kAppVersion', style: TextStyle(color: _palette.ink)),
        content: Text(
          'A Windows browser built with Flutter and Microsoft Edge WebView2.\n\n'
          'Open source (Apache-2.0).\n$kReleasesPage',
          style: TextStyle(color: _palette.muted),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              unawaited(_createTab(url: kReleasesPage));
            },
            child: const Text('Release notes'),
          ),
          TextButton(autofocus: true, onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Extensions
  // ---------------------------------------------------------------------------
  final GlobalKey _extButtonKey = GlobalKey();
  ExtensionPopupSession? _popup;

  // ---------------------------------------------------------------------------
  // Keyboard-only navigation: F6 / Shift+F6 move between the main areas.
  // ---------------------------------------------------------------------------
  final FocusScopeNode _stripScope = FocusScopeNode(debugLabel: 'tab strip');
  final FocusScopeNode _toolbarScope = FocusScopeNode(debugLabel: 'toolbar');
  final FocusScopeNode _bookmarksScope = FocusScopeNode(debugLabel: 'bookmarks');
  int _zone = 0;

  void _focusZone(int zone) {
    final zones = <String>[
      'address',
      'page',
      if (_showBookmarksBar) 'bookmarks',
      'tabs',
      'toolbar',
    ];
    final name = zones[zone % zones.length];
    _zone = zone % zones.length;
    void firstIn(FocusScopeNode scope) {
      final first = ReadingOrderTraversalPolicy().findFirstFocus(scope);
      first?.requestFocus();
    }

    switch (name) {
      case 'address':
        _urlFocusNode.requestFocus();
        _urlController.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _urlController.text.length,
        );
      case 'page':
        final tab = _activeTab;
        if (tab != null && tab.url.isNotEmpty && tab.isInitialized) {
          unawaited(tab.controller.focus());
          // Move Flutter focus off the chrome so keys reach the page.
          _shellFocusNode.requestFocus();
        } else {
          _urlFocusNode.requestFocus();
        }
      case 'bookmarks':
        firstIn(_bookmarksScope);
      case 'tabs':
        firstIn(_stripScope);
      case 'toolbar':
        firstIn(_toolbarScope);
    }
    SemanticsService.sendAnnouncement(
      View.of(context),
      switch (name) {
        'address' => 'Address bar',
        'page' => 'Page content',
        'bookmarks' => 'Bookmarks bar',
        'tabs' => 'Tab strip',
        _ => 'Toolbar',
      },
      TextDirection.ltr,
    );
  }

  Future<void> _initExtensions() async {
    try {
      await ExtensionManager.instance.init(
        root: ExtensionManager.defaultRoot(AppServices.launch.profileId),
        isPrivate: AppServices.launch.isPrivate,
      );
    } catch (error) {
      debugPrint('Extensions failed to load: ${error.runtimeType}');
    }
    if (mounted) setState(() {});
  }

  Future<void> _showExtensionsDialog() async {
    _closeExtensionPopup();
    await showExtensionsManager(
      context,
      _palette,
      isPrivateWindow: _isPrivate,
      openUrl: (url) => unawaited(_createTab(url: url)),
      openOptions: (ext) => unawaited(_openExtensionOptions(ext)),
    );
  }

  ({int id, String url, String title})? _activeTabForExtensions() {
    final tab = _activeTab;
    if (tab == null) return null;
    return (id: tab.id.hashCode & 0x7fffffff, url: tab.url, title: tab.title);
  }

  /// Toolbar button click: run "on click" scripts and/or show the popup.
  Future<void> _activateExtension(InstalledExtension ext) async {
    _closeExtensionPopup();
    final tab = _activeTab;
    if (tab != null && tab.url.isNotEmpty && tab.isInitialized) {
      await ExtensionRuntime.instance.runOnce(tab.controller, ext, tab.url);
    }
    if (!ext.hasPopup || !mounted) return;
    final session = ExtensionPopupSession(
      ext: ext,
      onOpenTab: (url) => unawaited(_createTab(url: url)),
      onClose: _closeExtensionPopup,
      activeTabInfo: _activeTabForExtensions,
    );
    setState(() => _popup = session);
    try {
      await session.start();
    } catch (error) {
      debugPrint('Extension popup failed: ${error.runtimeType}');
      _closeExtensionPopup();
    }
  }

  Future<void> _openExtensionOptions(InstalledExtension ext) async {
    final page = ext.manifest.optionsPage;
    if (page == null) return;
    _closeExtensionPopup();
    final session = ExtensionPopupSession(
      ext: ext,
      relativePath: page,
      onOpenTab: (url) => unawaited(_createTab(url: url)),
      onClose: _closeExtensionPopup,
      activeTabInfo: _activeTabForExtensions,
    )..size.value = const Size(640, 520);
    setState(() => _popup = session);
    try {
      await session.start();
    } catch (_) {
      _closeExtensionPopup();
    }
  }

  void _closeExtensionPopup() {
    final p = _popup;
    if (p == null) return;
    _popup = null;
    if (mounted) setState(() {});
    unawaited(p.dispose());
  }

  Widget _buildExtensionPopup() {
    final s = _popup!;
    return Positioned.fill(
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _closeExtensionPopup,
              child: const SizedBox.expand(),
            ),
          ),
          Positioned(
            top: 94,
            right: 12,
            child: Semantics(
              scopesRoute: true,
              namesRoute: true,
              label: '${s.ext.name} popup',
              child: ValueListenableBuilder<Size>(
                valueListenable: s.size,
                builder: (context, size, _) => Material(
                  elevation: 14,
                  color: _palette.chrome,
                  borderRadius: BorderRadius.circular(10),
                  clipBehavior: Clip.antiAlias,
                  child: Container(
                    width: size.width,
                    height: size.height,
                    decoration: BoxDecoration(
                      border: Border.all(color: _palette.divider),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: ValueListenableBuilder<bool>(
                      valueListenable: s.ready,
                      builder: (context, ready, _) => ready
                          ? Webview(s.controller, permissionRequested: (_, __, ___) => WebviewPermissionDecision.deny)
                          : const Center(child: CircularProgressIndicator()),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Pinned extension buttons plus the puzzle-piece menu.
  List<Widget> _extensionToolbarWidgets() {
    final mgr = ExtensionManager.instance;
    final pinned = mgr.active.where((e) => e.pinned).take(4).toList();
    return [
      for (final e in pinned)
        ToolbarButton(
          palette: _palette,
          tooltip: e.actionTitle,
          icon: Icons.extension_outlined,
          iconWidget: _extensionIcon(e),
          active: identical(_popup?.ext, e),
          onPressed: () => unawaited(_activateExtension(e)),
        ),
      KeyedSubtree(
        key: _extButtonKey,
        child: ToolbarButton(
          palette: _palette,
          tooltip: 'Extensions',
          icon: Icons.extension_outlined,
          onPressed: () => unawaited(_showExtensionsMenu()),
        ),
      ),
    ];
  }

  Widget _extensionIcon(InstalledExtension e) {
    final f = e.iconFile(32);
    if (f == null) return SiteGlyph(host: e.name, size: 20);
    return Image.file(
      File(f),
      width: 20,
      height: 20,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, _, _) => SiteGlyph(host: e.name, size: 20),
    );
  }

  Future<void> _showExtensionsMenu() async {
    final box = _extButtonKey.currentContext?.findRenderObject() as RenderBox?;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;
    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
    final position = RelativeRect.fromRect(
      Rect.fromLTWH(topLeft.dx, topLeft.dy + box.size.height, box.size.width, 0),
      Offset.zero & overlay.size,
    );
    final list = ExtensionManager.instance.active;
    final choice = await showMenu<String>(
      context: context,
      position: position,
      color: _palette.chrome,
      items: [
        if (list.isEmpty)
          PopupMenuItem<String>(
            enabled: false,
            child: Text(
              'No extensions in this window',
              style: TextStyle(color: _palette.muted, fontSize: 13),
            ),
          ),
        for (final e in list)
          PopupMenuItem<String>(
            value: 'run:${e.id}',
            height: 42,
            child: Row(
              children: [
                SizedBox(width: 22, height: 22, child: _extensionIcon(e)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    e.name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: _palette.ink, fontSize: 13.5),
                  ),
                ),
                if (e.grants.siteAccess == SiteAccess.onClick)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(
                      'on click',
                      style: TextStyle(color: _palette.muted, fontSize: 11),
                    ),
                  ),
              ],
            ),
          ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'manage',
          height: 40,
          child: Row(
            children: [
              Icon(Icons.settings_outlined, size: 18, color: _palette.ink),
              const SizedBox(width: 12),
              Text(
                'Manage extensions',
                style: TextStyle(color: _palette.ink, fontSize: 13.5),
              ),
            ],
          ),
        ),
      ],
    );
    if (choice == null || !mounted) return;
    if (choice == 'manage') {
      await _showExtensionsDialog();
    } else if (choice.startsWith('run:')) {
      final ext = ExtensionManager.instance.byId(choice.substring(4));
      if (ext != null) await _activateExtension(ext);
    }
  }

  /// Collects a URL and a destination folder, then hands the job to
  /// WebView2 so the request uses the browser's cookies and authenticated
  /// session. WebView2 chooses the destination path in this package version.
  Future<void> _startNewDownload() async {
    final url = await _promptForDownloadUrl();
    if (url == null || !mounted) return;

    final tab = _activeTab;
    if (tab == null) return;
    try {
      await tab.initialization;
      if (!tab.isInitialized) {
        throw StateError(tab.error ?? 'WebView2 is unavailable.');
      }
      await tab.controller.loadUrl(url);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'WebView2 is handling the request. If it is a file, progress will appear here.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not start download: $error')),
      );
    }
  }

  /// Asks for the address to download from. Returns `null` when the user
  /// cancels or the entry is not a usable HTTP(S) address.
  Future<String?> _promptForDownloadUrl() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _palette.chrome,
        title: Text('Download URL', style: TextStyle(color: _palette.ink)),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.url,
          style: TextStyle(color: _palette.ink),
          decoration: InputDecoration(
            hintText: 'https://example.com/file.zip',
            hintStyle: TextStyle(color: _palette.muted),
          ),
          onSubmitted: (value) => Navigator.pop(dialogContext, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Start Download'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null || result.isEmpty) return null;

    final uri = Uri.tryParse(result);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a valid HTTP(S) download URL.')),
        );
      }
      return null;
    }
    return result;
  }

  Future<void> _showDownloadsDialog() async {
    await DownloadService.instance.fetchHistoryFromCloud();
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, refreshDialog) {
          return Dialog(
            backgroundColor: _palette.chrome,
            surfaceTintColor: Colors.transparent,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 860, maxHeight: 650),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.download_rounded,
                          color: _palette.accent,
                          size: 26,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Download Manager',
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: _palette.ink,
                                    ),
                              ),
                              Text(
                                'WebView2-managed downloads • Live engine progress',
                                style: TextStyle(
                                  color: _palette.muted,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: () async {
                            Navigator.pop(dialogContext);
                            await _startNewDownload();
                          },
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('New Download'),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: 'Close',
                          onPressed: () => Navigator.pop(dialogContext),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(width: 0, height: 16),
                    Expanded(
                      child: ValueListenableBuilder<int>(
                        valueListenable: DownloadService.instance.revision,
                        builder: (context, _, _) {
                          final items = DownloadService.instance.items;
                          return items.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.download_done_rounded,
                                        size: 54,
                                        color: _palette.muted.withValues(
                                          alpha: 0.4,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        'No downloads yet',
                                        style: TextStyle(
                                          color: _palette.muted,
                                          fontSize: 15,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : ListView.separated(
                                  itemCount: items.length,
                                  separatorBuilder: (_, __) =>
                                      Divider(color: _palette.soft, height: 1),
                                  itemBuilder: (context, index) {
                                    final item = items[index];
                                    final isDownloading =
                                        item.status ==
                                        DownloadStatus.downloading;

                                    return Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 10,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Icon(
                                                isDownloading
                                                    ? Icons.downloading_rounded
                                                    : item.status ==
                                                          DownloadStatus
                                                              .completed
                                                    ? Icons
                                                          .check_circle_outline_rounded
                                                    : item.status ==
                                                          DownloadStatus
                                                              .cancelled
                                                    ? Icons.cancel_outlined
                                                    : Icons
                                                          .error_outline_rounded,
                                                color: isDownloading
                                                    ? _palette.accent
                                                    : item.status ==
                                                          DownloadStatus
                                                              .completed
                                                    ? Colors.green
                                                    : Colors.redAccent,
                                                size: 22,
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      item.filename,
                                                      style: TextStyle(
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        color: _palette.ink,
                                                        fontSize: 14,
                                                      ),
                                                    ),
                                                    Text(
                                                      item.url,
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: TextStyle(
                                                        color: _palette.muted,
                                                        fontSize: 11,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              if (isDownloading)
                                                Tooltip(
                                                  message:
                                                      'WebView2 owns this transfer; cancellation is not exposed by this integration.',
                                                  child: Icon(
                                                    Icons.info_outline,
                                                    color: _palette.muted,
                                                    size: 18,
                                                  ),
                                                )
                                              else
                                                IconButton(
                                                  tooltip: 'Delete Record',
                                                  icon: Icon(
                                                    Icons
                                                        .delete_outline_rounded,
                                                    color: _palette.muted,
                                                    size: 18,
                                                  ),
                                                  onPressed: () async {
                                                    await DownloadService
                                                        .instance
                                                        .deleteFromHistory(
                                                          item.id,
                                                        );
                                                    refreshDialog(() {});
                                                  },
                                                ),
                                            ],
                                          ),
                                          if (isDownloading) ...[
                                            const SizedBox(height: 8),
                                            LinearProgressIndicator(
                                              value: item.progress > 0
                                                  ? item.progress
                                                  : null,
                                              backgroundColor: _palette.soft,
                                              color: _palette.accent,
                                              minHeight: 4,
                                            ),
                                            const SizedBox(height: 6),
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment
                                                      .spaceBetween,
                                              children: [
                                                Text(
                                                  '${(item.downloadedBytes / (1024 * 1024)).toStringAsFixed(1)} MB'
                                                  '${item.totalBytes > 0 ? " / ${(item.totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB" : ""}',
                                                  style: TextStyle(
                                                    color: _palette.muted,
                                                    fontSize: 11,
                                                  ),
                                                ),
                                                Text(
                                                  '${(item.speedBytesPerSec / (1024 * 1024)).toStringAsFixed(2)} MB/s',
                                                  style: TextStyle(
                                                    color: _palette.accent,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 11,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ] else if (item.status ==
                                              DownloadStatus.completed) ...[
                                            const SizedBox(height: 4),
                                            Text(
                                              'Completed • Saved to ${item.localPath}',
                                              style: const TextStyle(
                                                color: Colors.green,
                                                fontSize: 11,
                                              ),
                                            ),
                                          ] else if (item.status ==
                                              DownloadStatus.failed) ...[
                                            const SizedBox(height: 4),
                                            Text(
                                              'Failed: ${item.errorMessage ?? "Unknown error"}',
                                              style: const TextStyle(
                                                color: Colors.redAccent,
                                                fontSize: 11,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    );
                                  },
                                );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _showAppearanceSettings() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, refreshDialog) => Dialog(
          backgroundColor: _palette.chrome,
          surfaceTintColor: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960, maxHeight: 720),
            child: DefaultTabController(
              length: 2,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.palette_outlined,
                          color: _palette.accent,
                          size: 24,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Appearance & Customization',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close',
                          onPressed: () => Navigator.pop(dialogContext),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    Text(
                      'Customize your browser themes and daily landscape wallpapers.',
                      style: TextStyle(color: _palette.muted, fontSize: 13),
                    ),
                    const SizedBox(height: 14),
                    TabBar(
                      labelColor: _palette.accent,
                      unselectedLabelColor: _palette.muted,
                      indicatorColor: _palette.accent,
                      indicatorWeight: 3,
                      tabs: const [
                        Tab(text: 'Color Themes'),
                        Tab(text: 'Background Wallpapers'),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Expanded(
                      child: TabBarView(
                        children: [
                          _buildThemeLibrary(() => refreshDialog(() {})),
                          _buildWallpaperLibrary(
                            dialogContext,
                            () => refreshDialog(() {}),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGalleryCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required String tag,
    required Widget bannerWidget,
    required bool isSelected,
    required VoidCallback onTap,
    bool isFavorited = false,
    VoidCallback? onFavoriteTap,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: _palette.raised.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected ? _palette.accent : _palette.soft,
          width: isSelected ? 2.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isSelected ? 0.12 : 0.04),
            blurRadius: isSelected ? 16 : 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 118,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  bannerWidget,
                  Positioned(
                    top: 10,
                    left: 10,
                    child: InkWell(
                      onTap: onFavoriteTap,
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: const BoxDecoration(
                          color: Color(0x55000000),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isFavorited ? Icons.favorite : Icons.favorite_border,
                          size: 15,
                          color: isFavorited ? Colors.redAccent : Colors.white,
                        ),
                      ),
                    ),
                  ),
                  if (isSelected)
                    Center(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xEE101820),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white24, width: 1),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black45,
                              blurRadius: 10,
                              offset: Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.check_circle_rounded,
                              size: 14,
                              color: _palette.accent,
                            ),
                            const SizedBox(width: 6),
                            const Text(
                              'Now Active',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _palette.ink,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Expanded(
                      child: Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _palette.muted,
                          fontSize: 10.5,
                          height: 1.3,
                        ),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: _palette.soft.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        tag,
                        style: TextStyle(
                          color: _palette.ink,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThemeLibrary(VoidCallback refreshDialog) {
    return GridView.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 250,
        mainAxisExtent: 228,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
      ),
      itemCount: kPalettes.length,
      itemBuilder: (context, index) {
        final palette = kPalettes[index];
        final selected = palette.id == _palette.id;
        final isFav = _favoriteThemes.contains(palette.id);
        return _buildGalleryCard(
          context: context,
          title: palette.name,
          subtitle: palette.subtitle,
          tag: palette.tag,
          isSelected: selected,
          isFavorited: isFav,
          onFavoriteTap: () {
            setState(() {
              if (isFav) {
                _favoriteThemes.remove(palette.id);
              } else {
                _favoriteThemes.add(palette.id);
              }
            });
            refreshDialog();
          },
          onTap: () {
            widget.onPaletteSelected(palette);
            refreshDialog();
          },
          bannerWidget: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [palette.raised, palette.chrome, palette.soft],
              ),
            ),
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                Container(
                  height: 16,
                  decoration: BoxDecoration(
                    color: palette.raised,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 6),
                      CircleAvatar(radius: 3, backgroundColor: palette.accent),
                      const SizedBox(width: 4),
                      CircleAvatar(radius: 3, backgroundColor: palette.soft),
                      const Spacer(),
                      Container(
                        width: 30,
                        height: 4,
                        color: palette.muted.withValues(alpha: 0.3),
                      ),
                      const SizedBox(width: 6),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        width: 24,
                        decoration: BoxDecoration(
                          color: palette.soft,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: palette.chrome,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: palette.soft),
                          ),
                          child: Center(
                            child: Icon(
                              Icons.public,
                              size: 24,
                              color: palette.accent,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildWallpaperLibrary(
    BuildContext dialogContext,
    VoidCallback refreshDialog,
  ) {
    final categories = <String>[
      'All',
      'Favorites',
      ...kWallpapers.map((wallpaper) => wallpaper.category).toSet(),
    ];
    return Column(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () async {
                  await _selectWallpaper(name: 'Daily rotation');
                  refreshDialog();
                },
                icon: Icon(Icons.auto_awesome, color: _palette.accent),
                label: const Text('Daily image'),
              ),
              FilledButton.tonalIcon(
                onPressed: () async {
                  final file = await FilePicker.pickFile(
                    dialogTitle: 'Choose a browser background',
                    type: FileType.image,
                  );
                  final path = file?.path;
                  if (path != null) {
                    await _selectWallpaper(filePath: path, name: file!.name);
                    refreshDialog();
                  }
                },
                icon: const Icon(Icons.folder_open_outlined),
                label: const Text('Choose image'),
              ),
              FilledButton.tonalIcon(
                onPressed: () async {
                  final url = await _promptForImageUrl(dialogContext);
                  if (url == null) return;
                  await _selectWallpaper(url: url, name: 'Custom image');
                  refreshDialog();
                },
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: const Text('Image URL'),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 11),
                child: Text(
                  'Selected: $_wallpaperName',
                  style: TextStyle(
                    color: _palette.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 38,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: categories.length,
            separatorBuilder: (_, _) => const SizedBox(width: 7),
            itemBuilder: (context, index) {
              final category = categories[index];
              return ChoiceChip(
                label: Text(category),
                selected: _wallpaperCategory == category,
                selectedColor: _palette.soft,
                onSelected: (_) {
                  setState(() => _wallpaperCategory = category);
                  refreshDialog();
                },
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 250,
              mainAxisExtent: 228,
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
            ),
            itemCount: _filteredWallpapers.length,
            itemBuilder: (context, index) {
              final wallpaper = _filteredWallpapers[index];
              final selected = wallpaper.proceduralId != null
                  ? _wallpaperProcedural == wallpaper.proceduralId
                  : wallpaper.solidColor != null
                  ? _wallpaperColor == wallpaper.solidColor
                  : _wallpaperProcedural == null &&
                        _wallpaperFilePath == null &&
                        _wallpaperColor == null &&
                        _wallpaperUrl == wallpaper.url;
              final isFav = _favoriteWallpapers.contains(wallpaper.id);
              return _buildGalleryCard(
                context: context,
                title: wallpaper.name,
                subtitle:
                    wallpaper.subtitle ?? '${wallpaper.category} wallpaper',
                tag: wallpaper.tag ?? wallpaper.category,
                isSelected: selected,
                isFavorited: isFav,
                onFavoriteTap: () {
                  setState(() {
                    if (isFav) {
                      _favoriteWallpapers.remove(wallpaper.id);
                    } else {
                      _favoriteWallpapers.add(wallpaper.id);
                    }
                  });
                  refreshDialog();
                },
                onTap: () async {
                  await _selectWallpaper(
                    url: wallpaper.url,
                    solidColor: wallpaper.solidColor,
                    procedural: wallpaper.proceduralId,
                    name: wallpaper.name,
                  );
                  refreshDialog();
                },
                bannerWidget: wallpaper.proceduralId != null
                    ? CinderWallpaper(
                        CinderWallpapers.byId(wallpaper.proceduralId) ??
                            CinderWallpapers.privateWindow,
                      )
                    : wallpaper.solidColor != null
                    ? ColoredBox(color: wallpaper.solidColor!)
                    : Image.network(
                        wallpaper.thumbnailUrl ?? wallpaper.url!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            ColoredBox(color: _palette.raised),
                      ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<String?> _promptForImageUrl(BuildContext dialogContext) async {
    final controller = TextEditingController(text: _wallpaperUrl ?? '');
    final result = await showDialog<String>(
      context: dialogContext,
      builder: (context) => AlertDialog(
        backgroundColor: _palette.chrome,
        title: const Text('Custom background'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: 'Image URL',
            hintText: 'https://example.com/image.jpg',
          ),
          onSubmitted: (value) => Navigator.pop(context, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null || result.isEmpty) return null;
    final uri = Uri.tryParse(result);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a valid HTTPS image URL.')),
        );
      }
      return null;
    }
    return result;
  }

  Future<void> _showHistoryDialog() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, refreshDialog) => Dialog(
          backgroundColor: _palette.chrome,
          surfaceTintColor: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 780, maxHeight: 600),
            child: DefaultTabController(
              length: 2,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 14, 22, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.history, color: _palette.accent),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Browsing & Search History (Cloud Synced)',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () async {
                            await HistoryService.instance.clearHistory();
                            refreshDialog(() {});
                          },
                          icon: const Icon(Icons.delete_outline, size: 18),
                          label: const Text('Clear History'),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.redAccent,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close',
                          onPressed: () => Navigator.pop(dialogContext),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    Text(
                      'Synced securely with your PostgreSQL Cloud Database.',
                      style: TextStyle(color: _palette.muted, fontSize: 13),
                    ),
                    const SizedBox(height: 14),
                    TabBar(
                      labelColor: _palette.accent,
                      unselectedLabelColor: _palette.muted,
                      indicatorColor: _palette.accent,
                      tabs: const [
                        Tab(text: 'Visited Pages'),
                        Tab(text: 'Search Queries'),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: TabBarView(
                        children: [
                          _buildBrowsingHistoryList(dialogContext),
                          _buildSearchHistoryList(dialogContext),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBrowsingHistoryList(BuildContext dialogContext) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: HistoryService.instance.fetchBrowsingHistory(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: CircularProgressIndicator(color: _palette.accent),
          );
        }
        final items = snapshot.data ?? [];
        if (items.isEmpty) {
          return Center(
            child: Text(
              'No browsing history recorded yet.',
              style: TextStyle(color: _palette.muted),
            ),
          );
        }
        return ListView.separated(
          itemCount: items.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final item = items[index];
            final url = item['url']?.toString() ?? '';
            final title = item['title']?.toString() ?? url;
            final timeStr = item['last_visited_at']?.toString() ?? '';
            return ListTile(
              dense: true,
              leading: Icon(
                Icons.language,
                color: _palette.muted,
                size: 20,
              ),
              title: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _palette.ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                '$url ${timeStr.isEmpty ? '' : '• $timeStr'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: _palette.muted, fontSize: 11),
              ),
              trailing: const Icon(Icons.arrow_forward_ios, size: 13),
              onTap: () {
                Navigator.pop(dialogContext);
                unawaited(_navigate(url, source: NavSource.restore));
              },
            );
          },
        );
      },
    );
  }

  Widget _buildSearchHistoryList(BuildContext dialogContext) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: HistoryService.instance.fetchSearchHistory(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: CircularProgressIndicator(color: _palette.accent),
          );
        }
        final items = snapshot.data ?? [];
        if (items.isEmpty) {
          return Center(
            child: Text(
              'No search queries recorded yet.',
              style: TextStyle(color: _palette.muted),
            ),
          );
        }
        return ListView.separated(
          itemCount: items.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final item = items[index];
            final query = item['query_text']?.toString() ?? '';
            final timeStr = item['searched_at']?.toString() ?? '';
            return ListTile(
              dense: true,
              leading: Icon(Icons.search, color: _palette.accent, size: 20),
              title: Text(
                query,
                style: TextStyle(
                  color: _palette.ink,
                  fontWeight: FontWeight.w500,
                ),
              ),
              subtitle: Text(
                timeStr,
                style: TextStyle(color: _palette.muted, fontSize: 11),
              ),
              trailing: const Icon(Icons.arrow_forward_ios, size: 13),
              onTap: () {
                Navigator.pop(dialogContext);
                unawaited(_navigate(query));
              },
            );
          },
        );
      },
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshBackgroundIfNewDay();
      _scheduleMidnightRefresh();
    }
  }

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  void _scheduleMidnightRefresh() {
    _midnightTimer?.cancel();
    final now = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day + 1);
    _midnightTimer = Timer(midnight.difference(now), () {
      if (!mounted) return;
      setState(() => _backgroundDate = _dateOnly(DateTime.now()));
      _scheduleMidnightRefresh();
    });
  }

  void _refreshBackgroundIfNewDay() {
    final today = _dateOnly(DateTime.now());
    if (today != _backgroundDate && mounted) {
      setState(() => _backgroundDate = today);
    }
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    _urlController.removeListener(_onUrlTextChanged);
    _urlFocusNode.removeListener(_onUrlFocusChanged);
    WidgetsBinding.instance.removeObserver(this);
    _midnightTimer?.cancel();
    AppServices.account.removeListener(_onAccountChanged);
    _sessionSaveTimer?.cancel();
    _sleepTimer?.cancel();
    _saveSessionNow();
    unawaited(AppServices.cloud.flush());
    if (_isPrivate) {
      // Dispose every web view first so the engine releases its files.
      unawaited(() async {
        for (final tab in _tabs) {
          await tab.dispose();
        }
        await _cleanUpPrivateProfile();
      }());
    }
    _findController.dispose();
    _findFocusNode.dispose();
    _urlController.dispose();
    _urlFocusNode.dispose();
    _shellFocusNode.dispose();
    _requestFilter?.dispose();
    unawaited(_devToolsController?.dispose() ?? Future<void>.value());
    for (final tab in _tabs) {
      unawaited(tab.dispose());
    }
    super.dispose();
  }

  Future<void> _createTab({
    String? url,
    NavSource source = NavSource.omnibox,
  }) async {
    final tab = _BrowserTab();
    setState(() {
      _tabs.add(tab);
      _activeTabIndex = _tabs.length - 1;
      _urlController.text = '';
    });
    tab.initialization = _initializeTab(tab);
    await tab.initialization;
    if (url != null && mounted) await _navigate(url, source: source);
    _scheduleSessionSave();
  }

  void _showBlocked(String? reason) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(reason ?? 'That address was blocked.'),
          duration: const Duration(seconds: 5),
        ),
      );
  }

  Future<void> _initializeTab(_BrowserTab tab) async {
    if (defaultTargetPlatform != TargetPlatform.windows) {
      tab.error = 'Embedded page rendering is currently available on Windows.';
      if (mounted) setState(() {});
      return;
    }

    try {
      await tab.controller.initialize();
      if (!_webviewUp.isCompleted) _webviewUp.complete();
      // Hold the very first navigation until request filtering is attached
      // (bounded wait: a broken filter must never block browsing).
      await _shieldsReady.future.timeout(const Duration(seconds: 5), onTimeout: () {});
      await tab.controller.setDefaultContextMenusEnabled(false);
      await tab.controller.setPopupWindowPolicy(WebviewPopupWindowPolicy.deny);
      tab.downloadSubscription = tab.controller.onDownloadEvent.listen(
        DownloadService.instance.handleWebviewDownloadEvent,
      );
      await tab.controller.addScriptToExecuteOnDocumentCreated(
        _contextMenuScript,
      );
      tab.webMessageSubscription = tab.controller.webMessage.listen(
        (message) => _onPageMessage(tab, message),
        onError: (_) {},
      );
      tab.isInitialized = true;
      unawaited(ExtensionRuntime.instance.attach(tab.controller));

      tab.urlSubscription = tab.controller.url.listen((url) {
        tab.url = url;
        tab.error = null;
        unawaited(_applyZoomForUrl(tab, url));
        _scheduleSessionSave();
        if (identical(_activeTab, tab) && mounted) {
          _urlController.text = url;
          // O(1) in-memory check — no Supabase call on every URL change
          _updateBookmarkStatus(url);
        }
        // Coalesce: schedule one rebuild instead of calling setState directly
        if (mounted) _scheduleRebuild();
      });

      tab.titleSubscription = tab.controller.title.listen((title) {
        if (!mounted) return;
        tab.title = title.trim().isEmpty ? _tabTitle(tab.url) : title;
        _scheduleRebuild();
      });

      tab.loadingSubscription = tab.controller.loadingState.listen((state) {
        if (!mounted) return;
        tab.isLoading = state == LoadingState.loading;
        if (!tab.isLoading && identical(_activeTab, tab) && tab.url.isNotEmpty) {
          SemanticsService.sendAnnouncement(
            View.of(context),
            'Page loaded: ${tab.title}',
            TextDirection.ltr,
          );
        }
        // Loading state changes are high priority — rebuild immediately
        setState(() {});
      });

      tab.historySubscription = tab.controller.historyChanged.listen((history) {
        if (!mounted) return;
        tab.canGoBack = history.canGoBack;
        tab.canGoForward = history.canGoForward;
        _scheduleRebuild();
      });

      tab.errorSubscription = tab.controller.onLoadError.listen((error) {
        if (!mounted) return;
        tab.error = 'Page load failed: ${error.name}';
        setState(() {});
        unawaited(_offerInsecureFallback(tab));
      });

      if (mounted) setState(() {});
    } catch (error) {
      tab.error = 'Could not start WebView2: $error';
      _webviewRuntimeError =
          'Install or repair the Microsoft Edge WebView2 Runtime to browse.';
      if (mounted) setState(() {});
    }
  }

  /// Injected into every page: WebView2 hosted via composition never shows
  /// its native context menu, so the page reports the click and Flutter
  /// draws the Cinder menu instead.
  static const String _contextMenuScript = r'''
(function () {
  if (window.__cinderCtx) return;
  window.__cinderCtx = true;
  document.addEventListener('contextmenu', function (e) {
    var t = e.target;
    var a = t.closest ? t.closest('a[href]') : null;
    var img = t.tagName === 'IMG' ? t : (t.closest ? t.closest('img') : null);
    var ed = t.isContentEditable || /^(INPUT|TEXTAREA)$/.test(t.tagName);
    var sel = String(window.getSelection ? window.getSelection() : '');
    if (ed && t.selectionStart != null && t.selectionEnd > t.selectionStart) {
      sel = t.value.substring(t.selectionStart, t.selectionEnd);
    }
    e.preventDefault();
    window.chrome.webview.postMessage({
      cinderContext: true, x: e.clientX, y: e.clientY,
      link: a ? a.href : '', image: img ? (img.currentSrc || img.src) : '',
      selection: sel.slice(0, 500), editable: !!ed
    });
  }, true);
})();
''';

  final GlobalKey _pageKey = GlobalKey();

  void _onPageMessage(_BrowserTab tab, dynamic message) {
    // Page content fully controls this message: PageMessages is the single
    // whitelist (one type, http(s) senders only, strict shapes and sizes).
    final msg = PageMessages.parseContext(message, senderUrl: tab.url);
    if (msg == null) return;
    if (!mounted || !identical(_activeTab, tab)) return;
    final box = _pageKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final size = box.size;
    final dx = msg.x.clamp(0.0, size.width);
    final dy = msg.y.clamp(0.0, size.height);
    final origin = box.localToGlobal(Offset.zero);
    unawaited(
      _showWebContextMenu(
        tab,
        origin + Offset(dx, dy),
        link: msg.link,
        image: msg.image,
        selection: msg.selection,
        editable: msg.editable,
      ),
    );
  }

  Future<void> _showWebContextMenu(
    _BrowserTab tab,
    Offset position, {
    required String link,
    required String image,
    required String selection,
    required bool editable,
  }) async {
    final groups = <List<_BrowserContextAction>>[
      if (link.isNotEmpty)
        [
          _BrowserContextAction.openInNewTab,
          _BrowserContextAction.copyAddress,
        ],
      if (image.isNotEmpty)
        [
          _BrowserContextAction.openImage,
          _BrowserContextAction.copyImageAddress,
        ],
      if (editable)
        [
          _BrowserContextAction.cut,
          _BrowserContextAction.copy,
          _BrowserContextAction.paste,
          _BrowserContextAction.selectAll,
        ]
      else if (selection.isNotEmpty)
        [
          _BrowserContextAction.copy,
          _BrowserContextAction.searchSelection,
        ],
      if (link.isEmpty && image.isEmpty && !editable && selection.isEmpty) ...[
        [
          if (tab.canGoBack) _BrowserContextAction.back,
          if (tab.canGoForward) _BrowserContextAction.forward,
          _BrowserContextAction.reload,
        ],
        [_BrowserContextAction.print, _BrowserContextAction.viewSource],
      ],
      [_BrowserContextAction.inspect],
    ];
    final action = await _showBrowserContextMenu(
      globalPosition: position,
      groups: groups,
    );
    if (!mounted || action == null) return;
    final c = tab.controller;
    switch (action) {
      case _BrowserContextAction.back:
        await c.goBack();
      case _BrowserContextAction.forward:
        await c.goForward();
      case _BrowserContextAction.reload:
        await c.reload();
      case _BrowserContextAction.print:
        await c.executeScript('window.print()');
      case _BrowserContextAction.viewSource:
        await _createTab(
          url: 'view-source:${tab.url}',
          source: NavSource.browser,
        );
      case _BrowserContextAction.inspect:
        if (!_devToolsOpen) await _openDevTools();
      case _BrowserContextAction.openInNewTab:
        // Link targets are page-controlled: always policy-checked.
        await _createTab(url: link, source: NavSource.link);
      case _BrowserContextAction.copyAddress:
        await Clipboard.setData(ClipboardData(text: link));
      case _BrowserContextAction.openImage:
        await _createTab(url: image, source: NavSource.link);
      case _BrowserContextAction.copyImageAddress:
        await Clipboard.setData(ClipboardData(text: image));
      case _BrowserContextAction.copy:
        await c.executeScript("document.execCommand('copy')");
      case _BrowserContextAction.cut:
        await c.executeScript("document.execCommand('cut')");
      case _BrowserContextAction.selectAll:
        await c.executeScript("document.execCommand('selectAll')");
      case _BrowserContextAction.paste:
        final data = await Clipboard.getData(Clipboard.kTextPlain);
        final text = jsonEncode(data?.text ?? '');
        await c.executeScript("document.execCommand('insertText',false,$text)");
      case _BrowserContextAction.searchSelection:
        // Always a search, even if the selected text looks like an address.
        await _createTab(
          url: AppServices.searchEngine.buildUri(selection).toString(),
          source: NavSource.browser,
        );
      default:
        break;
    }
  }

  String _tabTitle(String url) {
    final uri = Uri.tryParse(url);
    return uri?.host.isNotEmpty == true ? uri!.host : 'New tab';
  }

  /// Every address that reaches WebView2 goes through [UrlPolicy]: default
  /// deny, allowlisted schemes only, phishing/homograph checks.
  Future<void> _navigate(
    String value, {
    NavSource source = NavSource.omnibox,
  }) async {
    final tab = _activeTab;
    if (tab == null) return;
    final decision = source == NavSource.omnibox
        ? UrlPolicy.resolveOmnibox(value, AppServices.searchEngine)
        : UrlPolicy.checkNavigation(value, source);
    if (decision.isBlocked) {
      _urlFocusNode.unfocus();
      _showBlocked(decision.reason);
      return;
    }
    final target = decision.url;
    final isSearchQuery = decision.kind == NavKind.search;
    _urlFocusNode.unfocus();
    if (tab.sleeping) {
      tab.sleeping = false;
      tab.pendingUrl = null;
      tab.initialization = _initializeTab(tab);
    }
    setState(() {
      tab.error = null;
      tab.url = target;
      tab.title = _tabTitle(target);
      tab.isLoading = true;
      _urlController.text = target;
    });

    try {
      await tab.initialization;
      if (!tab.isInitialized) {
        throw StateError(
          tab.error ?? _webviewRuntimeError ?? 'WebView2 is unavailable.',
        );
      }
      await tab.controller.loadUrl(target);
      if (!_isPrivate) {
        // Fire-and-forget cloud sync — never blocks navigation and never
        // throws into this method (errors are swallowed inside the service).
        unawaited(
          HistoryService.instance.recordVisit(target, tab.title),
        );
        if (isSearchQuery) {
          unawaited(
            HistoryService.instance.recordSearch(decision.originalQuery ?? ''),
          );
        }
      }
      _scheduleSessionSave();
    } catch (error) {
      if (!mounted) return;
      // Do not echo raw exception text (may contain paths / internals).
      debugPrint('navigate failed: ${error.runtimeType}');
      setState(() {
        tab.error = 'Unable to load page.';
        tab.isLoading = false;
      });
    }
  }

  void _selectTab(int index) {
    if (index < 0 || index >= _tabs.length) return;
    final tab = _tabs[index];
    tab.lastActive = DateTime.now();
    setState(() {
      _activeTabIndex = index;
      _urlController.text = tab.savedUrl;
    });
    if (tab.sleeping) unawaited(_wakeTab(tab));
    if (_findOpen) unawaited(_runFind());
    if (_devToolsOpen && tab.isInitialized && tab.id != _devToolsTabId) {
      unawaited(_attachDevTools(tab));
    }
    _scheduleSessionSave();
  }

  Future<void> _closeTab(int index, {bool remember = true}) async {
    if (index < 0 || index >= _tabs.length) return;
    final tab = _tabs.removeAt(index);
    if (remember && !_isPrivate) _closedTabs.push(tab.toSnapshot());
    if (_tabs.isEmpty) {
      setState(() => _activeTabIndex = 0);
      await tab.dispose();
      await _createTab();
      return;
    }
    if (index < _activeTabIndex) {
      _activeTabIndex--;
    }
    if (_activeTabIndex >= _tabs.length) _activeTabIndex = _tabs.length - 1;
    _urlController.text = _tabs[_activeTabIndex].savedUrl;
    setState(() {});
    await tab.dispose();
    final next = _activeTab;
    if (next != null && next.sleeping) unawaited(_wakeTab(next));
    _scheduleSessionSave();
  }

  // ----- zoom / find / print ------------------------------------------------

  Future<void> _applyZoomForUrl(_BrowserTab tab, String url) async {
    final host = Uri.tryParse(url)?.host ?? '';
    if (host.isEmpty || !tab.isInitialized) return;
    final level = _siteZoom.levelFor(host);
    if ((level - tab.zoom).abs() < 0.001) return;
    tab.zoom = level;
    try {
      await tab.controller.setZoomFactor(level);
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _setZoom(double zoom) async {
    final tab = _activeTab;
    if (tab == null || !tab.isInitialized) return;
    final level = PageZoom.clamp(zoom);
    tab.zoom = level;
    try {
      await tab.controller.setZoomFactor(level);
    } catch (_) {}
    final host = Uri.tryParse(tab.url)?.host ?? '';
    if (host.isNotEmpty && !_isPrivate) {
      _siteZoom.set(host, level);
      _saveZoomMemory();
    }
    if (mounted) setState(() {});
  }

  void _zoomIn() => unawaited(_setZoom(PageZoom.zoomIn(_activeTab?.zoom ?? 1)));
  void _zoomOut() =>
      unawaited(_setZoom(PageZoom.zoomOut(_activeTab?.zoom ?? 1)));
  void _zoomReset() => unawaited(_setZoom(1.0));

  void _openFind() {
    final tab = _activeTab;
    if (tab == null || !tab.isInitialized) return;
    setState(() => _findOpen = true);
    _findController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _findController.text.length,
    );
    _findFocusNode.requestFocus();
    if (_findController.text.isNotEmpty) unawaited(_runFind());
  }

  void _closeFind() {
    if (!_findOpen) return;
    setState(() {
      _findOpen = false;
      _findResult = const FindResult(0, 0);
    });
    final tab = _activeTab;
    if (tab != null && tab.isInitialized) {
      unawaited(
        tab.controller.executeScript(FindInPage.clearScript).catchError((_) {}),
      );
    }
  }

  /// Runs the search (index 0) or steps to the next/previous match.
  Future<void> _runFind({int step = 0}) async {
    final tab = _activeTab;
    if (tab == null || !tab.isInitialized) return;
    final query = _findController.text;
    final index = step == 0 ? 0 : _findResult.index + step;
    try {
      final raw = await tab.controller.executeScript(
        FindInPage.searchScript(
          query,
          index: index < 0 ? _findResult.count - 1 : index,
        ),
      );
      if (!mounted) return;
      setState(() => _findResult = FindInPage.parse(raw));
    } catch (_) {
      if (mounted) setState(() => _findResult = const FindResult.unsupported());
    }
  }

  Future<void> _printPage() async {
    final tab = _activeTab;
    if (tab == null || !tab.isInitialized) return;
    await tab.controller.executeScript('window.print()');
  }

  Widget _buildFindBar() {
    return Container(
      color: _palette.raised,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          SizedBox(
            width: 280,
            height: 34,
            child: TextField(
              controller: _findController,
              focusNode: _findFocusNode,
              maxLength: FindInPage.maxQueryLength,
              autocorrect: false,
              enableSuggestions: false,
              style: TextStyle(color: _palette.ink, fontSize: 13),
              decoration: InputDecoration(
                counterText: '',
                hintText: 'Find in page',
                hintStyle: TextStyle(color: _palette.muted, fontSize: 13),
                isDense: true,
                filled: true,
                fillColor: _palette.chrome,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 9,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: _palette.soft),
                ),
              ),
              onChanged: (_) => unawaited(_runFind()),
              onSubmitted: (_) => unawaited(_runFind(step: 1)),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 120,
            child: Text(
              _findController.text.isEmpty ? '' : _findResult.label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: _palette.muted, fontSize: 12),
            ),
          ),
          ToolbarButton(
            palette: _palette,
            tooltip: 'Previous match (Shift+F3)',
            icon: Icons.keyboard_arrow_up,
            onPressed: _findResult.count > 0
                ? () => unawaited(_runFind(step: -1))
                : null,
          ),
          ToolbarButton(
            palette: _palette,
            tooltip: 'Next match (F3)',
            icon: Icons.keyboard_arrow_down,
            onPressed: _findResult.count > 0
                ? () => unawaited(_runFind(step: 1))
                : null,
          ),
          ToolbarButton(
            palette: _palette,
            tooltip: 'Close (Esc)',
            icon: Icons.close,
            onPressed: _closeFind,
          ),
        ],
      ),
    );
  }

  /// Ctrl+Shift+T: reopens the most recently closed tab.
  Future<void> _reopenClosedTab() async {
    final snapshot = _closedTabs.pop();
    if (snapshot == null) return;
    final decision = UrlPolicy.checkNavigation(snapshot.url, NavSource.restore);
    if (decision.isBlocked) return;
    final tab = _BrowserTab()
      ..pinned = snapshot.pinned
      ..groupId = _groups.containsKey(snapshot.groupId) ? snapshot.groupId : null
      ..title = snapshot.title;
    setState(() {
      _tabs.add(tab);
      _activeTabIndex = _tabs.length - 1;
    });
    tab.initialization = _initializeTab(tab);
    await tab.initialization;
    if (mounted) await _navigate(decision.url, source: NavSource.restore);
  }

  // ----- pin / group / sleep / reorder -------------------------------------

  void _togglePinTab(_BrowserTab tab) {
    setState(() {
      tab.pinned = !tab.pinned;
      // Pinned tabs live at the front. A newly pinned tab goes to the end of
      // the pinned region; an unpinned one to the start of the rest.
      final active = _activeTab;
      _tabs.remove(tab);
      final firstUnpinned = _tabs.indexWhere((t) => !t.pinned);
      _tabs.insert(firstUnpinned < 0 ? _tabs.length : firstUnpinned, tab);
      if (active != null) _activeTabIndex = _tabs.indexOf(active);
    });
    _scheduleSessionSave();
  }

  void _reorderTab(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _tabs.length) return;
    final active = _activeTab;
    final moving = _tabs[oldIndex];
    // onReorderItem already accounts for the removed item.
    var target = newIndex.clamp(0, _tabs.length - 1);
    // Pinned tabs stay in the pinned region and vice versa.
    final pinnedCount = _tabs.where((t) => t.pinned).length;
    target = moving.pinned
        ? target.clamp(0, pinnedCount - 1)
        : target.clamp(pinnedCount, _tabs.length - 1);
    setState(() {
      _tabs
        ..removeAt(oldIndex)
        ..insert(target, moving);
      if (active != null) _activeTabIndex = _tabs.indexOf(active);
    });
    _scheduleSessionSave();
  }

  static final Random _idRandom = Random.secure();

  String _newGroupId() => List.generate(
    10,
    (_) => 'abcdefghijklmnopqrstuvwxyz0123456789'[_idRandom.nextInt(36)],
  ).join();

  void _addTabToNewGroup(_BrowserTab tab) {
    if (_groups.length >= TabGroupSnapshot.maxGroups) return;
    final id = _newGroupId();
    setState(() {
      _groups[id] = TabGroupSnapshot(
        id: id,
        name: 'Group ${_groups.length + 1}',
        colorIndex: _groups.length % TabGroupSnapshot.colorCount,
      );
      tab.groupId = id;
    });
    _scheduleSessionSave();
  }

  void _removeTabFromGroup(_BrowserTab tab) {
    final id = tab.groupId;
    setState(() {
      tab.groupId = null;
      if (id != null && !_tabs.any((t) => t.groupId == id)) _groups.remove(id);
    });
    _scheduleSessionSave();
  }

  Future<void> _renameGroup(String groupId) async {
    final group = _groups[groupId];
    if (group == null) return;
    final controller = TextEditingController(text: group.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Name this group'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          onSubmitted: (v) => Navigator.of(context).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || !mounted) return;
    final clean = TabSnapshot.sanitizeTitle(name);
    setState(() {
      _groups[groupId] = TabGroupSnapshot(
        id: group.id,
        name: clean.length > 40 ? clean.substring(0, 40) : clean,
        colorIndex: group.colorIndex,
      );
    });
    _scheduleSessionSave();
  }

  Future<void> _sleepTab(_BrowserTab tab) async {
    if (identical(tab, _activeTab) || tab.savedUrl.isEmpty) return;
    await tab.sleep();
    if (mounted) setState(() {});
  }

  Future<void> _goBack() async {
    final tab = _activeTab;
    if (tab != null && tab.canGoBack) await tab.controller.goBack();
  }

  Future<void> _goForward() async {
    final tab = _activeTab;
    if (tab != null && tab.canGoForward) await tab.controller.goForward();
  }

  Future<void> _reloadOrStop() async {
    final tab = _activeTab;
    if (tab == null) return;
    if (tab.isLoading) {
      await tab.controller.stop();
      return;
    }
    if (tab.url.isEmpty) return;
    await tab.controller.reload();
  }

  Future<_BrowserContextAction?> _showBrowserContextMenu({
    required Offset globalPosition,
    required List<List<_BrowserContextAction>> groups,
  }) {
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final localPosition = overlay.globalToLocal(globalPosition);
    final menuPosition = RelativeRect.fromLTRB(
      localPosition.dx,
      localPosition.dy,
      overlay.size.width - localPosition.dx,
      overlay.size.height - localPosition.dy,
    );

    return showMenu<_BrowserContextAction>(
      context: context,
      position: menuPosition,
      color: _palette.raised,
      elevation: 12,
      shadowColor: Colors.black.withValues(alpha: 0.22),
      constraints: const BoxConstraints(minWidth: 204, maxWidth: 240),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: _palette.soft),
      ),
      items: [
        for (var groupIndex = 0; groupIndex < groups.length; groupIndex++) ...[
          if (groupIndex > 0) const PopupMenuDivider(height: 8),
          for (final action in groups[groupIndex])
            PopupMenuItem<_BrowserContextAction>(
              value: action,
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  Container(
                    width: 27,
                    height: 27,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _isDestructiveContextAction(action)
                          ? const Color(0xFFB42318).withValues(alpha: 0.1)
                          : _palette.accent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Icon(
                      _contextActionIcon(action),
                      size: 16,
                      color: _isDestructiveContextAction(action)
                          ? const Color(0xFFB42318)
                          : _palette.accent,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _contextActionLabel(action),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _isDestructiveContextAction(action)
                            ? const Color(0xFFB42318)
                            : _palette.ink,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }

  bool _isDestructiveContextAction(_BrowserContextAction action) =>
      action == _BrowserContextAction.removeBookmark;

  String _contextActionLabel(_BrowserContextAction action) => switch (action) {
    _BrowserContextAction.newTab => 'New tab',
    _BrowserContextAction.addShortcut => 'Add shortcut',
    _BrowserContextAction.reload => 'Reload',
    _BrowserContextAction.duplicateTab => 'Duplicate tab',
    _BrowserContextAction.closeTab => 'Close tab',
    _BrowserContextAction.closeOtherTabs => 'Close other tabs',
    _BrowserContextAction.open => 'Open',
    _BrowserContextAction.openInNewTab => 'Open in new tab',
    _BrowserContextAction.copyAddress => 'Copy address',
    _BrowserContextAction.removeBookmark => 'Remove bookmark',
    _BrowserContextAction.addBookmark => 'Add bookmark',
    _BrowserContextAction.back => 'Back',
    _BrowserContextAction.forward => 'Forward',
    _BrowserContextAction.viewSource => 'View page source',
    _BrowserContextAction.inspect => 'Inspect',
    _BrowserContextAction.openImage => 'Open image in new tab',
    _BrowserContextAction.copyImageAddress => 'Copy image address',
    _BrowserContextAction.copy => 'Copy',
    _BrowserContextAction.cut => 'Cut',
    _BrowserContextAction.paste => 'Paste',
    _BrowserContextAction.selectAll => 'Select all',
    _BrowserContextAction.searchSelection => 'Search the web for selection',
    _BrowserContextAction.print => 'Print…',
    _BrowserContextAction.pasteAndGo => 'Paste and go',
    _BrowserContextAction.toggleBookmarksBar =>
      _showBookmarksBar ? 'Hide bookmarks bar' : 'Show bookmarks bar',
    _BrowserContextAction.showBookmarks => 'Bookmarks',
    _BrowserContextAction.showHistory => 'History',
    _BrowserContextAction.showDownloads => 'Downloads',
    _BrowserContextAction.customize => 'Customize Cinder…',
    _BrowserContextAction.pinTab => 'Pin tab',
    _BrowserContextAction.unpinTab => 'Unpin tab',
    _BrowserContextAction.newGroup => 'Add to new group',
    _BrowserContextAction.removeFromGroup => 'Remove from group',
    _BrowserContextAction.renameGroup => 'Rename group',
    _BrowserContextAction.sleepTab => 'Put tab to sleep',
    _BrowserContextAction.reopenClosedTab => 'Reopen closed tab',
  };

  IconData _contextActionIcon(_BrowserContextAction action) => switch (action) {
    _BrowserContextAction.newTab => Icons.add_box_outlined,
    _BrowserContextAction.addShortcut => Icons.add_link_rounded,
    _BrowserContextAction.reload => Icons.refresh_rounded,
    _BrowserContextAction.duplicateTab => Icons.copy_all_outlined,
    _BrowserContextAction.closeTab => Icons.close_rounded,
    _BrowserContextAction.closeOtherTabs => Icons.layers_clear_outlined,
    _BrowserContextAction.open => Icons.open_in_browser_rounded,
    _BrowserContextAction.openInNewTab => Icons.open_in_new_rounded,
    _BrowserContextAction.copyAddress => Icons.content_copy_rounded,
    _BrowserContextAction.removeBookmark => Icons.bookmark_remove_outlined,
    _BrowserContextAction.addBookmark => Icons.bookmark_add_outlined,
    _BrowserContextAction.back => Icons.arrow_back_rounded,
    _BrowserContextAction.forward => Icons.arrow_forward_rounded,
    _BrowserContextAction.viewSource => Icons.code_rounded,
    _BrowserContextAction.inspect => Icons.bug_report_outlined,
    _BrowserContextAction.openImage => Icons.image_outlined,
    _BrowserContextAction.copyImageAddress => Icons.link_rounded,
    _BrowserContextAction.copy => Icons.content_copy_rounded,
    _BrowserContextAction.cut => Icons.content_cut_rounded,
    _BrowserContextAction.paste => Icons.content_paste_rounded,
    _BrowserContextAction.selectAll => Icons.select_all_rounded,
    _BrowserContextAction.searchSelection => Icons.search_rounded,
    _BrowserContextAction.print => Icons.print_outlined,
    _BrowserContextAction.pasteAndGo => Icons.content_paste_go_rounded,
    _BrowserContextAction.toggleBookmarksBar => Icons.bookmarks_outlined,
    _BrowserContextAction.showBookmarks => Icons.star_outline_rounded,
    _BrowserContextAction.showHistory => Icons.history_rounded,
    _BrowserContextAction.showDownloads => Icons.download_outlined,
    _BrowserContextAction.customize => Icons.palette_outlined,
    _BrowserContextAction.pinTab => Icons.push_pin_outlined,
    _BrowserContextAction.unpinTab => Icons.push_pin,
    _BrowserContextAction.newGroup => Icons.workspaces_outline,
    _BrowserContextAction.removeFromGroup => Icons.link_off_rounded,
    _BrowserContextAction.renameGroup => Icons.edit_outlined,
    _BrowserContextAction.sleepTab => Icons.bedtime_outlined,
    _BrowserContextAction.reopenClosedTab => Icons.restore_page_outlined,
  };

  Future<void> _showTabContextMenu(Offset position, _BrowserTab tab) async {
    final action = await _showBrowserContextMenu(
      globalPosition: position,
      groups: [
        [
          _BrowserContextAction.newTab,
          if (_closedTabs.isNotEmpty) _BrowserContextAction.reopenClosedTab,
        ],
        [_BrowserContextAction.reload, _BrowserContextAction.duplicateTab],
        [
          tab.pinned
              ? _BrowserContextAction.unpinTab
              : _BrowserContextAction.pinTab,
          if (tab.groupId == null)
            _BrowserContextAction.newGroup
          else ...[
            _BrowserContextAction.renameGroup,
            _BrowserContextAction.removeFromGroup,
          ],
          if (!identical(tab, _activeTab) && tab.savedUrl.isNotEmpty)
            _BrowserContextAction.sleepTab,
        ],
        [_BrowserContextAction.closeTab, _BrowserContextAction.closeOtherTabs],
      ],
    );
    if (!mounted || action == null) return;

    switch (action) {
      case _BrowserContextAction.newTab:
        await _createTab();
        break;
      case _BrowserContextAction.addShortcut:
        break;
      case _BrowserContextAction.reload:
        if (tab.isInitialized && tab.url.isNotEmpty) {
          await tab.controller.reload();
        }
        break;
      case _BrowserContextAction.duplicateTab:
        await _createTab(url: tab.url.isEmpty ? null : tab.url, source: NavSource.browser);
        break;
      case _BrowserContextAction.closeTab:
        final index = _tabs.indexOf(tab);
        if (index >= 0) await _closeTab(index);
        break;
      case _BrowserContextAction.closeOtherTabs:
        final index = _tabs.indexOf(tab);
        if (index >= 0) await _closeOtherTabs(index);
        break;
      case _BrowserContextAction.pinTab:
      case _BrowserContextAction.unpinTab:
        _togglePinTab(tab);
        break;
      case _BrowserContextAction.newGroup:
        _addTabToNewGroup(tab);
        break;
      case _BrowserContextAction.removeFromGroup:
        _removeTabFromGroup(tab);
        break;
      case _BrowserContextAction.renameGroup:
        final id = tab.groupId;
        if (id != null) await _renameGroup(id);
        break;
      case _BrowserContextAction.sleepTab:
        await _sleepTab(tab);
        break;
      case _BrowserContextAction.reopenClosedTab:
        await _reopenClosedTab();
        break;
      case _BrowserContextAction.open:
      case _BrowserContextAction.openInNewTab:
      case _BrowserContextAction.copyAddress:
      case _BrowserContextAction.removeBookmark:
      case _BrowserContextAction.addBookmark:
      default:
        break;
    }
  }

  Future<void> _closeOtherTabs(int keepIndex) async {
    if (keepIndex < 0 || keepIndex >= _tabs.length) return;
    final keepTab = _tabs[keepIndex];
    _selectTab(keepIndex);
    for (var index = _tabs.length - 1; index >= 0; index--) {
      if (!identical(_tabs[index], keepTab)) await _closeTab(index);
    }
  }

  Future<void> _showBookmarkContextMenu(String url, Offset position) async {
    final action = await _showBrowserContextMenu(
      globalPosition: position,
      groups: const [
        [
          _BrowserContextAction.open,
          _BrowserContextAction.openInNewTab,
          _BrowserContextAction.copyAddress,
        ],
        [_BrowserContextAction.removeBookmark],
      ],
    );
    if (!mounted || action == null) return;

    switch (action) {
      case _BrowserContextAction.open:
        await _navigate(url, source: NavSource.restore);
        break;
      case _BrowserContextAction.openInNewTab:
        await _createTab(url: url, source: NavSource.restore);
        break;
      case _BrowserContextAction.copyAddress:
        await Clipboard.setData(ClipboardData(text: url));
        break;
      case _BrowserContextAction.removeBookmark:
        setState(() {
          _bookmarks.removeWhere((bookmark) => bookmark['url'] == url);
          _bookmarkedUrls.remove(url);
          if (_activeTab?.url == url) _currentPageBookmarked = false;
        });
        await BookmarkService.instance.removeBookmark(url);
        if (mounted) unawaited(_loadBookmarks());
        break;
      case _BrowserContextAction.newTab:
      case _BrowserContextAction.addShortcut:
      case _BrowserContextAction.reload:
      case _BrowserContextAction.duplicateTab:
      case _BrowserContextAction.closeTab:
      case _BrowserContextAction.closeOtherTabs:
      case _BrowserContextAction.addBookmark:
      default:
        break;
    }
  }

  Future<void> _showShortcutContextMenu(
    String title,
    String url,
    Offset position,
  ) async {
    final action = await _showBrowserContextMenu(
      globalPosition: position,
      groups: const [
        [
          _BrowserContextAction.open,
          _BrowserContextAction.openInNewTab,
          _BrowserContextAction.copyAddress,
        ],
        [_BrowserContextAction.addBookmark],
      ],
    );
    if (!mounted || action == null) return;

    switch (action) {
      case _BrowserContextAction.open:
        await _navigate(url, source: NavSource.restore);
        break;
      case _BrowserContextAction.openInNewTab:
        await _createTab(url: url, source: NavSource.restore);
        break;
      case _BrowserContextAction.copyAddress:
        await Clipboard.setData(ClipboardData(text: url));
        break;
      case _BrowserContextAction.addBookmark:
        await BookmarkService.instance.addBookmark(url, title);
        if (mounted) unawaited(_loadBookmarks());
        break;
      case _BrowserContextAction.newTab:
      case _BrowserContextAction.addShortcut:
      case _BrowserContextAction.reload:
      case _BrowserContextAction.duplicateTab:
      case _BrowserContextAction.closeTab:
      case _BrowserContextAction.closeOtherTabs:
      case _BrowserContextAction.removeBookmark:
      default:
        break;
    }
  }

  Future<void> _showHomePageContextMenu(Offset position) async {
    final action = await _showBrowserContextMenu(
      globalPosition: position,
      groups: const [
        [_BrowserContextAction.newTab, _BrowserContextAction.pasteAndGo],
        [_BrowserContextAction.addShortcut, _BrowserContextAction.customize],
        [
          _BrowserContextAction.toggleBookmarksBar,
          _BrowserContextAction.showBookmarks,
          _BrowserContextAction.showHistory,
          _BrowserContextAction.showDownloads,
        ],
        [_BrowserContextAction.inspect],
      ],
    );
    if (!mounted || action == null) return;

    switch (action) {
      case _BrowserContextAction.newTab:
        await _createTab();
        break;
      case _BrowserContextAction.addShortcut:
        await _showEditShortcutDialog();
        break;
      case _BrowserContextAction.pasteAndGo:
        final data = await Clipboard.getData(Clipboard.kTextPlain);
        final text = data?.text?.trim() ?? '';
        if (text.isNotEmpty) await _navigate(text);
        break;
      case _BrowserContextAction.customize:
        await _showAppearanceSettings();
        break;
      case _BrowserContextAction.toggleBookmarksBar:
        await _toggleBookmarksBar();
        break;
      case _BrowserContextAction.showBookmarks:
        await _showBookmarksDialog();
        break;
      case _BrowserContextAction.showHistory:
        await _showHistoryDialog();
        break;
      case _BrowserContextAction.showDownloads:
        await _showDownloadsDialog();
        break;
      case _BrowserContextAction.inspect:
        if (!_devToolsOpen) await _openDevTools();
        break;
      case _BrowserContextAction.reload:
      case _BrowserContextAction.duplicateTab:
      case _BrowserContextAction.closeTab:
      case _BrowserContextAction.closeOtherTabs:
      case _BrowserContextAction.open:
      case _BrowserContextAction.openInNewTab:
      case _BrowserContextAction.copyAddress:
      case _BrowserContextAction.removeBookmark:
      case _BrowserContextAction.addBookmark:
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tab = _activeTab;
    return Focus(
      focusNode: _shellFocusNode,
      autofocus: true,
      onKeyEvent: (node, event) => _handleKeyEvent(event),
      child: Scaffold(
        backgroundColor: _palette.chrome,
        body: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  FocusScope(node: _stripScope, child: _buildTabStrip()),
                  if (tab != null)
                    FocusScope(node: _toolbarScope, child: _buildToolbar(tab)),
                  if (tab?.isLoading == true)
                    LinearProgressIndicator(
                      minHeight: 2,
                      color: _palette.accent,
                      backgroundColor: _palette.soft,
                    ),
                  if (_showBookmarksBar)
                    FocusScope(node: _bookmarksScope, child: _buildBookmarksBar()),
                  if (_findOpen) _buildFindBar(),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(child: AnimatedSwitcher(
                      duration: Duration(
                        milliseconds: MediaQuery.of(context).disableAnimations ? 0 : 240,
                      ),
                      reverseDuration: Duration(
                        milliseconds: MediaQuery.of(context).disableAnimations ? 0 : 160,
                      ),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0.012, 0),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      ),
                      child: tab == null
                          ? const SizedBox.shrink(
                              key: ValueKey('empty-browser'),
                            )
                          : KeyedSubtree(
                              key: ValueKey(tab.id),
                              child: _buildPage(tab),
                            ),
                        )),
                        if (_devToolsOpen) _buildDevToolsPanel(),
                      ],
                    ),
                  ),
                ],
              ),
              if (_showSuggestions && _fuzzySuggestions.isNotEmpty)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: CompositedTransformFollower(
                    link: _addressBarLayerLink,
                    showWhenUnlinked: false,
                    offset: const Offset(0, 46),
                    child: _buildFuzzySuggestionsOverlay(),
                  ),
                ),
              if (_popup != null) _buildExtensionPopup(),
            ],
          ),
        ),
      ),
    );
  }

  int get _devToolsPort => AppServices.launch.devToolsPort;
  WebviewController? _devToolsController;
  bool _devToolsOpen = false;
  bool _devToolsReady = false;
  String? _devToolsError;
  String? _devToolsTabId;
  double _devToolsWidth = 520;

  /// Toggles the docked DevTools panel (F12 / Ctrl+Shift+I).
  Future<void> _openDevTools() async {
    if (_devToolsOpen) {
      await _closeDevTools();
      return;
    }
    final tab = _activeTab;
    if (tab == null || !tab.isInitialized) return;
    if (_devToolsPort == 0) {
      _showBlocked('DevTools is not available in this window.');
      return;
    }
    setState(() {
      _devToolsOpen = true;
      _devToolsReady = false;
      _devToolsError = null;
    });
    await _attachDevTools(tab);
  }

  Future<void> _closeDevTools() async {
    final controller = _devToolsController;
    setState(() {
      _devToolsOpen = false;
      _devToolsReady = false;
      _devToolsController = null;
      _devToolsTabId = null;
    });
    await controller?.dispose();
  }

  /// Finds [tab] among the debuggable targets and loads its DevTools
  /// frontend into the docked panel.
  Future<void> _attachDevTools(_BrowserTab tab) async {
    try {
      final client = HttpClient();
      String? frontend;
      try {
        final request = await client.getUrl(
          Uri.parse('http://127.0.0.1:$_devToolsPort/json'),
        );
        final response = await request.close();
        final body = await utf8.decodeStream(response);
        final targets = (jsonDecode(body) as List).cast<Map<String, dynamic>>();
        final pages = targets.where((t) {
          final u = (t['url'] ?? '').toString();
          return t['type'] == 'page' &&
              !u.contains('devtools') &&
              !u.contains('inspector.html') &&
              !u.startsWith('about:') &&
              !u.startsWith('edge:');
        }).toList();
        final match = pages.firstWhere(
          (t) => t['url'] == tab.url,
          orElse: () => <String, dynamic>{},
        );
        final id = match['id']?.toString();
        if (id != null) {
          frontend =
              '/devtools/inspector.html?ws=127.0.0.1:$_devToolsPort/devtools/page/$id';
        }
      } finally {
        client.close(force: true);
      }
      if (frontend == null) {
        throw StateError('No debuggable page found for this tab.');
      }
      final url = frontend.startsWith('http')
          ? frontend
          : 'http://127.0.0.1:$_devToolsPort$frontend';

      final old = _devToolsController;
      final controller = WebviewController();
      await controller.initialize();
      await controller.loadUrl(url);
      if (!mounted || !_devToolsOpen) {
        await controller.dispose();
        return;
      }
      setState(() {
        _devToolsController = controller;
        _devToolsTabId = tab.id;
        _devToolsReady = true;
      });
      await old?.dispose();
    } catch (error) {
      if (!mounted) return;
      setState(() => _devToolsError = 'DevTools unavailable: $error');
    }
  }

  Widget _buildDevToolsPanel() {
    final controller = _devToolsController;
    return Row(
      children: [
        MouseRegion(
          cursor: SystemMouseCursors.resizeColumn,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragUpdate: (d) => setState(() {
              _devToolsWidth = (_devToolsWidth - d.delta.dx).clamp(280, 1100);
            }),
            child: Container(width: 6, color: _palette.soft),
          ),
        ),
        SizedBox(
          width: _devToolsWidth,
          child: Column(
            children: [
              Container(
                height: 32,
                color: _palette.raised,
                padding: const EdgeInsets.only(left: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'DevTools',
                        style: TextStyle(
                          color: _palette.ink,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close DevTools',
                      iconSize: 16,
                      onPressed: () => unawaited(_closeDevTools()),
                      icon: Icon(Icons.close, color: _palette.ink),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _devToolsError != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            _devToolsError!,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: _palette.ink),
                          ),
                        ),
                      )
                    : (_devToolsReady && controller != null)
                    ? Webview(controller, permissionRequested: (_, __, ___) => WebviewPermissionDecision.deny)
                    : const Center(child: CircularProgressIndicator()),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Handles global keyboard shortcuts at the browser-shell level.
  KeyEventResult _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final ctrl =
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    final key = event.logicalKey;

    if (_showSuggestions && _fuzzySuggestions.isNotEmpty) {
      if (key == LogicalKeyboardKey.arrowDown) {
        setState(() {
          _selectedSuggestionIndex =
              (_selectedSuggestionIndex + 1) % _fuzzySuggestions.length;
          _urlController.text = _fuzzySuggestions[_selectedSuggestionIndex].url;
          _urlController.selection = TextSelection.collapsed(
            offset: _urlController.text.length,
          );
        });
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowUp) {
        setState(() {
          _selectedSuggestionIndex =
              (_selectedSuggestionIndex - 1 + _fuzzySuggestions.length) %
              _fuzzySuggestions.length;
          _urlController.text = _fuzzySuggestions[_selectedSuggestionIndex].url;
          _urlController.selection = TextSelection.collapsed(
            offset: _urlController.text.length,
          );
        });
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.escape) {
        setState(() {
          _showSuggestions = false;
        });
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.enter &&
          _selectedSuggestionIndex >= 0 &&
          _selectedSuggestionIndex < _fuzzySuggestions.length) {
        _selectFuzzySuggestion(_fuzzySuggestions[_selectedSuggestionIndex]);
        return KeyEventResult.handled;
      }
    }

    if (key == LogicalKeyboardKey.f12 ||
        (ctrl && shift && key == LogicalKeyboardKey.keyI)) {
      unawaited(_openDevTools());
      return KeyEventResult.handled;
    }

    if (ctrl && shift && key == LogicalKeyboardKey.keyT) {
      unawaited(_reopenClosedTab());
      return KeyEventResult.handled;
    }
    if (ctrl && shift && key == LogicalKeyboardKey.keyN) {
      unawaited(_openPrivateWindow());
      return KeyEventResult.handled;
    }
    if (ctrl && key == LogicalKeyboardKey.keyF) {
      _openFind();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape && _popup != null) {
      _closeExtensionPopup();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape && _findOpen) {
      _closeFind();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.f3 ||
        (ctrl && key == LogicalKeyboardKey.keyG)) {
      if (_findOpen) unawaited(_runFind(step: shift ? -1 : 1));
      return KeyEventResult.handled;
    }
    if (ctrl &&
        (key == LogicalKeyboardKey.equal ||
            key == LogicalKeyboardKey.add ||
            key == LogicalKeyboardKey.numpadAdd)) {
      _zoomIn();
      return KeyEventResult.handled;
    }
    if (ctrl &&
        (key == LogicalKeyboardKey.minus ||
            key == LogicalKeyboardKey.numpadSubtract)) {
      _zoomOut();
      return KeyEventResult.handled;
    }
    if (ctrl &&
        (key == LogicalKeyboardKey.digit0 ||
            key == LogicalKeyboardKey.numpad0)) {
      _zoomReset();
      return KeyEventResult.handled;
    }
    if (ctrl && key == LogicalKeyboardKey.keyP) {
      unawaited(_printPage());
      return KeyEventResult.handled;
    }
    if (ctrl && key == LogicalKeyboardKey.tab) {
      if (_tabs.length > 1) {
        final next = shift
            ? (_activeTabIndex - 1 + _tabs.length) % _tabs.length
            : (_activeTabIndex + 1) % _tabs.length;
        _selectTab(next);
      }
      return KeyEventResult.handled;
    }
    if (ctrl && !shift) {
      const digits = [
        LogicalKeyboardKey.digit1,
        LogicalKeyboardKey.digit2,
        LogicalKeyboardKey.digit3,
        LogicalKeyboardKey.digit4,
        LogicalKeyboardKey.digit5,
        LogicalKeyboardKey.digit6,
        LogicalKeyboardKey.digit7,
        LogicalKeyboardKey.digit8,
        LogicalKeyboardKey.digit9,
      ];
      final at = digits.indexOf(key);
      if (at >= 0 && _tabs.isNotEmpty) {
        // Ctrl+9 always means "last tab", like Chrome and Firefox.
        _selectTab(at == 8 ? _tabs.length - 1 : at.clamp(0, _tabs.length - 1));
        return KeyEventResult.handled;
      }
    }
    if (ctrl && key == LogicalKeyboardKey.keyT) {
      unawaited(_createTab());
      return KeyEventResult.handled;
    }
    if (ctrl && key == LogicalKeyboardKey.keyW) {
      unawaited(_closeTab(_activeTabIndex));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.f6) {
      _focusZone(shift ? _zone - 1 + 5 : _zone + 1);
      return KeyEventResult.handled;
    }
    if (HardwareKeyboard.instance.isAltPressed && key == LogicalKeyboardKey.keyD) {
      _focusZone(0);
      return KeyEventResult.handled;
    }
    if (ctrl && key == LogicalKeyboardKey.keyL) {
      _urlFocusNode.requestFocus();
      _urlController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _urlController.text.length,
      );
      return KeyEventResult.handled;
    }
    if ((ctrl && key == LogicalKeyboardKey.keyR) ||
        key == LogicalKeyboardKey.f5) {
      unawaited(_reloadOrStop());
      return KeyEventResult.handled;
    }
    if (ctrl && shift && key == LogicalKeyboardKey.keyB) {
      unawaited(_toggleBookmarksBar());
      return KeyEventResult.handled;
    }
    if (ctrl && key == LogicalKeyboardKey.keyD) {
      unawaited(_toggleBookmark());
      return KeyEventResult.handled;
    }
    if (ctrl && key == LogicalKeyboardKey.keyH) {
      unawaited(_showHistoryDialog());
      return KeyEventResult.handled;
    }
    if (ctrl && key == LogicalKeyboardKey.keyJ) {
      unawaited(_showDownloadsDialog());
      return KeyEventResult.handled;
    }
    if (ctrl && key == LogicalKeyboardKey.keyM) {
      unawaited(_showBookmarksDialog());
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _buildFuzzySuggestionsOverlay() {
    return Align(
      alignment: Alignment.topLeft,
      child: Material(
        color: Colors.transparent,
        elevation: 12,
        shadowColor: Colors.black.withOpacity(0.3),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 720, maxHeight: 340),
          decoration: BoxDecoration(
            color: _palette.raised,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _palette.soft, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.25),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 6),
              shrinkWrap: true,
              itemCount: _fuzzySuggestions.length,
              separatorBuilder: (_, _) => Divider(
                height: 1,
                thickness: 1,
                color: _palette.soft.withOpacity(0.5),
              ),
              itemBuilder: (context, index) {
                final item = _fuzzySuggestions[index];
                final isSelected = index == _selectedSuggestionIndex;

                IconData icon;
                Color iconColor;
                String badgeText;

                switch (item.type) {
                  case FuzzySuggestionType.bookmark:
                    icon = Icons.star_rounded;
                    iconColor = const Color(0xFFFFB300);
                    badgeText = 'Bookmark';
                    break;
                  case FuzzySuggestionType.history:
                    icon = Icons.history_rounded;
                    iconColor = _palette.accent;
                    badgeText = 'History';
                    break;
                  case FuzzySuggestionType.searchHistory:
                    icon = Icons.manage_search_rounded;
                    iconColor = const Color(0xFFAB47BC);
                    badgeText = 'Recent Search';
                    break;
                  case FuzzySuggestionType.url:
                    icon = Icons.public_rounded;
                    iconColor = const Color(0xFF29B6F6);
                    badgeText = 'Direct URL';
                    break;
                  case FuzzySuggestionType.webSearch:
                    icon = Icons.search_rounded;
                    iconColor = _palette.accent;
                    badgeText = 'Google Search';
                    break;
                }

                return InkWell(
                  onTap: () => _selectFuzzySuggestion(item),
                  onHover: (hovered) {
                    if (hovered && _selectedSuggestionIndex != index) {
                      setState(() => _selectedSuggestionIndex = index);
                    }
                  },
                  child: Container(
                    color: isSelected
                        ? _palette.accent.withOpacity(0.18)
                        : Colors.transparent,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Icon(icon, size: 20, color: iconColor),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                item.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: _palette.ink,
                                  fontSize: 14,
                                  fontWeight: isSelected
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                ),
                              ),
                              if (item.url.isNotEmpty &&
                                  item.type != FuzzySuggestionType.webSearch)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    item.url,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: _palette.muted,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? _palette.accent.withOpacity(0.25)
                                : _palette.soft,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            badgeText,
                            style: TextStyle(
                              color: isSelected
                                  ? _palette.accent
                                  : _palette.muted,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTabStrip() {
    return Container(
      height: 48,
      padding: const EdgeInsets.fromLTRB(8, 2, 8, 0),
      color: _palette.frame,
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, right: 10),
            child: Tooltip(
              message: _isPrivate
                  ? 'Private window: nothing is saved or synced'
                  : 'Cinder',
              child: _isPrivate
                  ? Icon(
                      Icons.visibility_off_rounded,
                      size: 20,
                      color: _palette.accent,
                    )
                  : const CinderMark(size: 22),
            ),
          ),
          Expanded(child: _buildTabsArea()),
          if (_isPrivate) _buildPrivateBadge(),
        ],
      ),
    );
  }

  Widget _buildPrivateBadge() {
    return Container(
      margin: const EdgeInsets.only(left: 8, bottom: 2),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _palette.accent.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _palette.accent.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.visibility_off_rounded, size: 14, color: _palette.ink),
          const SizedBox(width: 6),
          Text(
            'Private',
            style: TextStyle(
              color: _palette.ink,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ----- account, private windows, profiles --------------------------------

  Future<void> _launchWindow(List<String> args) async {
    try {
      await Process.start(
        Platform.resolvedExecutable,
        args,
        mode: ProcessStartMode.detached,
      );
    } catch (error) {
      debugPrint('launch window failed: ${error.runtimeType}');
      _showBlocked('Could not open a new window.');
    }
  }

  /// Private window = a separate process with a temporary engine profile and
  /// no account, history, session or cloud writes.
  Future<void> _openPrivateWindow() => _launchWindow(const ['--private']);

  List<TabGroupSnapshot> get _profileList {
    final records = AppServices.cloud.values('profile');
    final out = <TabGroupSnapshot>[];
    for (final r in records) {
      final id = r['id'];
      final name = r['name'];
      if (id is String &&
          ProfilePaths.profileIdPattern.hasMatch(id) &&
          id != 'default' &&
          name is String) {
        out.add(TabGroupSnapshot(id: id, name: name, colorIndex: 0));
      }
    }
    return out;
  }

  Future<void> _createProfile() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New profile'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 24,
          decoration: const InputDecoration(
            hintText: 'e.g. Work',
            helperText: 'Each profile has its own cookies, logins and account.',
          ),
          onSubmitted: (v) => Navigator.of(context).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    controller.dispose();
    final clean = TabSnapshot.sanitizeTitle(name ?? '');
    if (clean.isEmpty) return;
    var id = clean
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    if (id.isEmpty) id = 'profile';
    if (id.length > 24) id = id.substring(0, 24);
    if (id == 'default' || AppServices.cloud.contains('profile', id)) {
      id = '$id-${_newGroupId().substring(0, 5)}';
    }
    if (!ProfilePaths.profileIdPattern.hasMatch(id)) return;
    AppServices.cloud.put('profile', id, {'id': id, 'name': clean});
    await _launchWindow(['--profile=$id']);
    if (mounted) setState(() {});
  }

  Widget _buildAccountButton() {
    return AnimatedBuilder(
      animation: AppServices.account,
      builder: (context, _) {
        final state = AppServices.account.state;
        final synced = state == AccountState.unlocked;
        final needsAction =
            state == AccountState.locked ||
            state == AccountState.needsVaultSetup;
        final profiles = _profileList;
        return PopupMenuButton<String>(
          tooltip: synced
              ? 'Account: sync on'
              : (needsAction ? 'Account: action needed' : 'Account: guest'),
          color: _palette.raised,
          position: PopupMenuPosition.under,
          icon: Badge(
            isLabelVisible: needsAction,
            smallSize: 8,
            child: Icon(
              synced
                  ? Icons.cloud_done_outlined
                  : (_isPrivate
                        ? Icons.visibility_off_outlined
                        : Icons.account_circle_outlined),
              size: 20,
              color: _palette.ink,
            ),
          ),
          onSelected: (value) {
            if (value == 'account') {
              unawaited(showAccountDialog(context, _palette));
            } else if (value == 'search') {
              unawaited(showSearchEngineDialog(context, _palette));
            } else if (value == 'private') {
              unawaited(_openPrivateWindow());
            } else if (value == 'new-profile') {
              unawaited(_createProfile());
            } else if (value.startsWith('profile:')) {
              final id = value.substring('profile:'.length);
              if (ProfilePaths.profileIdPattern.hasMatch(id)) {
                unawaited(_launchWindow(['--profile=$id']));
              }
            }
          },
          itemBuilder: (context) => [
            if (!_isPrivate)
              PopupMenuItem(
                value: 'account',
                child: Text(
                  synced
                      ? 'Account & sync'
                      : (needsAction ? 'Finish sync setup…' : 'Sign in to sync…'),
                ),
              ),
            const PopupMenuItem(value: 'search', child: Text('Search engine…')),
            const PopupMenuItem(
              value: 'private',
              child: Text('New private window  (Ctrl+Shift+N)'),
            ),
            if (!_isPrivate) ...[
              const PopupMenuDivider(),
              for (final p in profiles)
                PopupMenuItem(
                  value: 'profile:${p.id}',
                  child: Text('Profile: ${p.name}'),
                ),
              const PopupMenuItem(
                value: 'new-profile',
                child: Text('New profile…'),
              ),
            ],
          ],
        );
      },
    );
  }

  static const List<Color> _groupColors = [
    Color(0xFF3B82F6),
    Color(0xFFEF4444),
    Color(0xFFF59E0B),
    Color(0xFF10B981),
    Color(0xFF8B5CF6),
    Color(0xFFEC4899),
    Color(0xFF14B8A6),
    Color(0xFF6B7280),
  ];

  Widget _buildTabsArea() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final pinnedCount = _tabs.where((t) => t.pinned).length;
        const pinnedWidth = 40.0;
        const newTabWidth = 38.0;
        const gap = 2.0;
        final normalCount = _tabs.length - pinnedCount;
        final room =
            constraints.maxWidth -
            newTabWidth -
            pinnedCount * (pinnedWidth + gap) -
            normalCount * gap;
        final tabWidth = normalCount == 0
            ? 200.0
            : (room / normalCount).clamp(88.0, 220.0);
        final listWidth =
            pinnedCount * (pinnedWidth + gap) + normalCount * (tabWidth + gap);
        return Row(
          children: [
            SizedBox(
              width: listWidth.clamp(0.0, constraints.maxWidth - newTabWidth),
              child: ReorderableListView.builder(
                scrollDirection: Axis.horizontal,
                proxyDecorator: (child, index, animation) =>
                    Material(color: Colors.transparent, child: child),
                itemCount: _tabs.length,
                onReorderItem: _reorderTab,
                itemBuilder: (context, index) => _buildTabItem(
                  index,
                  _tabs[index].pinned ? pinnedWidth : tabWidth,
                ),
              ),
            ),
            const SizedBox(width: 4),
            ToolbarButton(
              palette: _palette,
              tooltip: 'New tab',
              icon: Icons.add_rounded,
              size: 30,
              iconSize: 20,
              onPressed: () => unawaited(_createTab()),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTabItem(int index, double width) {
    final tab = _tabs[index];
    final group = tab.groupId == null ? null : _groups[tab.groupId];
    final groupColor = group == null
        ? null
        : _groupColors[group.colorIndex % _groupColors.length];
    final firstInGroup =
        group != null &&
        (index == 0 || _tabs[index - 1].groupId != tab.groupId);
    final tooltip = tab.sleeping
        ? '${tab.title} (sleeping)'
        : (group != null && group.name.isNotEmpty
              ? '${group.name}: ${tab.title}'
              : tab.title);
    return Padding(
      key: ValueKey(tab.id),
      padding: const EdgeInsets.only(right: 2),
      child: Tooltip(
        // Blank tabs get no tooltip (it would only repeat "New tab").
        message: tab.savedUrl.isEmpty ? '' : tooltip,
        waitDuration: const Duration(milliseconds: 700),
        child: TabChip(
          palette: _palette,
          width: width,
          title: tab.title,
          host: Uri.tryParse(tab.savedUrl)?.host ?? '',
          selected: index == _activeTabIndex,
          pinned: tab.pinned,
          loading: tab.isLoading,
          sleeping: tab.sleeping,
          groupColor: groupColor,
          groupName: firstInGroup ? group.name : null,
          onGroupTap: group == null ? null : () => unawaited(_renameGroup(group.id)),
          onTap: () => _selectTab(index),
          onClose: () => unawaited(_closeTab(index)),
          onMiddleTap: () => unawaited(_closeTab(index)),
          onSecondaryTapDown: (details) =>
              unawaited(_showTabContextMenu(details.globalPosition, tab)),
        ),
      ),
    );
  }

  Widget _buildToolbar(_BrowserTab tab) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 760;
        return Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: _palette.toolbar,
            border: Border(
              bottom: BorderSide(
                color: _palette.divider.withValues(alpha: 0.7),
                width: 0.8,
              ),
            ),
          ),
          child: Row(
            children: [
              ToolbarButton(
                palette: _palette,
                tooltip: 'Back',
                icon: Icons.arrow_back_rounded,
                onPressed: tab.canGoBack ? _goBack : null,
              ),
              ToolbarButton(
                palette: _palette,
                tooltip: 'Forward',
                icon: Icons.arrow_forward_rounded,
                onPressed: tab.canGoForward ? _goForward : null,
              ),
              ToolbarButton(
                palette: _palette,
                tooltip: tab.isLoading ? 'Stop loading' : 'Reload page',
                icon: tab.isLoading ? Icons.close_rounded : Icons.refresh_rounded,
                onPressed: _reloadOrStop,
              ),
              const SizedBox(width: 6),
              Expanded(child: _addressBar(tab)),
              const SizedBox(width: 6),
              ValueListenableBuilder<int>(
                valueListenable: DownloadService.instance.activeDownloadsCount,
                builder: (context, count, _) => ToolbarButton(
                  palette: _palette,
                  tooltip: 'Downloads (Ctrl+J)',
                  icon: Icons.download_rounded,
                  badge: count > 0 ? '$count' : null,
                  onPressed: _showDownloadsDialog,
                ),
              ),
              ..._extensionToolbarWidgets(),
              if (wide)
                ToolbarButton(
                  palette: _palette,
                  tooltip: 'Appearance settings',
                  icon: Icons.palette_outlined,
                  onPressed: _showAppearanceSettings,
                ),
              _buildAccountButton(),
              _buildMenuButton(),
            ],
          ),
        );
      },
    );
  }

  /// The ☰ application menu (Firefox-style): everything not on the toolbar.
  Widget _buildMenuButton() {
    return PopupMenuButton<String>(
      tooltip: 'Open menu',
      color: _palette.toolbar,
      position: PopupMenuPosition.under,
      offset: const Offset(0, 4),
      icon: Icon(Icons.menu_rounded, size: 20, color: _palette.ink),
      onSelected: (value) {
        switch (value) {
          case 'new-tab':
            unawaited(_createTab());
          case 'private':
            unawaited(_openPrivateWindow());
          case 'bookmarks':
            unawaited(_showBookmarksDialog());
          case 'history':
            unawaited(_showHistoryDialog());
          case 'downloads':
            unawaited(_showDownloadsDialog());
          case 'find':
            _openFind();
          case 'print':
            unawaited(_printPage());
          case 'zoom-in':
            _zoomIn();
          case 'zoom-out':
            _zoomOut();
          case 'zoom-reset':
            _zoomReset();
          case 'bookmarks-bar':
            unawaited(_toggleBookmarksBar());
          case 'extensions':
            unawaited(_showExtensionsDialog());
          case 'site-permissions':
            unawaited(showSitePermissionsManager(context, _palette, _sitePerms));
          case 'shields':
            unawaited(_showShieldsSettingsDialog());
          case 'appearance':
            unawaited(_showAppearanceSettings());
          case 'search-engine':
            unawaited(showSearchEngineDialog(context, _palette));
          case 'devtools':
            unawaited(_openDevTools());
          case 'import-bookmarks':
            unawaited(_importBookmarks());
          case 'default-browser':
            unawaited(_openDefaultAppsSettings());
          case 'check-updates':
            unawaited(_checkForUpdates(manual: true));
          case 'about':
            _showAbout();
        }
      },
      itemBuilder: (context) {
        PopupMenuItem<String> item(String value, IconData icon, String label, [String? hint]) {
          return PopupMenuItem<String>(
            value: value,
            height: 38,
            child: Row(
              children: [
                Icon(icon, size: 18, color: _palette.muted),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(label, style: TextStyle(color: _palette.ink, fontSize: 13)),
                ),
                if (hint != null)
                  Text(hint, style: TextStyle(color: _palette.muted, fontSize: 11.5)),
              ],
            ),
          );
        }

        final zoom = _activeTab?.zoom ?? 1.0;
        return [
          item('new-tab', Icons.add_box_outlined, 'New tab', 'Ctrl+T'),
          item('private', Icons.visibility_off_outlined, 'New private window', 'Ctrl+Shift+N'),
          const PopupMenuDivider(),
          item('bookmarks', Icons.bookmarks_outlined, 'Bookmarks', 'Ctrl+M'),
          item('history', Icons.history_rounded, 'History', 'Ctrl+H'),
          item('downloads', Icons.download_rounded, 'Downloads', 'Ctrl+J'),
          item('extensions', Icons.extension_outlined, 'Extensions'),
          item('site-permissions', Icons.shield_outlined, 'Site permissions'),
          item('shields', Icons.security_rounded, 'Privacy and security'),
          const PopupMenuDivider(),
          item('find', Icons.search_rounded, 'Find in page…', 'Ctrl+F'),
          item('print', Icons.print_outlined, 'Print…', 'Ctrl+P'),
          PopupMenuItem<String>(
            // Not disabled: a disabled item dims its icons. Taps on the +/-
            // buttons are handled by the buttons themselves.
            height: 40,
            child: Row(
              children: [
                Icon(Icons.zoom_in_rounded, size: 18, color: _palette.muted),
                const SizedBox(width: 12),
                Text('Zoom', style: TextStyle(color: _palette.ink, fontSize: 13)),
                const Spacer(),
                _menuZoomButton(Icons.remove_rounded, 'zoom-out'),
                SizedBox(
                  width: 48,
                  child: Text(
                    PageZoom.label(zoom),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _palette.ink, fontSize: 12.5),
                  ),
                ),
                _menuZoomButton(Icons.add_rounded, 'zoom-in'),
              ],
            ),
          ),
          const PopupMenuDivider(),
          item(
            'bookmarks-bar',
            Icons.bookmark_border_rounded,
            _showBookmarksBar ? 'Hide bookmarks bar' : 'Show bookmarks bar',
            'Ctrl+Shift+B',
          ),
          item('appearance', Icons.palette_outlined, 'Themes & wallpapers'),
          item('search-engine', Icons.manage_search_rounded, 'Search engine…'),
          item('devtools', Icons.code_rounded, 'Developer tools', 'F12'),
          const PopupMenuDivider(),
          item('import-bookmarks', Icons.file_upload_outlined, 'Import bookmarks…'),
          item('default-browser', Icons.open_in_browser_rounded, 'Make Cinder your default browser'),
          item('check-updates', Icons.system_update_alt_rounded, 'Check for updates'),
          item('about', Icons.info_outline_rounded, 'About Cinder $kAppVersion'),
        ];
      },
    );
  }

  Widget _menuZoomButton(IconData icon, String action) {
    return Builder(
      builder: (context) => InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () {
          if (action == 'zoom-in') _zoomIn();
          if (action == 'zoom-out') _zoomOut();
          Navigator.of(context).pop();
        },
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 18, color: _palette.ink),
        ),
      ),
    );
  }

  Widget _addressBar(_BrowserTab tab) {
    final scheme = Uri.tryParse(tab.url)?.scheme.toLowerCase();
    final isHttp = _isHttpConnection(tab);
    final IconData identityIcon = tab.url.isEmpty
        ? Icons.search_rounded
        : isHttp
        ? Icons.warning_amber_rounded
        : (scheme == 'https' ? Icons.lock_rounded : Icons.info_outline_rounded);
    final identityColor = isHttp ? const Color(0xFFE08A1E) : _palette.muted;
    return CompositedTransformTarget(
      link: _addressBarLayerLink,
      child: AnimatedBuilder(
        animation: _urlFocusNode,
        builder: (context, _) {
          final focused = _urlFocusNode.hasFocus;
          return UrlBarFrame(
            palette: _palette,
            focused: focused,
            child: Row(
              children: [
                Tooltip(
                  message: _connectionSecurityMessage(tab),
                  child: Semantics(
                    button: true,
                    label: 'Site information and permissions',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: tab.url.isEmpty ? null : () => _showSiteInfo(tab),
                  child: Container(
                    margin: const EdgeInsets.only(left: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      color: isHttp
                          ? const Color(0xFFE08A1E).withValues(alpha: 0.14)
                          : _palette.hover.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(identityIcon, size: 15, color: identityColor),
                  ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: TextField(
                    controller: _urlController,
                    focusNode: _urlFocusNode,
                    textInputAction: TextInputAction.go,
                    autocorrect: false,
                    enableSuggestions: false,
                    cursorColor: _palette.accent,
                    style: TextStyle(color: _palette.ink, fontSize: 13.5),
                    decoration: InputDecoration(
                      hintText: _isPrivate
                          ? 'Search or enter address (private)'
                          : 'Search or enter address',
                      hintStyle: TextStyle(color: _palette.muted, fontSize: 13.5),
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 9),
                    ),
                    onSubmitted: _navigate,
                  ),
                ),
                if (focused && _urlController.text.isNotEmpty)
                  ToolbarButton(
                    palette: _palette,
                    tooltip: 'Clear address',
                    icon: Icons.close_rounded,
                    size: 28,
                    iconSize: 16,
                    onPressed: () {
                      _urlController.clear();
                      _urlFocusNode.requestFocus();
                      setState(() {});
                    },
                  ),
                if ((tab.zoom - 1.0).abs() > 0.001)
                  Padding(
                    padding: const EdgeInsets.only(right: 2),
                    child: Tooltip(
                      message: 'Reset zoom (Ctrl+0)',
                      child: GestureDetector(
                        onTap: _zoomReset,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: _palette.hover,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            PageZoom.label(tab.zoom),
                            style: TextStyle(color: _palette.ink, fontSize: 11.5),
                          ),
                        ),
                      ),
                    ),
                  ),
                ToolbarButton(
                  palette: _palette,
                  tooltip: _currentPageBookmarked
                      ? 'Remove bookmark (Ctrl+D)'
                      : 'Bookmark this page (Ctrl+D)',
                  icon: _currentPageBookmarked
                      ? Icons.star_rounded
                      : Icons.star_border_rounded,
                  active: _currentPageBookmarked,
                  size: 30,
                  iconSize: 19,
                  onPressed: _activeTab?.url.isNotEmpty == true
                      ? _toggleBookmark
                      : null,
                ),
                const SizedBox(width: 3),
              ],
            ),
          );
        },
      ),
    );
  }

  bool _isHttpConnection(_BrowserTab tab) =>
      Uri.tryParse(tab.url)?.scheme.toLowerCase() == 'http';

  String _connectionSecurityMessage(_BrowserTab tab) {
    final scheme = Uri.tryParse(tab.url)?.scheme.toLowerCase();
    if (scheme == 'https') {
      return 'Secure connection (HTTPS). WebView2 manages TLS; negotiated TLS and post-quantum details are not exposed to Cinder.';
    }
    if (scheme == 'http') {
      return 'Not secure: HTTP traffic is unencrypted.';
    }
    return 'Connection security details are unavailable for this address.';
  }

  Widget _buildPage(_BrowserTab tab) {
    if (tab.sleeping) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bedtime_outlined, size: 36, color: _palette.muted),
            const SizedBox(height: 10),
            Text(
              'This tab is asleep to save memory.',
              style: TextStyle(color: _palette.ink),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => unawaited(_wakeTab(tab)),
              child: const Text('Wake tab'),
            ),
          ],
        ),
      );
    }
    if (tab.url.isEmpty) return _buildStartPage(Theme.of(context).colorScheme);
    if (!tab.isInitialized) {
      return Center(
        child: Text(
          tab.error ?? _webviewRuntimeError ?? 'Starting WebView2...',
          textAlign: TextAlign.center,
          style: TextStyle(color: _palette.ink),
        ),
      );
    }
    // RepaintBoundary isolates the webview from parent repaints caused by
    // toolbar / tab-strip / bookmark-bar setState calls — eliminates jank.
    return RepaintBoundary(
      child: SizedBox.expand(
        key: _pageKey,
        child: Webview(
          tab.controller,
          key: ValueKey(tab.id),
          permissionRequested: _onPermissionRequested,
        ),
      ),
    );
  }

  Widget _buildBackgroundImage() {
    // Private windows always use Cinder's own artwork: never a user photo,
    // never a network image.
    if (_isPrivate) {
      return const CinderWallpaper(CinderWallpapers.privateWindow);
    }
    final painted = CinderWallpapers.byId(_wallpaperProcedural);
    if (painted != null) return CinderWallpaper(painted);
    final solidColor = _wallpaperColor;
    if (solidColor != null) {
      return ColoredBox(key: ValueKey(solidColor), color: solidColor);
    }
    final localPath = _wallpaperFilePath;
    if (localPath != null) {
      return Image.file(
        File(localPath),
        key: ValueKey(localPath),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _dailyArtwork(),
      );
    }
    final url = _wallpaperUrl;
    if (url != null) {
      return Image.network(
        url,
        key: ValueKey(url),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) => _dailyArtwork(),
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : _dailyArtwork(),
      );
    }
    // Default: "daily rotation" through Cinder's built-in artwork. Painted in
    // code, so it needs no network and shows instantly.
    return _dailyArtwork();
  }

  Widget _dailyArtwork() =>
      CinderWallpaper(CinderWallpapers.forDate(_backgroundDate));

  Widget _buildStartPage(ColorScheme scheme) {
    final now = DateTime.now();
    final hour = now.hour;
    final greeting = hour < 12
        ? 'Good morning'
        : (hour < 17 ? 'Good afternoon' : 'Good evening');
    final clock =
        '${hour % 12 == 0 ? 12 : hour % 12}:${now.minute.toString().padLeft(2, '0')}';

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTapDown: (details) =>
          unawaited(_showHomePageContextMenu(details.globalPosition)),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _buildBackgroundImage(),
          // Scrim keeps white text readable on any wallpaper.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x40000000), Color(0x00000000), Color(0x66000000)],
                stops: [0, 0.45, 1],
              ),
            ),
          ),
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final top = (constraints.maxHeight * 0.10).clamp(20.0, 110.0);
                return SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(24, top, 24, 72),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: _isPrivate
                          ? _privateHomeColumn()
                          : _normalHomeColumn(greeting, clock),
                    ),
                  ),
                );
              },
            ),
          ),
          if (!_isPrivate)
            Positioned(
              right: 18,
              bottom: 16,
              child: Tooltip(
                message: 'Customize themes and wallpapers',
                child: GestureDetector(
                  onTap: _showAppearanceSettings,
                  child: const MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: FrostedSurface(
                      radius: 20,
                      padding: EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.tune_rounded, size: 16, color: Colors.white),
                          SizedBox(width: 8),
                          Text(
                            'Customize',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _privateHomeColumn() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const PrivateHero(),
        const SizedBox(height: 34),
        _startSearchBox(),
      ],
    );
  }

  Widget _normalHomeColumn(String greeting, String clock) {
    Widget heading(String text) => Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w700,
            shadows: [Shadow(color: Color(0x80000000), blurRadius: 10)],
          ),
        ),
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CinderMark(size: 58),
        const SizedBox(height: 10),
        Text(
          clock,
          style: const TextStyle(
            fontFamily: 'Segoe UI Variable Display',
            fontFamilyFallback: ['Segoe UI', 'Inter'],
            fontWeight: FontWeight.w200,
            fontSize: 72,
            height: 1,
            letterSpacing: -2,
            color: Colors.white,
            shadows: [Shadow(color: Color(0x55000000), blurRadius: 24)],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          greeting,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w400,
            color: Color(0xE6FFFFFF),
            shadows: [Shadow(color: Color(0x66000000), blurRadius: 12)],
          ),
        ),
        const SizedBox(height: 28),
        _startSearchBox(),
        const SizedBox(height: 40),
        heading('Top sites'),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: Wrap(
            spacing: 10,
            runSpacing: 18,
            children: [
              for (final shortcut in _homeShortcuts)
                SiteTile(
                  label: shortcut.$1,
                  host: Uri.tryParse(shortcut.$2)?.host ?? shortcut.$1,
                  onTap: () => unawaited(
                    _navigate(shortcut.$2, source: NavSource.restore),
                  ),
                  onSecondaryTapDown: (details) => unawaited(
                    _showShortcutContextMenu(
                      shortcut.$1,
                      shortcut.$2,
                      details.globalPosition,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 40),
        heading('Pick up where you left off'),
        const SizedBox(height: 14),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _recentActivity(),
          builder: (context, snapshot) {
            final items = snapshot.data ?? const <Map<String, dynamic>>[];
            if (snapshot.connectionState == ConnectionState.waiting &&
                items.isEmpty) {
              return const SizedBox(height: 64);
            }
            if (items.isEmpty) {
              return const FrostedSurface(
                radius: 14,
                padding: EdgeInsets.all(22),
                child: Center(
                  child: Text(
                    'Pages you visit will appear here.',
                    style: TextStyle(color: Color(0xCCFFFFFF), fontSize: 13),
                  ),
                ),
              );
            }
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 372,
                mainAxisExtent: 62,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                final url = item['url']?.toString() ?? '';
                final host = Uri.tryParse(url)?.host ?? '';
                final title = item['title']?.toString() ?? url;
                return JumpBackCard(
                  title: title,
                  host: host,
                  onTap: () => unawaited(_navigate(url, source: NavSource.restore)),
                  onSecondaryTapDown: (details) => unawaited(
                    _showShortcutContextMenu(title, url, details.globalPosition),
                  ),
                );
              },
            );
          },
        ),
        const SizedBox(height: 34),
        Text(
          'Wallpaper: $_wallpaperName',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.55),
            fontSize: 11.5,
          ),
        ),
      ],
    );
  }

  Future<List<Map<String, dynamic>>>? _recentFuture;

  /// Cached so the new-tab page does not re-query history on every rebuild.
  Future<List<Map<String, dynamic>>> _recentActivity() =>
      _recentFuture ??= HistoryService.instance.fetchBrowsingHistory(limit: 6);

  Widget _startSearchBox() {
    return HomeSearchBar(
      palette: _palette,
      controller: _urlController,
      focusNode: _urlFocusNode,
      hint: _isPrivate
          ? 'Search privately or enter an address'
          : 'Search the web or enter an address',
      engineName: AppServices.searchEngine.name,
      onSubmitted: (value) => unawaited(_navigate(value)),
    );
  }

  // -------------------------------------------------------------------------
  // Bookmarks bar
  // -------------------------------------------------------------------------
  Widget _buildBookmarksBar() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: _showBookmarksBar ? 32 : 0,
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: _palette.toolbar,
        border: Border(
          bottom: BorderSide(
            color: _palette.divider.withValues(alpha: 0.7),
            width: 0.8,
          ),
        ),
      ),
      child: _bookmarks.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Bookmarks you add show up here. Press Ctrl+D to bookmark a page.',
                  style: TextStyle(color: _palette.muted, fontSize: 11.5),
                ),
              ),
            )
          : ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              itemCount: _bookmarks.length,
              separatorBuilder: (_, _) => const SizedBox(width: 2),
              itemBuilder: (context, index) {
                final bm = _bookmarks[index];
                final url = bm['url']?.toString() ?? '';
                final title = bm['title']?.toString() ?? url;
                return Tooltip(
                  message: url,
                  waitDuration: const Duration(milliseconds: 600),
                  child: BookmarkChip(
                    palette: _palette,
                    title: title,
                    host: Uri.tryParse(url)?.host ?? '',
                    onTap: () => unawaited(_navigate(url, source: NavSource.restore)),
                    onSecondaryTapDown: (details) => unawaited(
                      _showBookmarkContextMenu(url, details.globalPosition),
                    ),
                  ),
                );
              },
            ),
    );
  }

  // -------------------------------------------------------------------------
  // Bookmarks manager dialog
  // -------------------------------------------------------------------------
  Future<void> _showBookmarksDialog() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, refreshDialog) => Dialog(
          backgroundColor: _palette.chrome,
          surfaceTintColor: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680, maxHeight: 560),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 14, 22, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.bookmarks_outlined, color: _palette.accent),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Bookmarks',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      Tooltip(
                        message: 'Toggle bookmarks bar (Ctrl+Shift+B)',
                        child: TextButton.icon(
                          onPressed: () async {
                            await _toggleBookmarksBar();
                            refreshDialog(() {});
                          },
                          icon: Icon(
                            _showBookmarksBar
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            size: 16,
                          ),
                          label: Text(
                            _showBookmarksBar ? 'Hide bar' : 'Show bar',
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () => Navigator.pop(dialogContext),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  Text(
                    'Cloud-synced bookmarks. Right-click any bookmark in the bar to remove it.',
                    style: TextStyle(color: _palette.muted, fontSize: 13),
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: FutureBuilder<List<Map<String, dynamic>>>(
                      future: BookmarkService.instance.fetchBookmarks(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return Center(
                            child: CircularProgressIndicator(
                              color: _palette.accent,
                            ),
                          );
                        }
                        final items = snapshot.data ?? [];
                        if (items.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.bookmark_add_outlined,
                                  size: 52,
                                  color: _palette.soft,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'No bookmarks yet.',
                                  style: TextStyle(
                                    color: _palette.muted,
                                    fontSize: 15,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Press Ctrl+D on any page to bookmark it.',
                                  style: TextStyle(
                                    color: _palette.muted,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }
                        return ListView.separated(
                          itemCount: items.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final bm = items[index];
                            final url = bm['url']?.toString() ?? '';
                            final title = bm['title']?.toString() ?? url;
                            final createdAt =
                                bm['created_at']?.toString() ?? '';
                            return ListTile(
                              dense: true,
                              leading: Icon(
                                Icons.bookmark_rounded,
                                color: _palette.accent,
                                size: 20,
                              ),
                              title: Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: _palette.ink,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(
                                '$url${createdAt.isEmpty ? '' : '  •  $createdAt'}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: _palette.muted,
                                  fontSize: 11,
                                ),
                              ),
                              trailing: IconButton(
                                tooltip: 'Remove bookmark',
                                icon: const Icon(
                                  Icons.delete_outline,
                                  size: 18,
                                ),
                                color: Colors.redAccent,
                                onPressed: () async {
                                  await BookmarkService.instance.removeBookmark(
                                    url,
                                  );
                                  unawaited(_loadBookmarks());
                                  if (_activeTab?.url == url) {
                                    setState(
                                      () => _currentPageBookmarked = false,
                                    );
                                  }
                                  refreshDialog(() {});
                                },
                              ),
                              onTap: () {
                                Navigator.pop(dialogContext);
                                unawaited(_navigate(url, source: NavSource.restore));
                              },
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

}
