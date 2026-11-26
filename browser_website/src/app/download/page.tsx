import type { Metadata } from "next";
import { Suspense } from "react";
import { site } from "@/lib/site-config";
import { DownloadPanel } from "@/components/sections/download-panel";
import { Faq } from "@/components/sections/faq";
import { Skeleton } from "@/components/ui/skeleton";
import { Mascot } from "@/components/brand/mascot";
import { Reveal } from "@/components/brand/reveal";
import { SpotlightCard } from "@/components/brand/interactions";

export const metadata: Metadata = {
  title: "Download",
  description: `Download ${site.name} for Windows. ${site.requirements}.`,
};

const steps = [
  { n: "1", title: "Download", body: `Get ${site.installerName} from the panel above. It is a single installer.` },
  {
    n: "2",
    title: "Run the installer",
    body: "It adds the Visual C++ runtime and the WebView2 runtime if your PC doesn't have them yet.",
  },
  { n: "3", title: "Open Cinder", body: "Start in guest mode, or sign in to turn on encrypted sync." },
];

const ps = (text: string) => (
  <code className="block select-all overflow-x-auto rounded-xl border border-border bg-background/70 px-4 py-3 font-mono text-xs sm:text-sm">
    {text}
  </code>
);

export default function DownloadPage() {
  return (
    <div className="relative isolate overflow-hidden">
      <div className="bg-grid absolute inset-0 -z-10" aria-hidden="true" />
      <div className="glow-orb absolute -top-32 left-1/2 -z-10 size-[700px] -translate-x-1/2 rounded-full" aria-hidden="true" />

      <div className="mx-auto max-w-4xl px-4 pt-14 sm:px-6 sm:pt-20">
        <div className="flex items-end justify-between gap-6">
          <div>
            <h1 className="text-5xl font-extrabold sm:text-6xl">
              Get <span className="text-flame">Cinder</span>
            </h1>
            <p className="mt-4 max-w-xl text-lg text-muted-foreground">
              One installer for Windows. Free of analytics, ads and telemetry.
            </p>
          </div>
          <Mascot className="hidden w-40 shrink-0 sm:block" />
        </div>

        <div className="mt-10">
          <Suspense fallback={<Skeleton className="h-64 w-full rounded-[2rem]" />}>
            <DownloadPanel />
          </Suspense>
        </div>

        <section className="mt-12" aria-labelledby="steps-title">
          <h2 id="steps-title" className="text-2xl font-bold sm:text-3xl">Install in three steps</h2>
          <ol className="mt-6 grid gap-4 sm:grid-cols-3">
            {steps.map((s, i) => (
              <li key={s.n}>
                <Reveal delay={i * 0.08} className="h-full">
                  <SpotlightCard className="card-lift h-full rounded-3xl border border-border bg-card/70">
                    <div className="p-6">
                      <span className="grid size-10 place-items-center rounded-full bg-flame font-display text-lg font-extrabold text-[#1c0a03] shadow-[0_8px_24px_-8px_var(--glow-a)]">
                        {s.n}
                      </span>
                      <h3 className="mt-4 text-lg font-bold">{s.title}</h3>
                      <p className="mt-1.5 text-sm leading-relaxed text-muted-foreground">{s.body}</p>
                    </div>
                  </SpotlightCard>
                </Reveal>
              </li>
            ))}
          </ol>
        </section>

        <div className="mt-10 grid gap-4 sm:grid-cols-2">
          <Reveal className="h-full">
            <SpotlightCard className="card-lift h-full rounded-3xl border border-border bg-card/70">
              <section className="p-6" aria-labelledby="verify">
                <h2 id="verify" className="text-xl font-bold">Verify your download</h2>
                <p className="mt-2 text-sm text-muted-foreground">
                  Run these in PowerShell from the folder with the installer. Compare the hash
                  with the SHA-256 above or on the release page.
                </p>
                <div className="mt-4 space-y-3">
                  {ps(`Get-FileHash .\\${site.installerName} -Algorithm SHA256`)}
                  {ps(`Get-AuthenticodeSignature .\\${site.installerName} | Format-List Status, SignerCertificate`)}
                </div>
              </section>
            </SpotlightCard>
          </Reveal>

          <Reveal delay={0.08} className="h-full">
            <SpotlightCard className="card-lift h-full rounded-3xl border border-border bg-card/70">
              <section className="p-6" aria-labelledby="trust">
                <h2 id="trust" className="text-xl font-bold">About Windows warnings</h2>
                <p className="mt-2 text-sm leading-relaxed text-muted-foreground">
                  Cinder&apos;s release pipeline is set up to sign installers through the free
                  SignPath Foundation program. If Windows SmartScreen shows &ldquo;Unknown
                  publisher&rdquo; for a build, that build is not signed yet. Check the SHA-256
                  above, or build from the open source code.
                </p>
                <a
                  href={`${site.repo}/blob/HEAD/CODE_SIGNING_POLICY.md`}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="mt-3 inline-block text-sm font-medium text-primary hover:underline"
                >
                  Read the code signing policy
                  <span className="sr-only"> (opens in a new tab)</span>
                </a>
              </section>
            </SpotlightCard>
          </Reveal>

          <Reveal className="sm:col-span-2">
            <section className="rounded-3xl border border-border bg-card/70 p-6" aria-labelledby="platforms">
              <h2 id="platforms" className="text-xl font-bold">Other platforms</h2>
              <p className="mt-2 text-sm text-muted-foreground">
                Cinder is Windows-only for now. There are no macOS, Linux, Android or iOS builds
                yet, so we don&apos;t offer downloads for them.
              </p>
            </section>
          </Reveal>
        </div>
      </div>

      <Faq />
      <div className="h-8" />
    </div>
  );
}
