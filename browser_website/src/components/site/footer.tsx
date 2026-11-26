import Link from "next/link";
import { site } from "@/lib/site-config";
import { EmberMark } from "@/components/brand/ember-mark";
import { MotionToggle } from "./motion-toggle";

const repoFile = (name: string) => `${site.repo}/blob/HEAD/${name}`;

const columns = [
  {
    title: "Cinder",
    links: [
      { label: "Features", href: "/features" },
      { label: "Download", href: "/download" },
      { label: "Release notes", href: site.releases, external: true },
    ],
  },
  {
    title: "Trust",
    links: [
      { label: "Privacy", href: "/privacy" },
      { label: "Security policy", href: repoFile("SECURITY.md"), external: true },
      { label: "Code signing policy", href: repoFile("CODE_SIGNING_POLICY.md"), external: true },
    ],
  },
  {
    title: "Open source",
    links: [
      { label: "Source code", href: site.repo, external: true },
      { label: "License (Apache-2.0)", href: repoFile("LICENSE"), external: true },
      { label: "Report an issue", href: `${site.repo}/issues`, external: true },
    ],
  },
];

export function Footer() {
  return (
    <footer className="relative mt-24 border-t border-border bg-card/40">
      <div className="mx-auto max-w-6xl px-4 py-14 sm:px-6">
        <div className="grid gap-10 md:grid-cols-[1.4fr_repeat(3,1fr)]">
          <div className="max-w-xs">
            <div className="flex items-center gap-2">
              <EmberMark className="h-10 w-9" glow={false} sparks={false} title="" />
              <span className="font-display text-2xl font-bold">{site.short}</span>
            </div>
            <p className="mt-4 text-sm leading-relaxed text-muted-foreground">
              A Windows browser that keeps your data to itself. Built on Microsoft
              Edge WebView2, with the privacy and sync layers built by Cinder.
            </p>
          </div>

          {columns.map((col) => (
            <nav key={col.title} aria-label={col.title}>
              <h2 className="font-sans text-sm font-semibold uppercase tracking-wider text-muted-foreground">
                {col.title}
              </h2>
              <ul className="mt-4 space-y-2.5">
                {col.links.map((l) => (
                  <li key={l.label}>
                    {"external" in l && l.external ? (
                      <a
                        href={l.href}
                        target="_blank"
                        rel="noopener noreferrer"
                        className="text-sm hover:text-primary"
                      >
                        {l.label}
                        <span className="sr-only"> (opens in a new tab)</span>
                      </a>
                    ) : (
                      <Link href={l.href} className="text-sm hover:text-primary">
                        {l.label}
                      </Link>
                    )}
                  </li>
                ))}
              </ul>
            </nav>
          ))}
        </div>

        <div className="mt-12 flex flex-col gap-2 border-t border-border pt-6 text-xs text-muted-foreground sm:flex-row sm:items-center sm:justify-between">
          <p>
            This website uses no analytics, no cookies and no third-party scripts.
            Your theme choice is stored only in your own browser.
          </p>
          <div className="flex flex-wrap items-center gap-4">
            <p>Cinder Browser is open source under the Apache License 2.0.</p>
            <MotionToggle />
          </div>
        </div>
      </div>
    </footer>
  );
}
