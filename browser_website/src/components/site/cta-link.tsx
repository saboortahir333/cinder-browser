import Link from "next/link";
import { cn } from "@/lib/utils";
import { buttonVariants } from "@/components/ui/button";

type Props = React.ComponentProps<typeof Link> & {
  tone?: "flame" | "outline";
};

/** Link styled as a button. `flame` is the primary download-style action. */
export function CtaLink({ tone = "flame", className, ...props }: Props) {
  return (
    <Link
      {...props}
      className={cn(
        buttonVariants({ variant: "ghost" }),
        "h-12 gap-2 rounded-full px-6 text-base font-semibold",
        tone === "flame" &&
          "bg-flame text-[#1c0a03] shadow-[0_12px_40px_-12px_var(--glow-a)] hover:-translate-y-0.5 hover:brightness-110",
        tone === "outline" &&
          "border-border bg-card/50 backdrop-blur hover:bg-card",
        className,
      )}
    />
  );
}
