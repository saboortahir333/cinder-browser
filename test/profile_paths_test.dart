import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:saboor_browser/services/app_services.dart';
import 'package:saboor_browser/services/profile_paths.dart';

void main() {
  group('launch options', () {
    test('parses private and profile switches', () {
      final o = LaunchOptions.parse(['--private', '--profile=Work_1']);
      expect(o.isPrivate, isTrue);
      expect(o.profileId, 'work_1');
    });

    test('rejects path-traversal and malformed profile ids', () {
      for (final bad in [
        '--profile=../../Windows',
        '--profile=a/b',
        r'--profile=a\b',
        '--profile=',
        '--profile=${'x' * 40}',
        '--profile=con:',
        '--profile=a b',
      ]) {
        expect(LaunchOptions.parse([bad]).profileId, 'default', reason: bad);
      }
    });

    test('devtools port is accepted only from the ephemeral range', () {
      expect(LaunchOptions.parse(['--cinder-devtools-port=50123']).devToolsPort, 50123);
      for (final bad in [
        '--cinder-devtools-port=9222',
        '--cinder-devtools-port=80',
        '--cinder-devtools-port=70000',
        '--cinder-devtools-port=abc',
        '--cinder-devtools-port=',
      ]) {
        expect(LaunchOptions.parse([bad]).devToolsPort, 0, reason: bad);
      }
    });

    test('defaults are safe', () {
      final o = LaunchOptions.parse(const []);
      expect(o.isPrivate, isFalse);
      expect(o.profileId, 'default');
    });
  });

  group('profile directories', () {
    test('named profile path stays inside Cinder\\Profiles', () {
      final p = ProfilePaths.namedProfileDir('work', r'C:\Users\a\AppData\Local');
      expect(p, r'C:\Users\a\AppData\Local\Cinder\Profiles\work\WebView2');
      expect(ProfilePaths.namedProfileDir('default', r'C:\x'), isNull);
      expect(ProfilePaths.namedProfileDir('../evil', r'C:\x'), isNull);
    });

    test('private dir names are unique and match the strict pattern', () {
      final a = ProfilePaths.newPrivateDirName();
      final b = ProfilePaths.newPrivateDirName();
      expect(a, isNot(b));
      expect(ProfilePaths.privateDirPattern.hasMatch(a), isTrue);
    });
  });

  group('private directory cleanup', () {
    late Directory temp;

    setUp(() => temp = Directory.systemTemp.createTempSync('cinder-test-'));
    tearDown(() {
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    });

    test('deletes only strictly-named dirs directly inside the temp root', () async {
      final name = ProfilePaths.newPrivateDirName();
      final good = Directory('${temp.path}${Platform.pathSeparator}$name')
        ..createSync();
      File('${good.path}${Platform.pathSeparator}cookie.db').writeAsStringSync('x');
      final other = Directory('${temp.path}${Platform.pathSeparator}important')
        ..createSync();

      expect(await ProfilePaths.deletePrivateDir(good.path, temp.path), isTrue);
      expect(good.existsSync(), isFalse);
      expect(await ProfilePaths.deletePrivateDir(other.path, temp.path), isFalse);
      expect(other.existsSync(), isTrue);
    });

    test('refuses paths outside the temp root or with traversal', () async {
      final name = ProfilePaths.newPrivateDirName();
      final nested = Directory(
        '${temp.path}${Platform.pathSeparator}sub${Platform.pathSeparator}$name',
      )..createSync(recursive: true);
      expect(await ProfilePaths.deletePrivateDir(nested.path, temp.path), isFalse);
      expect(nested.existsSync(), isTrue);
      expect(await ProfilePaths.deletePrivateDir(temp.path, temp.path), isFalse);
    });

    test('sweep removes only old private dirs', () async {
      final oldDir = Directory(
        '${temp.path}${Platform.pathSeparator}${ProfilePaths.newPrivateDirName()}',
      )..createSync();
      final keep = Directory('${temp.path}${Platform.pathSeparator}notes')
        ..createSync();
      final removed = await ProfilePaths.sweepStalePrivateDirs(
        temp.path,
        now: DateTime.now().add(const Duration(days: 3)),
      );
      expect(removed, 1);
      expect(oldDir.existsSync(), isFalse);
      expect(keep.existsSync(), isTrue);
    });

    test('sweep never touches a private dir whose window still holds the lock', () async {
      final live = Directory(
        '${temp.path}${Platform.pathSeparator}${ProfilePaths.newPrivateDirName()}',
      )..createSync();
      final lock = ProfilePaths.acquireLock(live.path);
      expect(lock, isNotNull);
      final removed = await ProfilePaths.sweepStalePrivateDirs(
        temp.path,
        now: DateTime.now().add(const Duration(days: 3)),
      );
      expect(removed, 0);
      expect(live.existsSync(), isTrue);
      lock!.closeSync();
      expect(
        await ProfilePaths.sweepStalePrivateDirs(
          temp.path,
          now: DateTime.now().add(const Duration(days: 3)),
        ),
        1,
      );
    });

    test('sweep leaves recent private dirs (another window may be using them)', () async {
      final fresh = Directory(
        '${temp.path}${Platform.pathSeparator}${ProfilePaths.newPrivateDirName()}',
      )..createSync();
      expect(await ProfilePaths.sweepStalePrivateDirs(temp.path), 0);
      expect(fresh.existsSync(), isTrue);
    });
  });
}
