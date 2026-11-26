import { HugeiconsIcon } from "@hugeicons/react";
import { CheckmarkCircle02Icon } from "@hugeicons/core-free-icons";
import { trustFacts, notYet } from "@/lib/content";
import { Hero } from "@/components/sections/hero";
import { FeatureBands } from "@/components/sections/feature-grid";
import { CtaBand } from "@/components/sections/cta-band";
import { Reveal } from "@/components/brand/reveal";

const layers = [
  {
    title: "Engine",
    body: "Pages are rendered by Microsoft Edge WebView2, which is Chromium. That means the sites you use today work.",
  },
  {
    title: "Shell",
    body: "The browser interface is built with Flutter, with a native C++ bridge that hosts WebView2 and Manifest V3 extensions.",
  },
  {
    title: "Privacy core",
    body: "Tracker and ad matching runs locally in Rust, using Brave's open-source adblock engine and public filter lists.",
  },
  {
    title: "Sync",
    body: "Optional. Bookmarks, history and settings are encrypted on your device before they reach the Cinder cloud.",
  },
];

export default function Home() {
  return (
    <>
      <Hero />

      <section aria-label="What Cinder promises" className="mx-auto max-w-6xl px-4 sm:px-6">
        <Reveal>
          <ul className="grid gap-px overflow-hidden rounded-3xl border border-border bg-border sm:grid-cols-2 lg:grid-cols-4">
            {trustFacts.map((t) => (
              <li key={t.label} className="bg-card/80 p-6 backdrop-blur">
                <p className="flex items-center gap-2 font-display text-lg font-bold">
                  <HugeiconsIcon icon={CheckmarkCircle02Icon} size={20} className="text-primary" />
                  {t.label}
                </p>
                <p className="mt-1.5 text-sm text-muted-foreground">{t.detail}</p>
              </li>
            ))}
          </ul>
        </Reveal>
      </section>

      <section className="mx-auto mt-28 max-w-6xl px-4 sm:px-6" aria-labelledby="inside-title">
        <Reveal className="max-w-2xl">
          <p className="text-sm font-semibold uppercase tracking-wider text-primary">What&apos;s inside</p>
          <h2 id="inside-title" className="mt-3 text-4xl font-extrabold sm:text-5xl">
            A browser with the privacy <span className="text-flame">built in</span>, not bolted on.
          </h2>
        </Reveal>
      </section>

      <div className="mt-16">
        <FeatureBands ids={["trackers", "private", "sync", "extensions", "access"]} />
      </div>

      <section className="mx-auto mt-32 max-w-6xl px-4 sm:px-6" aria-labelledby="how-title">
        <Reveal className="max-w-2xl">
          <p className="text-sm font-semibold uppercase tracking-wider text-primary">How it&apos;s built</p>
          <h2 id="how-title" className="mt-3 text-4xl font-extrabold sm:text-5xl">
            Honest about what&apos;s under the hood.
          </h2>
          <p className="mt-4 text-lg text-muted-foreground">
            Cinder is not a new rendering engine. It is a privacy-focused shell around the
            engine that already powers Edge, with the layers that matter to you built by us.
          </p>
        </Reveal>
        <div className="mt-10 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
          {layers.map((l, i) => (
            <Reveal key={l.title} delay={i * 0.08}>
              <div className="card-lift h-full rounded-3xl border border-border bg-card/70 p-6">
                <p className="font-display text-sm font-bold text-primary">0{i + 1}</p>
                <h3 className="mt-2 text-xl font-bold">{l.title}</h3>
                <p className="mt-2 text-sm leading-relaxed text-muted-foreground">{l.body}</p>
              </div>
            </Reveal>
          ))}
        </div>
      </section>

      <section className="mx-auto mt-28 max-w-6xl px-4 sm:px-6" aria-labelledby="yet-title">
        <Reveal>
          <div className="rounded-3xl border border-dashed border-ember-700/50 bg-ember-700/5 p-8 sm:p-10">
            <h2 id="yet-title" className="text-2xl font-bold sm:text-3xl">
              Not there yet
            </h2>
            <p className="mt-2 max-w-2xl text-muted-foreground">
              Cinder is young. These are the things it does not do today, so you can decide
              with open eyes.
            </p>
            <ul className="mt-5 grid gap-2 sm:grid-cols-2">
              {notYet.map((n) => (
                <li key={n} className="flex gap-3 text-sm sm:text-base">
                  <span aria-hidden="true" className="mt-2 size-1.5 shrink-0 rounded-full bg-ember-500" />
                  {n}
                </li>
              ))}
            </ul>
          </div>
        </Reveal>
      </section>

      <CtaBand />
    </>
  );
}
