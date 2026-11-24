# Free code signing with SignPath Foundation

Goal: a signed `CinderBrowser_Setup.exe` that Windows Smart App Control allows,
at no cost. SignPath Foundation signs open-source projects for free.

## Eligibility (what they check)

* Public repository with an OSI-approved licence (Apache-2.0 is in `LICENSE`, attribution in `NOTICE`).
* Project is actively maintained, has releases, and is not malware/PUP.
* A code-signing policy and privacy statement are public
  (`CODE_SIGNING_POLICY.md`, `PRIVACY.md`, linked from the README).
* Builds come from CI (`.github/workflows/release.yml`) so SignPath can verify
  the binary was built from the repo.

## Steps (you do these; they need your accounts)

1. **Publish the repo** on GitHub (public). Before pushing, double-check no
   secrets: this repo only contains Supabase's public *anon* key; never push a
   `service_role` key. Make sure `supabase/001_secure_sync.sql` has been run on
   your project, because the anon key is only safe with row-level security on.
2. **Apply** at <https://signpath.org/apply> ("Open source" application). Give
   the repo URL, the README (it already contains the required attribution
   text), and say you build with GitHub Actions. Approval can take days.
3. In SignPath (after approval) create the project with slug `cinder-browser`.
   Add two **artifact configurations** by pasting
   `.signpath/artifact-configurations/release-files.xml` (slug `release-files`)
   and `installer.xml` (slug `installer`). Create the signing policy
   `release-signing` (manual approval by you).
4. Link GitHub as a trusted build system, create a **CI user**, and copy its
   API token.
5. In the GitHub repo: Settings → Secrets and variables → Actions:
   * secret `SIGNPATH_API_TOKEN`
   * variable `SIGNPATH_ORGANIZATION_ID`
6. Release: `git tag v1.0.0 && git push --tags`. The workflow builds, asks
   SignPath to sign the app binaries, builds the installer around them, signs
   the installer, verifies the signature, and attaches it to the GitHub release.
   You approve each signing request in the SignPath UI.

## Known limitations

* **The uninstaller is not signed.** Inno Setup embeds `unins000.exe` at
  compile time; signing it would need a SignPath request during the Inno
  compile. With Smart App Control on, *uninstalling* could be blocked even
  though installing works. Workarounds: ship a portable zip as well, or add a
  second pipeline stage that signs the uninstaller template.
* Until SignPath approves the project there is no way to sign for free; local
  builds (`tools/build_release.ps1`) stay unsigned unless you have your own
  certificate.
* Microsoft trusts the SignPath Foundation certificate, but a brand-new
  publisher can still see SmartScreen reputation warnings for a while (Smart
  App Control itself decides by signature).
