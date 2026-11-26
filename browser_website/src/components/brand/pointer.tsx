"use client";

import { createContext, useContext, useEffect, useMemo } from "react";
import { type MotionValue, useMotionValue, useSpring } from "motion/react";

type Pointer = { x: MotionValue<number>; y: MotionValue<number> };

const PointerContext = createContext<Pointer | null>(null);

/**
 * Tracks the cursor once for the whole page as smoothed values in [-1, 1].
 * The mascot's eyes, the flame's lean and the hero tilt all read from it,
 * so there is a single pointermove listener on the site.
 */
export function PointerProvider({ children }: { children: React.ReactNode }) {
  const rawX = useMotionValue(0);
  const rawY = useMotionValue(0);
  const x = useSpring(rawX, { stiffness: 110, damping: 20, mass: 0.6 });
  const y = useSpring(rawY, { stiffness: 110, damping: 20, mass: 0.6 });

  useEffect(() => {
    const onMove = (e: PointerEvent) => {
      rawX.set((e.clientX / window.innerWidth) * 2 - 1);
      rawY.set((e.clientY / window.innerHeight) * 2 - 1);
    };
    const onLeave = () => {
      rawX.set(0);
      rawY.set(0);
    };
    window.addEventListener("pointermove", onMove, { passive: true });
    document.documentElement.addEventListener("pointerleave", onLeave);
    return () => {
      window.removeEventListener("pointermove", onMove);
      document.documentElement.removeEventListener("pointerleave", onLeave);
    };
  }, [rawX, rawY]);

  const value = useMemo(() => ({ x, y }), [x, y]);
  return (
    <PointerContext.Provider value={value}>{children}</PointerContext.Provider>
  );
}

export function usePointer(): Pointer {
  const ctx = useContext(PointerContext);
  if (!ctx) throw new Error("usePointer must be used inside <PointerProvider>");
  return ctx;
}
