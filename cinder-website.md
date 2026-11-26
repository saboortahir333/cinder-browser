# Cinder Website: Master Plan

Plan for the public website of **Cinder Browser**, the Windows desktop browser built with Flutter and WebView2.

Target: `cinder-browser/browser_website/`. It already holds a fresh Next.js scaffold with no real content.

Companion docs: `CINDER_MASTER_PLAN.md` (browser roadmap), `docs/implementation-status.md`, `PRIVACY.md`, `CODE_SIGNING_POLICY.md`.

---

## 0. Summary

| | |
|---|---|
| **Goal** | A fast, accessible, honest site whose first job is to get a Windows user to download, install and trust Cinder. |
| **Reference** | The Firefox site (firefox.com, which mozilla.org/firefox now redirects to). We borrow its structure and discipline, not its look or its claims. |
| **Stack (already in repo)** | Next.js 16.4.6 App Router, React 19.3, Tailwind CSS 4.3, shadcn/ui (`base-maia` style on `@base-ui/react`), `motion`, `next-themes`, `react-hook-form` + `zod`, `sonner`. |
| **Hosting** | Vercel is the default for this stack. A static export to GitHub Pages is the fallback (see §6.5). |
| **Download source** | The `CinderBrowser_Setup.exe` asset on GitHub Releases (repo `saboortahir333/cinder-browser`). Releases are built and signed by `.github/workflows/release.yml`. |
| **Biggest risks** | There are no product screenshots (§4.4), and the brand color conflicts with the browser UI (§3.3). Marketing copy could also overclaim, and the installer is still unsigned (§9). |
| **Phases** | 0 Foundations, 1 Brand and design system, 2 Core pages, 3 Trust pages, 4 Content and docs, 5 Quality, 6 Launch, 7 Post-launch. |

---

## 1. What the research found

### 1.1 Firefox: how the site is built and organised

Sources: [firefox.com](https://www.firefox.com/en-US/), the [Windows download page](https://www.firefox.com/en-US/browsers/desktop/windows/), [Mozilla Protocol](https://protocol.mozilla.org/), [mozilla/bedrock](https://github.com/mozilla/bedrock) and [mozilla.org "About this site"](https://www.mozilla.org/about/this-site/).

**Stack.** mozilla.org (Bedrock) is Django with Jinja templates, a Wagtail CMS, the Protocol design system for the front end, and Fluent for localization. Firefox needs this scale because it ships in about 90 languages with a large content team. Cinder does not, so we use a lighter stack that keeps the same ideas: a reusable component system, content separate from layout, and localization-ready structure.

**Homepage anatomy** (as read this session). The page is a long single-column landing page of alternating full-width bands.

1. A dismissible announcement bar for the current promotion.
2. A hero with a kicker ("The independent browser"), a headline about protection ("Built to protect you, not track you"), one subhead, and the primary CTA ("Try Firefox"). Store badges sit beside it for mobile.
3. Honest platform notices, for example unsupported OS versions with a fallback download.
4. Product mockups, desktop and mobile.
5. Value bands, each one idea: privacy by default, optional AI, focus features, independence, fast switching.
6. A three-step "switch" walkthrough: download, choose what to import, click import.
7. A sync band, an extensions band, a data-protection statement, and a newsletter form.
8. A repeated download CTA, then the footer.

**Download page anatomy** (Windows). It has an OS switcher (Windows, macOS, Linux, Android, iOS, Chromebook) and one hero with one primary button ("Download Now") plus a Privacy Notice link. Below that come four feature cards (kicker, heading, one line) and a link to "See all features".

**Navigation.** The header has three menus: the browser (Mobile, Enterprise, What's New, Extensions, Support), Features, and Resources (data protection, blog, release notes). The right side has a persistent "Get Firefox" button.

**Footer.** It has Download (per OS plus Nightly and Beta), For Business, Community, Resources, social links and a legal block (Privacy Notice, Terms, Cookie Policy, Community Participation Guidelines, trademark). It ends with a tagline.

**Lessons we adopt**

| Firefox practice | Cinder adaptation |
|---|---|
| One primary action per page (download) | Every page ends in a download block. The download page has nothing else competing with it. |
| Kicker, headline and one-line body as the unit of copy | A `FeatureBand` component with exactly those three slots. |
| Light and dark product screenshots | We capture both themes of the real browser (it has high-contrast and dark support). |
| Plain-language OS support notices | A "Windows 10 1809+ / 11, 64-bit" notice with the VC++ and WebView2 runtime note, so installer behaviour isn't a surprise. |
| Release notes, channels and a "What's New" page | `/changelog` generated from GitHub Releases. Beta/nightly later, if they exist. |
| A data-protection page linked from the hero | `/privacy` and `/security` are prominent, because privacy is Cinder's pitch (§1.3). |
| A real legal footer | Privacy, Code Signing Policy, License (Apache-2.0), Security policy, Trademark and name use. |
| Localization built in | Routes and copy are structured for `next-intl` later. English only at launch. |

**Limits of this research.** The page text came back without visuals. Colors, type scale, spacing and motion on firefox.com are not confirmed, so none of them are copied or assumed. Design decisions in §3 come from Cinder's own assets.

**What we will not copy**

- Firefox's "independent browser" and "nonprofit-backed" claims. Cinder renders with Microsoft's WebView2 (Chromium), so it is not an independent engine. The honest story is *a privacy-hardened shell around a mainstream engine*.
- Firefox's AI, VPN and mobile messaging. Cinder is Windows-only today.
- Any claim of parity with Firefox, Chrome or Edge.

### 1.2 What the Cinder repo gives us

| Area | Finding | Source |
|---|---|---|
| Product | Windows desktop browser. Flutter UI, Rust (Brave `adblock`) for filter matching, C++ bridge for WebView2 and MV3 extensions. Version `1.1.0+2`. | `README.md`, `pubspec.yaml`, `docs/implementation-status.md` |
| Selling points that exist | Private windows and separate profiles. End-to-end encrypted sync (Supabase, key derived from a passphrase). Manifest V3 extensions with permission prompts. HTTPS-only mode, tracker and ad blocking, per-site permission prompts. High-contrast and keyboard-only support. Firefox-style UI. No analytics, ads or telemetry. | `README.md`, `PRIVACY.md` |
| Distribution | `CinderBrowser_Setup.exe` (Inno Setup) on GitHub Releases. It installs VC++ and WebView2 if missing. Windows 10 1809+ or 11, x64. | `README.md`, `installer.iss`, `release.yml` |
| Signing | SignPath Foundation (free OSS signing). The release workflow signs app binaries, then the installer. It is gated on `SIGNPATH_ORGANIZATION_ID`, so it only runs once SignPath is configured. | `release.yml`, `CODE_SIGNING_POLICY.md` |
| Other artifacts at repo root | `CinderBrowser.cer` and `CinderBrowser_noshields.msix` (alternate install paths). `Install-Cinder.ps1` is an install helper. All three need a decision before they are linked publicly (§9). | repo root |
| Legal and trust docs already written | `PRIVACY.md`, `SECURITY.md`, `CODE_SIGNING_POLICY.md`, `LICENSE` (Apache-2.0), `NOTICE`, and `docs/` (security and data model, threat model, extensions and accessibility, signing). | repo |
| Network behaviour to disclose accurately | The daily update check calls the GitHub releases API and downloads nothing automatically. Filter lists (EasyList, EasyPrivacy, URLhaus) are fetched about weekly. Extension installs contact the Chrome or Edge stores. Sync uses Supabase. | `PRIVACY.md` |
| Known gaps (do not market as features) | No extension management UI yet. No tab groups or workspaces. No devtools. No offline mode. The last known release build had failed and needed a re-run. | `docs/implementation-status.md` |

### 1.3 Positioning that follows

- **One-line pitch (working):** *A Windows browser that keeps your data yours: encrypted sync, tracker blocking, private profiles and real extensions, with no telemetry.*
- **Audience:** Windows users who want Chromium compatibility with stronger privacy defaults. Secondary audiences are open-source contributors and security-minded reviewers.
- **Honesty rules for all copy:** state the engine (WebView2/Chromium) plainly. Say "end-to-end encrypted sync", not "unhackable". Label unbuilt features as roadmap. Every privacy claim must match `PRIVACY.md`. The website is checked against it before each release (§8).

---

## 2. Analysis of the existing `browser_website/` codebase

**State: a scaffold only.** `src/app/page.tsx` renders "Hello world!", and `layout.tsx` still has the default metadata ("Create Next App"). There is no `public/` directory, so no logo, favicon or OG image. There is no content.

### 2.1 Stack

| Layer | Package / setting | Notes |
|---|---|---|
| Framework | `next 16.4.6`, `react 19.3.0` | `AGENTS.md` says this Next.js has breaking changes versus common knowledge. **Read `node_modules/next/dist/docs/` before writing framework code.** The plan below follows those docs where checked, and flags the rest. |
| Rendering config | `cacheComponents: true`, `partialPrefetching: true` | Cache Components mode. Per the bundled docs, async data is cached with `'use cache'`. Request-time data goes inside `<Suspense>` or the dev overlay raises a "blocking-route" insight. Partial Prefetching only works with `cacheComponents` on. |
| Styling | Tailwind CSS `4.3.3` via `@tailwindcss/turbopack`, `tw-animate-css`, `shadcn/tailwind.css` | CSS-first config (`@theme inline` in `globals.css`). There is no `tailwind.config`. The custom Turbopack rule in `next.config.ts` pipes `*.css` through the Tailwind loader. |
| Components | shadcn `base-maia` style on `@base-ui/react` | 20 primitives are already generated under `src/components/ui/`: accordion, alert, avatar, badge, button, card, checkbox, dialog, dropdown-menu, input, label, select, separator, sheet, skeleton, switch, table, tabs, textarea, tooltip. |
| Icons | `@hugeicons/react` + `@hugeicons/core-free-icons` (declared in `components.json`), plus `lucide-react` | Two icon libraries are installed. |
| Motion | `motion 14` | Not used yet. |
| Theming | `next-themes`, `.dark` class variant | Dark variables exist, but there is no `ThemeProvider` mounted. |
| Forms | `react-hook-form`, `@hookform/resolvers`, `zod 4` | Not used yet. Future uses: a contact or bug-report form, and a newsletter form if we ever add one. |
| Toasts | `sonner` | Not mounted yet. |
| Font | Figtree via `next/font/google` | Set as `--font-sans`. |
| Lint, types | ESLint 9 with `eslint-config-next`, TypeScript 5 | |
| Path alias | `@/*` to `src/*` | |

### 2.2 Problems and decisions found in the scaffold

1. **Theme tokens are the neutral gray shadcn defaults.** There is no Cinder brand color. They need replacing (§3.2).
2. **`--font-heading` and `--font-sans` reference themselves** in `@theme inline`. This is the generator's output and is worth verifying at build time. Fix it if fonts don't resolve.
3. **The `cn` package is intentional.** It is shadcn's own compiled class-name merger (a drop-in for `clsx` + `tailwind-merge`). `src/lib/utils.ts` re-exports it and the generated components import it. Keep it. (An earlier draft of this plan wrongly called it a mistake.) `clsx` and `tailwind-merge` are then redundant and can be dropped once nothing imports them.
4. **Two icon libraries.** Pick one. Hugeicons matches `components.json`, so keep it and drop `lucide-react` unless a generated component needs it.
5. **`shadcn` (the CLI) is in `dependencies`.** It belongs in `devDependencies`, or it should be run with `npx`.
6. **No `ThemeProvider` or `Toaster`.** Both are needed in `layout.tsx`.
7. **`next.config.ts` has no image, header or redirect config.** Security headers and the CSP go here (§6.6).
8. **No tests, no CI.** Added in Phase 5.
9. **The website lives inside the app repo** (`cinder-browser/browser_website/`). CI needs path filters so website changes don't trigger the Flutter release pipeline, and the reverse. `node_modules/` and `.next/` must stay out of any app tooling and any Flutter packaging.

### 2.3 Assets inventory

| Asset | Location | Verdict |
|---|---|---|
| Logo mark, SVG | `cinder-mark.svg` | Usable. It is an ember/flame built from two petals and a glow, using the gradient `#8a1f0f` to `#d84315` to `#ff8a3d` to `#ffd27a`. **It carries about 8 KB of embedded C2PA provenance metadata** (an AI-tooling manifest). Strip it with SVGO for the web, and decide deliberately whether to keep any provenance. Canvas is 800×800. |
| Logo mark, PNG | `cinder-mark-transparent.png`, `assets/newtab/cinder-mark.png` | Fine as a fallback. Check dimensions before using it for OG images or favicons. |
| App icon | `windows/runner/resources/app_icon.ico` | Source for favicon sizes (16, 32, 48). |
| Browser UI tokens | `assets/newtab/home.css` | Light: bg `#F9F9FB`, text `#1C1B22`, muted `#5B5B66`, border `#E0E0E6`, accent `#0060DF`. Dark: bg `#1C1B22`, surface `#2B2A33`, accent `#7FB3FF`. System font stack. Pill radius 999px, tile radius 12px. |
| Product screenshots | **None in the repo** | **Biggest asset gap.** Needed: new tab page, tabs and omnibox, private window, extension popup, permission prompt, sync sign-in, settings, both themes, plus a high-contrast shot. Plan in §4.4. |
| Wordmark | **None** (the new tab page renders text, 28px / 600) | Needs a proper lockup. |
| OG / social image | None | Create in Phase 1. |
| Installer, signed files | `Output/`, `CinderBrowser.cer`, `CinderBrowser_noshields.msix` | Not website assets. See the distribution decisions in §9. |
| Copy and legal text | `README.md`, `PRIVACY.md`, `SECURITY.md`, `CODE_SIGNING_POLICY.md`, `docs/*.md` | **Single source of truth for claims.** The site renders or adapts these rather than rewriting them from memory (§6.4). |

---

## 3. Brand and design direction

### 3.1 Principles

1. **Calm and trustworthy.** A privacy product loses credibility with noise. No dark patterns and no fake urgency.
2. **Ember as the signature.** Warm, small amounts of color against a quiet neutral base. The mark is the brand's one illustration.
3. **Show the real product.** Real screenshots only. Never invented UI.
4. **Readable first.** WCAG 2.2 AA is the floor, because the browser itself claims accessibility support.
5. **Fast.** Mostly static, little JavaScript, no layout shift.

### 3.2 Color

Replace the grayscale tokens in `globals.css` with an ember-derived palette, expressed in OKLCH like the current tokens.

- **Neutrals:** keep the structure of the existing neutrals, but warm them very slightly toward the logo's red so the page reads as one system.
- **Brand accent:** derive from the logo mid-stop `#d84315`. Pick an accessible text-safe variant and a lighter variant for dark mode. Verify contrast ≥ 4.5:1 for body-size text on both surfaces. The raw gradient stops are for illustration and large glows, not for text.
- **Gradient:** `#8a1f0f` → `#d84315` → `#ff8a3d` → `#ffd27a`. Use sparingly: hero glow and one accent per section.
- **Focus ring:** a clearly visible, high-contrast ring (≥ 3:1 against adjacent colors) on all interactive elements.
- **Semantic colors:** keep shadcn's `destructive`, and add `success` and `warning` for status messaging (for example the download and signature status).

### 3.3 Decision needed: brand accent vs. browser accent

The browser's own UI accent (`home.css`) is **Firefox blue `#0060DF`**, while the logo is ember orange-red. On the site we have to pick one dominant accent. **Recommendation:** the site uses ember. Product screenshots will still show the blue UI accent, so use them framed on neutral backgrounds and avoid placing blue UI next to ember CTAs without separation. Longer term, consider moving the browser accent to ember so the product and site match (this is a product decision, tracked in §9).

### 3.4 Typography and layout

- **Type:** keep **Figtree** (already wired through `next/font`, self-hosted by Next at build time, which avoids a runtime request to Google). Define a type scale with clamp-based fluid sizes. Headings 600–700, body 400. Use `font-display: swap`.
- **Layout:** a 12-column container with a max width near 1200px, and generous vertical rhythm (the alternating bands from §1.1). Mobile-first, with 16px gutters and no horizontal scroll.
- **Shape:** the pill and 12px-radius language from the browser UI, mapped onto the `--radius` token (currently 0.625rem).
- **Motion:** subtle. Fade and rise on scroll, and a slow ember glow in the hero, built with `motion`. Respect `prefers-reduced-motion` (the browser's own new tab page already does this) and disable all non-essential animation under it.
- **Dark mode:** system default via `next-themes`, with a manual toggle in the footer or header. Provide dark and light screenshot variants and swap with CSS (`<picture>` or paired images), not JS.

### 3.5 Logo, favicon and share assets (Phase 1 deliverables)

- Clean SVG mark (metadata stripped), plus a horizontal lockup (mark + "Cinder" wordmark in Figtree).
- Favicon set from `app_icon.ico` and the SVG: `icon.svg`, `favicon.ico`, `apple-touch-icon.png`, via Next's `app/` metadata file conventions.
- 1200×630 OG and Twitter images (a static default, plus per-page images later).
- A one-page brand and press kit at `/brand` (logo downloads, colors, usage rules, a trademark note).

---

## 4. Information architecture and page plan

### 4.1 Sitemap

```
/                      Home
/download              Download (Windows hero, system requirements, checksums, install help)
/features              Overview
  /features/privacy      Tracker blocking, HTTPS-only, private windows
  /features/sync         End-to-end encrypted sync (how it works, in plain terms)
  /features/extensions   MV3 extensions, permission prompts
  /features/accessibility High-contrast, keyboard-only
/security              Security overview + link to threat model and SECURITY.md
/privacy               Privacy policy (mirrors PRIVACY.md) + network behaviour table
/code-signing          Code signing policy (SignPath Foundation requirement)
/changelog             Release notes from GitHub Releases
/docs                  Getting started, install, uninstall, profiles, sync setup, extensions, troubleshooting
/roadmap               What's built, what's next (from implementation-status.md)
/open-source           License (Apache-2.0), repo link, contributing, third-party notices
/support               FAQ, bug reports (links to GitHub Issues), contact
/about                 Who builds it and why
/brand                 Logo, colors, press kit
/legal/terms           Terms (site and download)
/not-found             Custom 404
```

Phase 2 builds `/`, `/download` and `/features`. The rest follow in Phases 3 and 4. Nothing in the nav links to a page that doesn't exist yet.

### 4.2 Navigation

- **Header:** logo; *Features* (menu: Privacy, Sync, Extensions, Accessibility); *Security*; *Docs*; *Changelog*; a persistent **Download** button. On mobile it uses the existing `Sheet` component as a drawer.
- **Footer:** Download (Windows, release notes, system requirements, checksums); Product (Features, Roadmap, Changelog); Trust (Privacy, Security, Code Signing Policy, Open Source); Support (Docs, FAQ, Issues); and a legal row (Terms, Privacy, License, Brand). A theme toggle goes in the footer. The tagline matches the final positioning.
- **Announcement bar (optional):** a dismissible slot for release news, using `sessionStorage` or a cookie-less approach.

### 4.3 Home page spec (modeled on the Firefox structure)

1. **Hero:** kicker ("A private browser for Windows"), headline, one-sentence subhead, the primary **Download for Windows** button plus a secondary "See what's inside" link, and a note ("Windows 10 1809+ / 11, 64-bit · v{latest}"). Visual: the hero screenshot over the ember glow.
2. **Trust strip:** four short facts (no telemetry, end-to-end encrypted sync, open source (Apache-2.0), signed installer) each linking to its explanation. The signed-installer fact only appears once signing is real (§9).
3. **Value bands (alternating, one idea each):** tracker and ad blocking; private windows and profiles; encrypted sync; real extensions (MV3); accessibility.
4. **Honest "how it works" band:** a short, plain statement that Cinder renders pages with Microsoft's WebView2 (Chromium), with Cinder adding the privacy and sync layers. This is the replacement for Firefox's independence band, and it builds trust by being direct.
5. **"Switch in minutes" three-step walkthrough:** install, import (only if the product supports it, or leave it out), sign in to sync. Adapt the steps to what the product does today.
6. **Open-source band:** repo link and license.
7. **Final download block, then footer.**

### 4.4 Screenshot and capture plan

The repo has no screenshots. They are a dependency for Phases 1–2, so schedule them first.

- Capture from a **release build** on a clean Windows profile at 100% and 150% scaling, with realistic but non-personal sample content.
- Required set: new tab page, tabbed browsing with the omnibox, private window, extension popup, permission prompt, sync sign-in, settings, and a high-contrast shot. Each is captured in light and dark.
- Automate where possible: `integration_test/` already has fixtures (`fixtures/site`, `fixtures/sample_ext`), so extend it to take screenshots, which keeps captures reproducible and refreshable per release.
- Deliver as WebP and AVIF at 1x and 2x, with explicit width and height to prevent layout shift. Add real alt text.
- Until they exist, pages use a clearly marked placeholder component. Never ship invented UI mock-ups as if they were the product.

---

## 5. Download experience (the most important page)

- **OS detection** (client-side, progressive): show the Windows build as the primary button on Windows. On macOS, Linux and mobile, show **"Cinder is Windows-only for now"** with a "notify me" option only if we decide to collect email (§9). Never offer a download that won't run. Firefox's OS switcher is a model for the layout, but we don't list platforms we don't ship.
- **Latest version:** fetch the latest release from the GitHub API and cache it with `'use cache'` plus a time-based revalidation (for example 10–15 minutes), per the Cache Components model in the bundled docs. On API failure, fall back to a static link to the Releases page, so the download never breaks.
- **Link target:** the `CinderBrowser_Setup.exe` asset of the latest release. Validate that the asset exists before showing a direct link.
- **Beside the button:** version, release date, file size, SHA-256 checksum, a link to the release notes and a link to the Privacy page. Add a "verify your download" help section (PowerShell `Get-FileHash` and `Get-AuthenticodeSignature` commands, shown as copyable code blocks).
- **Requirements and notes:** Windows 10 1809+ / 11, 64-bit. Say that the installer adds the VC++ runtime and WebView2 runtime when missing. Explain the SmartScreen warning honestly while the installer is unsigned or has low reputation (§9).
- **Install help:** short steps, uninstall steps, and the location of user data (from `docs/security-and-data-model.md`).
- **Alternative installs** (MSIX, certificate, script) appear only if they are supported and documented (§9). Otherwise leave them off the page.

---

## 6. Technical architecture

### 6.1 Rendering strategy

Because `cacheComponents` is enabled, build the site as a **static shell with small dynamic islands**.

- Marketing pages, features, legal, docs and brand are fully static (prerendered).
- Dynamic or time-dependent data (latest release, changelog) uses `'use cache'` with revalidation. Anything truly request-time goes inside `<Suspense>` with a skeleton fallback (the `Skeleton` component exists).
- Verify each rendering assumption against `node_modules/next/dist/docs/` (for example `01-app/01-getting-started/08-caching.md` and the Partial Prefetching guide) while building. This version differs from older Next.js.
- Prefer Server Components. Client components only where needed: theme toggle, mobile menu, OS-aware download button, copy-to-clipboard, animation wrappers.

### 6.2 Proposed folder structure

```
browser_website/
  public/                    logo, favicons, og, screenshots (optimised), robots, no third-party scripts
  content/                   MDX: docs/, changelog fallbacks, legal drafts synced from repo docs
  src/
    app/
      (marketing)/           home, features, roadmap, about, brand, open-source
      download/
      docs/[[...slug]]/
      changelog/
      security/ privacy/ code-signing/ support/ legal/
      sitemap.ts  robots.ts  manifest.ts  opengraph-image.tsx
      layout.tsx  globals.css  not-found.tsx
    components/
      ui/                    existing shadcn primitives
      site/                  Header, Footer, AnnouncementBar, ThemeToggle, MobileNav
      sections/              Hero, FeatureBand, TrustStrip, Steps, DownloadBlock, CtaBand
      media/                 AppScreenshot (light/dark picture), EmberGlow
    lib/
      utils.ts  site-config.ts  releases.ts  seo.ts  content.ts
    hooks/
  tests/                     Playwright specs, a11y checks
```

### 6.3 Dependencies

- **Add (when each phase needs it):**
  - MDX for docs: `@next/mdx`, or `next-mdx-remote` with `gray-matter`.
  - `rehype-pretty-code` or `shiki` for code blocks.
  - `@playwright/test` and `@axe-core/playwright`.
  - Lighthouse CI.
  - `sharp` (installed with Next.js when needed) for images.
  - `next-intl` only when localization starts.
- **Remove or tidy:** one of the two icon libraries, and moving `shadcn` to devDependencies (§2.2).
- **No analytics or tag-manager dependency.** See §6.7.

### 6.4 Content and the "single source of truth" rule

- Privacy, security, code-signing and license text derive from the repo docs (`PRIVACY.md`, `SECURITY.md`, `CODE_SIGNING_POLICY.md`, `docs/*.md`). Either import them at build time (a script copies them into `content/`) or maintain the website versions with a "last reviewed against the repo on <date>" line and a CI check that fails when the source docs change without a website update.
- The roadmap page derives from `docs/implementation-status.md`.
- Release notes come from GitHub Releases through `lib/releases.ts`.
- All brand facts (name, version, requirements, repo URL, support links) live in one `site-config.ts`, so changing a fact is a one-file change.

### 6.5 Hosting and deployment

- **Default:** Vercel. It runs Next.js 16 and Cache Components with no extra setup, has preview deployments per PR, and has a custom domain with managed HTTPS.
- **Fallback:** a fully static export to GitHub Pages or Cloudflare Pages. This would lose runtime revalidation (the download page would use build-time version data plus a client-side fetch or a redeploy on each release). If we choose it, the release workflow triggers a site rebuild.
- **Domain:** to be decided (§9). Set up `www` to apex redirects and HSTS once the domain exists.
- **Release hook:** publishing a GitHub Release should trigger a website revalidation or rebuild, so the version, checksum and changelog update promptly.

### 6.6 Security headers

Configure in `next.config.ts` (`headers()`) and verify with a scanner:

- `Content-Security-Policy`: `default-src 'self'`, no third-party script hosts, `img-src 'self' data:`, `frame-ancestors 'none'`, and a nonce or hash strategy for any inline script (check the bundled Next docs for the supported CSP approach).
- `Strict-Transport-Security`, `X-Content-Type-Options: nosniff`, `Referrer-Policy: strict-origin-when-cross-origin`, `Permissions-Policy` (deny everything unused), `X-Frame-Options` or `frame-ancestors`.
- A `/.well-known/security.txt` that points to the `SECURITY.md` reporting process.
- Ship no secrets. The website needs none, because the GitHub releases API is public. Add a token only if rate limits demand it, and keep it server-side only.

### 6.7 Analytics and cookies

Cinder markets "no telemetry". **The site should match.** Default: **no analytics and no cookies**, which also means no cookie banner (Firefox needs one, we don't). If usage data becomes necessary, use a cookieless, self-hosted or privacy-first tool, disclose it on `/privacy`, and honor Do Not Track. Download counts are available from GitHub for free.

### 6.8 SEO and sharing

- Per-page `metadata` (title template, description, canonical URL, OG and Twitter cards), replacing the "Create Next App" defaults.
- `sitemap.ts`, `robots.ts`, `manifest.ts`.
- JSON-LD: `SoftwareApplication` (Windows, version, license, download URL) and `Organization`.
- Clean, stable URLs and one H1 per page.

### 6.9 Accessibility and internationalization

- WCAG 2.2 AA is the target. Use semantic landmarks, a skip-to-content link, visible focus, full keyboard operability, accessible names on icon buttons, sufficient target sizes, and text alternatives for every screenshot.
- Verify with axe in CI plus a manual keyboard pass and a screen-reader pass (Narrator or NVDA) on the home and download pages.
- i18n is out of scope for launch, but write copy and routes so `next-intl` can be added without a rewrite: no hard-coded copy inside deeply nested components, and a `lang` attribute driven from config.

---

## 7. Phases

Estimates assume one developer working on the website part-time.

### Phase 0: Foundations (2–3 days)
- Read the relevant bundled Next.js docs (`node_modules/next/dist/docs/`).
- Fix the scaffold: real metadata, `ThemeProvider`, `Toaster`, `public/` assets (placeholder logo and favicon), choose one icon library, move the `shadcn` CLI to devDependencies.
- Confirm `next build`, `next lint` and `tsc --noEmit` pass.
- Add `site-config.ts`.
- Decide the open questions in §9 that block design: domain, accent color, screenshots owner.
- **Exit gate:** the scaffold builds cleanly and deploys as a preview.

### Phase 1: Brand and design system (1 week)
- Final logo (stripped SVG), lockup, favicon set and OG image.
- Ember palette in `globals.css`, both themes, with documented contrast ratios.
- Type scale, spacing and radius tokens.
- Core site components: Header, Footer, MobileNav, ThemeToggle, Button variants, `FeatureBand`, `DownloadBlock`, `AppScreenshot`.
- A hidden `/design` page (not linked, `noindex`) for reviewing components in both themes.
- **Exit gate:** the component gallery passes axe in light and dark, and the contrast table is complete.

### Phase 2: Core pages (1–1.5 weeks)
- Home (§4.3), Download (§5, working with the live release data and the fallback), Features overview.
- Screenshot capture (§4.4) completes in this phase, with placeholders only as a temporary measure.
- **Exit gate:** a Windows user can land, understand the product and download the installer, and the flow works with the GitHub API both up and down.

### Phase 3: Trust pages (1 week)
- `/privacy` (aligned to `PRIVACY.md`, including the network-behaviour table), `/security` (summary of the threat model, with a link to `SECURITY.md`), `/code-signing` (required by SignPath Foundation), `/open-source`, and `/legal/terms`.
- `security.txt`.
- **Exit gate:** every claim on these pages traces to a repo document. A reviewer signs off on the copy against the code (§8).

### Phase 4: Content and docs (1–2 weeks)
- Feature subpages (privacy, sync, extensions, accessibility).
- MDX docs: install, uninstall, profiles and private windows, sync setup, extensions, troubleshooting.
- `/changelog` from GitHub Releases, `/roadmap` from the status doc, `/support`, `/about`, `/brand`.
- **Exit gate:** no dead links, and all docs match the shipped version.

### Phase 5: Quality (3–5 days)
- Playwright tests for key flows: nav, theme toggle, download page with a mocked releases API, the not-found page.
- axe checks per route, Lighthouse CI budgets, a link checker, and a spell and claim check.
- Cross-browser pass (Chromium, Firefox, WebKit) at mobile, tablet and desktop widths, plus keyboard and reduced-motion passes.
- GitHub Actions: lint, types, build, tests on PRs, with path filters (§2.2 item 9).
- **Exit gate:** CI is green and the budgets in §8 are met.

### Phase 6: Launch (2–3 days)
- Domain, DNS, HTTPS and HSTS. Production environment variables, if any.
- Redirect map, sitemap submission, and a final read-through against `PRIVACY.md`.
- Wire the release workflow to refresh the site.
- Announce only after the installer's trust story is true (§9).
- **Exit gate:** production is live and monitored, and the rollback path is known.

### Phase 7: Post-launch
- Fix what real users hit. Review the download funnel using GitHub download counts.
- Add beta and nightly channels if they exist. Add `next-intl` and a first extra language if there is demand.
- Per-release routine: update version data, screenshots if the UI changed, the changelog and the claims check.

---

## 8. Quality bar and verification

| Area | Target |
|---|---|
| Performance (mobile, simulated 4G) | LCP < 2.0 s, CLS < 0.05, INP < 200 ms. Lighthouse Performance ≥ 95 on home and download. |
| Weight | Home route JS as small as practical (aim under about 150 KB gzipped), and every image has explicit dimensions. |
| Accessibility | Zero axe violations on every route. Lighthouse Accessibility = 100. Manual keyboard and screen-reader pass. |
| SEO | Lighthouse SEO ≥ 95, valid structured data, and a sitemap with no 404s. |
| Security | A- or better on a headers scanner, a CSP with no `unsafe-inline` for scripts, and `npm audit` clean at high severity. |
| Privacy | The network panel on any page shows requests only to our own origin (plus the GitHub API from the server side). No third-party scripts, fonts or trackers. |
| Claim accuracy | Each privacy, security and feature claim has a repo reference. Reviewed before every release. |
| Process | Every phase ends with its exit gate. Don't mark a phase done without running its checks and recording the output. |

---

## 9. Open decisions and risks

**Decisions needed from the project owner**

1. **Domain and site name:** which domain, and is the product name final (Cinder / "Cinder Browser")?
2. **Brand accent:** ember on the site and blue in the product, or move the product to ember too (§3.3)?
3. **Installer trust:** the SignPath step in `release.yml` only runs once configured. Until a signed installer exists, the site must say the installer is unsigned and explain SmartScreen. Do we launch before or after signing is live?
4. **Alternative installs:** do we publicly support the MSIX (`CinderBrowser_noshields.msix`), the certificate file and `Install-Cinder.ps1`, or keep them off the site? If the MSIX is public, document what "noshields" means.
5. **Email collection:** a newsletter or "notify me for other platforms" form means collecting personal data, which conflicts with the no-telemetry story unless it is handled carefully. Default: don't collect any.
6. **Hosting:** Vercel vs. a static host (§6.5).
7. **Who captures the screenshots and reviews the copy?**
8. **Logo provenance:** the SVG carries C2PA metadata from AI tooling. Decide whether the metadata should be removed for the web version and whether the logo needs a human-finalised version.

**Risks**

| Risk | Mitigation |
|---|---|
| Marketing overclaims (independence, "unbreakable", "faster than…") | The honesty rules in §1.3, the claim-to-source check in §8, and no comparison page until we can substantiate it. |
| Website promises features that aren't built (extension management UI, tab groups, devtools, offline mode) | Label them as roadmap, and derive the roadmap page from the status doc. |
| The download breaks (API rate limit, missing asset) | Cached release data plus a static Releases-page fallback, and a test with a mocked API outage. |
| This Next.js version differs from common knowledge | Read the bundled docs first and use the dev overlay insights. Prefer well-understood patterns for the core pages. |
| SmartScreen warnings scare users away | Honest install help, then signed releases and time. |
| Scope creep (blog, localization, comparisons) | These stay in Phase 7 and are not part of launch. |
| Docs go stale against releases | Docs live in the repo and are reviewed per release, and CI flags changed source docs. |
| Website and app repos interfere | CI path filters, and a separate deploy pipeline (§2.2 item 9). |

---

## 10. Immediate next steps

1. Answer the open decisions in §9 (domain, accent, installer trust, alternative installs).
2. Start Phase 0. Read the bundled Next.js docs first, then fix the scaffold and confirm it builds.
3. Schedule screenshot capture on a release build, since Phase 2 depends on it.
4. Build the Phase 1 design system, then the core pages.

---

## Appendix: sources

- Firefox: [firefox.com](https://www.firefox.com/en-US/), [Windows download page](https://www.firefox.com/en-US/browsers/desktop/windows/)
- Mozilla web stack: [Protocol design system](https://protocol.mozilla.org/), [mozilla/bedrock](https://github.com/mozilla/bedrock), [About mozilla.org](https://www.mozilla.org/about/this-site/)
- Cinder repo files cited in §1.2 and §2: `README.md`, `PRIVACY.md`, `SECURITY.md`, `CODE_SIGNING_POLICY.md`, `docs/*.md`, `pubspec.yaml`, `installer.iss`, `.github/workflows/release.yml`, `assets/newtab/home.css`, `cinder-mark.svg`, and everything under `browser_website/`
- Next.js 16 behaviour: the docs bundled in `browser_website/node_modules/next/dist/docs/`
