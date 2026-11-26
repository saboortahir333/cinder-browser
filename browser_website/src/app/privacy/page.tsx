import type { Metadata } from "next";
import { site } from "@/lib/site-config";
import { Reveal } from "@/components/brand/reveal";
import { SpotlightCard } from "@/components/brand/interactions";

export const metadata: Metadata = {
  title: "Privacy",
  description:
    "What Cinder Browser stores, what it sends, and to whom. No analytics, ads or telemetry.",
};

const modes = [
  {
    title: "Guest mode",
    body: "Everything stays in memory. Nothing is sent to Cinder's servers.",
  },
  {
    title: "Signed-in mode",
    body: "Bookmarks, history, settings and your downloads list sync to the Cinder cloud (hosted on Supabase), end-to-end encrypted with a key derived from your passphrase. The server cannot read your data.",
  },
  {
    title: "Private windows",
    body: "No history, session, cache or cookies are written to disk, and nothing syncs. Extensions are off unless you allow them.",
  },
  {
    title: "Extensions",
    body: "Each shows a permission prompt first. Installing from a store contacts that store (Google or Microsoft).",
  },
];

const network = [
  {
    what: "Update check",
    who: "GitHub's public API",
    when: "Once a day, not in private windows",
    detail:
      "Asks whether a newer release exists. Nothing is downloaded or installed automatically. GitHub sees your IP address and a Cinder/<version> user agent.",
  },
  {
    what: "Filter lists",
    who: "easylist.to (EasyList, EasyPrivacy) and abuse.ch (URLhaus)",
    when: "About once a week",
    detail:
      "Public lists, matched locally. The request carries no account or browsing data. The list hosts can see your IP address.",
  },
  {
    what: "Sync",
    who: "Cinder cloud (Supabase)",
    when: "Only when signed in",
    detail: "Encrypted on your device first. The server stores ciphertext.",
  },
  {
    what: "Page rendering",
    who: "Microsoft Edge WebView2",
    when: "Always",
    detail:
      "The engine itself is Microsoft's. Engine-level behaviour is covered by Microsoft's privacy statement.",
  },
];

export default function PrivacyPage() {
  return (
    <div className="mx-auto max-w-4xl px-4 pt-14 sm:px-6 sm:pt-20">
      <h1 className="text-5xl font-extrabold sm:text-6xl">
        Privacy, <span className="text-flame">in plain words.</span>
      </h1>
      <p className="mt-5 max-w-2xl text-lg text-muted-foreground">
        Cinder includes no analytics, advertising or telemetry. If diagnostics are ever
        added, they will be opt-in, off by default, and never active in private windows.
      </p>

      <ul className="mt-8 flex flex-wrap gap-3" aria-label="At a glance">
        {["No analytics", "No ads", "No telemetry", "Encrypted sync"].map((t) => (
          <li
            key={t}
            className="flex items-center gap-2 rounded-full border border-ember-500/40 bg-ember-500/10 px-4 py-2 text-sm font-semibold"
          >
            <span
              aria-hidden="true"
              className="grid size-5 place-items-center rounded-full bg-flame text-[11px] text-[#1c0a03]"
            >
              ✓
            </span>
            {t}
          </li>
        ))}
      </ul>

      <div className="mt-12 grid gap-4 sm:grid-cols-2">
        {modes.map((m, i) => (
          <Reveal key={m.title} delay={i * 0.06} className="h-full">
            <SpotlightCard className="card-lift h-full rounded-3xl border border-border bg-card/70">
              <section className="p-6">
                <p className="font-display text-sm font-bold text-primary">0{i + 1}</p>
                <h2 className="mt-1 text-xl font-bold">{m.title}</h2>
                <p className="mt-2 text-sm leading-relaxed text-muted-foreground">{m.body}</p>
              </section>
            </SpotlightCard>
          </Reveal>
        ))}
      </div>

      <section className="mt-16" aria-labelledby="network-title">
        <h2 id="network-title" className="text-3xl font-bold">What the browser connects to</h2>
        <p className="mt-2 text-muted-foreground">
          Cinder does not load favicons from third-party services. These are the only
          network behaviours the browser adds on its own.
        </p>
        <div className="mt-6 overflow-x-auto rounded-3xl border border-border">
          <table className="w-full min-w-[640px] text-left text-sm">
            <caption className="sr-only">Network connections made by Cinder Browser</caption>
            <thead className="bg-muted/60 text-xs uppercase tracking-wider text-muted-foreground">
              <tr>
                <th scope="col" className="px-5 py-3">What</th>
                <th scope="col" className="px-5 py-3">Who</th>
                <th scope="col" className="px-5 py-3">When</th>
                <th scope="col" className="px-5 py-3">Details</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-border">
              {network.map((n) => (
                <tr key={n.what} className="align-top">
                  <th scope="row" className="px-5 py-4 font-semibold">{n.what}</th>
                  <td className="px-5 py-4 text-muted-foreground">{n.who}</td>
                  <td className="px-5 py-4 text-muted-foreground">{n.when}</td>
                  <td className="px-5 py-4 text-muted-foreground">{n.detail}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>

      <section className="mt-16 rounded-3xl border border-border bg-card/70 p-6 sm:p-8" aria-labelledby="site-title">
        <h2 id="site-title" className="text-2xl font-bold">This website</h2>
        <p className="mt-2 text-sm leading-relaxed text-muted-foreground">
          This site uses no analytics, no cookies and no third-party scripts. Fonts are
          served from this site. Your light or dark theme choice is saved only in your own
          browser&apos;s local storage. The download page asks GitHub&apos;s public API for
          the latest release from our server, not from your browser.
        </p>
      </section>

      <p className="mt-10 text-sm text-muted-foreground">
        The full notice lives with the code:{" "}
        <a
          href={`${site.repo}/blob/HEAD/PRIVACY.md`}
          target="_blank"
          rel="noopener noreferrer"
          className="font-medium text-primary hover:underline"
        >
          PRIVACY.md
          <span className="sr-only"> (opens in a new tab)</span>
        </a>
        .
      </p>
    </div>
  );
}
