import type { Metadata, Viewport } from "next";
import { Montserrat, Montserrat_Alternates } from "next/font/google";
import "./globals.css";
import Header from "./components/Header";

const montserrat = Montserrat({
  subsets: ["latin"],
  variable: "--font-montserrat",
  fallback: ["Arial", "sans-serif"],
});

const montserratAlternates = Montserrat_Alternates({
  subsets: ["latin"],
  variable: "--font-montserrat-alternates",
  weight: ["400", "600", "700"],
});

export const metadata: Metadata = {
  title: "Ritual Roast | Share Your Signature Dish",
  description: "Cook Up a Storm: Submit your best recipe for the Ritual Roast contest!",
  icons: {
    icon: "/favicon.ico", // Ensure you have this in your public folder
  },
};

// 1. ACCESSIBILITY FIX: Re-enable scaling for better UX and SEO ranking
export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  // maximumScale removed to allow user zooming
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en" className="scroll-smooth">
      <body
        className={`${montserrat.variable} ${montserratAlternates.variable} font-montserrat min-h-screen flex flex-col antialiased`}
      >
        <Header />
        
        {/* 2. LAYOUT STABILITY: flex-grow ensures footer stays at bottom on short pages */}
        <main className="w-full mx-auto flex-grow outline-none" id="main-content">
          {children}
        </main>

        <footer className="w-full flex flex-col sm:flex-row text-[color:var(--brown-dark)]">
          <div className="flex-grow bg-[color:var(--brown-dark)] hidden sm:block"></div>
          <div
            className="py-4 px-4 sm:px-10 text-center text-sm md:text-base bg-[color:var(--gold)] font-bold w-full sm:w-auto"
            style={{ fontFamily: "var(--font-montserrat-alternates)" }}
          >
            Copyrights &copy; {new Date().getFullYear()} Ritual Roast Limited
          </div>
          <div className="flex-grow bg-[color:var(--brown-dark)] hidden sm:block"></div>
        </footer>
      </body>
    </html>
  );
}