# Cinder: data model and security design

## Principle
All user-owned data lives in the user's Supabase account, **end-to-end
encrypted on the device first**. The only things written to local disk are the
minimum the platform requires (inventory below). Guests (not signed in) keep
everything in memory only.

## Local data inventory (everything that touches disk)
| Data | Where | Why it must be local |
|---|---|---|
| Supabase session (refresh token) | OS secret store (Windows DPAPI via `lib/security/dpapi_secret_store.dart`) | Keeps the user signed in |
| Vault master key (optional cache) | OS secret store | Avoids retyping the sync passphrase each launch; cleared on sign-out |
| WebView2 profile (cookies, cache, site storage) | default folder / `%LOCALAPPDATA%\Cinder\Profiles\<id>\WebView2` | The Chromium engine cannot run without it |
| Private-window profile | `%TEMP%\cinder-private-<16 hex>` | Same; locked while open, deleted on exit, swept if a crash leaves it |
| Unpacked extension registry (folder paths) | SharedPreferences | Extension files are per-device by nature |
| Downloaded files | user-chosen folder | They are the user's files |

Not stored locally: history, bookmarks, searches, open tabs / session, closed
tabs, zoom levels, search-engine choice, theme, wallpaper, shortcuts, download
history, profile list.

## Cloud storage (Supabase)
* `synced_records` - one row per record: `ciphertext` + opaque `record_id`.
* `user_keys` - Argon2id parameters + the **wrapped** master key (and a second
  copy wrapped by the recovery key). No passphrase, no plaintext key.
* Every policy: `TO authenticated USING (user_id = auth.uid())`. `anon` has no
  access. Legacy tables are locked (deny-by-default) by `supabase/001_secure_sync.sql`.

## Cryptography (`lib/security/vault_crypto.dart`)
* Master key: 256 random bits per account, generated on device.
* KEK: Argon2id (19 MiB, t=2, p=1 minimum; stored with the bundle; ceilings
  prevent a hostile server forcing huge parameters).
* Records: AES-256-GCM, random 96-bit nonce, per-kind subkey via HKDF.
  AAD = user id | profile | kind | record id, so ciphertext cannot be moved
  between rows, kinds, profiles or users.
* Record ids: HMAC-SHA256 under a master-key subkey, so the server cannot test
  "did this user visit X".
* Recovery key: 160 random bits, shown once. Forgetting both the passphrase and
  the recovery key means the data is unrecoverable by design.

### What the server can still see (metadata)
Row counts per kind, ciphertext sizes, write timing, and the account e-mail.
It cannot read URLs, titles, tabs, searches or settings values.

## Browser hardening implemented
* `UrlPolicy` is the single gate for every address: default-deny scheme
  allowlist (http/https only; `file:` and `view-source:` only from trusted
  sources); `javascript:`, `data:`, `blob:`, `ms-msdt:`, `search-ms:` etc.
  blocked; control/bidi/zero-width characters stripped; `user:pass@host`
  blocked; IDN shown as punycode, mixed-script hosts flagged; length caps.
* Saved sessions / history / bookmarks are re-validated on load (cloud data is
  treated as untrusted); titles are sanitised.
* Page -> shell messages (context menu) are type/range/size checked.
* Find-in-page embeds the query only as a JSON literal; results parsed
  defensively.
* DevTools port is random per launch (was fixed `9222`) and loopback-only.
* Profile ids are `[a-z0-9_-]{1,32}` (no path traversal); private-dir deletion
  only ever targets a strictly named, non-link directory inside `%TEMP%`.

## One-time setup you must do
1. Run `supabase/001_secure_sync.sql` in the Supabase SQL editor.
2. Authentication -> Providers: enable Email, "Confirm email" ON, minimum
   password length 12, leaked-password protection ON, CAPTCHA/rate limits ON.
3. Do **not** run the old `supabase_*.sql` files (they are marked as unsafe).
4. Rotate the anon key if you ever shared builds before this fix (the old open
   policies exposed all data to anyone holding the key).

## Known limits / follow-ups
* Shell shortcuts (Ctrl+F, Ctrl+T, ...) only fire while Flutter has focus, not
  while the web page has native keyboard focus (pre-existing plugin behaviour).
* Tab "mute" and audio indicators, picture-in-picture and window fullscreen are
  not implemented yet.
* Page-initiated downloads and extensions still need their own threat review.
* DevTools on a random loopback port is a convenience trade-off; a hardened
  build should disable it.
* Not yet covered by tests: the Flutter UI wiring (sign-in dialog, tab-strip
  drag reorder) and the native C++ change were not exercised in a running app.
