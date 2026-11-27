import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:saboor_browser/diagnostics/win_memory.dart';

void main() {
  group('formatBytes', () {
    test('picks a readable unit', () {
      expect(formatBytes(512 * 1024), '512 KB');
      expect(formatBytes(412 * 1024 * 1024), '412 MB');
      expect(formatBytes(3 * 1024 * 1024 * 1024), '3.00 GB');
    });
  });

  group('WinMemory (real Win32 calls)', () {
    test(
      'reads this process and finds a spawned child in the process tree',
      () async {
        // A child that lives long enough to be seen. ping is on every Windows.
        final child = await Process.start('ping', ['-n', '20', '127.0.0.1']);
        unawaited(child.stdout.drain<void>());
        unawaited(child.stderr.drain<void>());
        addTearDown(child.kill);

        // Give the OS a moment to register the process.
        MemoryTree? tree;
        for (var i = 0; i < 20; i++) {
          tree = WinMemory.snapshot();
          if (tree != null && tree.children.any((p) => p.pid == child.pid)) {
            break;
          }
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }

        expect(
          tree,
          isNotNull,
          reason: 'Win32 memory APIs should be available',
        );
        // This test process itself.
        expect(tree!.app.pid, pid);
        expect(tree.app.privateBytes, greaterThan(5 * 1024 * 1024));
        expect(tree.app.workingSetBytes, greaterThan(5 * 1024 * 1024));

        // The spawned child, with believable numbers.
        final found = tree.children.where((p) => p.pid == child.pid).toList();
        expect(found, hasLength(1), reason: 'child process missing from tree');
        expect(found.single.name.toLowerCase(), contains('ping'));
        expect(found.single.privateBytes, greaterThan(100 * 1024));
        expect(found.single.privateBytes, lessThan(200 * 1024 * 1024));
        expect(tree.totalPrivateBytes, greaterThan(tree.app.privateBytes));
      },
      skip: Platform.isWindows ? false : 'Windows only',
    );

    test(
      'serialises to JSON without throwing',
      () {
        final tree = WinMemory.snapshot();
        expect(tree, isNotNull);
        final json = tree!.toJson();
        expect(json['appPrivateBytes'], isA<int>());
        expect(json['processes'], isA<List<Object?>>());
      },
      skip: Platform.isWindows ? false : 'Windows only',
    );
  });
}
