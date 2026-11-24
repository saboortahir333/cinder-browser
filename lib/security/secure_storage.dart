import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:saboor_browser/security/dpapi_secret_store.dart';

/// The only data Cinder writes to local disk for account features, and it is
/// OS-protected (Windows DPAPI via `DpapiSecretStore`):
///
///  * the Supabase session (refresh token) so users stay signed in, and
///  * the unwrapped vault master key so they are not asked for the sync
///    passphrase on every launch.
///
/// Everything else (history, bookmarks, tabs, settings) lives only in memory
/// and in the encrypted cloud store.
abstract class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// The platform secret store: Windows DPAPI on Windows. Anywhere else (no
/// supported OS vault yet) it is memory-only, so nothing is ever persisted
/// unprotected.
class OsSecretStore implements SecretStore {
  const OsSecretStore();

  static final SecretStore _impl = Platform.isWindows
      ? DpapiSecretStore()
      : MemorySecretStore();

  @override
  Future<String?> read(String key) => _impl.read(key);

  @override
  Future<void> write(String key, String value) => _impl.write(key, value);

  @override
  Future<void> delete(String key) => _impl.delete(key);
}

/// In-memory implementation for tests and for guest/private sessions.
class MemorySecretStore implements SecretStore {
  final Map<String, String> _values = {};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  Future<void> delete(String key) async => _values.remove(key);
}

/// Supabase session persistence backed by the OS secret store instead of the
/// default plaintext SharedPreferences file.
class SecureSupabaseStorage extends LocalStorage {
  /// [profileId] keeps separate Cinder profiles signed in to separate
  /// accounts. It must already be validated (`[a-z0-9_-]{1,32}`).
  SecureSupabaseStorage(this._store, {String profileId = 'default'})
    : _key = 'cinder.supabase.session.$profileId';

  final SecretStore _store;
  final String _key;

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> hasAccessToken() async => (await _store.read(_key)) != null;

  @override
  Future<String?> accessToken() => _store.read(_key);

  @override
  Future<void> persistSession(String persistSessionString) =>
      _store.write(_key, persistSessionString);

  @override
  Future<void> removePersistedSession() => _store.delete(_key);
}

/// Caches the unwrapped master key in the OS secret store, per user.
class MasterKeyCache {
  const MasterKeyCache(this._store);

  final SecretStore _store;

  String _key(String userId) => 'cinder.vault.mk.$userId';

  Future<Uint8List?> load(String userId) async {
    final raw = await _store.read(_key(userId));
    if (raw == null) return null;
    try {
      final bytes = base64Decode(raw);
      return bytes.length == 32 ? Uint8List.fromList(bytes) : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> save(String userId, Uint8List masterKey) =>
      _store.write(_key(userId), base64Encode(masterKey));

  Future<void> clear(String userId) => _store.delete(_key(userId));
}
