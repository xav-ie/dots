import type { Browser, BrowserContext, Page } from "puppeteer-core";
import type { StateStore } from "./state.ts";
import { resolveUA } from "./userAgent.ts";

export type SessionInfo = {
  readonly sessionId: string;
  readonly pageCount: number;
  readonly activeUrl: string | null;
};

export class SessionNotFoundError extends Error {
  constructor(sessionId: string) {
    super(`Session not found: ${sessionId}. Call open_browser_session first.`);
    this.name = "SessionNotFoundError";
  }
}

/**
 * Maps the public `sessionId` (string) onto a Puppeteer `BrowserContext`.
 *
 * Browser handle is acquired lazily — the MCP boots cleanly even if Chrome
 * is unreachable. We use the CDP browser-context id as the sessionId, which
 * means a session survives this MCP subprocess restarting; a fresh
 * subprocess reconnects to Chrome and finds existing contexts by id.
 *
 * Console + network history is captured by a separate, always-running
 * listener daemon that writes to disk — see logs.ts and listener.ts. This
 * class doesn't track events itself.
 */
export class SessionManager {
  constructor(
    private readonly getBrowser: () => Promise<Browser>,
    private readonly state: StateStore,
  ) {}

  async open(
    opts: {
      viewport?: { width: number; height: number };
      useMobileUA?: boolean;
    } = {},
  ): Promise<SessionInfo> {
    const browser = await this.getBrowser();
    const override = await resolveUA(browser, opts);
    const context = await browser.createBrowserContext();
    const id = context.id;
    if (!id) {
      await context.close();
      throw new Error("Chrome did not return a browser context id");
    }

    this.state.setUserAgentOverride(id, override);

    const page = await context.newPage();
    // setUserAgent before any navigation so even about:blank's load uses the
    // override — Puppeteer's setUserAgent maps to Network.setUserAgentOverride.
    await page.setUserAgent(override.userAgent, override.userAgentMetadata);
    await page.setViewport(opts.viewport ?? { width: 1280, height: 800 });
    await page.goto("about:blank");

    this.state.touch(id);
    return { sessionId: id, pageCount: 1, activeUrl: "about:blank" };
  }

  private async applyUA(sessionId: string, page: Page): Promise<void> {
    // Sessions opened before this feature have no override stored — leave them
    // alone rather than retroactively masking only newly-opened tabs.
    const override = this.state.getUserAgentOverride(sessionId);
    if (!override) return;
    await page.setUserAgent(override.userAgent, override.userAgentMetadata);
  }

  async close(sessionId: string): Promise<void> {
    const context = await this.findContext(sessionId);
    await context.close();
    this.state.forget(sessionId);
  }

  async list(): Promise<SessionInfo[]> {
    const browser = await this.getBrowser();
    const out: SessionInfo[] = [];
    for (const ctx of browser.browserContexts()) {
      if (!ctx.id) continue;
      const pages = await ctx.pages();
      const active = pages[pages.length - 1];
      out.push({
        sessionId: ctx.id,
        pageCount: pages.length,
        activeUrl: active ? active.url() : null,
      });
    }
    return out;
  }

  async findContext(sessionId: string): Promise<BrowserContext> {
    const browser = await this.getBrowser();
    for (const ctx of browser.browserContexts()) {
      if (ctx.id === sessionId) {
        this.state.touch(sessionId);
        return ctx;
      }
    }
    throw new SessionNotFoundError(sessionId);
  }

  async activePage(sessionId: string): Promise<Page> {
    const ctx = await this.findContext(sessionId);
    const pages = await ctx.pages();
    if (pages.length === 0) {
      const page = await ctx.newPage();
      await this.applyUA(sessionId, page);
      return page;
    }
    return pages[pages.length - 1]!;
  }

  async newPage(sessionId: string): Promise<Page> {
    const ctx = await this.findContext(sessionId);
    const page = await ctx.newPage();
    await this.applyUA(sessionId, page);
    return page;
  }

  async pages(sessionId: string): Promise<Page[]> {
    const ctx = await this.findContext(sessionId);
    return await ctx.pages();
  }
}
