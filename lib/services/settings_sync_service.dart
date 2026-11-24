import 'package:saboor_browser/services/prefs_store.dart';

/// Thin compatibility wrapper: settings now live in [PrefsStore] (memory +
/// one encrypted cloud record) instead of a plaintext `user_settings` table.
class SettingsSyncService {
  SettingsSyncService._();
  static final SettingsSyncService instance = SettingsSyncService._();

  Future<void> saveSetting(String key, String value) =>
      PrefsStore.instance.setString(key, value);

  Future<String?> fetchSetting(String key) => PrefsStore.instance.getString(key);
}
