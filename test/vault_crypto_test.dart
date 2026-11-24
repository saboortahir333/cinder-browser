import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:saboor_browser/security/vault_crypto.dart';

void main() {
  const user = '11111111-1111-1111-1111-111111111111';
  const pass = 'correct horse battery staple';

  late VaultSetup setup;

  setUpAll(() async {
    setup = await VaultCrypto.createVault(userId: user, passphrase: pass);
  });

  group('vault key wrapping', () {
    test('unlocks with the right passphrase', () async {
      final mk = await VaultCrypto.unlockWithPassphrase(
        userId: user,
        passphrase: pass,
        bundle: setup.bundle,
      );
      expect(mk, setup.masterKey);
    });

    test('rejects a wrong passphrase', () async {
      final mk = await VaultCrypto.unlockWithPassphrase(
        userId: user,
        passphrase: 'correct horse battery stapl3',
        bundle: setup.bundle,
      );
      expect(mk, isNull);
    });

    test('bundle is bound to the user id', () async {
      final mk = await VaultCrypto.unlockWithPassphrase(
        userId: '22222222-2222-2222-2222-222222222222',
        passphrase: pass,
        bundle: setup.bundle,
      );
      expect(mk, isNull);
    });

    test('recovery key unlocks and tolerates formatting noise', () async {
      final noisy = setup.recoveryKey.toLowerCase().replaceAll('-', ' ');
      final mk = await VaultCrypto.unlockWithRecoveryKey(
        userId: user,
        recoveryKey: noisy,
        bundle: setup.bundle,
      );
      expect(mk, setup.masterKey);
    });

    test('wrong or malformed recovery key is rejected', () async {
      for (final bad in ['', 'AAAA-BBBB', '!' * 32, 'A' * 32]) {
        final mk = await VaultCrypto.unlockWithRecoveryKey(
          userId: user,
          recoveryKey: bad,
          bundle: setup.bundle,
        );
        expect(mk, isNull, reason: bad);
      }
    });

    test('changePassphrase keeps the master key and retires the old one', () async {
      final next = await VaultCrypto.changePassphrase(
        userId: user,
        masterKey: setup.masterKey,
        newPassphrase: 'a brand new long passphrase',
        current: setup.bundle,
      );
      final viaNew = await VaultCrypto.unlockWithPassphrase(
        userId: user,
        passphrase: 'a brand new long passphrase',
        bundle: next,
      );
      final viaOld = await VaultCrypto.unlockWithPassphrase(
        userId: user,
        passphrase: pass,
        bundle: next,
      );
      expect(viaNew, setup.masterKey);
      expect(viaOld, isNull);
    });

    test('refuses hostile KDF parameters from a server', () async {
      final hostile = KeyBundle(
        kdfSalt: setup.bundle.kdfSalt,
        params: const KdfParams(
          memoryKib: 8 * 1024 * 1024,
          iterations: 1000,
          parallelism: 64,
        ),
        wrappedMasterKey: setup.bundle.wrappedMasterKey,
      );
      expect(
        () => VaultCrypto.unlockWithPassphrase(
          userId: user,
          passphrase: pass,
          bundle: hostile,
        ),
        throwsArgumentError,
      );
    });
  });

  group('record encryption', () {
    Future<String> enc(String text, {String id = 'r1', String kind = 'history'}) =>
        VaultCrypto.encryptRecord(
          masterKey: setup.masterKey,
          userId: user,
          profileId: 'default',
          kind: kind,
          recordId: id,
          plaintext: text,
        );

    Future<String?> dec(
      String envelope, {
      String id = 'r1',
      String kind = 'history',
      String profile = 'default',
      String uid = user,
      Uint8List? key,
    }) => VaultCrypto.decryptRecord(
      masterKey: key ?? setup.masterKey,
      userId: uid,
      profileId: profile,
      kind: kind,
      recordId: id,
      envelope: envelope,
    );

    test('round-trips unicode and never leaks plaintext', () async {
      const text = '{"url":"https://example.com/ünï","title":"日本語"}';
      final box = await enc(text);
      expect(box.contains('example.com'), isFalse);
      expect(await dec(box), text);
    });

    test('same plaintext encrypts differently each time (random nonce)', () async {
      expect(await enc('same'), isNot(await enc('same')));
    });

    test('ciphertext cannot be moved to another row, kind, profile or user', () async {
      final box = await enc('secret');
      expect(await dec(box, id: 'r2'), isNull);
      expect(await dec(box, kind: 'bookmark'), isNull);
      expect(await dec(box, profile: 'work'), isNull);
      expect(await dec(box, uid: '22222222-2222-2222-2222-222222222222'), isNull);
    });

    test('tampering and a wrong key are detected', () async {
      final box = await enc('secret');
      final parts = box.split('.');
      final flipped = parts[2].startsWith('A')
          ? 'B${parts[2].substring(1)}'
          : 'A${parts[2].substring(1)}';
      parts[2] = flipped;
      expect(await dec(parts.join('.')), isNull);
      expect(await dec(box, key: Uint8List(32)), isNull);
    });

    test('malformed envelopes return null instead of throwing', () async {
      for (final bad in ['', 'v1', 'v2.a.b.c', 'v1.!!.??.##', 'v1.AAAA.AAAA.AAAA']) {
        expect(await dec(bad), isNull, reason: bad);
      }
    });
  });

  group('passphrase policy', () {
    test('rejects short, repeated and common passphrases', () {
      expect(VaultCrypto.validatePassphrase('short'), isNotNull);
      expect(VaultCrypto.validatePassphrase('aaaaaaaaaaaaaaaa'), isNotNull);
      expect(VaultCrypto.validatePassphrase('Password1234'), isNotNull);
      expect(VaultCrypto.validatePassphrase('            x'), isNotNull);
    });

    test('accepts a long passphrase', () {
      expect(VaultCrypto.validatePassphrase('correct horse battery'), isNull);
    });
  });
}
