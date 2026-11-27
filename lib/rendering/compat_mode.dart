import 'dart:ffi';
import 'dart:io';

/// How the user wants pages drawn.
///
/// - [auto]: use the compatibility renderer only where the default one is
///   known to fail (Remote Desktop sessions, forced software rendering).
/// - [on]: always use it.
/// - [off]: never use it.
enum CompatPreference {
  auto,
  on,
  off;

  static CompatPreference parse(String? value) => switch (value) {
    'on' => CompatPreference.on,
    'off' => CompatPreference.off,
    _ => CompatPreference.auto,
  };

  String get storageValue => name;
}

/// Whether to draw pages with the compatibility renderer.
///
/// [canAttach] is false when the window has no DevTools port (the renderer
/// reaches the engine through it), in which case it can never be used.
bool shouldUseCompat(
  CompatPreference preference, {
  required bool remoteSession,
  required bool softwareGpu,
  required bool canAttach,
}) {
  if (!canAttach) return false;
  return switch (preference) {
    CompatPreference.on => true,
    CompatPreference.off => false,
    CompatPreference.auto => remoteSession || softwareGpu,
  };
}

/// `CINDER_DISABLE_GPU=1` makes the runner start the engine without GPU
/// compositing, which is also when frame capture most often yields nothing.
bool softwareRenderingRequested([Map<String, String>? environment]) =>
    (environment ?? Platform.environment)['CINDER_DISABLE_GPU'] == '1';

typedef _GetSystemMetricsC = Int32 Function(Int32);
typedef _GetSystemMetricsD = int Function(int);

/// True when this process is running inside a Remote Desktop session
/// (`GetSystemMetrics(SM_REMOTESESSION)`). Frame capture of the browser
/// surface is unreliable there because the session's only display adapter is
/// the remote-display one.
bool isRemoteSession() {
  if (!Platform.isWindows) return false;
  try {
    const smRemoteSession = 0x1000;
    final fn = DynamicLibrary.open('user32.dll')
        .lookupFunction<_GetSystemMetricsC, _GetSystemMetricsD>(
          'GetSystemMetrics',
        );
    return fn(smRemoteSession) != 0;
  } catch (_) {
    return false;
  }
}
