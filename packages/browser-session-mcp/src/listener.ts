/**
 * browser-session-listener — long-running CDP attach + per-visit NDJSON log.
 *
 * Connects to Chrome once. Drives target discovery via raw CDP (so we see
 * browserContextIds for contexts created by other clients — puppeteer's
 * own BrowserContext map only knows about contexts puppeteer itself created).
 *
 * For every page in every non-default BrowserContext we open a "visit" file
 * and route console + network events to it. Top-level navigation (via
 * Page.frameNavigated on the main frame) opens a fresh visit file. Layout:
 *
 *   <LOGS_DIR>/<sessionId>/<padded-seq>-<targetId>.ndjson
 *
 * Decoupled from mcp-proxy / executor: lifecycle is tied to chrome-headless
 * via a systemd service with Restart=always.
 *
 * Environment:
 *   BROWSER_URL   (default: http://127.0.0.1:9222)
 *   LOGS_DIR      (default: /var/lib/browser-session-mcp/logs)
 */

import puppeteer, { type Browser, type CDPSession } from "puppeteer-core";
import type { Protocol } from "devtools-protocol";

import { resolveWsEndpoint } from "./chrome.ts";
import { LogWriter, type ConsoleEntry, type NetworkEntry } from "./logs.ts";

const BROWSER_URL = process.env.BROWSER_URL ?? "http://127.0.0.1:9222";
const RECONNECT_BACKOFF_MS = 2_000;

const writer = new LogWriter();

const log = (msg: string) => process.stdout.write(`[listener] ${msg}\n`);
const warn = (msg: string) => process.stderr.write(`[listener] ${msg}\n`);

/**
 * Thrown when we never reached an established CDP session — chrome's port
 * isn't bound yet (early boot) or the proxy is down. The reconnect loop
 * treats these as expected and logs at info level instead of warning.
 */
class ConnectError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ConnectError";
  }
}

/**
 * Per-target state. The current `seq` is captured when each request fires
 * (in inflight) so a navigation mid-request still attributes the request
 * to the visit it was started under.
 */
type TargetState = {
  readonly ctxId: string;
  readonly targetId: string;
  currentSeq: number;
};

type Inflight = {
  readonly method: string;
  readonly url: string;
  readonly t: string;
  /**
   * The visit seq this request belongs to. Mutable: top-level Document
   * requests fire *before* Page.frameNavigated, so they're initially tagged
   * with the previous visit's seq. The frameNavigated handler retroactively
   * bumps them to the new visit so loadingFinished writes to the right file.
   */
  seq: number;
  status?: number;
  readonly frameId?: string;
  readonly type?: string;
};

async function attachToTarget(
  session: CDPSession,
  state: TargetState,
): Promise<void> {
  try {
    await session.send("Network.enable");
    await session.send("Runtime.enable");
    await session.send("Page.enable");
  } catch (err) {
    warn(
      `enable failed for target ${state.targetId}: ${err instanceof Error ? err.message : String(err)}`,
    );
    return;
  }

  const inflight = new Map<string, Inflight>();

  const writeEntry = (
    seq: number,
    entry: ConsoleEntry | NetworkEntry,
  ): void => {
    if (seq <= 0) return; // no visit open yet — drop pre-attach noise
    writer
      .append(state.ctxId, seq, state.targetId, entry)
      .catch((err) =>
        warn(
          `append failed for ${state.ctxId}/${seq}: ${err instanceof Error ? err.message : String(err)}`,
        ),
      );
  };

  // ---- navigation ----

  session.on("Page.frameNavigated", (e: Protocol.Page.FrameNavigatedEvent) => {
    // Only top-level navigations open new visits.
    if (e.frame.parentId) return;
    // Skip back-forward-cache restores; they reuse existing page state.
    if (e.type === "BackForwardCacheRestore") return;
    writer
      .openVisit(state.ctxId, state.targetId, e.frame.url)
      .then((newSeq) => {
        const oldSeq = state.currentSeq;
        state.currentSeq = newSeq;
        // Reattribute the document-level request that triggered this
        // navigation: it fired before frameNavigated and was therefore
        // tagged with the previous visit's seq. Bump it so loadingFinished
        // writes to the new visit's file.
        for (const inf of inflight.values()) {
          if (
            inf.type === "Document" &&
            inf.frameId === e.frame.id &&
            inf.seq === oldSeq
          ) {
            inf.seq = newSeq;
          }
        }
        log(
          `new visit seq=${newSeq} ctx=${state.ctxId.slice(0, 8)} url=${e.frame.url}`,
        );
      })
      .catch((err) =>
        warn(
          `openVisit failed: ${err instanceof Error ? err.message : String(err)}`,
        ),
      );
  });

  // ---- network ----

  session.on(
    "Network.requestWillBeSent",
    (e: Protocol.Network.RequestWillBeSentEvent) => {
      inflight.set(e.requestId, {
        method: e.request.method,
        url: e.request.url,
        t: new Date().toISOString(),
        seq: state.currentSeq,
        frameId: e.frameId,
        type: e.type,
      });
    },
  );

  session.on(
    "Network.responseReceived",
    (e: Protocol.Network.ResponseReceivedEvent) => {
      const inf = inflight.get(e.requestId);
      if (inf) inf.status = e.response.status;
    },
  );

  session.on(
    "Network.loadingFinished",
    (e: Protocol.Network.LoadingFinishedEvent) => {
      const inf = inflight.get(e.requestId);
      if (!inf) return;
      inflight.delete(e.requestId);
      writeEntry(inf.seq, {
        t: inf.t,
        kind: "network",
        method: inf.method,
        url: inf.url,
        status: inf.status ?? null,
      });
    },
  );

  session.on(
    "Network.loadingFailed",
    (e: Protocol.Network.LoadingFailedEvent) => {
      const inf = inflight.get(e.requestId);
      if (!inf) return;
      inflight.delete(e.requestId);
      writeEntry(inf.seq, {
        t: inf.t,
        kind: "network",
        method: inf.method,
        url: inf.url,
        status: null,
        failure: e.errorText,
      });
    },
  );

  // ---- console ----

  session.on(
    "Runtime.consoleAPICalled",
    (e: Protocol.Runtime.ConsoleAPICalledEvent) => {
      const text = e.args
        .map((a) => {
          if (a.value !== undefined) return String(a.value);
          if (a.description !== undefined) return a.description;
          return "";
        })
        .join(" ");
      writeEntry(state.currentSeq, {
        t: new Date().toISOString(),
        kind: "console",
        type: e.type,
        text,
      });
    },
  );

  session.on(
    "Runtime.exceptionThrown",
    (e: Protocol.Runtime.ExceptionThrownEvent) => {
      const ex = e.exceptionDetails;
      const description = ex.exception?.description ?? "";
      const text = description ? `${ex.text} ${description}`.trim() : ex.text;
      writeEntry(state.currentSeq, {
        t: new Date().toISOString(),
        kind: "console",
        type: "pageerror",
        text,
      });
    },
  );
}

async function runOnce(): Promise<void> {
  log(`connecting to ${BROWSER_URL}`);
  let browser: Browser;
  try {
    const wsEndpoint = await resolveWsEndpoint(BROWSER_URL);
    browser = await puppeteer.connect({
      browserWSEndpoint: wsEndpoint,
      defaultViewport: null,
      protocolTimeout: 0,
    });
  } catch (err) {
    throw new ConnectError(err instanceof Error ? err.message : String(err));
  }
  log(`connected; enabling auto-attach`);

  const browserCdp = await browser.target().createCDPSession();
  const conn = browserCdp.connection();
  if (!conn) throw new Error("CDP connection unavailable from browser session");

  const wired = new Set<string>();

  browserCdp.on(
    "Target.attachedToTarget",
    (e: Protocol.Target.AttachedToTargetEvent) => {
      const { sessionId: cdpSessionId, targetInfo } = e;
      if (targetInfo.type !== "page") return;
      const ctxId = targetInfo.browserContextId;
      if (!ctxId) return;
      if (wired.has(targetInfo.targetId)) return;

      const session = conn.session(cdpSessionId);
      if (!session) {
        warn(`no CDP session for ${cdpSessionId}`);
        return;
      }
      wired.add(targetInfo.targetId);

      // Open initial visit only if the target already has a real URL — that
      // happens when we adopt an existing tab (e.g. after a listener restart).
      // For freshly-created targets, targetInfo.url is empty; we defer until
      // the first Page.frameNavigated fires with the actual URL.
      const initialUrl = targetInfo.url;
      const initial: Promise<number> = initialUrl
        ? writer.openVisit(ctxId, targetInfo.targetId, initialUrl)
        : Promise.resolve(0);

      initial
        .then((seq) => {
          const state: TargetState = {
            ctxId,
            targetId: targetInfo.targetId,
            currentSeq: seq,
          };
          log(
            `attached page ${targetInfo.targetId.slice(0, 8)} ctx=${ctxId.slice(0, 8)} seq=${seq}`,
          );
          return attachToTarget(session, state);
        })
        .catch((err) =>
          warn(
            `failed to attach ${targetInfo.targetId}: ${err instanceof Error ? err.message : String(err)}`,
          ),
        );
    },
  );

  browserCdp.on(
    "Target.detachedFromTarget",
    (e: Protocol.Target.DetachedFromTargetEvent) => {
      if (e.targetId) wired.delete(e.targetId);
    },
  );

  await browserCdp.send("Target.setAutoAttach", {
    autoAttach: true,
    waitForDebuggerOnStart: false,
    flatten: true,
  });

  await new Promise<void>((_, reject) => {
    browser.on("disconnected", () => reject(new Error("browser disconnected")));
  });
}

async function main(): Promise<void> {
  let shuttingDown = false;
  process.on("SIGINT", () => {
    shuttingDown = true;
    process.exit(0);
  });
  process.on("SIGTERM", () => {
    shuttingDown = true;
    process.exit(0);
  });

  while (!shuttingDown) {
    try {
      await runOnce();
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      if (err instanceof ConnectError) {
        log(`waiting for browser: ${msg}`);
      } else {
        warn(`session ended: ${msg}`);
      }
    }
    if (shuttingDown) return;
    await new Promise((resolve) => setTimeout(resolve, RECONNECT_BACKOFF_MS));
  }
}

main().catch((err: unknown) => {
  process.stderr.write(
    `Fatal: ${err instanceof Error ? (err.stack ?? err.message) : String(err)}\n`,
  );
  process.exit(1);
});
