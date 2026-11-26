import type { Metadata } from "next";
import { Suspense } from "react";
import { site } from "@/lib/site-config";
import { DownloadPanel } from "@/components/sections/download-panel";
import { Skeleton } from "@/components/ui/skeleton";
import { Mascot } from "@/components/brand/mascot";
import { Reveal } from "@/components/brand/reveal";

export const metadata: Metadata = {
  title: "Download",
  description: `Download ${site.name} for Windows. ${site.requirements}.`,
};

const ps = (text: string) => (
  <code className="block select-all overflow-x-auto rounded-xl border border-border bg-background/70 px-4 py-3 font-mono text-xs sm:text-sm">
    {text}
  </code>
);

export default function DownloadPage() {
  return (
    <div className="mx-auto max-w-4xl px-4 pt-14 sm:px-6 sm:pt-20">
      <div className="flex items-end justify-between gap-6">
        <div>
          <h1 className="text-5xl font-extrabold sm:text-6xl">
            Get <span className="text-flame">Cinder</span>
          </h1>
          <p className="mt-4 max-w-xl text-lg text-muted-foreground">
            One installer for Windows. It adds the Visual C++ runtime and the WebView2
            runtime for you if they are missing.
          </p>
        </div>
        <Mascot className="hidden w-40 shrink-0 sm:block" />
      </div>

      <div className="mt-10">
        <Suspense fallback={<Skeleton className="h-64 w-full rounded-[2rem]" />}>
          <DownloadPanel />
        </Suspense>
      </div>

      <div className="mt-10 grid gap-4 sm:grid-cols-2">
        <Reveal>
          <section className="h-full rounded-3xl border border-border bg-card/70 p-6" aria-labelledby="verify">
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
        </Reveal>

        <Reveal delay={0.08}>
          <section className="h-full rounded-3xl border border-border bg-card/70 p-6" aria-labelledby="trust">
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
        </Reveal>

        <Reveal>
          <section className="rounded-3xl border border-border bg-card/70 p-6 sm:col-span-2" aria-labelledby="platforms">
            <h2 id="platforms" className="text-xl font-bold">Other platforms</h2>
            <p className="mt-2 text-sm text-muted-foreground">
              Cinder is Windows-only for now. There are no macOS, Linux, Android or iOS builds
              yet, so we don&apos;t offer downloads for them.
            </p>
          </section>
        </Reveal>
      </div>
    </div>
  );
}
