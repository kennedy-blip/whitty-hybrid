"use client";
// Browser-side helper: remembers the tunnel URL for YOUR daemon (localStorage)
// and forwards it to our own API routes via the x-bridge-url header.
const KEY = "whitty.bridgeUrl";

export function getBridgeUrl(): string {
  if (typeof window === "undefined") return "";
  return window.localStorage.getItem(KEY) || "";
}

export function setBridgeUrl(url: string) {
  if (typeof window === "undefined") return;
  const clean = url.trim().replace(/\/$/, "");
  if (clean) window.localStorage.setItem(KEY, clean);
  else window.localStorage.removeItem(KEY);
  window.dispatchEvent(new Event("whitty:bridge-changed"));
}

export async function bfetch(path: string, init: RequestInit = {}) {
  const url = getBridgeUrl();
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
    ...((init.headers as Record<string, string>) || {}),
  };
  if (url) headers["x-bridge-url"] = url;
  return fetch(path, { ...init, headers, cache: "no-store" });
}

export async function bjson(path: string, init: RequestInit = {}) {
  const res = await bfetch(path, init);
  return res.json();
}
