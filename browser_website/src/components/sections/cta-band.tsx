import { HugeiconsIcon } from "@hugeicons/react";
import { Download01Icon } from "@hugeicons/core-free-icons";
import { site } from "@/lib/site-config";
import { Mascot } from "@/components/brand/mascot";
import { EmberField } from "@/components/brand/ember-field";
import { Reveal } from "@/components/brand/reveal";
import { CtaLink } from "@/components/site/cta-link";

export function CtaBand() {
  return (
    <section className="mx-auto mt-28 max-w-6xl px-4 sm:px-6" aria-labelledby="cta-title">
      <Reveal>
        <div className="relative isolate overflow-hidden rounded-[2rem] border border-ember-700/40 bg-gradient-to-br from-coal-800 via-coal-900 to-ember-950 px-6 py-14 text-[#f8ece1] sm:px-12">
          <div className="absolute inset-0 -z-10 opacity-80" aria-hidden="true">
            <EmberField count={55} />
          </div>
          <div className="glow-orb absolute -bottom-40 right-0 -z-10 size-[520px] rounded-full" aria-hidden="true" />
          <div className="grid items-center gap-8 md:grid-cols-[1.3fr_0.7fr]">
            <div>
              <h2 id="cta-title" className="text-4xl font-extrabold leading-tight sm:text-5xl">
                Ready to fire it up?
              </h2>
              <p className="mt-4 max-w-lg text-lg text-[#d9c6b8]">
                Download {site.name} for Windows and take your browsing back from
                the trackers.
              </p>
              <div className="mt-7 flex flex-wrap items-center gap-4">
                <CtaLink href="/download">
                  <HugeiconsIcon icon={Download01Icon} size={20} />
                  Download for Windows
                </CtaLink>
                <span className="text-sm text-[#b9a597]">{site.requirements}</span>
              </div>
            </div>
            <Mascot className="mx-auto w-48 sm:w-60" />
          </div>
        </div>
      </Reveal>
    </section>
  );
}
