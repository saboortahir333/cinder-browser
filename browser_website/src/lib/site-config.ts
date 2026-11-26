/**
 * Single source of truth for brand facts. Every claim here must match the
 * browser repo docs (README.md, PRIVACY.md, docs/implementation-status.md).
 */
export const site = {
  name: "Cinder Browser",
  short: "Cinder",
  url: "https://cinder.com",
  description:
    "Cinder Browser is a Windows desktop browser with tracker blocking, end-to-end encrypted sync, private profiles and Manifest V3 extensions. No analytics, ads or telemetry.",
  repo: "https://github.com/saboortahir333/cinder-browser",
  repoApi: "saboortahir333/cinder-browser",
  releases: "https://github.com/saboortahir333/cinder-browser/releases",
  installerName: "CinderBrowser_Setup.exe",
  requirements: "Windows 10 (1809+) or Windows 11, 64-bit",
} as const;

export const nav = [
  { href: "/features", label: "Features" },
  { href: "/privacy", label: "Privacy" },
  { href: "/download", label: "Download" },
] as const;
