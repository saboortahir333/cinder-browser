"use client";

import { motion, useScroll, useTransform } from "motion/react";
import { useReducedMotion } from "@/components/brand/use-reduced-motion";
import { HugeiconsIcon } from "@hugeicons/react";
import { Download01Icon, ArrowRight01Icon } from "@hugeicons/core-free-icons";
import { site } from "@/lib/site-config";
import { EmberMark } from "@/components/brand/ember-mark";
import { Mascot } from "@/components/brand/mascot";
import { EmberField } from "@/components/brand/ember-field";
import { usePointer } from "@/components/brand/pointer";
import { CtaLink } from "@/components/site/cta-link";
import { Magnetic } from "@/components/brand/interactions";
import { BrowserWindow } from "./browser-window";

const WORDS_A = ["Burn", "the", "trackers."];
const WORDS_B = ["Keep", "your", "data."];

function Words({ words, flame, start }: { words: string[]; flame?: boolean; start: number }) {
  const reduce = useReducedMotion();
  return (
    <span className="block">
      {words.map((w, i) => (
        <motion.span
          key={w}
          className={`mr-[0.25em] inline-block ${flame ? "text-flame" : ""}`}
          initial={reduce ? false : { opacity: 0, y: 36, rotate: 2 }}
          animate={{ opacity: 1, y: 0, rotate: 0 }}
          transition={{ duration: 0.8, delay: start + i * 0.09, ease: [0.2, 0.8, 0.2, 1] }}
        >
          {w}
        </motion.span>
      ))}
    </span>
  );
}

export function Hero() {
  const { x, y } = usePointer();
  const rotY = useTransform(x, [-1, 1], [-5, 5]);
  const rotX = useTransform(y, [-1, 1], [3, -3]);
  const reduce = useReducedMotion();
  const { scrollY } = useScroll();
  const flameY = useTransform(scrollY, [0, 700], [0, -70]);

  return (
    <section className="relative isolate overflow-hidden">
      <div className="bg-grid absolute inset-0 -z-10" aria-hidden="true" />
      <div
        className="glow-orb animate-pulse-glow absolute left-1/2 top-[-10%] -z-10 size-[900px] max-w-none -translate-x-1/2 rounded-full"
        aria-hidden="true"
      />

      <div className="mx-auto grid max-w-6xl items-center gap-12 px-4 pb-20 pt-14 sm:px-6 lg:grid-cols-[1.05fr_0.95fr] lg:pb-28 lg:pt-20">
        <div>
          <motion.p
            initial={{ opacity: 0, y: 12 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.6 }}
            className="inline-flex items-center gap-2 rounded-full border border-border bg-card/60 px-3.5 py-1.5 text-sm font-medium text-muted-foreground backdrop-blur"
          >
            <span className="size-2 rounded-full bg-flame shadow-[0_0_10px_var(--color-ember-500)]" />
            Private browser for Windows
          </motion.p>

          <h1 className="mt-6 text-5xl font-extrabold leading-[1.02] sm:text-6xl lg:text-[3.4rem] xl:text-[3.75rem]">
            <Words words={WORDS_A} start={0.1} />
            <Words words={WORDS_B} flame start={0.45} />
          </h1>

          <motion.p
            initial={{ opacity: 0, y: 16 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.7, delay: 0.8 }}
            className="mt-6 max-w-xl text-lg leading-relaxed text-muted-foreground"
          >
            {site.short} is a Windows browser with built-in tracker blocking,
            end-to-end encrypted sync and private profiles. No analytics. No
            ads. No telemetry.
          </motion.p>

          <motion.div
            initial={{ opacity: 0, y: 16 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.7, delay: 0.95 }}
            className="mt-8 flex flex-wrap items-center gap-3"
          >
            <Magnetic>
              <CtaLink href="/download">
                <HugeiconsIcon icon={Download01Icon} size={20} />
                Download for Windows
              </CtaLink>
            </Magnetic>
            <CtaLink href="/features" tone="outline">
              See what&apos;s inside
              <HugeiconsIcon icon={ArrowRight01Icon} size={18} />
            </CtaLink>
          </motion.div>

          <motion.p
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            transition={{ duration: 0.7, delay: 1.2 }}
            className="mt-5 text-sm text-muted-foreground"
          >
            Open source (Apache-2.0) · {site.requirements}
          </motion.p>
        </div>

        {/* stage */}
        <div>
          <div className="relative h-[430px] [--win-h:290px] sm:h-[520px] sm:[--win-h:350px]">
            <div className="glow-orb animate-pulse-glow absolute -inset-10 -z-10 rounded-full" aria-hidden="true" />
            <div className="absolute inset-0 -z-10" aria-hidden="true">
              <EmberField count={48} />
            </div>

            <motion.div
              className="absolute -left-2 top-2 z-0 w-36 sm:w-48"
              style={reduce ? undefined : { y: flameY }}
            >
              <EmberMark className="w-full" title="" />
            </motion.div>

            <div className="absolute inset-x-0 bottom-0 z-10 h-[var(--win-h)] [perspective:1200px]">
              <motion.div className="h-full w-full" style={{ rotateY: rotY, rotateX: rotX }}>
                <BrowserWindow />
              </motion.div>
            </div>

            <Mascot className="absolute right-0 z-20 w-[48%] max-w-[280px] bottom-[calc(var(--win-h)-18px)] sm:right-3" />
          </div>
          <p className="mt-3 text-center text-xs text-muted-foreground">
            Illustration of the new tab page. Say hi to Ash: move your mouse, or tap.
          </p>
        </div>
      </div>
      <a
        href="#trust"
        aria-label="Scroll to the next section"
        className="absolute bottom-5 left-1/2 hidden -translate-x-1/2 text-muted-foreground transition-colors hover:text-primary lg:block"
      >
        <span className="animate-float grid size-10 place-items-center rounded-full border border-border bg-card/60 backdrop-blur">
          <svg viewBox="0 0 24 24" className="size-4" fill="none" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
            <path d="M6 9l6 6 6-6" />
          </svg>
        </span>
      </a>
    </section>
  );
}
