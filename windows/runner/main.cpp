// rand_s() needs this defined before <stdlib.h> is included.
#define _CRT_RAND_S
#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <stdlib.h>
#include <windows.h>

#include <string>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  // Expose WebView2's DevTools protocol on loopback only so the app can dock
  // the DevTools frontend inside the window. The port is random per launch
  // (a fixed, well-known port would let any local process or script probe
  // for and attach to the browser) and the websocket origin is limited to
  // that same loopback origin. The chosen port is handed to the Dart side as
  // --cinder-devtools-port=<n>; it is never written to disk.
  unsigned int random_value = 0;
  if (::rand_s(&random_value) != 0) {
    random_value = ::GetTickCount();
  }
  const std::string devtools_port = std::to_string(49152 + (random_value % 16000));
  const std::string browser_args =
      "--remote-debugging-port=" + devtools_port +
      " --remote-debugging-address=127.0.0.1"
      " --remote-allow-origins=http://127.0.0.1:" + devtools_port;
  ::_putenv_s("WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS", browser_args.c_str());

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  command_line_arguments.push_back("--cinder-devtools-port=" + devtools_port);

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"Cinder", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
