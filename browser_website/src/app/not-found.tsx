import { Mascot } from "@/components/brand/mascot";
import { CtaLink } from "@/components/site/cta-link";

export default function NotFound() {
  return (
    <div className="mx-auto flex max-w-3xl flex-col items-center px-4 py-20 text-center sm:py-28">
      <Mascot className="w-56 sm:w-64" label="Ash the salamander, looking for the page" />
      <p className="mt-6 font-display text-sm font-bold uppercase tracking-widest text-primary">404</p>
      <h1 className="mt-2 text-4xl font-extrabold sm:text-5xl">This page burned up.</h1>
      <p className="mt-3 max-w-md text-muted-foreground">
        Ash looked everywhere but couldn&apos;t find what you were after.
      </p>
      <CtaLink href="/" className="mt-8">
        Back to the home page
      </CtaLink>
    </div>
  );
}
