import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// End-to-end encryption primitives for Cinder cloud sync.
///
/// Threat model: Supabase (operators, backups, a database breach, a leaked
/// service key) must learn nothing about browsing data. Therefore:
///
///  * A random 256-bit **master key** (MK) encrypts all records. It is
///    generated on-device and only ever uploaded *wrapped* (encrypted).
///  * The wrapping key is derived from the user's **sync passphrase** with
///    Argon2id, so the server cannot unwrap the MK or brute-force cheaply.
///  * A second wrapped copy is protected by a high-entropy **recovery key**
///    shown once at setup, so a forgotten passphrase is not fatal.
///  * Every record is AES-256-GCM encrypted with a per-kind subkey (HKDF) and
///    a fresh random nonce. The record's identity (user, profile, kind, id) is
///    bound as AAD, so the server cannot swap ciphertexts between rows, users
///    or kinds without detection.
class VaultCrypto {
  VaultCrypto._();

  static const int formatVersion = 1;
  static final AesGcm _aes = AesGcm.with256bits();

  /// OWASP-recommended Argon2id minimum (19 MiB, t=2, p=1). Stored with the
  /// key bundle so it can be raised later without breaking old vaults.
  static const KdfParams defaultKdf = KdfParams(
    memoryKib: 19456,
    iterations: 2,
    parallelism: 1,
  );

  // Hard ceilings so a hostile server cannot make us burn unbounded
  // memory/CPU by returning absurd Argon2 parameters.
  static const int _maxMemoryKib = 262144; // 256 MiB
  static const int _maxIterations = 10;
  static const int _maxParallelism = 8;
  static const int _minMemoryKib = 19456;
  static const int _minIterations = 2;

  /// Creates a brand-new vault: random MK, wrapped by [passphrase] and by a
  /// freshly generated recovery key.
  static Future<VaultSetup> createVault({
    required String userId,
    required String passphrase,
    KdfParams params = defaultKdf,
  }) async {
    final passphraseError = validatePassphrase(passphrase);
    if (passphraseError != null) throw ArgumentError(passphraseError);
    _validateParams(params);

    final masterKey = _randomBytes(32);
    final salt = _randomBytes(16);
    final recoveryBytes = _randomBytes(20); // 160 bits

    final kek = await _deriveKek(passphrase, salt, params);
    final wrapped = await _wrap(
      masterKey,
      kek,
      _wrapAad('pass', userId),
    );
    final recoveryKek = await _recoveryKek(recoveryBytes);
    final recoveryWrapped = await _wrap(
      masterKey,
      recoveryKek,
      _wrapAad('recovery', userId),
    );

    return VaultSetup(
      bundle: KeyBundle(
        kdfSalt: _b64(salt),
        params: params,
        wrappedMasterKey: wrapped,
        recoveryWrappedMasterKey: recoveryWrapped,
      ),
      masterKey: masterKey,
      recoveryKey: _formatRecoveryKey(recoveryBytes),
    );
  }

  /// Returns the master key, or `null` when the passphrase is wrong or the
  /// bundle was tampered with (GCM authentication failure).
  static Future<Uint8List?> unlockWithPassphrase({
    required String userId,
    required String passphrase,
    required KeyBundle bundle,
  }) async {
    _validateParams(bundle.params);
    final salt = _unb64(bundle.kdfSalt);
    if (salt == null || salt.length < 16) return null;
    final kek = await _deriveKek(passphrase, salt, bundle.params);
    return _unwrap(bundle.wrappedMasterKey, kek, _wrapAad('pass', userId));
  }

  /// Unlocks with the recovery key printed at setup.
  static Future<Uint8List?> unlockWithRecoveryKey({
    required String userId,
    required String recoveryKey,
    required KeyBundle bundle,
  }) async {
    final wrapped = bundle.recoveryWrappedMasterKey;
    if (wrapped == null) return null;
    final bytes = _parseRecoveryKey(recoveryKey);
    if (bytes == null) return null;
    final kek = await _recoveryKek(bytes);
    return _unwrap(wrapped, kek, _wrapAad('recovery', userId));
  }

  /// Re-wraps the existing master key under a new passphrase. Records do not
  /// need re-encryption because the MK itself is unchanged.
  static Future<KeyBundle> changePassphrase({
    required String userId,
    required Uint8List masterKey,
    required String newPassphrase,
    required KeyBundle current,
    KdfParams params = defaultKdf,
  }) async {
    final error = validatePassphrase(newPassphrase);
    if (error != null) throw ArgumentError(error);
    _validateParams(params);
    final salt = _randomBytes(16);
    final kek = await _deriveKek(newPassphrase, salt, params);
    return KeyBundle(
      kdfSalt: _b64(salt),
      params: params,
      wrappedMasterKey: await _wrap(masterKey, kek, _wrapAad('pass', userId)),
      recoveryWrappedMasterKey: current.recoveryWrappedMasterKey,
    );
  }

  /// Encrypts [plaintext] into a self-describing envelope string.
  static Future<String> encryptRecord({
    required Uint8List masterKey,
    required String userId,
    required String profileId,
    required String kind,
    required String recordId,
    required String plaintext,
  }) async {
    final key = await _recordKey(masterKey, kind);
    final box = await _aes.encrypt(
      utf8.encode(plaintext),
      secretKey: key,
      aad: _recordAad(userId, profileId, kind, recordId),
    );
    return _envelope(box);
  }

  /// Decrypts a record. Returns `null` on ANY failure (wrong key, tampering,
  /// row-swap, malformed input) - callers must treat null as "discard".
  static Future<String?> decryptRecord({
    required Uint8List masterKey,
    required String userId,
    required String profileId,
    required String kind,
    required String recordId,
    required String envelope,
  }) async {
    try {
      final box = _openEnvelope(envelope);
      if (box == null) return null;
      final key = await _recordKey(masterKey, kind);
      final clear = await _aes.decrypt(
        box,
        secretKey: key,
        aad: _recordAad(userId, profileId, kind, recordId),
      );
      return utf8.decode(clear);
    } catch (_) {
      return null;
    }
  }

  /// Returns a human-readable problem, or `null` when acceptable.
  static String? validatePassphrase(String passphrase) {
    if (passphrase.length < 12) {
      return 'Use at least 12 characters.';
    }
    if (passphrase.length > 256) return 'Passphrase is too long.';
    if (RegExp(r'^(.)\1+$').hasMatch(passphrase)) {
      return 'Passphrase cannot be one repeated character.';
    }
    final lower = passphrase.toLowerCase();
    const weak = [
      'password1234',
      '123456789012',
      'qwertyuiopas',
      'letmein12345',
      'iloveyou1234',
      'cinderbrowser',
    ];
    if (weak.contains(lower)) return 'That passphrase is too common.';
    if (passphrase.trim().length < 12) {
      return 'Passphrase cannot be mostly spaces.';
    }
    return null;
  }

  // -- internals ------------------------------------------------------------

  static void _validateParams(KdfParams p) {
    if (p.memoryKib < _minMemoryKib ||
        p.memoryKib > _maxMemoryKib ||
        p.iterations < _minIterations ||
        p.iterations > _maxIterations ||
        p.parallelism < 1 ||
        p.parallelism > _maxParallelism) {
      throw ArgumentError('Unsafe key-derivation parameters.');
    }
  }

  static Future<SecretKey> _deriveKek(
    String passphrase,
    Uint8List salt,
    KdfParams p,
  ) async {
    final pass = utf8.encode(passphrase);
    final memory = p.memoryKib;
    final iterations = p.iterations;
    final parallelism = p.parallelism;
    // Argon2id is deliberately slow; keep it off the UI isolate.
    final bytes = await Isolate.run(() async {
      final kdf = Argon2id(
        memory: memory,
        iterations: iterations,
        parallelism: parallelism,
        hashLength: 32,
      );
      final key = await kdf.deriveKey(
        secretKey: SecretKey(pass),
        nonce: salt,
      );
      return Uint8List.fromList(await key.extractBytes());
    });
    return SecretKey(bytes);
  }

  static Future<SecretKey> _recoveryKek(Uint8List recoveryBytes) {
    return Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
      secretKey: SecretKey(recoveryBytes),
      nonce: utf8.encode('cinder/recovery/salt/v1'),
      info: utf8.encode('cinder/recovery/kek/v1'),
    );
  }

  static Future<SecretKey> _recordKey(Uint8List masterKey, String kind) {
    return Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
      secretKey: SecretKey(masterKey),
      nonce: utf8.encode('cinder/record/salt/v1'),
      info: utf8.encode('cinder/record/key/v1/$kind'),
    );
  }

  static List<int> _wrapAad(String slot, String userId) =>
      utf8.encode('cinder|v$formatVersion|wrap|$slot|$userId');

  static List<int> _recordAad(
    String userId,
    String profileId,
    String kind,
    String recordId,
  ) => utf8.encode(
    'cinder|v$formatVersion|rec|$userId|$profileId|$kind|$recordId',
  );

  static Future<String> _wrap(
    Uint8List masterKey,
    SecretKey kek,
    List<int> aad,
  ) async {
    final box = await _aes.encrypt(masterKey, secretKey: kek, aad: aad);
    return _envelope(box);
  }

  static Future<Uint8List?> _unwrap(
    String envelope,
    SecretKey kek,
    List<int> aad,
  ) async {
    try {
      final box = _openEnvelope(envelope);
      if (box == null) return null;
      final clear = await _aes.decrypt(box, secretKey: kek, aad: aad);
      if (clear.length != 32) return null;
      return Uint8List.fromList(clear);
    } catch (_) {
      return null;
    }
  }

  static String _envelope(SecretBox box) =>
      'v$formatVersion.${_b64(box.nonce)}.${_b64(box.cipherText)}.${_b64(box.mac.bytes)}';

  static SecretBox? _openEnvelope(String envelope) {
    if (envelope.length > 400000) return null;
    final parts = envelope.split('.');
    if (parts.length != 4 || parts[0] != 'v$formatVersion') return null;
    final nonce = _unb64(parts[1]);
    final cipher = _unb64(parts[2]);
    final mac = _unb64(parts[3]);
    if (nonce == null || cipher == null || mac == null) return null;
    if (nonce.length != 12 || mac.length != 16) return null;
    return SecretBox(cipher, nonce: nonce, mac: Mac(mac));
  }

  static Uint8List _randomBytes(int n) {
    final rng = Random.secure();
    return Uint8List.fromList(List<int>.generate(n, (_) => rng.nextInt(256)));
  }

  static String _b64(List<int> bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');

  static Uint8List? _unb64(String s) {
    try {
      final padded = s + '=' * ((4 - s.length % 4) % 4);
      return Uint8List.fromList(base64Url.decode(padded));
    } catch (_) {
      return null;
    }
  }

  // Crockford-style base32 (no I, L, O, U) in groups of 4 for easy transcription.
  static const String _alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

  static String _formatRecoveryKey(Uint8List bytes) {
    final out = StringBuffer();
    var buffer = 0;
    var bits = 0;
    for (final b in bytes) {
      buffer = (buffer << 8) | b;
      bits += 8;
      while (bits >= 5) {
        out.write(_alphabet[(buffer >> (bits - 5)) & 31]);
        bits -= 5;
      }
      buffer &= (1 << bits) - 1;
    }
    final raw = out.toString(); // 160 bits -> 32 chars
    final groups = <String>[];
    for (var i = 0; i < raw.length; i += 4) {
      groups.add(raw.substring(i, min(i + 4, raw.length)));
    }
    return groups.join('-');
  }

  static Uint8List? _parseRecoveryKey(String input) {
    final cleaned = input
        .toUpperCase()
        .replaceAll(RegExp(r'[\s-]'), '')
        .replaceAll('O', '0')
        .replaceAll('I', '1')
        .replaceAll('L', '1');
    if (cleaned.length != 32) return null;
    final bytes = <int>[];
    var buffer = 0;
    var bits = 0;
    for (final ch in cleaned.split('')) {
      final v = _alphabet.indexOf(ch);
      if (v < 0) return null;
      buffer = (buffer << 5) | v;
      bits += 5;
      if (bits >= 8) {
        bytes.add((buffer >> (bits - 8)) & 0xFF);
        bits -= 8;
        buffer &= (1 << bits) - 1;
      }
    }
    return bytes.length == 20 ? Uint8List.fromList(bytes) : null;
  }
}

class KdfParams {
  const KdfParams({
    required this.memoryKib,
    required this.iterations,
    required this.parallelism,
  });

  final int memoryKib;
  final int iterations;
  final int parallelism;
}

/// What is stored server-side in `user_keys` (never the passphrase, never the
/// plaintext master key).
class KeyBundle {
  const KeyBundle({
    required this.kdfSalt,
    required this.params,
    required this.wrappedMasterKey,
    this.recoveryWrappedMasterKey,
  });

  final String kdfSalt;
  final KdfParams params;
  final String wrappedMasterKey;
  final String? recoveryWrappedMasterKey;

  Map<String, dynamic> toRow() => {
    'kdf': 'argon2id',
    'kdf_salt': kdfSalt,
    'kdf_memory_kib': params.memoryKib,
    'kdf_iterations': params.iterations,
    'kdf_parallelism': params.parallelism,
    'wrapped_master_key': wrappedMasterKey,
    'recovery_wrapped_master_key': recoveryWrappedMasterKey,
  };

  static KeyBundle? fromRow(Map<String, dynamic> row) {
    try {
      return KeyBundle(
        kdfSalt: row['kdf_salt'] as String,
        params: KdfParams(
          memoryKib: row['kdf_memory_kib'] as int,
          iterations: row['kdf_iterations'] as int,
          parallelism: row['kdf_parallelism'] as int,
        ),
        wrappedMasterKey: row['wrapped_master_key'] as String,
        recoveryWrappedMasterKey: row['recovery_wrapped_master_key'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}

class VaultSetup {
  const VaultSetup({
    required this.bundle,
    required this.masterKey,
    required this.recoveryKey,
  });

  final KeyBundle bundle;
  final Uint8List masterKey;

  /// Show to the user exactly once; never persist or log it.
  final String recoveryKey;
}
