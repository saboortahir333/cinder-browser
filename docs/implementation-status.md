# Implementation Status: Cinder Browser

## 1. Existing Architecture
- **Framework & Language:** Flutter (Dart) for UI, Rust for security probes (`flutter_rust_bridge`), C++ for Windows-specific platform channels.
- **Rendering Engine:** Chromium (via WebView2 / `webview_flutter_windows`).
- **Target OS:** Windows (x64) exclusively at this stage.
- **Persistence:** Supabase PostgreSQL for telemetry and sync (Bookmarks, History, Downloads). SharedPreferences for local settings (Themes, Wallpapers). No local SQLite database currently used.
- **Extensions:** Custom C++ bridge (`saboor_browser/extensions`) to interact with WebView2 `AddBrowserExtension` (Manifest V3).

## 2. Repository Structure
- `lib/main.dart`: UI shell + browser state (3.5k lines after the first decomposition pass).
- `lib/models/`: `download_item.dart`, `fuzzy_suggestion.dart`, `browser_palette.dart`, `browser_wallpaper.dart`, `browser_extension.dart`.
- `lib/services/`: `download_service.dart`, `history_service.dart`, `bookmark_service.dart`, `extension_service.dart`, `settings_sync_service.dart`.
- `lib/utils/`: `constants.dart` (Supabase credentials), `download_paths.dart` (download file naming).
- `lib/src/rust/`: generated `flutter_rust_bridge` bindings.
- `test/`: `widget_test.dart` (shell smoke tests), `download_paths_test.dart` (download naming unit tests).
- `windows/runner/`: Native C++ application host, containing custom WebView2 bridges (`extension_channel.cpp`, `flutter_window.cpp`).
- `rust/`, `rust_builder/`: Rust crate wrapping Brave's `adblock` engine (EasyList/EasyPrivacy matching) via flutter_rust_bridge. The old PQC/DoH probe code was removed: it never affected real traffic.
- `Output/`: Inno Setup compiled installer artifacts (`CinderBrowser_Setup.exe`).

## 3. Current Build and Test Status
Environment: Flutter 3.44.2 (stable), Dart 3.12.2, Windows x64.

| Command | Result |
| --- | --- |
| `flutter pub get` | Pass — resolved `http 1.6.0` / `collection 1.19.1` after they were declared directly. |
| `flutter analyze` | Pass — **27 issues, 0 errors, 0 warnings** (down from 30). All remaining issues are `info`-level (`withOpacity` deprecations in `main.dart`, two style nits in `extension_service.dart`). |
| `flutter test` | **Pass — 13/13** (2 widget tests, 11 unit tests). |
| `flutter build windows --release` | **Not run this session** (deferred by request). Last known state: failed to compile due to the `FilePicker` call signature; that call has since been rewritten, so a re-run is required before release. |


## 4. Completed and Incomplete Features
### Completed
- Foundational browser shell (Tabs, Omnibox, Navigation, Window management).
- Cloud-synced Bookmarks and History (Supabase).
- Download Manager with parallel streaming and Supabase telemetry.
- Download destination flow migrated to the `file_picker` 13.x API (URL prompt → folder picker → collision-safe derived file name).
- Appearance Settings (Themes, 4K Wallpapers).
- C++ bridge for unpacking extensions to WebView2.
- **Decomposition pass 1:** models, services and constants extracted out of `main.dart` into `lib/models/`, `lib/services/`, `lib/utils/`.
- **Test suite green:** `flutter test` passes 13/13, including new unit tests for download file naming.

### Incomplete / Not Started
- **Extension Management UI:** The Flutter UI for installing/disabling extensions does not exist yet (only the C++ backend is ready).
- **Tab Groups & Workspaces.**
- **Developer Tools & Offline Research Workspace.**
- **Robust Local Offline Mode:** Currently relies heavily on Supabase; lacks a fallback SQLite implementation if the user is offline.

## 5. Known Defects and Technical Risks
### Fixed in this session
- **Invalid `FilePicker.saveFile` usage in the download flow (build-breaking).** `file_picker` 13.x removed the path-only save dialog: `saveFile` now *writes the supplied bytes* to the chosen file (`windows_file_picker` calls `file.writeAsBytes(bytes)`). The previous code passed `bytes: Uint8List(0)` merely to obtain a destination path, which created a stray 0-byte file before the URL was known and dropped the dialog's overwrite confirmation.
- **Unhandled Supabase assertion in `DownloadService`.** `Supabase.instance` was dereferenced *outside* the `try` block, so any unavailable/uninitialised client escaped as an unhandled async error (it crashed the widget tests). Now routed through a lazy `_client` getter used inside `try`, matching `HistoryService`/`SettingsSyncService`.
- **`collection` / `http` used but not declared** in `pubspec.yaml` (relied on transitive resolution). Both are now direct dependencies.
- **2 px `RenderFlex` overflow** in the 84×84 `_StartShortcut` tile when a shortcut label wrapped to two lines; the label is now `Flexible` with `maxLines: 2` + ellipsis.
- **Stale widget test** asserting the removed `'A quieter place to explore.'` copy; it now asserts the current start page (time-based greeting, "Top Sites").

### Open
- **Monolithic `main.dart`:** ~3.5k lines remain. Models, services and constants are extracted, but the UI (dialogs, start page, toolbar, tab strip) is still inline in one class. This remains the top maintainability risk.
- **Supabase Dependency:** Hardcoding Supabase for core browser functions (Downloads, History) means the browser is effectively broken without internet access.
- **WebView2 Limitations:** Deep network interception and custom TLS handshakes are notoriously difficult with WebView2 without using a local proxy architecture.
- **`withOpacity` deprecations:** ~25 `info`-level findings on `main.dart`; migrate to `withValues(alpha: ...)`.
- **Tests are shallow:** only shell smoke tests plus pure-function unit tests exist; no coverage of navigation, tabs, or service behaviour.


## 6. Recommended Implementation Order
1. **Finish the refactor (in progress):** pass 1 moved models/services/utils out of `main.dart`; pass 2 should move the UI out (empty `lib/ui/` is already scaffolded).
2. **Offline Resilience:** Implement local SQLite caches for History and Bookmarks so the browser functions without an active Supabase connection.
3. **Extensions UI:** Build the Flutter interface to manage extensions installed via the C++ bridge.
5. **Tab Groups & Workspaces.**
6. **Housekeeping:** migrate `withOpacity` → `withValues(alpha: ...)` and widen test coverage.

## 7. Exact Next Task with Acceptance Criteria
**Task:** Monolith Decomposition, pass 2 — extract the UI layer into `lib/ui/`

Pass 1 is complete: models, services, constants and the download path helpers now live in `lib/models/`, `lib/services/`, `lib/utils/`, and the extracted `DownloadService` was validated (see §3 and §5).

- **Description:** `lib/main.dart` is still ~3.5k lines because the entire UI lives inside `_BrowserShellState`. Extract the self-contained dialogs and shared widgets into `lib/ui/` so new features (Extensions UI, Tab Groups) do not grow the monolith further. Behaviour must not change.
- **Suggested split:**
  - `lib/ui/dialogs/downloads_dialog.dart` (`_showDownloadsDialog` body)
  - `lib/ui/dialogs/history_dialog.dart` (`_showHistoryDialog`, `_buildBrowsingHistoryList`, `_buildSearchHistoryList`)
  - `lib/ui/dialogs/appearance_dialog.dart` (`_showAppearanceSettings`, `_buildGalleryCard`, `_buildThemeLibrary`, `_buildWallpaperLibrary`)
  - `lib/ui/widgets/start_page.dart` (`_buildStartPage`, `_StartShortcut`, `_RecentActivityCard`)
  - `lib/ui/widgets/chrome_icon_button.dart`, `lib/ui/widgets/security_status.dart`
- **Acceptance Criteria:**
  - Extracted widgets take data + callbacks as constructor parameters; no `State` object is passed wholesale.
  - `flutter analyze` reports **0 errors and 0 warnings** (info count must not increase).
  - `flutter test` stays green at **13/13**.
  - `flutter build windows --release` compiles successfully (still outstanding from the previous session).
  - No user-visible behaviour change: tabs, omnibox, downloads, appearance settings and the start page all still work.



## Security and privacy (Tier 2)

| Feature | Status |
|---|---|
| Per-origin permission prompts (camera, mic, location, notifications, clipboard) | Done. Secure origins only, remembered per site (encrypted sync), revocable from the lock icon and Menu > Site permissions, never remembered in private windows. Extension popups and DevTools are denied everything. |
| HTTPS-only mode | Done, on by default. http:// documents are upgraded through the DevTools-protocol request filter; a failed upgrade asks before using HTTP. Loopback/LAN/intranet names are exempt. |
| Mixed content / certificate errors | Handled natively by WebView2 (active mixed content blocked, native interstitial for bad certificates). Cinder adds no custom bypass. |
| Tracker and ad blocking | Done, on by default, per-site off switch. Rust `adblock` engine, EasyList + EasyPrivacy fetched weekly (built-in fallback list offline). |
| Deceptive-site warning | Done as a local host list (abuse.ch URLhaus), not Google Safe Browsing. |
| Chrome vs content isolation | One whitelisted page-to-chrome message type, http(s) senders only, strict validation (`lib/security/page_messages.dart`). |
| Threat model, supply chain, fuzzing | `docs/threat-model.md`; CI runs `cargo audit`, `cargo deny`, `cargo fuzz` and Dart fuzz-style tests. |
| Telemetry | None exists. `TelemetryConsent` gates any future reporting: opt-in only, never in private windows. |

Known limits: the request filter uses the window's loopback DevTools port, which any local process can reach (see the threat model); filtering starts when the first WebView is ready (the first navigation waits up to 5 s for it); service-worker and extension background traffic is filtered like any other request, but cosmetic (element-hiding) filters are not applied yet.
