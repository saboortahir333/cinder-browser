const words = [
  "Tracker blocking",
  "Encrypted sync",
  "Private profiles",
  "Manifest V3 extensions",
  "HTTPS-only mode",
  "No telemetry",
  "Open source",
];

function Row({ hidden }: { hidden?: boolean }) {
  return (
    <ul
      aria-hidden={hidden || undefined}
      className="flex shrink-0 items-center gap-10 pr-10"
    >
      {words.map((w) => (
        <li
          key={w}
          className="flex items-center gap-10 whitespace-nowrap font-display text-2xl font-bold text-muted-foreground/70 sm:text-3xl"
        >
          <span>{w}</span>
          <span aria-hidden="true" className="size-2 rounded-full bg-flame" />
        </li>
      ))}
    </ul>
  );
}

/** Slow, pausable ticker of what Cinder is. The second row is a visual duplicate. */
export function Marquee() {
  return (
    <section
      aria-label="Cinder at a glance"
      className="mt-2 overflow-hidden border-y border-border/60 py-5 [mask-image:linear-gradient(90deg,transparent,#000_10%,#000_90%,transparent)]"
    >
      <div className="flex w-max animate-marquee hover:[animation-play-state:paused]">
        <Row />
        <Row hidden />
      </div>
    </section>
  );
}
