import "./globals.css";
export const metadata = { title: "Whitty Hybrid — Diagnostic Agent", description: "AI cloud + local network diagnostics with one-click VPN" };
export default function RootLayout({ children }: { children: React.ReactNode }) {
  return <html lang="en"><body className="bg-slate-950 text-slate-100 antialiased">{children}</body></html>;
}
