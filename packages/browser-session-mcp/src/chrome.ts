import puppeteer, { type Browser } from "puppeteer-core";

let browser: Browser | undefined;

/**
 * Connect once, reuse across calls. Reconnects transparently if the previous
 * handle disconnected (e.g. Chrome restarted).
 *
 * We don't pass `browserURL` to puppeteer.connect because Puppeteer's
 * `getWSEndpoint(browserURL)` returns whatever Chrome reports in its
 * `/json/version` response verbatim — and Chrome reports its own loopback
 * (e.g. `ws://127.0.0.1:9222/devtools/browser/<id>`). When this MCP runs
 * inside a container, that 127.0.0.1 is the container's loopback, so the
 * subsequent WebSocket connect fails with ECONNREFUSED.
 *
 * Instead we fetch /json/version ourselves, take only the path of the
 * `webSocketDebuggerUrl`, and rebuild the URL using the externally-reachable
 * host we already have. The proxy (Traefik in our setup) routes that back
 * to Chrome on the host.
 */
export async function getBrowser(browserURL: string): Promise<Browser> {
  if (browser?.connected) return browser;
  const wsEndpoint = await resolveWsEndpoint(browserURL);
  browser = await puppeteer.connect({
    browserWSEndpoint: wsEndpoint,
    defaultViewport: null,
    protocolTimeout: 180_000,
  });
  return browser;
}

export async function resolveWsEndpoint(browserURL: string): Promise<string> {
  const versionURL = new URL("/json/version", browserURL);
  const res = await fetch(versionURL.toString(), { method: "GET" });
  if (!res.ok) {
    throw new Error(
      `GET ${versionURL.toString()} returned ${res.status} ${res.statusText}`,
    );
  }
  const json = (await res.json()) as { webSocketDebuggerUrl?: string };
  const reported = json.webSocketDebuggerUrl;
  if (!reported) {
    throw new Error(
      `${versionURL.toString()} response did not include webSocketDebuggerUrl`,
    );
  }
  // Take only the path/search of what Chrome reports; keep our reachable host.
  const reportedURL = new URL(reported);
  const ws = new URL(versionURL.toString());
  ws.protocol = ws.protocol === "https:" ? "wss:" : "ws:";
  ws.pathname = reportedURL.pathname;
  ws.search = reportedURL.search;
  return ws.toString();
}

export async function closeBrowser(): Promise<void> {
  if (!browser) return;
  try {
    await browser.disconnect();
  } catch {
    // ignore
  }
  browser = undefined;
}
