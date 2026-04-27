import type { Browser, BrowserContext, Page } from "puppeteer-core";
import type { StateStore } from "./state.ts";

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

  async open(viewport?: {
    width: number;
    height: number;
  }): Promise<SessionInfo> {
    const browser = await this.getBrowser();
    const context = await browser.createBrowserContext();
    const id = context.id;
    if (!id) {
      await context.close();
      throw new Error("Chrome did not return a browser context id");
    }

    const page = await context.newPage();
    await page.setViewport(viewport ?? { width: 1280, height: 800 });
    await page.goto("about:blank");

    this.state.touch(id);
    return { sessionId: id, pageCount: 1, activeUrl: "about:blank" };
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
      return await ctx.newPage();
    }
    return pages[pages.length - 1]!;
  }

  async newPage(sessionId: string): Promise<Page> {
    const ctx = await this.findContext(sessionId);
    return await ctx.newPage();
  }

  async pages(sessionId: string): Promise<Page[]> {
    const ctx = await this.findContext(sessionId);
    return await ctx.pages();
  }
}
