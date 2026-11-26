# Cinder threat model (STRIDE)

Scope: the Cinder desktop app (Flutter shell + WebView2 engine), its Rust
filtering crate, the Supabase cloud used for encrypted sync, and the
extension runtime. Out of scope: bugs inside Chromium/WebView2 itself (we rely
on the Evergreen runtime being kept up to date by Windows) and physical access
to an unlocked PC.

## Assets

| Asset | Where it lives | Why it matters |
|---|---|---|
| Browsing data (history, bookmarks, tabs, permissions, settings) | Memory; end-to-end encrypted records in Supabase when signed in | Privacy |
| Master/vault key | Derived from the user's password; DPAPI-protected on disk | Decrypts all synced data |
| Session cookies, site storage | WebView2 profile folder (`%LOCALAPPDATA%\Cinder`) | Account takeover on websites |
| Installed extensions | `%LOCALAPPDATA%\Cinder\extensions` | Code running on pages |
| The installer and updates | GitHub releases | Supply chain |

## Trust boundaries

1. **Web content → browser chrome.** Pages are hostile. They reach the chrome only
   through `chrome.webview.postMessage` (one validated message type, see
   `lib/security/page_messages.dart`) and through navigation/download/permission
   requests that go through `UrlPolicy`, the permission store and the download
   service.
2. **Browser ↔ cloud.** Supabase is untrusted for confidentiality: records are
   encrypted client-side. Row-level security restricts rows per user.
3. **Extension pages ↔ chrome.** Extension popups run on their own virtual origin
   with an allow-listed bridge (`lib/extensions/popup_bridge.dart`).
4. **Local machine.** Other processes of the same user are *not* fully trusted;
   other users certainly are not.
5. **Network.** Everything is assumed observable and modifiable.

## STRIDE

### Spoofing
| Threat | Mitigation | Residual |
|---|---|---|
| Look-alike (IDN/homograph) domains in the address bar | `UrlPolicy` shows punycode for mixed-script/confusable labels and warns | Whole-script confusables are not all detected |
| Page spoofs a chrome message (e.g. fake context menu) | Chrome accepts one message type, only from http(s) tabs, with strict field validation (`PageMessages`) | A page can still draw a *fake* menu inside its own area, like any browser |
| Forged extension package | CRX3 signature + extension-id binding verified before install | Store endpoint is unofficial; best effort |
| Fake update | Update check only *notifies*; installer comes from GitHub over HTTPS | Installer is currently unsigned (SignPath declined), so SmartScreen warns |
| Plain-HTTP page impersonation | HTTPS-only mode upgrades http:// and asks before falling back | User can opt into HTTP per site |

### Tampering
| Threat | Mitigation | Residual |
|---|---|---|
| Network attacker alters pages | HTTPS-only; WebView2 enforces TLS and blocks active mixed content natively | Passive mixed content (images) is upgraded/allowed by the engine |
| Tampered sync records | AES-GCM authenticated encryption with record-bound associated data | Server can delete/withhold records |
| Tampered filter lists | Fetched over HTTPS only, size-capped, parsed by a memory-safe Rust crate, fuzzed | A compromised list publisher can over-block (not run code) |
| Zip-slip / archive bombs in extensions | Path, symlink, count and size limits | — |
| Local process edits the profile | OS file permissions; DPAPI for secrets | Same-user malware can read cookies (true of every browser) |

### Repudiation
Cinder keeps no server-side audit trail of browsing. Security-relevant client
events (install of an extension, permission grants) are visible to the user in
the UI. No telemetry is sent (`lib/services/telemetry_consent.dart`).

### Information disclosure
| Threat | Mitigation | Residual |
|---|---|---|
| Cloud operator reads data | Client-side E2E encryption, key never leaves the device unwrapped | Metadata (record counts, timing, sizes) is visible |
| Trackers fingerprint/follow the user | Request blocking with EasyList/EasyPrivacy; private windows are memory-only | No fingerprint-resistance beyond what WebView2 provides |
| Sites silently use camera, mic, location | Per-origin prompts, secure-origin only, revocable, abuse limiter | — |
| Private-window data persists | Separate process, temp profile deleted on exit, no cloud writes | Swap/crash dumps are OS-level |
| **Local DevTools port** | Bound to 127.0.0.1, random ephemeral port per launch, used by the request filter and DevTools panel | **Any local process of the same machine can connect to it** (as with every Chromium `--remote-debugging-port`). Tracked as the main accepted risk of the filtering design; mitigation options: pipe transport (`--remote-debugging-pipe`) if the plugin ever exposes it |
| Filter-list download reveals "a Cinder user" to list hosts | Fetch is anonymous and weekly | IP address visible to list publishers |

### Denial of service
| Threat | Mitigation |
|---|---|
| Permission-prompt spam | Three blocks silence an origin; gesture-less notification/location prompts auto-deny |
| Huge/hostile URLs, JSON, messages, lists | Length caps (URL 8 KB, messages 16 KB, lists 30 MB), fuzz tests, Rust matcher never panics on arbitrary input |
| Broken filter freezes browsing | Filtering failures fail open; first navigation waits at most 5 s for the filter |
| Window-opening abuse | Popups denied by policy |

### Elevation of privilege
| Threat | Mitigation | Residual |
|---|---|---|
| Page reaches native/Dart code | Only the whitelisted context message; no host objects exposed | WebView2 sandbox bugs |
| Extension gains more than granted | MV3 permission model, per-site access, no privileged bridge in content scripts, popup bridge allow-list | Content scripts run in the page world (no isolated worlds in the plugin) |
| `javascript:`/`file:`/custom-scheme navigation | Default-deny scheme allow-list in `UrlPolicy` | — |
| Malicious dependency | `cargo audit`, `cargo deny`, pinned lockfiles, weekly CI schedule; Dependabot recommended for pub | Transitive Dart packages are reviewed manually |
| Malicious page host-mapped extension origin | `.cinder.local` hosts are internal-only, never filtered or navigable from web pages | — |

## What Cinder deliberately does *not* claim

* No post-quantum or custom-TLS claims: TLS is entirely WebView2/Chromium.
* No custom certificate-error UI: WebView2 shows its own interstitial and Cinder
  does not offer a bypass of its own.
* The "deceptive site" list is a local host list from abuse.ch URLhaus, not
  Google Safe Browsing (which requires an API key and a Google-operated server
  lookup). It catches known malware-distribution hosts only.

## Checks that enforce this

* `flutter test`: policy, parser, store and fuzz-style tests (`test/fuzz_inputs_test.dart`).
* `cargo test`, `cargo audit`, `cargo deny check` and short `cargo fuzz` runs on every push and weekly (`.github/workflows/ci.yml`).
