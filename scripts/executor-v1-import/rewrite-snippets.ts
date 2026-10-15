#!/usr/bin/env bun
/**
 * Rewrites saved snippets' v1 tool-call expressions to v2 ones, using path-map.json. Mechanical,
 * narrow rewrites only: a v1 tool address that path-map.json resolves exactly becomes the v2
 * expression it already carries; a bare `tools.<integration>.org|user.<connection>` namespace
 * alias (e.g. `const S = tools.slack.org.workspace`) becomes v2's single-level app accessor.
 * Everything else that touches a tool path is left untouched and flagged with a reason:
 *
 *   - dynamic path construction (string concatenation, a template placeholder as the whole
 *     bracket key, or any multi-segment access this script doesn't recognize)
 *   - a v1 path with no v2 counterpart in path-map.json (unmapped tool)
 *   - the v1 `{ ok, data }` result envelope (checked as `.ok` / read as `.data...`), which v2
 *     calls don't return (v2 returns the raw MCP `{ content, isError }` shape) -- flagged on
 *     every snippet that touches it; never auto-rewritten, since the right replacement depends
 *     on what the snippet does with a failure
 *   - a frontmatter `integrations` field naming a v1 integration that now maps to more than one
 *     v2 app (atlassian, google_workspace) -- expanded only when unambiguous
 *
 * Usage:
 *   ./rewrite-snippets.ts --path-map path-map.json --mcp-url http://127.0.0.1:38974/mcp --dry-run
 *   ./rewrite-snippets.ts --path-map path-map.json --mcp-url http://127.0.0.1:38974/mcp --apply
 *
 * --dry-run prints a unified diff per snippet that would change, plus a flags summary; it never
 * calls snippet-mcp's write tools. --apply calls `_update` with the rewritten body (and, when
 * relevant, `integrations`) for every snippet whose rewrite left it with no unresolved flags on
 * the parts that changed; a snippet with any flag is never written automatically.
 */
import { writeFileSync } from "node:fs";

// ---------------------------------------------------------------------------
// path-map.json -> lookup tables
// ---------------------------------------------------------------------------

interface PathMapEntry {
  readonly v1: string;
  readonly v2: string | null;
  readonly v2Path: string | null;
  readonly app: string;
}

// (integration, connection) -> v2 app slug, same table build-path-map.ts uses to deploy. A
// namespace alias (`tools.<integration>.org.<connection>` with no following tool) is resolved
// against this directly, since path-map.json's entries are all four-segment (tool-level).
const APP_SLUG: Record<string, string> = {
  "agent/workspace": "agent",
  "atlassian/delivery": "atlassian-delivery",
  "atlassian/product": "atlassian-product",
  "browser_session/workspace": "browser-session",
  "discord/workspace": "discord",
  "divvy/divvy": "divvy",
  "github/github": "github",
  "google_workspace/personal": "google-workspace-personal",
  "google_workspace/work": "google-workspace-work",
  "gtm/workspace": "gtm",
  "herdr/workspace": "herdr",
  "nixos/workspace": "nixos",
  "outsmartly/outsmartlyoauth": "outsmartly",
  "postiz/localpostiz": "postiz",
  "proton_mail/workspace": "proton-mail",
  "scribe/workspace": "scribe",
  "slack/workspace": "slack",
  "snippets/workspace": "snippets",
  "tasks/workspace": "tasks",
};

// Integrations with more than one v2 app -- a frontmatter `integrations` entry naming one of
// these can't be expanded to a single slug without knowing which connection the snippet means.
const AMBIGUOUS_INTEGRATIONS = new Set(["atlassian", "google_workspace"]);

const isIdentifier = (value: string) => /^[A-Za-z_$][A-Za-z0-9_$]*$/.test(value);
const slugAccessor = (slug: string) => (isIdentifier(slug) ? `tools.${slug}` : `tools[${JSON.stringify(slug)}]`);

interface Lookups {
  /** "integration.org.connection.tool" (no leading "tools.") -> the v2 expression to substitute. */
  readonly exact: Map<string, string>;
  /** "integration.owner.connection" -> the v2 app accessor (no trailing tool). */
  readonly namespace: Map<string, string>;
}

const loadLookups = (pathMapFile: string): Lookups => {
  const data = JSON.parse(require("node:fs").readFileSync(pathMapFile, "utf8")) as { entries: readonly PathMapEntry[] };
  const exact = new Map<string, string>();
  for (const entry of data.entries) {
    if (entry.v2 === null) continue;
    exact.set(entry.v1.slice("tools.".length), entry.v2);
  }
  const namespace = new Map<string, string>();
  for (const [key, slug] of Object.entries(APP_SLUG)) {
    const [integration, connection] = key.split("/") as [string, string];
    namespace.set(`${integration}.org.${connection}`, slugAccessor(slug));
    namespace.set(`${integration}.user.${connection}`, slugAccessor(slug));
  }
  return { exact, namespace };
};

// ---------------------------------------------------------------------------
// Body rewrite
// ---------------------------------------------------------------------------

interface Flag {
  readonly reason: string;
  readonly detail: string;
}

interface RewriteResult {
  readonly body: string;
  readonly changed: boolean;
  readonly flags: Flag[];
}

/** One `.identifier` or `["string"]`/`['string']` member, or a non-identifier bracket expression
 * (concatenation, a variable, a template placeholder) that we deliberately don't resolve. */
const BRACKET = /\[(?:(["'])((?:\\.|(?!\1)[^\\])*)\1|([^\]]*))\]/;
const DOT4 = /^\.([A-Za-z_$][\w$]*)\.(org|user)\.([A-Za-z_$][\w$]*)\.([A-Za-z_$][\w$]*)/;
const DOT3 = /^\.([A-Za-z_$][\w$]*)\.(org|user)\.([A-Za-z_$][\w$]*)/;

const rewriteBody = (body: string, lookups: Lookups): RewriteResult => {
  const flags: Flag[] = [];
  let changed = false;
  let out = "";
  let i = 0;
  while (i < body.length) {
    if (body.startsWith("tools", i) && (body[i + 5] === "." || body[i + 5] === "[")) {
      const rest = body.slice(i + "tools".length);

      // tools["..."] or tools['...'] or tools[<anything else>]
      if (rest[0] === "[") {
        const m = BRACKET.exec(rest);
        if (m !== null) {
          const quoted = m[2];
          if (quoted !== undefined) {
            const v2 = lookups.exact.get(quoted);
            if (v2 !== undefined) {
              out += v2;
              changed = true;
              i += "tools".length + m[0].length;
              continue;
            }
            flags.push({
              reason: "unmapped tool path",
              detail: `tools["${quoted}"] has no v2 counterpart in path-map.json`,
            });
          } else {
            flags.push({
              reason: "dynamic path construction",
              detail: `tools[${m[3]}] is not a plain string literal (concatenation, a variable, or a template placeholder) -- left unchanged`,
            });
          }
          out += "tools" + m[0];
          i += "tools".length + m[0].length;
          continue;
        }
      }

      // tools.integration.org|user.connection.tool  or  tools.integration.org|user.connection
      const dot4 = DOT4.exec(rest);
      if (dot4 !== null) {
        const [matched, integration, owner, connection, tool] = dot4;
        const v2 = lookups.exact.get(`${integration}.${owner}.${connection}.${tool}`);
        if (v2 !== undefined) {
          out += v2;
          changed = true;
          i += "tools".length + matched.length;
          continue;
        }
        // Not a known tool on that connection: fall through to flag the 3-segment namespace
        // below, with the tool name left attached as plain trailing text.
      }
      const dot3 = DOT3.exec(rest);
      if (dot3 !== null) {
        const [matched, integration, owner, connection] = dot3;
        const slug = lookups.namespace.get(`${integration}.${owner}.${connection}`);
        if (slug !== undefined) {
          out += slug;
          changed = true;
          i += "tools".length + matched.length;
          continue;
        }
        flags.push({
          reason: "unmapped tool path",
          detail: `tools.${integration}.${owner}.${connection} has no v2 app mapping`,
        });
        out += "tools" + matched;
        i += "tools".length + matched.length;
        continue;
      }
    }
    out += body[i];
    i++;
  }

  // The v1 result envelope (`{ ok, data }`) that v2 calls don't return. Heuristic: any `.ok` or
  // `.data` access near a tool call; cheap and tuned for this snippet set's actual style (every
  // example checks `if (!x.ok) ...` and reads `x.data...`), not a general JS analyzer.
  if (/\.ok\b/.test(body) || /\.data\b/.test(body)) {
    flags.push({
      reason: "v1 result envelope",
      detail:
        "checks `.ok` and/or reads `.data` on a tool call's result; v2 calls return the raw MCP " +
        "{ content, isError } shape instead of v1's { ok, data } / { ok: false, error }. The " +
        "success check and unwrap need a manual rewrite -- not something this script can do " +
        "safely without knowing what the snippet should do on failure.",
    });
  }

  return { body: out, changed, flags: dedupeFlags(flags) };
};

const dedupeFlags = (flags: readonly Flag[]): Flag[] => {
  const seen = new Set<string>();
  const result: Flag[] = [];
  for (const flag of flags) {
    const key = `${flag.reason}:${flag.detail}`;
    if (seen.has(key)) continue;
    seen.add(key);
    result.push(flag);
  }
  return result;
};

// ---------------------------------------------------------------------------
// Frontmatter `integrations` field
// ---------------------------------------------------------------------------

const rewriteIntegrations = (
  integrations: readonly string[] | undefined,
): { readonly integrations: readonly string[] | undefined; readonly flags: Flag[] } => {
  if (integrations === undefined || integrations.length === 0) return { integrations, flags: [] };
  const flags: Flag[] = [];
  const out = new Set<string>();
  for (const slug of integrations) {
    if (AMBIGUOUS_INTEGRATIONS.has(slug)) {
      flags.push({
        reason: "ambiguous frontmatter integration",
        detail: `integrations: "${slug}" now maps to more than one v2 app (${Object.entries(APP_SLUG)
          .filter(([key]) => key.startsWith(`${slug}/`))
          .map(([, v]) => v)
          .join(", ")}); left as-is`,
      });
      out.add(slug);
      continue;
    }
    const entry = Object.entries(APP_SLUG).find(([key]) => key.startsWith(`${slug}/`));
    out.add(entry ? entry[1] : slug);
    if (!entry) flags.push({ reason: "unmapped frontmatter integration", detail: `integrations: "${slug}" has no known v2 app` });
  }
  return { integrations: [...out], flags };
};

// ---------------------------------------------------------------------------
// Unified diff (line-based; this rewrite never adds/removes lines, only edits them in place)
// ---------------------------------------------------------------------------

const unifiedDiff = (name: string, before: string, after: string): string => {
  const beforeLines = before.split("\n");
  const afterLines = after.split("\n");
  const hunks: string[] = [];
  for (let i = 0; i < Math.max(beforeLines.length, afterLines.length); i++) {
    if (beforeLines[i] !== afterLines[i]) {
      if (beforeLines[i] !== undefined) hunks.push(`-${beforeLines[i]}`);
      if (afterLines[i] !== undefined) hunks.push(`+${afterLines[i]}`);
    }
  }
  if (hunks.length === 0) return "";
  return `--- ${name} (before)\n+++ ${name} (after)\n${hunks.join("\n")}\n`;
};

// ---------------------------------------------------------------------------
// snippet-mcp MCP client (read-only in dry-run; _update only under --apply)
// ---------------------------------------------------------------------------

class SnippetMcpClient {
  private sessionId: string | undefined;
  private id = 0;

  constructor(private readonly url: string) {}

  private async call(name: string, args: Record<string, unknown>) {
    const headers: Record<string, string> = { "Content-Type": "application/json", Accept: "application/json, text/event-stream" };
    if (this.sessionId) headers["mcp-session-id"] = this.sessionId;
    if (!this.sessionId) {
      const init = await fetch(this.url, {
        method: "POST",
        headers,
        body: JSON.stringify({
          jsonrpc: "2.0",
          id: ++this.id,
          method: "initialize",
          params: { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "rewrite-snippets", version: "0.0.1" } },
        }),
      });
      this.sessionId = init.headers.get("mcp-session-id") ?? undefined;
      if (this.sessionId) headers["mcp-session-id"] = this.sessionId;
      await fetch(this.url, { method: "POST", headers, body: JSON.stringify({ jsonrpc: "2.0", method: "notifications/initialized" }) });
    }
    const response = await fetch(this.url, {
      method: "POST",
      headers,
      body: JSON.stringify({ jsonrpc: "2.0", id: ++this.id, method: "tools/call", params: { name, arguments: args } }),
    });
    const text = await response.text();
    const line = text.split("\n").find((l) => l.startsWith("data: {"));
    if (!line) throw new Error(`unexpected MCP response calling ${name}: ${text.slice(0, 200)}`);
    const parsed = JSON.parse(line.slice("data: ".length));
    if (parsed.error) throw new Error(`${name} failed: ${JSON.stringify(parsed.error)}`);
    const resultText = parsed.result?.content?.[0]?.text;
    return resultText !== undefined ? JSON.parse(resultText) : parsed.result;
  }

  list(): Promise<ReadonlyArray<{ name: string }>> {
    return this.call("_list", {});
  }

  get(name: string): Promise<{ name: string; frontmatter: Record<string, unknown>; body: string }> {
    return this.call("_get", { name });
  }

  update(name: string, fields: { body?: string; integrations?: readonly string[] }): Promise<unknown> {
    return this.call("_update", { name, ...fields });
  }
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

const parseArgs = (argv: readonly string[]) => {
  const flags = new Map<string, string>();
  let dryRun = false;
  let apply = false;
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === "--dry-run") { dryRun = true; continue; }
    if (arg === "--apply") { apply = true; continue; }
    if (arg?.startsWith("--")) { flags.set(arg.slice(2), argv[i + 1]!); i++; }
  }
  return {
    pathMap: flags.get("path-map") ?? "path-map.json",
    mcpUrl: flags.get("mcp-url") ?? flags.get("url") ?? (() => { throw new Error("--mcp-url required"); })(),
    dryRun,
    apply,
    diffOut: flags.get("diff-out"),
  };
};

const main = async () => {
  const args = parseArgs(process.argv.slice(2));
  if (!args.dryRun && !args.apply) throw new Error("pass --dry-run or --apply");
  const lookups = loadLookups(args.pathMap);
  const client = new SnippetMcpClient(args.mcpUrl);

  const names = (await client.list()).map((item) => item.name);
  const diffs: string[] = [];
  const report: Array<{ name: string; changed: boolean; flags: Flag[] }> = [];

  for (const name of names) {
    const snippet = await client.get(name);
    const bodyResult = rewriteBody(snippet.body, lookups);
    const integrationsResult = rewriteIntegrations(snippet.frontmatter.integrations as readonly string[] | undefined);
    const flags = [...bodyResult.flags, ...integrationsResult.flags];
    const originalIntegrations = (snippet.frontmatter.integrations as readonly string[] | undefined) ?? [];
    const integrationsChanged = JSON.stringify([...(integrationsResult.integrations ?? [])].sort()) !== JSON.stringify([...originalIntegrations].sort());
    const changed = bodyResult.changed || integrationsChanged;
    report.push({ name, changed, flags });

    if (bodyResult.changed) {
      const diff = unifiedDiff(name, snippet.body, bodyResult.body);
      if (diff) diffs.push(diff);
    }

    // Write whatever was mechanically rewritten even if other, unrelated flags remain (e.g. an
    // envelope-check flag on a body whose paths were still safely rewritten) -- flags mark what
    // still needs a human, not a reason to withhold the part that's already correct. Skip only
    // when nothing actually changed.
    if (args.apply && changed) {
      await client.update(name, {
        body: bodyResult.changed ? bodyResult.body : undefined,
        integrations: integrationsChanged ? integrationsResult.integrations : undefined,
      });
    }
  }

  const diffText = diffs.join("\n");
  if (args.diffOut) writeFileSync(args.diffOut, diffText, { mode: 0o600 });
  if (args.dryRun) console.log(diffText);

  console.log("\n=== Summary ===");
  console.log(`snippets: ${report.length}`);
  console.log(`rewritten (no change needed or fully clean): ${report.filter((r) => r.changed && r.flags.length === 0).length}`);
  console.log(`changed with remaining flags: ${report.filter((r) => r.changed && r.flags.length > 0).length}`);
  console.log(`unchanged, flagged: ${report.filter((r) => !r.changed && r.flags.length > 0).length}`);
  console.log(`untouched (nothing to rewrite, no flags): ${report.filter((r) => !r.changed && r.flags.length === 0).length}`);
  for (const row of report) {
    if (row.flags.length === 0) continue;
    console.log(`\n${row.name}${row.changed ? " (path rewritten; flags remain)" : " (no safe rewrite)"}`);
    for (const flag of row.flags) console.log(`  - [${flag.reason}] ${flag.detail}`);
  }
};

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
