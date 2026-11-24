import 'dart:io';
import 'dart:math';

/// Locations of the browser engine's on-disk profile (cookies, cache, site
/// storage). WebView2 cannot run without one, so this is the one piece of
/// local state that is genuinely necessary; everything user-owned (history,
/// bookmarks, tabs, settings) is memory + encrypted cloud only.
///
///  * default profile   -> the WebView2 plugin's default folder
///  * named profile     -> %LOCALAPPDATA%\Cinder\Profiles\<id>\WebView2
///  * private window    -> a random temp folder deleted on exit
class ProfilePaths {
  ProfilePaths._();

  static final RegExp privateDirPattern = RegExp(r'^cinder-private-[a-f0-9]{16}$');
  static final RegExp profileIdPattern = RegExp(r'^[a-z0-9_-]{1,32}$');

  /// Creates a unique private directory name. 64 bits of randomness makes
  /// the path unguessable by other local users/processes.
  static String newPrivateDirName([Random? random]) {
    final rng = random ?? Random.secure();
    final hex = List.generate(
      16,
      (_) => rng.nextInt(16).toRadixString(16),
    ).join();
    return 'cinder-private-$hex';
  }

  /// Folder for a named profile, or null for the default profile.
  /// [localAppData] is `%LOCALAPPDATA%`.
  static String? namedProfileDir(String profileId, String localAppData) {
    if (profileId == 'default') return null;
    if (!profileIdPattern.hasMatch(profileId)) return null;
    final sep = Platform.pathSeparator;
    return '$localAppData${sep}Cinder${sep}Profiles$sep$profileId${sep}WebView2';
  }

  /// Deletes [path] only if it is a real (non-link) directory directly inside
  /// [tempRoot] whose name matches the private-dir pattern. Anything else is
  /// ignored, so a bad path can never delete user data.
  static Future<bool> deletePrivateDir(String path, String tempRoot) async {
    try {
      final dir = Directory(path);
      final parent = dir.parent.path.toLowerCase().replaceAll('/', '\\');
      final expected = tempRoot.toLowerCase().replaceAll('/', '\\');
      final trimmed = expected.endsWith('\\')
          ? expected.substring(0, expected.length - 1)
          : expected;
      final actualParent = parent.endsWith('\\')
          ? parent.substring(0, parent.length - 1)
          : parent;
      final name = dir.uri.pathSegments.where((s) => s.isNotEmpty).last;
      if (actualParent != trimmed || !privateDirPattern.hasMatch(name)) {
        return false;
      }
      if (FileSystemEntity.typeSync(path, followLinks: false) !=
          FileSystemEntityType.directory) {
        return false;
      }
      await dir.delete(recursive: true);
      return true;
    } catch (_) {
      return false;
    }
  }

  static const String lockFileName = '.cinder.lock';

  /// A running private window keeps this exclusive lock for its lifetime so
  /// crash-cleanup never deletes a profile that is still in use.
  static RandomAccessFile? acquireLock(String dir) {
    try {
      final file = File('$dir${Platform.pathSeparator}$lockFileName');
      final handle = file.openSync(mode: FileMode.write);
      handle.lockSync(FileLock.exclusive);
      return handle;
    } catch (_) {
      return null;
    }
  }

  static bool _isLocked(Directory dir) {
    final file = File('${dir.path}${Platform.pathSeparator}$lockFileName');
    if (!file.existsSync()) return false;
    RandomAccessFile? handle;
    try {
      handle = file.openSync(mode: FileMode.append);
      handle.lockSync(FileLock.exclusive);
      return false;
    } catch (_) {
      return true;
    } finally {
      try {
        handle?.closeSync();
      } catch (_) {}
    }
  }

  /// Removes private folders left behind by a crash. Only folders older than
  /// [maxAge] are touched so another running private window is never hurt.
  static Future<int> sweepStalePrivateDirs(
    String tempRoot, {
    Duration maxAge = const Duration(days: 1),
    DateTime? now,
  }) async {
    var removed = 0;
    try {
      final cutoff = (now ?? DateTime.now()).subtract(maxAge);
      await for (final entity in Directory(tempRoot).list(followLinks: false)) {
        if (entity is! Directory) continue;
        final name = entity.uri.pathSegments.where((s) => s.isNotEmpty).last;
        if (!privateDirPattern.hasMatch(name)) continue;
        final stat = await entity.stat();
        if (stat.modified.isAfter(cutoff)) continue;
        if (_isLocked(entity)) continue;
        if (await deletePrivateDir(entity.path, tempRoot)) removed++;
      }
    } catch (_) {}
    return removed;
  }
}
