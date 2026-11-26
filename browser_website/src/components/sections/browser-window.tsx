"use client";

import { useEffect, useState } from "react";
import { useReducedMotion } from "@/components/brand/use-reduced-motion";
import { EmberMark } from "@/components/brand/ember-mark";

const PHRASES = ["private browsers", "no telemetry", "open source"];

function useTypewriter(enabled: boolean) {
  const [text, setText] = useState("");
  useEffect(() => {
    if (!enabled) return;
    let i = 0;
    let j = 0;
    let deleting = false;
    let timer: ReturnType<typeof setTimeout>;
    const tick = () => {
      const phrase = PHRASES[i];
      if (!deleting) {
        j++;
        setText(phrase.slice(0, j));
        if (j === phrase.length) {
          deleting = true;
          timer = setTimeout(tick, 1600);
          return;
        }
        timer = setTimeout(tick, 70);
      } else {
        j--;
        setText(phrase.slice(0, j));
        if (j === 0) {
          deleting = false;
          i = (i + 1) % PHRASES.length;
          timer = setTimeout(tick, 400);
          return;
        }
        timer = setTimeout(tick, 35);
      }
    };
    timer = setTimeout(tick, 900);
    return () => clearTimeout(timer);
  }, [enabled]);
  return text;
}

const TILE_HUES = ["#3b2a22", "#2f3340", "#2b3a33", "#3a2f3f", "#40342a", "#2c3a40", "#3d2c2c", "#33333d"];

/**
 * Illustration of Cinder's new tab page: logo, wordmark, pill search bar and a
 * top-sites grid (layout from assets/newtab/home.html). Colours follow the
 * browser's own dark theme tokens (home.css). It is an illustration, not a
 * screenshot, and is hidden from assistive technology.
 */
export function BrowserWindow() {
  const reduce = useReducedMotion();
  const typed = useTypewriter(!reduce);

  return (
    <div
      aria-hidden="true"
      className="flex h-full w-full flex-col overflow-hidden rounded-2xl border border-white/10 bg-[#1C1B22] text-[#F9F9FB] shadow-[0_40px_90px_-30px_rgba(0,0,0,0.7),0_0_0_1px_rgba(255,138,61,0.08)]"
    >
      {/* tab strip */}
      <div className="flex items-end gap-2 bg-[#15141a] px-3 pt-2.5">
        <div className="flex items-center gap-2 rounded-t-lg bg-[#2B2A33] px-3 py-2 text-xs">
          <span className="size-2.5 rounded-full bg-gradient-to-br from-[#ffb25e] to-[#d84315]" />
          New Tab
          <span className="ml-3 text-[#8A8A96]">×</span>
        </div>
        <span className="mb-1.5 px-2 text-[#8A8A96]">+</span>
        <div className="ml-auto mb-1.5 flex gap-3 text-[#8A8A96]">
          <span>—</span>
          <span>▢</span>
          <span>×</span>
        </div>
      </div>

      {/* toolbar */}
      <div className="flex items-center gap-3 bg-[#2B2A33] px-3 py-2">
        <span className="text-[#B6B6C0]">‹</span>
        <span className="text-[#B6B6C0]">›</span>
        <span className="text-[#B6B6C0]">⟳</span>
        <div className="flex h-8 flex-1 items-center gap-2 rounded-full bg-[#1C1B22] px-3 text-xs text-[#8A8A96]">
          <span className="size-3 rounded-sm border border-[#8A8A96]" />
          Search or enter address
        </div>
        <span className="size-6 rounded-full bg-[#38373F]" />
      </div>

      {/* page */}
      <div className="relative flex flex-1 flex-col items-center justify-center gap-5 px-6 py-4">
        <div className="flex items-center gap-3">
          <EmberMark className="h-9 w-8" glow={false} sparks={false} title="" />
          <span className="font-display text-2xl font-semibold tracking-tight">Cinder</span>
        </div>

        <div className="flex h-11 w-full max-w-md items-center gap-3 rounded-full border border-[#38373F] bg-[#2B2A33] px-4 text-sm text-[#B6B6C0] ring-2 ring-[#7FB3FF]/25">
          <svg viewBox="0 0 24 24" className="size-4 shrink-0" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
            <circle cx="11" cy="11" r="8" />
            <path d="M21 21l-4.35-4.35" />
          </svg>
          <span>
            {reduce ? "Search the web" : typed || " "}
            {!reduce && <span className="ml-px inline-block h-4 w-px translate-y-0.5 animate-pulse bg-[#7FB3FF]" />}
          </span>
        </div>

        <ul className="grid grid-cols-4 gap-3">
          {TILE_HUES.map((c, i) => (
            <li
              key={i}
              className="grid size-14 place-items-center rounded-xl border border-[#38373F] sm:size-16"
              style={{ background: c }}
            >
              <span className="size-5 rounded-md bg-white/15" />
            </li>
          ))}
        </ul>
      </div>
    </div>
  );
}
