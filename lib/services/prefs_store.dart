import 'package:flutter/foundation.dart';

import 'package:saboor_browser/services/app_services.dart';

/// Preferences (theme, wallpaper, shortcuts, toolbar flags, ...) kept in
/// memory and synced as ONE encrypted cloud record. Nothing touches the disk.
/// The API mirrors the small subset of SharedPreferencesAsync the browser
/// used, so call sites barely change.
///
/// Guests get defaults on every launch (by design: guest mode saves nothing).
class PrefsStore extends ChangeNotifier {
  PrefsStore._();

  static final PrefsStore instance = PrefsStore._();

  static const String kind = 'setting';
  static const String recordId = 'prefs';
  static const int maxKeys = 200;
  static const int maxStringLength = 64 * 1024;

  final Map<String, Object> _values = {};

  /// Replaces memory with the account's cloud copy (call after unlock).
  Future<void> load() async {
    final cloud = AppServices.cloud;
    await cloud.load(kind);
    _values.clear();
    final record = cloud.get(kind, recordId);
    if (record != null) {
      for (final entry in record.entries) {
        final v = _clean(entry.value);
        if (entry.key.length <= 100 && v != null && _values.length < maxKeys) {
          _values[entry.key] = v;
        }
      }
    }
    notifyListeners();
  }

  /// Forget everything (sign-out).
  void clearMemory() {
    _values.clear();
    notifyListeners();
  }

  Future<String?> getString(String key) async {
    final v = _values[key];
    return v is String ? v : null;
  }

  Future<bool?> getBool(String key) async {
    final v = _values[key];
    return v is bool ? v : null;
  }

  Future<int?> getInt(String key) async {
    final v = _values[key];
    return v is int ? v : null;
  }

  Future<List<String>?> getStringList(String key) async {
    final v = _values[key];
    return v is List ? v.whereType<String>().toList() : null;
  }

  Future<void> setString(String key, String value) =>
      _set(key, value.length > maxStringLength ? null : value);
  Future<void> setBool(String key, bool value) => _set(key, value);
  Future<void> setInt(String key, int value) => _set(key, value);
  Future<void> setStringList(String key, List<String> value) =>
      _set(key, List<String>.of(value));

  Future<void> remove(String key) async {
    if (_values.remove(key) != null) _persist();
  }

  Future<void> _set(String key, Object? value) async {
    if (value == null || key.isEmpty || key.length > 100) return;
    if (!_values.containsKey(key) && _values.length >= maxKeys) return;
    _values[key] = value;
    _persist();
  }

  void _persist() {
    AppServices.cloud.put(kind, recordId, Map<String, dynamic>.of(_values));
  }

  /// Accepts only JSON scalar / string-list values from untrusted storage.
  static Object? _clean(Object? v) {
    if (v is String && v.length <= maxStringLength) return v;
    if (v is bool || v is int) return v;
    if (v is double && v.isFinite) return v.toInt();
    if (v is List && v.length <= 500 && v.every((e) => e is String)) {
      return v.cast<String>();
    }
    return null;
  }
}
