# Comprehensive Project Plan: Building a Production-Grade, User-Controlled Web Browser

> **Execution note for Cursor:** This document is the project source of truth. Continue from the repository's current state; do not recreate, replace, or restructure working code merely to match this document. First inspect the existing codebase, identify completed work, and map it to the phases below. Preserve existing naming, architecture, and working behavior unless a concrete issue requires a change. Implement incrementally, run relevant checks after each change, and report files changed, commands run, results, risks, and the next step.

## Introduction & Reality Check

Building a modern browser from scratch to compete with Chrome (Blink/V8) or Firefox (Gecko/SpiderMonkey) is an exceptionally complex undertaking. This plan therefore prioritizes a practical browser product built around an established rendering engine, with carefully scoped custom browser services and a distinctive, user-controlled experience.

The product goal is not simply to accumulate features. It is to make browsing more **controllable, coherent, dependable, private, and useful for real workflows**, without relying on AI features.

### The Engine Decision

1. **Wrapper approach (recommended for V1):** Build a custom browser UI and browser-services layer around an established rendering engine such as CEF, WebKit, or Servo.
2. **From-scratch approach:** Build the HTML parser, CSS layout engine, JavaScript runtime, and related platform capabilities. This is not a realistic solo-developer V1 goal.

This plan assumes Path 1. Keep engine-specific functionality behind well-defined interfaces so the implementation can evolve without rewriting the entire application.

### Product principles

- **User agency:** settings are understandable, reversible, and under user control.
- **Privacy by design:** minimize collection, avoid unnecessary telemetry, and make data handling visible.
- **Security before convenience:** never weaken origin boundaries, sandboxing, certificate validation, or permission controls to ship a feature.
- **Progressive delivery:** ship a stable core before advanced features.
- **Standards and compatibility:** prefer established browser-engine capabilities and standards over custom reimplementations.
- **No AI dependency:** all planned features work through deterministic controls, conventional software, and user-defined rules.
- **Honest capability labels:** distinguish implemented, experimental, engine-provided, and planned features in the UI and documentation.

---

## Phase 0: Repository Audit & Execution Baseline

**Do this before modifying code.**

1. Inspect the complete repository, existing plan, README, build scripts, dependency manifests, tests, and current application behavior.
2. Identify the actual language, UI framework, embedded engine, target operating systems, packaging approach, and current branch.
3. Run existing build, lint, type-check, and test commands without changing code. Record baseline failures separately from regressions.
4. Map existing files and features to this plan. Mark each item `Complete`, `Partial`, `Not started`, `Blocked`, or `Needs verification`.
5. Identify architectural mismatches between the current implementation and this plan. Propose the smallest safe migration; do not silently replace working components.
6. Create or update a concise `docs/implementation-status.md` containing:
   - current architecture and dependency versions;
   - verified build/test commands and baseline results;
   - implemented features and their source files;
   - known defects and security limitations;
   - next small, testable task.

**Cursor completion gate:** provide the audit and proposed sequence first. Then implement only the next approved/sensible task, rather than generating the entire browser in one pass.

---

## Phase 1: Foundational Architecture & Tech Stack

### 1. High-level architecture

Keep responsibilities separated:

- **Browser UI:** windows, tabs, address bar, navigation, menus, settings, bookmarks, downloads, and accessible controls.
- **Browser coordinator:** owns application state and mediates between UI, engine, storage, and privileged services.
- **Rendering engine adapter:** wraps the selected engine's navigation, page lifecycle, devtools, permissions, and events.
- **Networking/security services:** only where the engine exposes safe, supported integration points; do not claim full network interception if the chosen engine does not permit it.
- **Persistence:** local browser data, profiles, settings, sessions, bookmarks, history, and offline archives.
- **Extension host:** a later isolated subsystem, not a privileged plugin system embedded in the UI.
- **Platform integration:** OS keychain, file chooser, notifications, proxy settings, and native window behavior.

### 2. Technology choices

- **Core logic:** Rust is preferred for new security-sensitive services and memory-safe application code.
- **UI:** retain the repository's existing framework if it is viable. For a new implementation, evaluate Tauri/native UI and the chosen engine's integration constraints before committing.
- **Rendering:** use a maintained engine with a clear embedding API. Evaluate engine maturity, platform coverage, security updates, media support, accessibility, and Web Platform Test results.
- **Persistence:** SQLite for structured local data; use OS-protected storage or a vetted cryptographic design for secrets.
- **Cryptography:** use maintained, audited libraries and OS facilities. Do not invent cryptographic protocols.
- **IPC:** typed, validated messages with explicit authorization and narrow capabilities.

### 3. Core architectural requirements

- Keep UI responsive even when a page is slow or unresponsive.
- Make browser-owned privileged actions pass through a trusted coordinator.
- Separate browser chrome from web content.
- Define clear ownership for tabs, windows, profiles, storage, and engine instances.
- Add structured logs with privacy-conscious redaction.
- Use feature flags for incomplete or engine-dependent functionality.
- Document platform and engine limitations instead of simulating unsupported behavior.

**Deliverable:** a working, navigable desktop browser shell that loads ordinary websites through the selected engine, with a documented architecture and repeatable build.

---

## Phase 2: Security, Networking & Privacy Foundation

Security is a foundation, not a cosmetic feature. Implement and verify engine-supported protections before adding complex user-facing controls.

### 1. Network and transport

- Support modern HTTP behavior through the embedded engine, including HTTP/1.1, HTTP/2, and HTTP/3 where the engine and platform support them.
- Use the engine's supported network hooks for proxy configuration, request observation, and policy enforcement.
- Do not route traffic through a separate Rust client unless the architecture can preserve browser semantics, cookies, cache behavior, service workers, CORS, redirects, WebSockets, WebRTC, authentication, and certificate handling.
- Provide configurable system proxy and per-profile proxy settings only where supported and tested.
- Treat DNS-over-HTTPS (DoH) and DNS-over-TLS (DoT) as explicit, documented options. Explain resolver choice and fallback behavior; avoid claiming they prevent all ISP or network observation.

### 2. TLS and certificates

- Rely on a maintained TLS implementation and the engine/OS certificate validation path where appropriate.
- Validate certificate chains, hostnames, validity periods, and applicable revocation behavior.
- Clearly explain certificate and connection errors; never silently bypass them.
- Use modern TLS defaults supported by the engine. Do not label TLS 1.2 as inherently unsafe; prefer current secure configurations and deprecate obsolete protocols according to standards and engine policy.
- Provide a human-readable connection details view without overstating what HTTPS guarantees.

### 3. Post-quantum cryptography (PQC)

- Treat PQC as a staged compatibility and research track, not a prerequisite for the first usable browser.
- Prefer standardized, engine-supported hybrid key exchange and maintained cryptographic libraries.
- Track current standards and upstream engine support before selecting algorithms or names.
- Do not independently patch TLS handshakes or certificate verification in production without expert review, interoperability testing, and a documented threat model.
- Add a diagnostic view only when the engine can reliably expose negotiated protocol details.

### 4. Process isolation and sandboxing

- Use the rendering engine's process model and sandbox. Verify actual behavior on every supported OS.
- Preserve same-origin policy, site isolation, renderer privilege separation, and least-privilege IPC.
- Keep renderer processes away from direct filesystem, keychain, and browser-profile access except through explicit, constrained browser-mediated APIs.
- Treat downloaded files, extensions, imported data, and web content as untrusted.
- Document any platform where sandboxing or site isolation is unavailable or weaker.

### 5. Privacy control center

Build a clear privacy dashboard on top of real engine capabilities:

- Show site permissions and allow users to review, revoke, or reset them.
- Display available tracking/cookie protection state and explain its scope.
- Provide per-site controls for camera, microphone, location, notifications, clipboard, pop-ups, and other supported permissions.
- Show recent permission decisions and relevant security events.
- Provide a site-data view with clear, site-specific deletion.
- Offer exportable privacy information without exposing secrets.
- Avoid arbitrary “privacy scores” unless their methodology is transparent, evidence-based, and clearly explained.

**Deliverable:** verified security boundaries, documented network capabilities, certificate handling, and a functional permission/privacy center. No security claims should exceed tested engine behavior.

---

## Phase 3: Rendering & JavaScript Engine Integration

### 1. Rendering pipeline

The embedded engine handles the standards-heavy rendering pipeline:

1. HTML parsing and DOM construction.
2. CSS parsing and style calculation.
3. Layout and reflow.
4. Painting.
5. Compositing and GPU presentation.

The application should integrate the engine rather than reimplement these stages. Keep an adapter layer for navigation, page events, lifecycle, permissions, downloads, and supported developer tooling.

### 2. JavaScript and Web APIs

- Use the engine's own JavaScript runtime and Web API bindings.
- Do not create a second independent JS runtime for ordinary page execution.
- Ensure web content cannot call privileged native APIs directly.
- Restrict any application bridge to explicit, narrow, origin-checked capabilities.
- Test common web application behavior: forms, storage, media, workers, service workers, WebSockets, and authentication, as supported by the engine.

### 3. Compatibility and diagnostics

- Establish a small representative website test set: news, documentation, commerce, video, webmail, and complex web apps.
- Record engine limitations and known incompatibilities.
- Add crash reporting only with informed consent, data minimization, and redaction.
- Maintain a reproducible smoke-test procedure for navigation, back/forward, reload, downloads, permissions, and tab closure.

**Deliverable:** stable rendering integration, correct browser lifecycle handling, and repeatable compatibility smoke tests.

---

## Phase 4: Core Browser UI & Everyday Features

Build the reliable browser foundation before advanced differentiators.

### 1. Core UI

- Omnibox with URL navigation and configurable search provider.
- Back, forward, reload, stop, home, and new-tab actions.
- Tabs with independent loading/error state and responsive UI behavior.
- Window management, settings, history, bookmarks, and downloads.
- Keyboard navigation, accessible labels, focus management, and sensible shortcuts.
- SQLite-backed local metadata with migrations and safe recovery.
- Clear loading, offline, error, permission, and empty states.

### 2. Tab lifecycle and session recovery

- Tab groups and named workspaces.
- Duplicate-tab detection and safe consolidation.
- Configurable inactive-tab suspension, respecting media, downloads, forms, and engine constraints.
- Warn about potentially unsaved work before closing where detectable; do not promise detection for every site.
- Save and restore windows, tab order, groups, and supported layout state.
- Maintain crash-recovery snapshots and a recently closed list.
- Exclude private sessions from persistent history and snapshots.

### 3. Workspace and multi-profile model

- Separate workspaces for task organization.
- Separate browser profiles for genuine identity/storage isolation.
- Define exactly which data belongs to a profile: cookies, cache, history, extensions, permissions, downloads, and settings.
- Support moving a tab between profiles only through an explicit user action and clear identity-context warning.
- Provide temporary profiles with clear deletion semantics.
- Avoid describing workspaces as security boundaries unless they use separate profiles and the isolation is verified.

### 4. Split view and window layouts

- Support two-pane split view first, then evaluate additional layouts.
- Independent navigation and scroll state per pane.
- Resizable divider, keyboard controls, and accessible focus behavior.
- Save named layouts and restore them with sessions.
- Handle window resizing and small screens gracefully.

**Deliverable:** dependable everyday browser use, persistent workspaces, profiles, and recoverable sessions.

---

## Phase 5: Differentiating User Features

Implement these in small increments, behind feature flags where necessary. Each feature must have acceptance criteria, tests, settings, and a documented limitation section.

### 1. Resource and performance manager

- Show per-tab resource information only to the extent exposed by the engine/OS.
- Include memory and CPU estimates, activity state, and relevant process mapping.
- Offer manual tab discard/suspend and configurable automatic suspension.
- Warn before terminating a page with active work when possible.
- Avoid claiming precise per-tab battery usage if the platform does not provide it.

### 2. Offline-first library and research workspace

- Save readable page snapshots with source URL and capture date.
- Preserve supported text, images, links, and basic structure.
- Provide full-text search, tags, folders, and project collections.
- Allow user-added notes and highlighted excerpts with source references.
- Offer export in documented, portable formats.
- Respect copyright and site access controls; do not bypass paywalls or access restrictions.
- Make offline completeness explicit; dynamic pages and authenticated apps may not archive fully.

### 3. Download manager

- Queue, pause, resume, cancel, and organize downloads where the engine exposes these operations.
- Show source URL, destination, file type, progress, and available integrity metadata.
- Offer duplicate detection and user-configurable organization rules.
- Use OS file dialogs and safe destination handling.
- Treat file scanning as OS/security-product dependent; do not claim malware detection unless integrated and verified.

### 4. Extension permissions and ecosystem

- Begin with a documented extension compatibility assessment.
- Prefer a supported WebExtensions implementation or an established engine capability.
- Do not claim full `chrome.*` / `browser.*` compatibility until tested against a published compatibility matrix.
- Implement least-privilege extension permissions, per-site access where supported, and clear permission review.
- Isolate extension execution and prevent unauthorized access to browser secrets.
- Defer Manifest V3 service-worker and declarative request support until the selected engine's capabilities are confirmed.
- Provide extension update visibility, disable/remove controls, and permission-change review.

### 5. Accessibility and focus tools

- Add readable page mode, font sizing, line spacing, contrast options, and reduced motion where feasible.
- Provide keyboard-first navigation and visible focus.
- Add notification quiet hours and user-defined focus sessions.
- Offer reversible page cleanup for distracting elements, clearly distinguishing local presentation changes from site behavior.
- Test with keyboard-only use and supported accessibility tooling.

### 6. Customization studio

- Allow safe rearrangement of browser-owned panels and toolbar items.
- Support themes, density, tab appearance, and user-configurable shortcuts.
- Save and restore UI presets.
- Validate imported settings and reject malformed or unsafe configuration.
- Keep a reliable reset-to-default path.

### 7. Sync and portability

- Make sync opt-in and selectable by data category.
- Exclude private browsing data by default.
- Use vetted encryption and key management; do not invent cryptography.
- Show linked devices and provide revocation.
- Support portable export/import of bookmarks, settings, and workspace definitions.
- Clearly distinguish local backup, encrypted sync, and account-based services.

### 8. Form and identity controls

- Support separate user-managed form profiles if the engine provides secure autofill integration.
- Preview sensitive values before filling where practical.
- Use OS-backed secret storage for credentials and payment-related data.
- Avoid storing sensitive personal data in ordinary application settings or logs.
- Do not submit forms automatically without explicit user action.

### 9. Notifications and connection controls

- Provide a centralized view of supported site notifications.
- Support per-site allow/block/reset and quiet hours.
- Provide connection profiles such as metered or low-bandwidth mode.
- Offer optional image/media reduction and autoplay controls where supported.
- Track data usage only when the platform exposes reliable measurements.

**Deliverable:** a coherent set of user-facing differentiators integrated into the browser's architecture, not a disconnected collection of settings.

---

## Phase 6: Developer Workspace

Treat developer tooling as a focused product area, not a replacement for the browser's core security model.

- Integrate the engine's supported developer tools and remote debugging interface securely.
- Add responsive viewport presets and custom dimensions where supported.
- Provide a project workspace for related tabs, local preview URLs, documentation, and notes.
- Consider an API request workspace only after defining safe storage for credentials and environment variables.
- Keep local development integrations opt-in and bound to explicit local origins.
- Never expose debugging ports or privileged bridges to untrusted networks by default.
- Document which capabilities are supplied by the engine and which are custom.

**Deliverable:** a developer-focused workflow that remains isolated from ordinary browsing and does not weaken browser security.

---

## Phase 7: Testing, Compliance, Security Review & CI/CD

### 1. Automated quality gates

- Build and test on every supported target OS.
- Run formatting, linting, type checks, unit tests, integration tests, and packaging checks.
- Add UI smoke tests for navigation, tabs, workspaces, settings, downloads, and session restoration.
- Maintain regression tests for every fixed defect.
- Use Web Platform Tests (WPT) selectively to assess the embedded engine; do not imply that a wrapper project independently passes the full WPT suite unless it actually runs and reports those results.

### 2. Security testing

- Threat-model browser UI, renderer, IPC, extensions, downloads, profiles, sync, and update mechanisms.
- Fuzz custom parsers and custom protocol/IPC components where present.
- Prefer engine-provided security testing and upstream advisories for engine internals.
- Test origin isolation, permission prompts, profile boundaries, file access, malicious downloads, and extension privilege boundaries.
- Establish a process for dependency updates, vulnerability triage, and emergency releases.

### 3. Release engineering

- Reproducible build instructions and versioned release artifacts.
- Signed installers and update packages where platform infrastructure permits.
- Safe update and rollback strategy.
- Release notes covering user-visible changes, security fixes, known issues, and removed/experimental features.
- Crash recovery and data migration tests before releases.

**Release gate:** no feature is “production-ready” solely because it compiles. It must pass its acceptance tests, have a documented security/privacy impact, and behave safely under failure.

---

## Phase 8: Solo-Developer Roadmap & Delivery Sequence

The original month-based estimates are planning placeholders, not guarantees. Scope, engine maturity, platform support, and current repository state will determine actual duration.

### Milestone 0 — Audit and stabilize

- Inspect the existing Cursor-generated project and verify its current state.
- Build, run, and document the baseline.
- Resolve only blocking setup/build defects.
- Establish architecture notes, task tracking, and quality gates.

### Milestone 1 — Usable browser shell

- Window, omnibox, navigation, tabs, settings, bookmarks, history, and downloads.
- Engine adapter and stable page lifecycle.
- Basic keyboard and accessibility support.
- Smoke tests and packaged development build.

### Milestone 2 — Reliable state and organization

- Tab groups, workspaces, profiles, split view, and session recovery.
- Persistence schema and migrations.
- Crash recovery and safe close behavior.
- Tests for restoration, isolation, and data integrity.

### Milestone 3 — Security and privacy foundation

- Verify engine sandbox and process model.
- Permission center, site-data controls, certificate information, and secure defaults.
- Threat model, dependency review, and security regression tests.
- Document limitations of network customization and DNS options.

### Milestone 4 — Distinctive everyday experience

- Performance manager, offline library, research notes, and improved downloads.
- Notification controls, focus mode, accessibility tools, and customization.
- Deliver each as a separately testable increment.

### Milestone 5 — Developer and ecosystem capabilities

- Developer workspace and secure debugging integration.
- Extension compatibility prototype and permission model.
- Sync and portability design; implement only after key management and data boundaries are reviewed.

### Milestone 6 — Hardening and release

- Cross-platform testing, targeted WPT evaluation, fuzzing of custom components, and security review.
- Packaging, signing, updates, recovery, and release documentation.
- Publish a transparent compatibility matrix and known-limitations page.

### Milestone 7 — Advanced research

- Evaluate PQC support based on current standards and upstream engine readiness.
- Consider advanced network policy features only where the engine provides safe hooks.
- Reassess whether any engine components should be replaced; avoid a from-scratch rendering effort without a dedicated team and long-term funding.

---

## Cursor Execution Protocol

Cursor should follow this protocol for every task:

1. **Inspect before editing.** Read the relevant source files and project instructions; identify existing patterns and dependencies.
2. **State the task narrowly.** Name the feature, files likely involved, acceptance criteria, and dependencies.
3. **Plan before broad changes.** For cross-cutting work, present a short implementation plan and identify risks.
4. **Preserve working code.** Prefer incremental modifications; do not overwrite whole files or regenerate the project without need.
5. **Implement in vertical slices.** Deliver a usable path through UI, state, persistence, and tests rather than adding disconnected placeholders.
6. **Verify.** Run the relevant build, lint, type-check, unit, and smoke tests. Report exact commands and outcomes; never claim a test passed if it was not run.
7. **Review security and privacy.** Check permissions, IPC, data storage, logging, origin boundaries, and failure behavior.
8. **Update documentation.** Keep README, architecture notes, feature status, and setup instructions aligned with actual implementation.
9. **Report honestly.** Summarize changes, files, verification, limitations, and the next recommended task.
10. **Stop at the milestone gate.** Do not silently proceed into unrelated phases or implement speculative features without confirming the architecture supports them.

### Required status format

For each milestone, maintain a table with:

| Feature/task | Status | Evidence | Remaining work |
|---|---|---|---|
| Example: session restore | Partial | Restores tabs on normal restart | Crash recovery and private-session exclusion |

Use only these statuses: `Not started`, `In progress`, `Partial`, `Complete`, `Blocked`, `Needs verification`.

---

## Recommended Reading & Resources

1. *How Browsers Work* by Tali Garsiel.
2. Chromium architecture and security documentation.
3. Web Platform Tests documentation.
4. NIST post-quantum cryptography standards and current implementation guidance.
5. Documentation for the chosen embedding engine, its process model, network hooks, permissions, and release/security policy.

## Final Product Definition

A successful first production release is a **secure, stable, maintainable desktop browser built on a proven rendering engine**, with a polished and accessible interface, reliable tab/workspace/session handling, transparent privacy controls, and a small set of differentiated features that are fully tested.

It is not necessary for V1 to implement a custom rendering engine, complete WebExtensions compatibility, custom TLS, universal offline execution, or every advanced feature listed here. Those are staged capabilities whose feasibility must be demonstrated before they become release commitments.
