import 'package:saboor_browser/browser/search_engines.dart';
import 'package:saboor_browser/services/account_service.dart';
import 'package:saboor_browser/services/cloud_store.dart';

/// Process-wide singletons. Created lazily so tests that never touch Supabase
/// keep working (guest mode never makes a network call).
class AppServices {
  AppServices._();

  /// Launch options parsed from the command line (see [LaunchOptions]).
  static LaunchOptions launch = const LaunchOptions();

  static final AccountService account = AccountService.instance;

  static CloudStore? _cloud;

  /// Encrypted, memory-first store for everything the user owns.
  static CloudStore get cloud => _cloud ??= CloudStore(
    api: SupabaseRecordApi(),
    keys: account,
    profileId: launch.profileId,
  );

  /// Test hook.
  static void overrideCloud(CloudStore store) => _cloud = store;

  /// Chosen search engine (loaded from settings; default until then).
  static SearchEngine searchEngine = SearchEngines.defaultEngine;
}

/// Command-line switches for the separate Windows processes that implement
/// private windows and profiles:
///   cinder.exe --private
///   cinder.exe --profile=work
class LaunchOptions {
  const LaunchOptions({
    this.isPrivate = false,
    this.profileId = 'default',
    this.devToolsPort = 0,
  });

  /// Random loopback port chosen by the native runner for DevTools (0 = none).
  final int devToolsPort;

  /// Private window: no history, no session, no cloud writes, temporary
  /// browser profile that is deleted when the window closes.
  final bool isPrivate;

  /// Validated profile id (`[a-z0-9_-]{1,32}`); anything else becomes
  /// `default`, which also blocks path-traversal via the profile folder name.
  final String profileId;

  static final RegExp _profileRe = RegExp(r'^[a-z0-9_-]{1,32}$');

  static LaunchOptions parse(List<String> args) {
    var isPrivate = false;
    var profile = 'default';
    var devToolsPort = 0;
    for (final arg in args) {
      if (arg == '--private') {
        isPrivate = true;
      } else if (arg.startsWith('--profile=')) {
        final value = arg.substring('--profile='.length).toLowerCase();
        if (_profileRe.hasMatch(value)) profile = value;
      } else if (arg.startsWith('--cinder-devtools-port=')) {
        final port = int.tryParse(arg.substring('--cinder-devtools-port='.length));
        // Only the ephemeral range the runner picks from.
        if (port != null && port >= 49152 && port <= 65535) devToolsPort = port;
      }
    }
    return LaunchOptions(
      isPrivate: isPrivate,
      profileId: profile,
      devToolsPort: devToolsPort,
    );
  }
}
