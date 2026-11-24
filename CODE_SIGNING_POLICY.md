# Code signing policy

Free code signing for Cinder Browser is provided by [SignPath.io](https://signpath.io),
certificate by [SignPath Foundation](https://signpath.org).

## What is signed

Only release builds produced by the GitHub Actions workflow
[`.github/workflows/release.yml`](.github/workflows/release.yml) from this
repository: `saboor_browser.exe`, Cinder's own DLLs, and the installer
`CinderBrowser_Setup.exe`. Third-party binaries that are already signed by their
publishers (for example `WebView2Loader.dll` and the bundled Microsoft
redistributables) are not re-signed.

Nothing built on a developer's machine is submitted for signing.

## Roles

| Role | Who |
|---|---|
| Authors / committers | Orbit Tech and contributors who have had a pull request merged |
| Reviewers (approve every release) | Orbit Tech maintainers |
| Approvers (approve each signing request in SignPath) | Orbit Tech maintainers |

Each signing request requires manual approval by an approver.

## Privacy

Cinder does not send data to the signing service at run time. See
[PRIVACY.md](PRIVACY.md) for what the application itself does with network access.

## Reporting a problem with a signed build

Open an issue, or see [SECURITY.md](SECURITY.md) for vulnerabilities.
