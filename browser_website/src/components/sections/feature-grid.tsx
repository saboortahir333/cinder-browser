"use client";

import { useEffect, useState } from "react";
import { motion } from "motion/react";
import { useReducedMotion } from "@/components/brand/use-reduced-motion";
import { HugeiconsIcon } from "@hugeicons/react";
import { Tick02Icon } from "@hugeicons/core-free-icons";
import { features, type Feature } from "@/lib/content";
import { cn } from "@/lib/utils";
import { Reveal } from "@/components/brand/reveal";
import { EmberMark } from "@/components/brand/ember-mark";

/* ---------- small illustrative visuals (all hidden from assistive tech) ---------- */

function Panel({ children, label = "Illustration" }: { children: React.ReactNode; label?: string }) {
  return (
    <div
      aria-hidden="true"
      className="relative overflow-hidden rounded-3xl border border-border bg-card/70 p-5 shadow-[0_30px_80px_-40px_var(--glow-a)] backdrop-blur sm:p-6"
    >
      <div className="glow-orb pointer-events-none absolute -right-20 -top-20 size-64 rounded-full opacity-60" />
      <span className="absolute right-4 top-3 text-[10px] font-medium uppercase tracking-widest text-muted-foreground/70">
        {label}
      </span>
      <div className="relative">{children}</div>
    </div>
  );
}

const REQUESTS = [
  { host: "news.example/index.html", bad: false },
  { host: "ads.example/banner.js", bad: true },
  { host: "cdn.example/app.css", bad: false },
  { host: "tracker.example/pixel.gif", bad: true },
  { host: "fonts.example/body.woff2", bad: false },
  { host: "metrics.example/collect", bad: true },
];

function TrackerVisual() {
  const reduce = useReducedMotion();
  return (
    <Panel>
      <ul className="mt-5 space-y-2 font-mono text-xs sm:text-sm">
        {REQUESTS.map((r, i) => (
          <motion.li
            key={r.host}
            initial={reduce ? false : { opacity: 0, x: -16 }}
            whileInView={{ opacity: 1, x: 0 }}
            viewport={{ once: true }}
            transition={{ delay: i * 0.12, duration: 0.5 }}
            className={cn(
              "relative flex items-center justify-between gap-3 overflow-hidden rounded-xl border px-3.5 py-2.5",
              r.bad ? "border-ember-700/50 bg-ember-700/10" : "border-border bg-background/60",
            )}
          >
            <span className={cn("truncate", r.bad && "text-muted-foreground line-through decoration-ember-500")}>
              {r.host}
            </span>
            <span
              className={cn(
                "shrink-0 rounded-full px-2.5 py-0.5 text-[11px] font-semibold",
                r.bad ? "bg-ember-700 text-white" : "bg-muted text-muted-foreground",
              )}
            >
              {r.bad ? "burned" : "allowed"}
            </span>
            {r.bad && !reduce && (
              <motion.span
                className="pointer-events-none absolute inset-y-0 left-0 w-1/3 bg-gradient-to-r from-transparent via-ember-500/30 to-transparent"
                animate={{ x: ["-120%", "380%"] }}
                transition={{ duration: 2.4, delay: 0.8 + i * 0.3, repeat: Infinity, repeatDelay: 2.5, ease: "easeInOut" }}
              />
            )}
          </motion.li>
        ))}
      </ul>
    </Panel>
  );
}

function PrivateVisual() {
  const rows = ["History", "Cookies", "Session", "Cache"];
  return (
    <Panel>
      <div className="mt-5 grid gap-3 sm:grid-cols-2">
        <div className="rounded-2xl border border-border bg-background/60 p-4">
          <p className="text-sm font-semibold">Profile window</p>
          <ul className="mt-3 space-y-1.5 text-sm text-muted-foreground">
            {rows.map((r) => (
              <li key={r}>{r}: saved</li>
            ))}
          </ul>
        </div>
        <div className="relative overflow-hidden rounded-2xl border border-ember-700/50 bg-ember-700/10 p-4">
          <p className="text-sm font-semibold">Private window</p>
          <ul className="mt-3 space-y-1.5 text-sm text-muted-foreground">
            {rows.map((r) => (
              <li key={r}>{r}: not written to disk</li>
            ))}
          </ul>
          <EmberMark className="absolute -bottom-2 right-1 h-16 w-14 opacity-90" glow={false} title="" />
        </div>
      </div>
    </Panel>
  );
}

function useCipher(enabled: boolean) {
  const [text, setText] = useState("a91f 03c7 e2b8 5d40 71ac");
  useEffect(() => {
    if (!enabled) return;
    const id = setInterval(() => {
      const hex = () => Math.floor(Math.random() * 65536).toString(16).padStart(4, "0");
      setText([hex(), hex(), hex(), hex(), hex()].join(" "));
    }, 140);
    return () => clearInterval(id);
  }, [enabled]);
  return text;
}

function SyncVisual() {
  const reduce = useReducedMotion();
  const cipher = useCipher(!reduce);
  return (
    <Panel>
      <div className="mt-5 grid items-center gap-3 sm:grid-cols-[1fr_auto_1fr]">
        <div className="rounded-2xl border border-border bg-background/60 p-4">
          <p className="text-xs uppercase tracking-wider text-muted-foreground">Your device</p>
          <p className="mt-2 break-all font-mono text-sm">bookmark: example.org/notes</p>
        </div>
        <div className="mx-auto grid size-12 place-items-center rounded-full bg-flame text-[#1c0a03] shadow-[0_0_30px_-6px_var(--glow-a)]">
          <svg viewBox="0 0 24 24" className="size-5" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round">
            <rect x="4" y="11" width="16" height="10" rx="2" />
            <path d="M8 11V7a4 4 0 0 1 8 0v4" />
          </svg>
        </div>
        <div className="rounded-2xl border border-ember-700/50 bg-ember-700/10 p-4">
          <p className="text-xs uppercase tracking-wider text-muted-foreground">Cinder cloud sees</p>
          <p className="mt-2 break-all font-mono text-sm text-ember-500">{cipher}</p>
        </div>
      </div>
      <p className="mt-4 text-center text-xs text-muted-foreground">
        Encrypted with a key derived from your passphrase, on your device.
      </p>
    </Panel>
  );
}

function ExtensionsVisual() {
  return (
    <Panel>
      <div className="mx-auto mt-6 max-w-sm rounded-2xl border border-border bg-background/80 p-5 shadow-lg">
        <div className="flex items-center gap-3">
          <span className="grid size-10 place-items-center rounded-xl bg-flame text-[#1c0a03]">
            <svg viewBox="0 0 24 24" className="size-5" fill="currentColor"><path d="M10 3h4v3a2 2 0 1 0 0 4v3h-4v-1a2 2 0 1 0-4 0v1H3V9h3V7a2 2 0 1 1 4 0V3z" opacity=".9"/></svg>
          </span>
          <div>
            <p className="text-sm font-semibold">Example extension</p>
            <p className="text-xs text-muted-foreground">wants to read and change data on example.org</p>
          </div>
        </div>
        <div className="mt-4 flex justify-end gap-2">
          <span className="rounded-full border border-border px-4 py-1.5 text-xs font-medium">Deny</span>
          <span className="rounded-full bg-flame px-4 py-1.5 text-xs font-semibold text-[#1c0a03]">Allow</span>
        </div>
      </div>
    </Panel>
  );
}

const CONTROLS = ["Back", "Reload", "Address bar", "Menu"];

function AccessVisual() {
  const reduce = useReducedMotion();
  const [active, setActive] = useState(0);
  useEffect(() => {
    if (reduce) return;
    const id = setInterval(() => setActive((a) => (a + 1) % CONTROLS.length), 1300);
    return () => clearInterval(id);
  }, [reduce]);
  return (
    <Panel>
      <div className="mt-6 flex flex-wrap items-center justify-center gap-3">
        {CONTROLS.map((c, i) => (
          <span
            key={c}
            className={cn(
              "rounded-full border px-4 py-2 text-sm transition-all duration-300",
              active === i
                ? "border-ember-500 bg-ember-500/15 text-foreground ring-4 ring-ember-500/40"
                : "border-border bg-background/60 text-muted-foreground",
            )}
          >
            {c}
          </span>
        ))}
      </div>
      <p className="mt-5 text-center text-xs text-muted-foreground">
        <kbd className="rounded-md border border-border bg-muted px-2 py-0.5 font-mono">Tab</kbd> moves focus through the browser controls.
      </p>
    </Panel>
  );
}

function HttpsVisual() {
  return (
    <Panel>
      <div className="mt-6 space-y-3">
        <div className="flex items-center gap-3 rounded-full border border-border bg-background/70 px-4 py-2.5 font-mono text-sm">
          <svg viewBox="0 0 24 24" className="size-4 text-ember-500" fill="none" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round"><rect x="4" y="11" width="16" height="10" rx="2" /><path d="M8 11V7a4 4 0 0 1 8 0v4" /></svg>
          https://example.org
        </div>
        <div className="flex items-center justify-between rounded-full border border-ember-700/50 bg-ember-700/10 px-4 py-2.5 font-mono text-sm">
          <span className="line-through decoration-ember-500">http://example.org</span>
          <span className="rounded-full bg-ember-700 px-2.5 py-0.5 font-sans text-[11px] font-semibold text-white">warned</span>
        </div>
      </div>
    </Panel>
  );
}

const VISUALS: Record<Feature["id"], () => React.ReactElement> = {
  trackers: TrackerVisual,
  private: PrivateVisual,
  sync: SyncVisual,
  extensions: ExtensionsVisual,
  access: AccessVisual,
  https: HttpsVisual,
};

/* ---------- the bands ---------- */

export function FeatureBands({
  ids,
  detailed = false,
}: {
  ids?: Feature["id"][];
  detailed?: boolean;
}) {
  const list = ids ? ids.map((id) => features.find((f) => f.id === id)!) : features;

  return (
    <div className="mx-auto max-w-6xl space-y-24 px-4 sm:space-y-32 sm:px-6">
      {list.map((f, i) => {
        const Visual = VISUALS[f.id];
        return (
          <section
            key={f.id}
            id={f.id}
            aria-labelledby={`${f.id}-title`}
            className="grid scroll-mt-32 items-center gap-10 md:grid-cols-2 md:gap-16"
          >
            <Reveal className={cn(i % 2 === 1 && "md:order-2")}>
              <div className="flex items-center gap-3">
                <span className="grid size-11 place-items-center rounded-2xl bg-flame text-[#1c0a03] shadow-[0_8px_30px_-10px_var(--glow-a)]">
                  <HugeiconsIcon icon={f.icon} size={22} />
                </span>
                <p className="text-sm font-semibold uppercase tracking-wider text-primary">{f.kicker}</p>
              </div>
              <h3 id={`${f.id}-title`} className="mt-5 text-3xl font-bold leading-tight sm:text-4xl">
                {f.title}
              </h3>
              <p className="mt-4 text-lg leading-relaxed text-muted-foreground">{f.body}</p>
              {(detailed || f.points.length > 0) && (
                <ul className="mt-6 space-y-3">
                  {f.points.map((p) => (
                    <li key={p} className="flex gap-3 text-sm leading-relaxed sm:text-base">
                      <span className="mt-0.5 grid size-5 shrink-0 place-items-center rounded-full bg-primary/15 text-primary">
                        <HugeiconsIcon icon={Tick02Icon} size={14} />
                      </span>
                      {p}
                    </li>
                  ))}
                </ul>
              )}
            </Reveal>
            <Reveal delay={0.1}>
              <Visual />
            </Reveal>
          </section>
        );
      })}
    </div>
  );
}
