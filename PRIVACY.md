# Privacy

Cinder is a desktop browser built on Microsoft Edge WebView2.

* **Guest mode** keeps everything in memory. Nothing is sent to Cinder's servers.
* **Signed-in mode** syncs bookmarks, history, settings and downloads list to the
  Cinder cloud (Supabase) **end-to-end encrypted** with a key derived from your
  passphrase. The server cannot read your data. See
  [docs/security-and-data-model.md](docs/security-and-data-model.md).
* **Private windows** write no history, session, cache or cookies to disk and do
  not sync.
* **Extensions** you install can see what their permissions allow; each shows a
  prompt first. Extensions are off in private windows unless you allow them.
* Cinder does not load favicons from third-party services.
* Installing extensions from a store contacts that store (Google or Microsoft).
* The WebView2 engine itself is Microsoft's; see Microsoft's privacy statement
  for engine-level behaviour.

Cinder does not include analytics or advertising.

## Update check
Once a day (not in private windows) Cinder asks GitHub's public API whether a
newer release exists (`api.github.com/repos/saboortahir333/cinder-browser/releases/latest`).
No account data is sent, and nothing is downloaded or installed automatically:
you are only told a new version exists and can open its release page. GitHub
sees your IP address and a `Cinder/<version>` user agent, as for any web request.
