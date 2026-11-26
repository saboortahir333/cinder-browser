"use client";

import { useSyncExternalStore } from "react";

const QUERY = "(prefers-reduced-motion: reduce)";

function subscribe(onChange: () => void) {
  const mq = window.matchMedia(QUERY);
  mq.addEventListener("change", onChange);
  return () => mq.removeEventListener("change", onChange);
}

/**
 * Hydration-safe reduced-motion check. Returns false on the server and during
 * hydration, then the real preference, so server and client markup always match.
 * Used for LARGE motion only (scroll reveals, parallax, particle canvas).
 */
export function useReducedMotion(): boolean {
  return useSyncExternalStore(
    subscribe,
    () => window.matchMedia(QUERY).matches,
    () => false,
  );
}

/* ---- User-controlled pause for the mascot and flame ------------------------
 * Ash and the flame only make small, local idle movements, so they keep running
 * under reduced motion. People who want them still can pause them here.
 */
const KEY = "cinder:pause-animations";
const listeners = new Set<() => void>();

function readPaused(): boolean {
  try {
    return localStorage.getItem(KEY) === "1";
  } catch {
    return false;
  }
}

function subscribePaused(onChange: () => void) {
  listeners.add(onChange);
  window.addEventListener("storage", onChange);
  return () => {
    listeners.delete(onChange);
    window.removeEventListener("storage", onChange);
  };
}

export function useAnimationsPaused(): boolean {
  return useSyncExternalStore(subscribePaused, readPaused, () => false);
}

export function setAnimationsPaused(paused: boolean) {
  try {
    localStorage.setItem(KEY, paused ? "1" : "0");
  } catch {
    /* storage unavailable: the in-memory listeners below still update the page */
  }
  listeners.forEach((l) => l());
}
