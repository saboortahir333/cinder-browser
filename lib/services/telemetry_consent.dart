import 'package:saboor_browser/services/prefs_store.dart';

/// Telemetry is opt-in only and currently not implemented: Cinder collects and
/// sends nothing. This gate exists so that if diagnostics are ever added,
/// they have exactly one switch to respect:
///
///  * default is OFF, and a missing/unreadable setting means OFF;
///  * private windows never report, whatever the setting says;
///  * code must call [mayReport] immediately before every send.
///
/// See PRIVACY.md.
class TelemetryConsent {
  TelemetryConsent._();

  static const String prefKey = 'telemetry_opt_in';

  static Future<bool> mayReport({required bool isPrivate}) async {
    if (isPrivate) return false;
    try {
      return await PrefsStore.instance.getBool(prefKey) ?? false;
    } catch (_) {
      return false;
    }
  }
}
