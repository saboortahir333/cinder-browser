import { cacheLife } from "next/cache";
import { site } from "./site-config";

export type Release = {
  tag: string;
  version: string;
  publishedAt: string;
  pageUrl: string;
  installer: {
    name: string;
    url: string;
    sizeBytes: number;
    sha256: string | null;
  } | null;
};

type GhAsset = {
  name: string;
  size: number;
  browser_download_url: string;
  digest?: string | null;
};

type GhRelease = {
  tag_name: string;
  published_at: string;
  html_url: string;
  assets?: GhAsset[];
};

/**
 * Latest GitHub release of the browser. Cached for minutes; returns null on any
 * failure so the download page can fall back to the Releases page.
 */
export async function getLatestRelease(): Promise<Release | null> {
  "use cache";
  cacheLife("minutes");

  try {
    const res = await fetch(
      `https://api.github.com/repos/${site.repoApi}/releases/latest`,
      { headers: { Accept: "application/vnd.github+json" } },
    );
    if (!res.ok) return null;
    const data = (await res.json()) as GhRelease;

    const assets = data.assets ?? [];
    const exe =
      assets.find((a) => a.name.toLowerCase() === site.installerName.toLowerCase()) ??
      assets.find((a) => a.name.toLowerCase().endsWith(".exe"));

    const digest = exe?.digest ?? null;

    return {
      tag: data.tag_name,
      version: data.tag_name.replace(/^v/i, ""),
      publishedAt: data.published_at,
      pageUrl: data.html_url,
      installer: exe
        ? {
            name: exe.name,
            url: exe.browser_download_url,
            sizeBytes: exe.size,
            sha256: digest?.startsWith("sha256:") ? digest.slice(7) : null,
          }
        : null,
    };
  } catch {
    return null;
  }
}
