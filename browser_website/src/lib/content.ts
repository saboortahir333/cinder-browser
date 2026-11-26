import type { IconSvgElement } from "@hugeicons/react";
import {
  Shield01Icon,
  IncognitoIcon,
  CloudIcon,
  PuzzleIcon,
  KeyboardIcon,
  LockIcon,
} from "@hugeicons/core-free-icons";

/**
 * Feature copy. Every statement here is taken from the browser repo
 * (README.md, PRIVACY.md, docs/*.md). Do not add a claim without a source.
 */
export type Feature = {
  id: "trackers" | "private" | "sync" | "extensions" | "access" | "https";
  icon: IconSvgElement;
  kicker: string;
  title: string;
  body: string;
  points: string[];
};

export const features: Feature[] = [
  {
    id: "trackers",
    icon: Shield01Icon,
    kicker: "Tracker and ad blocking",
    title: "Trackers get burned before they load.",
    body: "Requests are matched against the EasyList and EasyPrivacy filter lists by Brave's open-source adblock engine, running locally in Rust. A host list of known-malicious sites (URLhaus) is checked the same way.",
    points: [
      "Matching happens on your device, not on a server.",
      "Lists refresh about once a week with a request that carries no account or browsing data.",
      "Per-site permission prompts for camera, microphone, location and notifications.",
    ],
  },
  {
    id: "private",
    icon: IncognitoIcon,
    kicker: "Private windows and profiles",
    title: "Private means nothing is left behind.",
    body: "Private windows and separate profiles run as separate processes. A private window writes no history, session, cache or cookies to disk, and it never syncs.",
    points: [
      "Guest mode keeps everything in memory. Nothing is sent to Cinder's servers.",
      "Extensions are off in private windows unless you allow them.",
      "Favicons are never loaded from third-party services.",
    ],
  },
  {
    id: "sync",
    icon: CloudIcon,
    kicker: "End-to-end encrypted sync",
    title: "Sync that the server cannot read.",
    body: "Signed-in mode syncs bookmarks, history, settings and your downloads list through the Cinder cloud, encrypted with a key derived from your passphrase. The server stores ciphertext only.",
    points: [
      "Your passphrase never leaves your device.",
      "Sync is optional. Guest mode needs no account.",
      "The data model and threat model are published in the repo.",
    ],
  },
  {
    id: "extensions",
    icon: PuzzleIcon,
    kicker: "Manifest V3 extensions",
    title: "Real extensions, with a permission prompt first.",
    body: "Cinder runs Manifest V3 extensions, including content scripts and toolbar popups. Each extension shows a permission prompt before it can see what its permissions allow.",
    points: [
      "Installing from a store contacts that store (Google or Microsoft).",
      "A management screen for installing and disabling extensions is still being built.",
    ],
  },
  {
    id: "access",
    icon: KeyboardIcon,
    kicker: "Accessibility",
    title: "Built to be used without a mouse.",
    body: "Cinder has a high-contrast mode and keyboard-only support, in a Firefox-style interface that keeps the controls you expect where you expect them.",
    points: [
      "Keyboard-only navigation across the browser chrome.",
      "High-contrast support.",
    ],
  },
  {
    id: "https",
    icon: LockIcon,
    kicker: "HTTPS-only mode",
    title: "Secure connections by default.",
    body: "HTTPS-only mode upgrades connections and warns before loading a site over plain HTTP.",
    points: ["Works together with per-site permission prompts."],
  },
];

/** What is not built yet, taken from docs/implementation-status.md. */
export const notYet = [
  "A management screen for installing and disabling extensions",
  "Tab groups and workspaces",
  "Developer tools",
  "A full offline mode (sync and history currently need a connection)",
];

export const trustFacts = [
  { label: "No telemetry", detail: "No analytics, ads or tracking in the browser." },
  { label: "Encrypted sync", detail: "The server cannot read your data." },
  { label: "Open source", detail: "Apache-2.0 licensed." },
  { label: "HTTPS-only mode", detail: "Secure connections by default." },
];
