"use client";

import { useEffect, useId, useRef, useState } from "react";
import {
  motion,
  useMotionValue,
  useSpring,
  useTransform,
  type MotionValue,
} from "motion/react";
import { useAnimationsPaused } from "./use-reduced-motion";
import { FlameBody, FLAME_VIEWBOX } from "./ember-mark";

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

const EYES = [
  { x: 160, y: 166 },
  { x: 280, y: 166 },
];

/** How far (SVG units) an iris can travel inside its eye. */
const IRIS_REACH = { x: 11, y: 10 };
/** Cursor distance (screen px) at which an eye is fully turned toward it. */
const FULL_TURN_DISTANCE = 140;

const SPRING = { stiffness: 260, damping: 20, mass: 0.4 };
const RIM = { stroke: "#ff8a3d", strokeOpacity: 0.55, strokeWidth: 3 } as const;

function useSmooth() {
  const raw = useMotionValue(0);
  const smooth = useSpring(raw, SPRING);
  return { raw, smooth };
}

/** One eye: dark socket, iris, pupil, highlights and a blinking lid. */
function Eye({
  cx,
  cy,
  baseRef,
  ix,
  iy,
  irisId,
  run,
}: {
  cx: number;
  cy: number;
  baseRef: React.RefObject<SVGEllipseElement | null>;
  ix: MotionValue<number>;
  iy: MotionValue<number>;
  irisId: string;
  run: boolean;
}) {
  // Pupil and highlight lead the iris a little, which sells the depth of the eye.
  const pupilX = useTransform(ix, (v) => v * 0.41);
  const pupilY = useTransform(iy, (v) => v * 0.35);
  const hlX = useTransform(ix, (v) => v * 0.27);
  const hlY = useTransform(iy, (v) => v * 0.2);

  return (
    <g>
      <motion.ellipse
        ref={baseRef}
        cx={cx}
        cy={cy}
        rx="28"
        ry="33"
        fill="#0d0605"
        stroke="#ff8a3d"
        strokeOpacity="0.35"
        strokeWidth="2"
        style={origin(cx, cy)}
        variants={{ tap: { scaleX: 1.14, scaleY: 1.1 } }}
      />
      <motion.g style={{ x: ix, y: iy }}>
        <circle cx={cx} cy={cy} r="15" fill={`url(#${irisId})`} />
        <motion.circle cx={cx} cy={cy} r="8" fill="#0a0402" style={{ x: pupilX, y: pupilY }} />
        <motion.circle cx={cx - 7} cy={cy - 10} r="6.5" fill="#fff" style={{ x: hlX, y: hlY }} />
        <motion.circle cx={cx + 8} cy={cy + 9} r="3" fill="#fff" opacity="0.85" style={{ x: hlX, y: hlY }} />
      </motion.g>
      <motion.ellipse
        cx={cx}
        cy={cy}
        rx="29"
        ry="34"
        fill="#3a251d"
        style={origin(cx, cy - 34)}
        initial={{ scaleY: 0 }}
        animate={run ? { scaleY: [0, 0, 1, 0, 0] } : undefined}
        transition={{
          duration: 5,
          times: [0, 0.9, 0.94, 0.98, 1],
          repeat: Infinity,
          ease: "easeInOut",
        }}
      />
    </g>
  );
}

/**
 * "Ash", the Cinder salamander. Modelled on the real fire salamander: coal-black
 * with glowing orange blotches. In old folklore the salamander lives in fire,
 * which makes it the natural companion for a browser called Cinder.
 *
 * Gaze: ONLY the cursor moves the eyes. Every frame each eye measures the real
 * on-screen direction from itself to the cursor and turns its iris that way.
 * Before the cursor has moved, Ash looks straight ahead.
 *
 * Life: breathing, tail sway, pulsing blotches, blinking, an occasional tongue
 * flick and happy shimmy. Hover: Ash waves. Tap: hop, wide eyes, ember burst.
 * The body and head lean toward the cursor.
 */
export function Mascot({
  className,
  label = "Ash, the Cinder salamander, with a flame on its head",
}: {
  className?: string;
  label?: string;
}) {
  const uid = useId().replace(/[^a-zA-Z0-9_-]/g, "");
  const paused = useAnimationsPaused();
  const run = !paused;
  const [burst, setBurst] = useState(0);

  const rootRef = useRef<HTMLDivElement>(null);
  const eyeLRef = useRef<SVGEllipseElement>(null);
  const eyeRRef = useRef<SVGEllipseElement>(null);

  const ixL = useSmooth();
  const iyL = useSmooth();
  const ixR = useSmooth();
  const iyR = useSmooth();
  const hx = useSmooth();
  const hy = useSmooth();
  const lean = useSmooth();
  const headRot = useTransform(hx.smooth, (v) => v * 0.4);

  useEffect(() => {
    // Where the cursor is, in client (screen) pixels. NaN until it first moves.
    const cursor = { x: Number.NaN, y: Number.NaN };
    let raf = 0;

    const onPointer = (e: PointerEvent) => {
      cursor.x = e.clientX;
      cursor.y = e.clientY;
    };
    window.addEventListener("pointermove", onPointer, { passive: true });
    window.addEventListener("pointerdown", onPointer, { passive: true });

    const aim = (el: SVGEllipseElement | null, ix: MotionValue<number>, iy: MotionValue<number>) => {
      if (!el || Number.isNaN(cursor.x)) {
        ix.set(0);
        iy.set(0);
        return;
      }
      const r = el.getBoundingClientRect();
      const dx = cursor.x - (r.left + r.width / 2);
      const dy = cursor.y - (r.top + r.height / 2);
      const d = Math.hypot(dx, dy);
      if (d < 0.5) {
        ix.set(0);
        iy.set(0);
        return;
      }
      const s = Math.min(1, d / FULL_TURN_DISTANCE);
      const k = s * s * (3 - 2 * s); // smoothstep: gentle near the eye, full when far
      ix.set((dx / d) * IRIS_REACH.x * k);
      iy.set((dy / d) * IRIS_REACH.y * k);
    };

    const tick = () => {
      aim(eyeLRef.current, ixL.raw, iyL.raw);
      aim(eyeRRef.current, ixR.raw, iyR.raw);

      const root = rootRef.current;
      if (root && !Number.isNaN(cursor.x)) {
        const r = root.getBoundingClientRect();
        const dx = cursor.x - (r.left + r.width / 2);
        const dy = cursor.y - (r.top + r.height * 0.35);
        hx.raw.set(Math.tanh(dx / 320) * 10);
        hy.raw.set(Math.tanh(dy / 320) * 6);
        lean.raw.set(Math.tanh(dx / 520) * 4);
      }
      raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);

    return () => {
      cancelAnimationFrame(raf);
      window.removeEventListener("pointermove", onPointer);
      window.removeEventListener("pointerdown", onPointer);
    };
  }, [ixL.raw, iyL.raw, ixR.raw, iyR.raw, hx.raw, hy.raw, lean.raw]);

  const body = `${uid}-body`;
  const belly = `${uid}-belly`;
  const tail = `${uid}-tail`;
  const iris = `${uid}-iris`;
  const glow = `${uid}-glow`;

  /** A glowing lava blotch: orange rim, hot yellow centre, slow pulse. */
  const blotch = (cx: number, cy: number, r: number, d: number, delay: number) => (
    <motion.g
      key={`${cx}-${cy}`}
      style={origin(cx, cy)}
      initial={{ opacity: 0.9 }}
      animate={run ? { opacity: [0.65, 1, 0.65], scale: [1, 1.2, 1] } : undefined}
      transition={loop(d, delay)}
    >
      <ellipse cx={cx} cy={cy} rx={r * 1.5} ry={r * 1.2} fill="#ff7a2a" />
      <ellipse cx={cx} cy={cy} rx={r * 0.85} ry={r * 0.65} fill="#ffd27a" />
    </motion.g>
  );

  const legParts = (cx: number) => (
    <>
      <ellipse cx={cx} cy="362" rx="30" ry="19" fill="#2c1c16" {...RIM} />
      <circle cx={cx - 20} cy="373" r="8" fill="#2c1c16" {...RIM} />
      <circle cx={cx} cy="379" r="8" fill="#2c1c16" {...RIM} />
      <circle cx={cx + 20} cy="373" r="8" fill="#2c1c16" {...RIM} />
      {blotch(cx, 360, 3.5, 2.5 + (cx % 3) * 0.3, 0.4)}
    </>
  );

  return (
    <motion.div
      ref={rootRef}
      className={className}
      whileHover="hover"
      whileTap="tap"
      onTap={() => setBurst((b) => b + 1)}
      variants={{
        hover: { rotate: [0, -2.5, 2.5, 0], transition: { duration: 0.7 } },
        tap: { y: -22, scaleY: 1.05, transition: { type: "spring", stiffness: 520, damping: 11 } },
      }}
      style={{ cursor: "pointer", touchAction: "manipulation" }}
    >
      <svg viewBox="0 0 440 400" role="img" aria-label={label} className="h-auto w-full" overflow="visible">
        <defs>
          <linearGradient id={body} x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor="#4d3026" />
            <stop offset="55%" stopColor="#2c1c16" />
            <stop offset="100%" stopColor="#170f0c" />
          </linearGradient>
          <linearGradient id={belly} x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor="#7a4328" />
            <stop offset="100%" stopColor="#3f2418" />
          </linearGradient>
          <linearGradient id={tail} x1="0" y1="0" x2="1" y2="0">
            <stop offset="0%" stopColor="#2c1c16" />
            <stop offset="100%" stopColor="#523327" />
          </linearGradient>
          <radialGradient id={iris} cx="50%" cy="50%" r="50%">
            <stop offset="0%" stopColor="#ffe08a" />
            <stop offset="60%" stopColor="#ff8a3d" />
            <stop offset="100%" stopColor="#c8380f" />
          </radialGradient>
          <radialGradient id={glow} cx="50%" cy="50%" r="50%">
            <stop offset="0%" stopColor="#ff8a3d" stopOpacity="0.35" />
            <stop offset="100%" stopColor="#ff8a3d" stopOpacity="0" />
          </radialGradient>
        </defs>

        {/* warm halo so the dark body reads on dark backgrounds */}
        <motion.ellipse
          cx="220"
          cy="250"
          rx="215"
          ry="170"
          fill={`url(#${glow})`}
          style={origin(220, 250)}
          animate={run ? { opacity: [0.7, 1, 0.7], scale: [1, 1.05, 1] } : undefined}
          transition={loop(3.6)}
        />

        {/* ground shadow */}
        <ellipse cx="220" cy="380" rx="135" ry="14" fill="#000" opacity="0.35" />

        {/* happy shimmy every few seconds */}
        <motion.g
          style={origin(220, 380)}
          animate={run ? { rotate: [0, -3, 3, -2.5, 2.5, -1, 0, 0] } : undefined}
          transition={{ duration: 8, times: [0, 0.02, 0.04, 0.06, 0.08, 0.1, 0.12, 1], repeat: Infinity, ease: "easeInOut", delay: 2.5 }}
        >
          {/* body leans toward the cursor and breathes */}
          <motion.g
            style={{ rotate: lean.smooth, ...origin(220, 380) }}
            animate={run ? { scaleY: [1, 1.03, 1], scaleX: [1, 0.985, 1], y: [0, -3, 0] } : undefined}
            transition={loop(2.6)}
          >
            {/* tail with glowing blotches */}
            <motion.g
              style={origin(290, 310)}
              animate={run ? { rotate: [0, 13, -6, 10, 0] } : undefined}
              transition={loop(3.4)}
            >
              <path
                d="M296 318 C 370 334, 420 292, 409 224 C 404 197, 384 185, 367 192"
                fill="none"
                stroke="#ff8a3d"
                strokeOpacity="0.5"
                strokeWidth="42"
                strokeLinecap="round"
              />
              <path
                d="M296 318 C 370 334, 420 292, 409 224 C 404 197, 384 185, 367 192"
                fill="none"
                stroke="#150d0a"
                strokeWidth="38"
                strokeLinecap="round"
              />
              <path
                d="M296 318 C 370 334, 420 292, 409 224 C 404 197, 384 185, 367 192"
                fill="none"
                stroke={`url(#${tail})`}
                strokeWidth="30"
                strokeLinecap="round"
              />
              {blotch(338, 327, 6, 2.6, 0.2)}
              {blotch(398, 288, 6, 3, 0.9)}
              {blotch(408, 232, 5.5, 2.8, 1.5)}
            </motion.g>

            {/* back legs */}
            <ellipse cx="128" cy="314" rx="37" ry="24" fill="#1d130f" {...RIM} transform="rotate(-20 128 314)" />
            <ellipse cx="312" cy="314" rx="37" ry="24" fill="#1d130f" {...RIM} transform="rotate(20 312 314)" />

            {/* body and belly */}
            <ellipse cx="220" cy="296" rx="103" ry="84" fill={`url(#${body})`} {...RIM} />
            <ellipse cx="220" cy="322" rx="60" ry="52" fill={`url(#${belly})`} />
            {blotch(150, 262, 9, 2.6, 0)}
            {blotch(292, 256, 8, 3.1, 0.6)}
            {blotch(220, 236, 7, 2.2, 1.1)}
            {blotch(190, 300, 5, 3.4, 0.3)}
            {blotch(252, 304, 5, 2.9, 1.7)}

            {/* front legs: the right one waves on hover */}
            <g>{legParts(158)}</g>
            <motion.g
              style={origin(282, 345)}
              variants={{ hover: { rotate: [0, -38, -8, -38, -8, 0], transition: { duration: 1.3 } } }}
            >
              {legParts(282)}
            </motion.g>

            {/* head */}
            <motion.g style={{ x: hx.smooth, y: hy.smooth, rotate: headRot, ...origin(220, 250) }}>
              <ellipse cx="220" cy="172" rx="120" ry="88" fill={`url(#${body})`} {...RIM} />
              <ellipse cx="188" cy="118" rx="52" ry="15" fill="#ffb25e" opacity="0.18" transform="rotate(-14 188 118)" />
              {blotch(136, 134, 8, 2.8, 0.3)}
              {blotch(304, 132, 7, 3.3, 0.9)}
              {blotch(168, 100, 6, 2.4, 1.4)}
              {blotch(272, 98, 6, 3, 0.2)}
              {blotch(220, 120, 5, 2.7, 1)}

              {/* the head flame */}
              <svg x="184" y="24" width="72" height="75" viewBox={FLAME_VIEWBOX} overflow="visible">
                <FlameBody glow={false} sparks={run} lean={false} animated={run} />
              </svg>

              {/* cheeks puff gently */}
              {[128, 312].map((cx) => (
                <motion.ellipse
                  key={cx}
                  cx={cx}
                  cy="206"
                  rx="22"
                  ry="13"
                  fill="#ff6a2a"
                  opacity="0.5"
                  style={origin(cx, 206)}
                  animate={run ? { scale: [1, 1.14, 1] } : undefined}
                  transition={loop(3.2, cx / 400)}
                />
              ))}

              {/* eyes: each one aims at the cursor on its own */}
              <Eye cx={EYES[0].x} cy={EYES[0].y} baseRef={eyeLRef} ix={ixL.smooth} iy={iyL.smooth} irisId={iris} run={run} />
              <Eye cx={EYES[1].x} cy={EYES[1].y} baseRef={eyeRRef} ix={ixR.smooth} iy={iyR.smooth} irisId={iris} run={run} />

              {/* nostrils, tongue flick, smile */}
              <circle cx="210" cy="198" r="3" fill="#ff8a3d" />
              <circle cx="230" cy="198" r="3" fill="#ff8a3d" />
              <motion.path
                d="M213 236 Q220 268 227 236 Z"
                fill="#ff7b8e"
                style={origin(220, 236)}
                initial={{ scaleY: 0 }}
                animate={run ? { scaleY: [0, 0, 1.05, 1.05, 0, 0] } : undefined}
                transition={{ duration: 7, times: [0, 0.7, 0.74, 0.8, 0.84, 1], repeat: Infinity, ease: "easeInOut" }}
              />
              <path d="M192 224 Q220 246 248 224" fill="none" stroke="#ffb25e" strokeWidth="5" strokeLinecap="round" />
            </motion.g>
          </motion.g>
        </motion.g>

        {/* ember burst when tapped */}
        {burst > 0 && (
          <g key={burst} aria-hidden="true">
            {Array.from({ length: 12 }, (_, i) => {
              const a = (i / 12) * Math.PI * 2;
              return (
                <motion.circle
                  key={i}
                  cx={220}
                  cy={110}
                  r={4}
                  fill={i % 2 ? "#ffd27a" : "#ff8a3d"}
                  initial={{ opacity: 1, x: 0, y: 0, scale: 1 }}
                  animate={{
                    opacity: 0,
                    x: Math.cos(a) * (100 + (i % 3) * 24),
                    y: Math.sin(a) * (80 + (i % 3) * 20) - 30,
                    scale: 0.3,
                  }}
                  transition={{ duration: 0.9, ease: "easeOut" }}
                />
              );
            })}
          </g>
        )}

        {/* drifting embers */}
        {run &&
          [
            { cx: 70, cy: 230, d: 4.2, de: 0 },
            { cx: 380, cy: 120, d: 3.6, de: 1.2 },
            { cx: 40, cy: 130, d: 4.8, de: 2 },
            { cx: 410, cy: 300, d: 4.1, de: 0.7 },
            { cx: 110, cy: 60, d: 3.9, de: 1.7 },
          ].map((p, i) => (
            <motion.circle
              key={i}
              cx={p.cx}
              cy={p.cy}
              r={3}
              fill="#ffd27a"
              initial={{ opacity: 0 }}
              animate={{ opacity: [0, 0.95, 0], y: [0, -70], x: [0, i % 2 ? 10 : -10] }}
              transition={{ duration: p.d, delay: p.de, repeat: Infinity, ease: "easeOut" }}
            />
          ))}
      </svg>
    </motion.div>
  );
}
