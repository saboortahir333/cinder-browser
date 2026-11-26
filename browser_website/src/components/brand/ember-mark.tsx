"use client";

import { useId } from "react";
import { motion, useTransform } from "motion/react";
import { useAnimationsPaused } from "./use-reduced-motion";
import { usePointer } from "./pointer";

/* Paths come from the Cinder logo (cinder-mark.svg, 800x800 canvas). */
const OUTER_L =
  "M400 210 C 300 250, 240 350, 260 460 C 275 540, 335 590, 400 600 C 355 540, 340 470, 365 410 C 380 370, 405 340, 400 210 Z";
const OUTER_R =
  "M400 210 C 500 250, 560 350, 540 460 C 525 540, 465 590, 400 600 C 445 540, 460 470, 435 410 C 420 370, 395 340, 400 210 Z";
const INNER =
  "M400 270 C 345 320, 320 390, 340 450 C 352 490, 375 520, 400 535 C 425 520, 448 490, 460 450 C 480 390, 455 320, 400 270 Z";

/** viewBox that frames the flame plus its glow. */
export const FLAME_VIEWBOX = "150 130 500 520";

const origin = (x: number, y: number) => ({
  transformBox: "view-box" as const,
  transformOrigin: `${x}px ${y}px`,
});

const loop = (duration: number, delay = 0) => ({
  duration,
  delay,
  repeat: Infinity,
  ease: "easeInOut" as const,
});

/**
 * The living flame. Every petal flickers on its own rhythm, the core pulses,
 * sparks rise, and the whole flame leans toward the cursor.
 */
export function FlameBody({
  animated = true,
  glow = true,
  sparks = true,
  lean = true,
}: {
  animated?: boolean;
  glow?: boolean;
  sparks?: boolean;
  lean?: boolean;
}) {
  const uid = useId().replace(/[^a-zA-Z0-9_-]/g, "");
  const paused = useAnimationsPaused();
  const run = animated && !paused;
  const { x } = usePointer();
  const rotate = useTransform(x, [-1, 1], lean ? [-5, 5] : [0, 0]);

  const outer = `${uid}-outer`;
  const inner = `${uid}-inner`;
  const core = `${uid}-core`;
  const blur = `${uid}-blur`;

  return (
    <>
      <defs>
        <linearGradient id={outer} x1="0%" y1="100%" x2="60%" y2="0%">
          <stop offset="0%" stopColor="#8a1f0f" />
          <stop offset="45%" stopColor="#d84315" />
          <stop offset="100%" stopColor="#ff8a3d" />
        </linearGradient>
        <linearGradient id={inner} x1="0%" y1="100%" x2="50%" y2="0%">
          <stop offset="0%" stopColor="#d84315" />
          <stop offset="55%" stopColor="#ff8f3f" />
          <stop offset="100%" stopColor="#ffd27a" />
        </linearGradient>
        <radialGradient id={core} cx="50%" cy="50%" r="50%">
          <stop offset="0%" stopColor="#fff7e6" />
          <stop offset="55%" stopColor="#ffd27a" />
          <stop offset="100%" stopColor="#ff8a3d" stopOpacity="0" />
        </radialGradient>
        <filter id={blur} x="-50%" y="-50%" width="200%" height="200%">
          <feGaussianBlur stdDeviation="14" />
        </filter>
      </defs>

      {glow && (
        <motion.circle
          cx="400"
          cy="380"
          r="220"
          fill={`url(#${core})`}
          filter={`url(#${blur})`}
          style={origin(400, 380)}
          initial={{ opacity: 0.5, scale: 1 }}
          animate={run ? { opacity: [0.4, 0.75, 0.45], scale: [1, 1.12, 1] } : undefined}
          transition={loop(3.6)}
        />
      )}

      <motion.g style={{ rotate, ...origin(400, 600) }}>
        <motion.path
          d={OUTER_L}
          fill={`url(#${outer})`}
          style={origin(400, 600)}
          animate={
            run
              ? {
                  scaleY: [1, 1.06, 0.98, 1.04, 1],
                  scaleX: [1, 0.97, 1.02, 0.98, 1],
                  skewX: [0, -2.5, 1.5, -1, 0],
                }
              : undefined
          }
          transition={loop(2.6)}
        />
        <motion.path
          d={OUTER_R}
          fill={`url(#${outer})`}
          opacity={0.92}
          style={origin(400, 600)}
          animate={
            run
              ? {
                  scaleY: [1, 0.97, 1.05, 0.99, 1],
                  scaleX: [1, 1.03, 0.97, 1.02, 1],
                  skewX: [0, 2, -2, 1, 0],
                }
              : undefined
          }
          transition={loop(3.1, 0.3)}
        />
        <motion.path
          d={INNER}
          fill={`url(#${inner})`}
          style={origin(400, 535)}
          animate={
            run
              ? {
                  scaleY: [1, 1.1, 0.95, 1.08, 1],
                  scaleX: [1, 0.94, 1.04, 0.96, 1],
                  skewX: [0, 3, -3, 1.5, 0],
                }
              : undefined
          }
          transition={loop(1.9, 0.15)}
        />
        <motion.circle
          cx="400"
          cy="440"
          r="34"
          fill={`url(#${core})`}
          style={origin(400, 440)}
          animate={run ? { scale: [1, 1.25, 0.9, 1.18, 1], opacity: [0.9, 1, 0.8, 1, 0.9] } : undefined}
          transition={loop(1.7)}
        />
      </motion.g>

      {run && sparks && (
        <g>
          {[
            { cx: 372, d: 2.8, de: 0, s: 5 },
            { cx: 428, d: 3.4, de: 0.9, s: 4 },
            { cx: 400, d: 3.1, de: 1.7, s: 6 },
            { cx: 350, d: 3.8, de: 2.3, s: 3.5 },
            { cx: 452, d: 3.3, de: 0.4, s: 3.5 },
          ].map((p, i) => (
            <motion.circle
              key={i}
              cx={p.cx}
              cy={250}
              r={p.s}
              fill="#ffd27a"
              initial={{ opacity: 0, y: 0 }}
              animate={{ opacity: [0, 1, 0], y: [0, -90, -170], x: [0, i % 2 ? 14 : -14, i % 2 ? -6 : 6] }}
              transition={{ duration: p.d, delay: p.de, repeat: Infinity, ease: "easeOut" }}
            />
          ))}
        </g>
      )}
    </>
  );
}

/** Standalone logo mark. */
export function EmberMark({
  className,
  animated = true,
  glow = true,
  sparks = true,
  title = "Cinder",
}: {
  className?: string;
  animated?: boolean;
  glow?: boolean;
  sparks?: boolean;
  title?: string;
}) {
  return (
    <svg
      viewBox={FLAME_VIEWBOX}
      role="img"
      aria-label={title}
      className={className}
      overflow="visible"
    >
      <FlameBody animated={animated} glow={glow} sparks={sparks} />
    </svg>
  );
}
