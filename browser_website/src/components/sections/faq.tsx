import { site } from "@/lib/site-config";
import { Reveal } from "@/components/brand/reveal";

/** Answers are limited to what the browser repo's README, PRIVACY.md and docs state. */
const items = [
  {
    q: "What engine does Cinder use?",
    a: "Pages are rendered by Microsoft Edge WebView2, which is Chromium, the same engine family as Edge. Cinder adds its own interface, tracker blocking, encrypted sync and extension host on top.",
  },
  {
    q: "Does Cinder collect my data?",
    a: "The browser includes no analytics, advertising or telemetry. It makes a few small requests on its own, such as a daily update check against GitHub and a weekly filter-list refresh. The Privacy page lists every one.",
  },
  {
    q: "Do I need an account?",
    a: "No. Guest mode works without one: everything stays in memory and nothing is sent to Cinder's servers. An account is only needed for end-to-end encrypted sync.",
  },
  {
    q: "Why does Windows warn me when I install?",
    a: "Cinder's release pipeline is set up to sign installers through the free SignPath Foundation program. If SmartScreen says “Unknown publisher”, that build isn't signed yet. Compare the installer's SHA-256 with the one on the download page.",
  },
  {
    q: "Is there a macOS, Linux or mobile version?",
    a: "Not yet. Cinder is Windows-only today, so there are no downloads for other platforms.",
  },
  {
    q: "Which versions of Windows are supported?",
    a: `${site.requirements}. The installer adds the Visual C++ runtime and the WebView2 runtime if they are missing.`,
  },
  {
    q: "Can I use extensions?",
    a: "Cinder runs Manifest V3 extensions, including content scripts and toolbar popups, and asks for permission first. Not every extension is guaranteed to work, and the screen for managing extensions is still being built.",
  },
  {
    q: "Can I read the code?",
    a: "Yes. Cinder is open source under the Apache License 2.0, and the repository is linked in the footer.",
  },
];

export function Faq() {
  return (
    <section className="mx-auto mt-28 max-w-3xl px-4 sm:px-6" aria-labelledby="faq-title">
      <Reveal>
        <p className="text-sm font-semibold uppercase tracking-wider text-primary">FAQ</p>
        <h2 id="faq-title" className="mt-3 text-4xl font-extrabold sm:text-5xl">
          Questions, answered
        </h2>
      </Reveal>
      <div className="mt-8 space-y-3">
        {items.map((item, i) => (
          <Reveal key={item.q} delay={i * 0.04} y={16}>
            <details className="group rounded-2xl border border-border bg-card/70 px-5 py-4 transition-colors open:border-ember-500/50 open:bg-card hover:border-ember-500/40">
              <summary className="flex cursor-pointer list-none items-center justify-between gap-4 font-display text-lg font-semibold [&::-webkit-details-marker]:hidden">
                {item.q}
                <span
                  aria-hidden="true"
                  className="grid size-7 shrink-0 place-items-center rounded-full bg-muted text-xl leading-none transition-all duration-300 group-open:rotate-45 group-open:bg-flame group-open:text-[#1c0a03]"
                >
                  +
                </span>
              </summary>
              <p className="mt-3 leading-relaxed text-muted-foreground">{item.a}</p>
            </details>
          </Reveal>
        ))}
      </div>
    </section>
  );
}
