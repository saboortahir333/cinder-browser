# Extensions and accessibility

## Extensions (Manifest V3)

Cinder runs its own MV3 extension runtime (`lib/extensions/`). The old C++
`extension_channel` (a folder validator) and `ExtensionService` (regex JSON
parsing, unconditional injection) were removed.

### What works

| Area | Status |
|---|---|
| Manifest parsing | Strict JSON, MV3 only (MV2 gets a clear message). Paths are validated (no `..`, absolute, drive or backslash paths). |
| Match patterns | Chromium `URLPattern` rules for http/https/file; `*.example.com` never matches `evilexample.com`; userinfo can't spoof hosts. A JS regex is generated from the same pattern and tested against the Dart matcher. |
| Content scripts | JS + CSS, `matches` / `exclude_matches`, `run_at`, `all_frames`. Registered per tab via `addScriptToExecuteOnDocumentCreated`, one script per extension so one broken extension can't break another. CSS uses adopted stylesheets (not blocked by page CSP). |
| Permissions | Install prompt lists every API permission with risk level, host access, and flags unsupported ones. Per-extension site access: **on all sites / on click / on specific sites**. Optional permissions can be toggled. The Web Store is never script-injectable. |
| Toolbar + popups | Pinned extensions get a toolbar button; a puzzle menu lists the rest. `action.default_popup` and `options_page` open in a dedicated WebView on the extension's own virtual origin (`https://<id>.extension.cinder.local`), navigation locked to that origin, MV3 CSP enforced. |
| APIs in extension pages | `storage.local/sync/session`, `tabs.query` (url/title only with `tabs` or an `activeTab` grant), `tabs.create`, `runtime.getURL/getManifest/openOptionsPage`, `i18n`, `clipboard` write. Everything else returns a clear error. |
| Manager UI | Install from store link/id, from `.crx`/`.zip`, or unpacked folder; enable/disable; pin; allow in private; site access; permissions; remove; check for updates. |
| Private windows | Extensions are **off** in private windows unless the user allows each one; their storage is memory-only there. |
| Distribution | Chrome Web Store and Edge Add-ons by id/URL (CRX3 download over HTTPS, redirects limited to store domains, 100 MB cap), local `.crx`/`.zip`, unpacked developer folders, and Chrome Web Store update checks. |

### Security model

* **CRX3 is verified** (`package_format.dart`): RSA PKCS#1 v1.5 / SHA-256
  signature (strict byte-for-byte padding comparison, `e >= 65537`), the
  `crx_id` must equal the hash of the signing key, and a store install must
  produce exactly the id that was requested. Tampered, wrongly-identified,
  unsigned or CRX2 packages are rejected. (ECDSA co-signatures such as the
  store's publisher proof are not relied on; the developer key defines the id.)
* **Zip hardening**: zip-slip, symlinks, absolute paths, file-count (5k),
  total (250 MB) and per-file limits.
* **Content scripts run in the page's main world.** The WebView2 plugin has
  no isolated worlds, so page scripts can see them. For that reason content
  scripts get *no* privileged bridge: their `chrome` object has no storage
  or tab access (storage there is an in-memory stub). Privileged APIs exist
  only in extension pages on the extension's own origin.
* The popup bridge validates every message (size, types, method allow-list),
  checks each method against granted permissions, and only answers while the
  page is on the extension's origin.
* Updates that request new permissions or hosts require consent again; silent
  updates keep the user's existing grants.

### Known limits (be honest with users)

* **No background service workers** → `runtime.sendMessage`, `alarms`,
  `webRequest`/`declarativeNetRequest` (ad blockers), `contextMenus`,
  `notifications`, `scripting`, `cookies`, `history`, `bookmarks` are not
  implemented. Extensions needing them are marked "Limited" and may only
  partly work. Implementing them needs a real engine-level extension host
  (patching the WebView2 plugin to expose
  `ICoreWebView2Profile::AddBrowserExtension`) — the natural next step.
* Content scripts always run in the page world (see above).
* The Web Store CRX endpoint is the one Chromium derivatives use, but Google
  does not publish it as a public API. Treat store installs as best-effort and
  keep the file / unpacked paths working. Firefox add-ons (`.xpi`) are not
  supported.
* Registering/changing extensions applies to the *next* page load in open tabs.
* Not exercised in a running window yet: only unit/widget tests and
  generated-JS checks (Node) were run.

## Accessibility

Done:

* **Keyboard only**: every chrome control is focusable (`ToolbarButton`,
  tabs, bookmarks, start-page tiles via `A11yFocus`), activates with
  Enter/Space, shows a 2 px focus ring; Delete closes a focused tab; **F6 /
  Shift+F6** cycle address bar → page → bookmarks → tabs → toolbar; **Alt+D /
  Ctrl+L** focus the address bar; Esc closes the extension popup.
* **Narrator**: custom controls expose one spoken label (e.g. "Docs, pinned,
  loading, tab", selected state, "Close tab" action), toolbar buttons are
  buttons with labels/toggled state, region changes and "Page loaded: title"
  are announced, dialogs have headers and live status regions.
* **High contrast**: automatically switches to a black or white high-contrast
  palette when Windows high contrast is on (and in private windows too); the
  same palettes are selectable manually. All palettes are checked in tests for
  WCAG AA text contrast (7:1 for body text) and 3:1 accent contrast.
* **Reduced motion / text size**: tab transitions turn off with the OS "show
  animations" setting; system text scale is honoured (clamped to 1.5x so
  fixed-height chrome doesn't break).

Not done / limits:

* **Web page content is not exposed to Narrator.** The page is a WebView2
  composition surface hosted through `webview_flutter_windows`, which does not
  bridge the page's UI Automation tree. Fixing this needs a windowed WebView2
  host or a custom DOM → semantics bridge.
* Not tested with a real screen reader yet (widget semantics tests only).
* Menus built with Material `showMenu`/`PopupMenuButton` rely on Flutter's own
  keyboard handling; the ☰ menu has not been audited item by item.
