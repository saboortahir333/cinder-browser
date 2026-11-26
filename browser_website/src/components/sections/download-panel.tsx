import { HugeiconsIcon } from "@hugeicons/react";
import { Download01Icon, ArrowUpRight01Icon } from "@hugeicons/core-free-icons";
import { getLatestRelease } from "@/lib/releases";
import { site } from "@/lib/site-config";
import { CtaLink } from "@/components/site/cta-link";

function formatMb(bytes: number) {
  return `${(bytes / 1024 / 1024).toFixed(1)} MB`;
}

function formatDate(iso: string) {
  return new Intl.DateTimeFormat("en-US", {
    dateStyle: "medium",
    timeZone: "UTC",
  }).format(new Date(iso));
}

export async function DownloadPanel() {
  const release = await getLatestRelease();
  const installer = release?.installer ?? null;

  return (
    <div className="relative overflow-hidden rounded-[2rem] border border-border bg-card/70 p-6 shadow-[0_40px_100px_-50px_var(--glow-a)] backdrop-blur sm:p-10">
      <div className="glow-orb pointer-events-none absolute -right-24 -top-24 size-80 rounded-full" aria-hidden="true" />

      <div className="relative">
        <p className="text-sm font-semibold uppercase tracking-wider text-primary">Windows</p>
        <h2 className="mt-2 text-3xl font-bold sm:text-4xl">Download {site.name}</h2>
        <p className="mt-3 max-w-xl text-muted-foreground">
          {release
            ? `Version ${release.version} · released ${formatDate(release.publishedAt)}${installer ? ` · ${formatMb(installer.sizeBytes)}` : ""}`
            : "We couldn't load the latest version number right now. The Releases page always has the newest installer."}
        </p>

        <div className="mt-7 flex flex-wrap items-center gap-4">
          {installer ? (
            <CtaLink href={installer.url}>
              <HugeiconsIcon icon={Download01Icon} size={20} />
              Download {installer.name}
            </CtaLink>
          ) : (
            <CtaLink href={release?.pageUrl ?? site.releases} target="_blank" rel="noopener noreferrer">
              <HugeiconsIcon icon={ArrowUpRight01Icon} size={20} />
              Open GitHub Releases
            </CtaLink>
          )}
          <p className="text-sm text-muted-foreground">{site.requirements}</p>
        </div>

        {installer?.sha256 && (
          <div className="mt-8">
            <p className="text-sm font-semibold">SHA-256</p>
            <p className="mt-1 select-all break-all rounded-xl border border-border bg-background/70 px-4 py-3 font-mono text-xs sm:text-sm">
              {installer.sha256}
            </p>
          </div>
        )}
      </div>
    </div>
  );
}
