import type { Metadata } from "next";
import { HugeiconsIcon } from "@hugeicons/react";
import { FeatureBands } from "@/components/sections/feature-grid";
import { CtaBand } from "@/components/sections/cta-band";
import { Reveal } from "@/components/brand/reveal";
import { features, notYet } from "@/lib/content";

export const metadata: Metadata = {
  title: "Features",
  description:
    "Tracker blocking, private windows and profiles, end-to-end encrypted sync, Manifest V3 extensions, HTTPS-only mode and accessibility in Cinder Browser.",
};

export default function FeaturesPage() {
  return (
    <>
      <div className="relative isolate overflow-hidden">
        <div className="bg-grid absolute inset-0 -z-10" aria-hidden="true" />
        <div className="glow-orb absolute -top-40 left-1/2 -z-10 size-[700px] -translate-x-1/2 rounded-full" aria-hidden="true" />
        <div className="mx-auto max-w-6xl px-4 pt-14 sm:px-6 sm:pt-20">
          <p className="text-sm font-semibold uppercase tracking-wider text-primary">Features</p>
          <h1 className="mt-3 max-w-3xl text-5xl font-extrabold sm:text-6xl">
            Everything Cinder does, <span className="text-flame">and what it doesn&apos;t yet.</span>
          </h1>
          <p className="mt-5 max-w-2xl text-lg text-muted-foreground">
            Each feature below is something the browser does today. The sources are the
            project&apos;s own README, privacy notice and implementation docs.
          </p>
        </div>
      </div>

      <nav
        aria-label="Jump to a feature"
        className="sticky top-16 z-40 mt-10 border-y border-border/60 bg-background/80 py-3 backdrop-blur-xl"
      >
        <ul className="mx-auto flex max-w-6xl gap-2 overflow-x-auto px-4 sm:px-6">
          {features.map((f) => (
            <li key={f.id}>
              <a
                href={`#${f.id}`}
                className="flex items-center gap-2 whitespace-nowrap rounded-full border border-border bg-card/60 px-4 py-2 text-sm font-medium transition-colors hover:border-ember-500 hover:text-primary"
              >
                <HugeiconsIcon icon={f.icon} size={16} />
                {f.kicker}
              </a>
            </li>
          ))}
        </ul>
      </nav>

      <div className="mt-16">
        <FeatureBands detailed />
      </div>

      <section className="mx-auto mt-28 max-w-6xl px-4 sm:px-6" aria-labelledby="yet-title">
        <Reveal>
          <div className="rounded-3xl border border-dashed border-ember-700/50 bg-ember-700/5 p-8 sm:p-10">
            <h2 id="yet-title" className="text-2xl font-bold sm:text-3xl">Not built yet</h2>
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
