import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:saboor_browser/security/secure_storage.dart';
import 'package:saboor_browser/security/vault_crypto.dart';
import 'package:saboor_browser/services/cloud_store.dart';

enum AccountState {
  /// Not signed in. The browser works, but nothing is saved anywhere.
  guest,

  /// Signed in, no vault exists yet - the user must create a sync passphrase.
  needsVaultSetup,

  /// Signed in, vault exists, master key not available on this device.
  locked,

  /// Signed in and the master key is in memory: cloud sync is active.
  unlocked,
}

/// Result of an auth action. Messages are deliberately generic so we never
/// reveal whether an e-mail address already has an account.
class AccountResult {
  const AccountResult.ok({this.message, this.recoveryKey}) : ok = true;
  const AccountResult.fail(this.message) : ok = false, recoveryKey = null;

  final bool ok;
  final String? message;

  /// Present only right after vault creation - show once, then discard.
  final String? recoveryKey;
}

/// Owns sign-in state and the in-memory vault master key.
class AccountService extends ChangeNotifier implements VaultKeySource {
  AccountService({
    SupabaseClient? client,
    SecretStore? secrets,
  }) : _clientOverride = client,
       _cache = MasterKeyCache(secrets ?? const OsSecretStore());

  static final AccountService instance = AccountService();

  final SupabaseClient? _clientOverride;
  final MasterKeyCache _cache;

  AccountState _state = AccountState.guest;
  Uint8List? _masterKey;
  KeyBundle? _bundle;
  int _failedUnlocks = 0;
  DateTime? _lockedUntil;

  SupabaseClient get _client => _clientOverride ?? Supabase.instance.client;

  AccountState get state => _state;
  bool get isUnlocked => _state == AccountState.unlocked && _masterKey != null;
  /// Null (never throws) when Supabase is not initialised, e.g. in tests.
  User? get _user {
    try {
      return _client.auth.currentUser;
    } catch (_) {
      return null;
    }
  }

  @override
  String? get userId => _user?.id;
  String? get email => _user?.email;
  @override
  Uint8List? get masterKey => _masterKey;

  /// Call once at startup (after Supabase.initialize).
  Future<void> restore() async {
    final user = _user;
    if (user == null) {
      _setState(AccountState.guest);
      return;
    }
    await _resolveVaultState(user.id);
  }

  Future<AccountResult> signUp(String email, String password) async {
    final cleaned = email.trim();
    final problem = _validateCredentials(cleaned, password);
    if (problem != null) return AccountResult.fail(problem);
    try {
      final res = await _client.auth.signUp(email: cleaned, password: password);
      if (res.session == null) {
        return const AccountResult.ok(
          message:
              'Check your inbox to confirm your e-mail address, then sign in.',
        );
      }
      await _resolveVaultState(res.session!.user.id);
      return const AccountResult.ok();
    } on AuthException catch (e) {
      return AccountResult.fail(_friendly(e));
    } catch (_) {
      return const AccountResult.fail('Could not reach the server.');
    }
  }

  Future<AccountResult> signIn(String email, String password) async {
    final cleaned = email.trim();
    final now = DateTime.now();
    if (_lockedUntil != null && now.isBefore(_lockedUntil!)) {
      return const AccountResult.fail(
        'Too many attempts. Please wait a minute and try again.',
      );
    }
    if (cleaned.isEmpty || password.isEmpty) {
      return const AccountResult.fail('Enter your e-mail and password.');
    }
    try {
      final res = await _client.auth.signInWithPassword(
        email: cleaned,
        password: password,
      );
      final user = res.user;
      if (user == null) return const AccountResult.fail('Sign-in failed.');
      _failedUnlocks = 0;
      await _resolveVaultState(user.id);
      return const AccountResult.ok();
    } on AuthException catch (e) {
      _registerFailure();
      return AccountResult.fail(_friendly(e));
    } catch (_) {
      return const AccountResult.fail('Could not reach the server.');
    }
  }

  /// Signs out and wipes every secret held for this user on this device.
  Future<void> signOut() async {
    final uid = userId;
    _wipeKey();
    _bundle = null;
    if (uid != null) await _cache.clear(uid);
    try {
      await _client.auth.signOut();
    } catch (_) {
      // Session is dropped locally even if the network call fails.
    }
    _setState(AccountState.guest);
  }

  /// First-time vault creation. Returns the recovery key to show once.
  Future<AccountResult> createVault(String passphrase) async {
    final uid = userId;
    if (uid == null || _state != AccountState.needsVaultSetup) {
      return const AccountResult.fail('Sign in first.');
    }
    final problem = VaultCrypto.validatePassphrase(passphrase);
    if (problem != null) return AccountResult.fail(problem);
    try {
      final setup = await VaultCrypto.createVault(
        userId: uid,
        passphrase: passphrase,
      );
      await _client.from('user_keys').insert(setup.bundle.toRow());
      _bundle = setup.bundle;
      _adoptKey(uid, setup.masterKey);
      return AccountResult.ok(recoveryKey: setup.recoveryKey);
    } catch (_) {
      return const AccountResult.fail('Could not create your vault.');
    }
  }

  Future<AccountResult> unlock(String passphrase) async {
    final uid = userId;
    final bundle = _bundle;
    if (uid == null || bundle == null || _state != AccountState.locked) {
      return const AccountResult.fail('Nothing to unlock.');
    }
    if (_lockedUntil != null && DateTime.now().isBefore(_lockedUntil!)) {
      return const AccountResult.fail('Too many attempts. Wait a minute.');
    }
    final key = await VaultCrypto.unlockWithPassphrase(
      userId: uid,
      passphrase: passphrase,
      bundle: bundle,
    );
    if (key == null) {
      _registerFailure();
      return const AccountResult.fail('Incorrect sync passphrase.');
    }
    _failedUnlocks = 0;
    _adoptKey(uid, key);
    return const AccountResult.ok();
  }

  Future<AccountResult> unlockWithRecoveryKey(String recoveryKey) async {
    final uid = userId;
    final bundle = _bundle;
    if (uid == null || bundle == null || _state != AccountState.locked) {
      return const AccountResult.fail('Nothing to unlock.');
    }
    final key = await VaultCrypto.unlockWithRecoveryKey(
      userId: uid,
      recoveryKey: recoveryKey,
      bundle: bundle,
    );
    if (key == null) {
      _registerFailure();
      return const AccountResult.fail('That recovery key is not valid.');
    }
    _adoptKey(uid, key);
    return const AccountResult.ok();
  }

  Future<AccountResult> changePassphrase(String newPassphrase) async {
    final uid = userId;
    final key = _masterKey;
    final bundle = _bundle;
    if (uid == null || key == null || bundle == null) {
      return const AccountResult.fail('Unlock your vault first.');
    }
    final problem = VaultCrypto.validatePassphrase(newPassphrase);
    if (problem != null) return AccountResult.fail(problem);
    try {
      final next = await VaultCrypto.changePassphrase(
        userId: uid,
        masterKey: key,
        newPassphrase: newPassphrase,
        current: bundle,
      );
      await _client
          .from('user_keys')
          .update({...next.toRow(), 'updated_at': DateTime.now().toUtc().toIso8601String()})
          .eq('user_id', uid);
      _bundle = next;
      return const AccountResult.ok(message: 'Sync passphrase updated.');
    } catch (_) {
      return const AccountResult.fail('Could not update the passphrase.');
    }
  }

  // -- internals ------------------------------------------------------------

  Future<void> _resolveVaultState(String uid) async {
    try {
      final row = await _client
          .from('user_keys')
          .select()
          .eq('user_id', uid)
          .maybeSingle();
      if (row == null) {
        _bundle = null;
        _wipeKey();
        _setState(AccountState.needsVaultSetup);
        return;
      }
      final bundle = KeyBundle.fromRow(row);
      if (bundle == null) {
        _setState(AccountState.guest);
        return;
      }
      _bundle = bundle;
      // A cached key cannot be verified without the passphrase. If it is
      // stale (e.g. the vault was recreated elsewhere), CloudStore sees every
      // record fail to decrypt and calls [invalidateKey], which re-locks.
      final cached = await _cache.load(uid);
      if (cached != null) {
        _masterKey = cached;
        _setState(AccountState.unlocked);
      } else {
        _wipeKey();
        _setState(AccountState.locked);
      }
    } catch (_) {
      // Offline or server error: stay usable as a guest rather than blocking
      // the browser. The vault state is re-resolved on the next restore().
      _wipeKey();
      _setState(AccountState.guest);
    }
  }

  /// Drops a master key that failed to decrypt the user's own data and asks
  /// for the passphrase again.
  @override
  Future<void> invalidateKey() async {
    final uid = userId;
    _wipeKey();
    if (uid != null) await _cache.clear(uid);
    if (_state == AccountState.unlocked) _setState(AccountState.locked);
  }

  void _adoptKey(String uid, Uint8List key) {
    _masterKey = key;
    unawaited(_cache.save(uid, key));
    _setState(AccountState.unlocked);
  }

  void _wipeKey() {
    final key = _masterKey;
    if (key != null) {
      key.fillRange(0, key.length, 0);
    }
    _masterKey = null;
  }

  void _registerFailure() {
    _failedUnlocks++;
    if (_failedUnlocks >= 5) {
      _lockedUntil = DateTime.now().add(const Duration(minutes: 1));
      _failedUnlocks = 0;
    }
  }

  void _setState(AccountState next) {
    _state = next;
    notifyListeners();
  }

  static String? _validateCredentials(String email, String password) {
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$').hasMatch(email) ||
        email.length > 254) {
      return 'Enter a valid e-mail address.';
    }
    if (password.length < 12) {
      return 'Account password must be at least 12 characters.';
    }
    if (password.length > 128) return 'Password is too long.';
    return null;
  }

  static String _friendly(AuthException e) {
    final code = e.code ?? '';
    if (code == 'weak_password') {
      return 'That password is too weak or appears in a data breach.';
    }
    if (code == 'over_request_rate_limit' ||
        code == 'over_email_send_rate_limit') {
      return 'Too many requests. Please wait and try again.';
    }
    if (code == 'email_not_confirmed') {
      return 'Please confirm your e-mail address first.';
    }
    // Same message for wrong password / unknown account (no enumeration).
    return 'E-mail or password is incorrect.';
  }
}
