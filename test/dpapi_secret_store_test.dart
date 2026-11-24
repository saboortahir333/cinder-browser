import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:saboor_browser/security/dpapi_secret_store.dart';

void main() {
  final onWindows = Platform.isWindows;

  late Directory dir;
  late DpapiSecretStore store;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('cinder-dpapi-');
    store = DpapiSecretStore(directory: dir.path);
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  group('DPAPI secret store', () {
    test('round-trips a secret', () async {
      await store.write('cinder.test.key', 'refresh-token-€-日本');
      expect(await store.read('cinder.test.key'), 'refresh-token-€-日本');
    });

    test('the file on disk is ciphertext, never the plaintext', () async {
      const secret = 'super-secret-refresh-token-0123456789';
      await store.write('cinder.test.key', secret);
      final files = dir.listSync().whereType<File>().toList();
      expect(files, hasLength(1));
      final raw = files.single.readAsBytesSync();
      expect(String.fromCharCodes(raw).contains(secret), isFalse);
      expect(String.fromCharCodes(raw).contains('super-secret'), isFalse);
      expect(raw.length, greaterThan(secret.length));
    });

    test('overwrite replaces the value and leaves no temp files', () async {
      await store.write('k', 'one');
      await store.write('k', 'two');
      expect(await store.read('k'), 'two');
      expect(dir.listSync().where((e) => e.path.endsWith('.tmp')), isEmpty);
    });

    test('delete removes the secret', () async {
      await store.write('k', 'v');
      await store.delete('k');
      expect(await store.read('k'), isNull);
      expect(dir.listSync(), isEmpty);
    });

    test('missing keys return null', () async {
      expect(await store.read('nope'), isNull);
    });

    test('tampered or truncated blobs fail closed (null, no crash)', () async {
      await store.write('k', 'value');
      final file = dir.listSync().whereType<File>().single;
      final bytes = file.readAsBytesSync();
      final flipped = Uint8List.fromList(bytes)..[bytes.length ~/ 2] ^= 0xFF;
      file.writeAsBytesSync(flipped);
      expect(await store.read('k'), isNull);
      file.writeAsBytesSync(bytes.sublist(0, 20));
      expect(await store.read('k'), isNull);
      file.writeAsBytesSync(const []);
      expect(await store.read('k'), isNull);
    });

    test('hostile key names are rejected and cannot escape the directory', () async {
      for (final bad in [
        '../../evil',
        r'..\..\evil',
        'a/b',
        'con:',
        '',
        'x' * 300,
        'a b',
        'k\u0000',
      ]) {
        await store.write(bad, 'x');
        expect(await store.read(bad), isNull, reason: bad);
      }
      expect(dir.listSync(), isEmpty);
      expect(dir.parent.listSync().any((e) => e.path.endsWith('evil')), isFalse);
    });

    test('oversized values are refused', () async {
      await store.write('k', 'a' * (DpapiSecretStore.maxValueBytes + 1));
      expect(await store.read('k'), isNull);
    });

    test('a blob moved to another key slot does not decrypt there', () async {
      await store.write('session.token', 'alpha');
      await store.write('vault.key', 'beta');
      final files = dir.listSync().whereType<File>().toList();
      expect(files, hasLength(2));
      // Swap the two ciphertexts (a file-level swap attack).
      final bytesA = files[0].readAsBytesSync();
      final bytesB = files[1].readAsBytesSync();
      files[0].writeAsBytesSync(bytesB);
      files[1].writeAsBytesSync(bytesA);
      expect(await store.read('session.token'), isNull);
      expect(await store.read('vault.key'), isNull);
    });
  }, skip: onWindows ? false : 'DPAPI is Windows-only');
}
