"use client";

import {
  setAnimationsPaused,
  useAnimationsPaused,
} from "@/components/brand/use-reduced-motion";

/** Lets visitors pause the mascot and flame animations (WCAG 2.2.2). */
export function MotionToggle() {
  const paused = useAnimationsPaused();
  return (
    <button
      type="button"
      aria-pressed={paused}
      onClick={() => setAnimationsPaused(!paused)}
      className="rounded-full border border-border px-3 py-1 text-xs font-medium text-muted-foreground transition-colors hover:border-ember-500 hover:text-foreground"
    >
      {paused ? "Play mascot animations" : "Pause mascot animations"}
    </button>
  );
}
