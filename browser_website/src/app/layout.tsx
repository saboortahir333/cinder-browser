import type { Metadata, Viewport } from "next";
import "./globals.css";
import { Figtree, Bricolage_Grotesque, JetBrains_Mono } from "next/font/google";
import { cn } from "@/lib/utils";
import { site } from "@/lib/site-config";
import { ThemeProvider } from "@/components/site/theme-provider";
import { PointerProvider } from "@/components/brand/pointer";
import { Header } from "@/components/site/header";
import { Footer } from "@/components/site/footer";

const figtree = Figtree({ subsets: ["latin"], variable: "--font-figtree" });
const bricolage = Bricolage_Grotesque({
  subsets: ["latin"],
  variable: "--font-bricolage",
});
const jetbrains = JetBrains_Mono({
  subsets: ["latin"],
  variable: "--font-jetbrains",
});

export const metadata: Metadata = {
  metadataBase: new URL(site.url),
  title: {
    default: `${site.name}: a private browser for Windows`,
    template: `%s | ${site.name}`,
  },
  description: site.description,
  applicationName: site.name,
  openGraph: {
    title: `${site.name}: a private browser for Windows`,
    description: site.description,
    url: site.url,
    siteName: site.name,
    type: "website",
  },
  twitter: { card: "summary_large_image" },
};

export const viewport: Viewport = {
  themeColor: [
    { media: "(prefers-color-scheme: dark)", color: "#110b09" },
    { media: "(prefers-color-scheme: light)", color: "#fff8f1" },
  ],
};

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html
      lang="en"
      suppressHydrationWarning
      className={cn(
        "font-sans",
        figtree.variable,
        bricolage.variable,
        jetbrains.variable,
      )}
    >
      <body>
        <ThemeProvider
          attribute="class"
          defaultTheme="dark"
          enableSystem={false}
          disableTransitionOnChange
        >
          <PointerProvider>
            <a
              href="#main"
              className="sr-only focus:not-sr-only focus:fixed focus:left-4 focus:top-4 focus:z-[100] focus:rounded-full focus:bg-primary focus:px-4 focus:py-2 focus:text-primary-foreground"
            >
              Skip to content
            </a>
            <Header />
            <main id="main">{children}</main>
            <Footer />
          </PointerProvider>
        </ThemeProvider>
      </body>
    </html>
  );
}
