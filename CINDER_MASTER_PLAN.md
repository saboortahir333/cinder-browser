# Cinder Browser — Phased Master Plan (Architect + Developer + Security)

Target file after approval: `D:\saboor_browser\CINDER_MASTER_PLAN.md` (plan mode blocks writing there now).

## Context
Cinder today = Flutter/Dart shell (`lib/main.dart`, 4,137-line monolith) + WebView2 (Chromium) renderer + Rust core (`rust/src/api/simple.rs`: reqwest/rustls, hickory DoH/DoT, x509) via flutter_rust_bridge + Supabase sync + Inno Setup installer. The user also wants a **custom, self-owned engine**. Existing `web_browser_project_plan_revised.md` assumes a wrapper; this plan supersedes it by running two tracks:

- **Track A – Product**: harden and finish the WebView2-based browser (ships, earns users).
- **Track B – Engine ("Cinder Engine")**: new Rust workspace, grown in stages, plugged into the shell behind an `EngineAdapter` interface; WebView2 stays the fallback forever until parity.

Principle: the engine must never block shipping the product. Every engine phase ends in a usable artifact.

## Target architecture
```
Flutter shell (UI only)
   └─ BrowserCoordinator (Dart): tabs, profiles, permissions, policy
        ├─ EngineAdapter interface
        │     ├─ WebView2Adapter (current)
        │     └─ CinderEngineAdapter (new, via flutter_rust_bridge + texture)
        ├─ Storage (Supabase = source of truth; no local DB; OS keychain only for the auth token)
        └─ Services (downloads, history, bookmarks, sync, extensions)
rust/ workspace
   ├─ cinder_core   (existing api: net, dns, tls)
   ├─ cinder_engine (html, css, dom, layout, paint, js glue)
   └─ cinder_sandbox (renderer process, IPC, OS sandbox)
```

## Phase 0 — Baseline & hygiene (1–2 wks)
- Audit: run `flutter analyze`, `flutter test`, `cargo test`, `cargo clippy`; record baseline in `docs/implementation-status.md`.
- Repo cleanup: delete `main.dart.bak`, `inno_setup*.exe`, `node_modules` (if unused); add `.gitignore`; **`git init`** (project has no VCS) + CI (GitHub Actions: analyze/test/build).
- Merge the two plan docs into this one; archive the old ones.
- Verify claimed features actually work (DoH/DoT does not apply to WebView2's own network stack — confirm; if so, label honestly or route via proxy).
- Exit gate: green baseline, git history, status doc.

## Phase 1 — Architecture refactor (2–3 wks)
- Split `main.dart` into `features/{tabs,address_bar,bookmarks,history,downloads,settings,newtab}` + `core/` (coordinator, state). Pick one state mgmt (Riverpod or Bloc).
- Define `EngineAdapter` (navigate, back/forward, reload, title/url/loading events, find, zoom, devtools, permissions, downloads, user-agent) and wrap WebView2 behind it.
- Define typed IPC schemas for Rust calls; replace stringly APIs.
- Exit gate: no behaviour change, UI tests pass, `main.dart` < 300 lines.

## Phase 2 — Product core (4–6 wks, Track A)
- Persistence: cloud-first. History, bookmarks, sessions and settings live in Supabase (Postgres + RLS, per-user, E2E-encrypted where sensitive). No local SQLite; only in-memory state plus the OS keychain for the auth token. Optional encrypted offline cache is an open decision.
- Tabs: pinning, groups, drag-reorder, discard/sleep, private window (ephemeral profile), multi-profile.
- Omnibox: search engines, suggestions (reuse `fuzzy_suggestion`), URL sanitising.
- Downloads manager, find-in-page, print/PDF, zoom, reader mode, context menus, keyboard shortcuts, accessibility (Narrator, high contrast).
- Passwords/autofill: store in Windows Credential Manager / DPAPI + AES-GCM vault; never plaintext.
- Settings sync (Supabase): end-to-end encrypted, RLS policies reviewed (`supabase_*.sql`).
- Exit gate: daily-drivable on Windows.

## Phase 3 — Security & privacy baseline (parallel with 2, 3–4 wks)
Threat model doc (STRIDE) for: chrome↔content boundary, IPC, extension host, sync, installer.
- Chrome/content separation: web content can never call privileged Dart/Rust APIs; whitelist-only JS channels with origin checks.
- Permission prompts (camera/mic/geo/notifications) per-origin, revocable; HTTPS-only mode, mixed-content blocking, cert-error interstitial (use x509 module), safe-browsing list (offline hash prefix).
- Tracker/ad blocking: filter lists engine in Rust (adblock-rust crate).
- Secrets: remove any keys from repo, Supabase anon key only + RLS; `cargo audit`, `cargo deny`, `dart pub outdated` in CI.
- Installer: code-signing, auto-update with signature verification (no unsigned updates).
- Telemetry: none by default; opt-in only.
- Exit gate: external-style checklist passed, fuzz targets for URL parsing and IPC.

## Phase 4 — Release 1.0 (2–3 wks)
- Updater, crash reporter (local, opt-in upload), installer polish, privacy policy, docs, website.
- Beta channel, bug triage, perf budget (startup < 1.5 s, memory per tab).
- Exit gate: public 1.0 on WebView2 engine.

## Engine Track (B) — runs after Phase 1; each stage standalone-testable

### E0 — Foundations (2 wks)
Cargo workspace, `cinder_engine` crate, headless test harness (render HTML → PNG, snapshot tests), CI. Decide: reuse crates (html5ever, cssparser/selectors, taffy, vello/tiny-skia, cosmic-text, rquickjs/boa) — **build the pipeline glue and layout/paint yourself, reuse spec-heavy parsers**. Write ADR in `docs/adr/`.

### E1 — Parse + DOM (4–6 wks)
URL (WHATWG `url` crate), HTML parse via html5ever, own DOM tree (arena-based), selectors, `querySelector`. Tests: html5lib-tests.

### E2 — CSS + style (6–8 wks)
Own cascade/specificity/inheritance, computed values, units, `var()`, `calc()`, media queries, UA stylesheet. Tests: selected WPT css subsets.

### E3 — Layout + paint (10–14 wks)
Block, inline + line breaking, text shaping (cosmic-text), floats, positioning, then flexbox (taffy as reference/verify), images (PNG/JPEG/WebP decoders). Display list → CPU raster (tiny-skia) first, GPU (wgpu/vello) later. Scrolling + hit testing.
Milestone: renders static pages (docs, blogs, Wikipedia) legibly.

### E4 — Shell integration (3–4 wks)
`CinderEngineAdapter`: engine renders to shared texture, Flutter `Texture` widget; input events, navigation, tab-level toggle "Use Cinder engine (experimental)"; auto-fallback to WebView2 on unsupported features.

### E5 — JavaScript (8–12 wks)
Embed QuickJS (rquickjs) or Boa — **not** writing a JS VM. Event loop, timers, promises, DOM bindings (generated from IDL-like table), events, `fetch`/XHR on `cinder_core` net, `localStorage`, Canvas 2D. Tests: Test262 subset via engine, WPT dom.

### E6 — Compat & forms (ongoing, 12+ wks)
Forms/inputs, iframes, cookies, CORS, CSP, same-origin, history API, grid, transforms, animations/transitions, web fonts, video/audio (FFmpeg/symphonia). Track pass-rate dashboard (WPT %), top-100-sites smoke list.

### E7 — Multi-process & sandbox (6–8 wks, security-critical)
Renderer in separate process, Windows AppContainer/job-object + restricted token, IPC over named pipes with validated schemas, site isolation by origin, crash containment, fuzzing (cargo-fuzz) of HTML/CSS/URL parsers and IPC. Memory safety: forbid `unsafe` outside audited modules.

### E8 — Performance & parity (continuous)
Incremental layout, style invalidation, GPU compositing, image/font caches, profiling. Honest target: "good for simple/medium sites" before any Chrome-parity claim.

## Timeline (solo, rough)
- Phases 0–4 (product): ~4–5 months.
- Engine E0–E4 (static-page renderer in shell): ~7–9 months, overlapping.
- E5–E7 (JS, compat, sandbox): +12–18 months.
- Real-web parity: multi-year; define success as WPT % and site list, not "replaces Chrome".

## Risks
| Risk | Mitigation |
|---|---|
| Engine scope creep starves product | Strict track separation; product ships first |
| Security debt in custom engine | Process isolation (E7) before default-on; fuzzing; keep WebView2 default |
| Solo bandwidth | Reuse spec-heavy crates; fixed milestone gates |
| Monolith regressions | Phase 1 refactor + tests before features |

## Verification (per phase)
- CI green: `flutter analyze && flutter test`, `cargo test && cargo clippy -D warnings`, `cargo audit`.
- Engine: snapshot PNG tests, html5lib/WPT pass-rate tracked in `docs/engine-conformance.md`.
- Manual: run `run_on_d.bat`, smoke-test checklist per exit gate.

## Immediate next step on approval
1. Save this as `D:\saboor_browser\CINDER_MASTER_PLAN.md`.
2. Start Phase 0: git init, cleanup, baseline run, status doc.
