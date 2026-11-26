# Cinder Browser

A Windows desktop browser built with Flutter and Microsoft Edge WebView2.

* Private windows and separate profiles (separate processes, temp-only data)
* End-to-end encrypted sync of bookmarks, history and settings (Supabase)
* Manifest V3 extensions (content scripts, toolbar popups, permission prompts)
* Firefox-style UI, high-contrast and keyboard-only support
* HTTPS-only mode, tracker and ad blocking, per-site permission prompts

Docs: [security & data model](docs/security-and-data-model.md) ·
[extensions & accessibility](docs/extensions-and-accessibility.md) ·
[threat model](docs/threat-model.md) ·
[code signing](docs/signing-with-signpath.md)

## Build

```powershell
flutter pub get
flutter test
flutter build windows --release
.	oolsetch_installer_deps.ps1
.	oolsuild_release.ps1 -SkipBuild    # produces CinderBrowser_Setup.exe (unsigned)
```

## Install

Download `CinderBrowser_Setup.exe` from the [Releases](../../releases) page
(Windows 10 1809+ / Windows 11, 64-bit). It installs the Visual C++ runtime and
the WebView2 runtime automatically if they are missing.

## Code signing policy

Free code signing provided by [SignPath.io](https://signpath.io), certificate by
[SignPath Foundation](https://signpath.org). See [CODE_SIGNING_POLICY.md](CODE_SIGNING_POLICY.md)
and [PRIVACY.md](PRIVACY.md).

## License

[Apache License 2.0](LICENSE)
