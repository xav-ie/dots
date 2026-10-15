#!/usr/bin/env bun
/**
 * Executor v1 -> v2 LOCAL data importer.
 *
 * Reads a v1 SQLite snapshot (integration/connection/tool/tool_policy tables) and drives a
 * local v2 server's HTTP + MCP API to recreate the same setup: MCP apps deployed with
 * generated source, fixed-header "account selector" apps collapsed into one app per selector
 * value, secret-bearing connections turned into a one-use browser connect link (credentials are
 * never read or printed by this script -- v2 only accepts them through its own connect form),
 * and v1 tool policies baked into each app's generated `tools.ts` approval rules.
 *
 * Usage:
 *   ./import.ts --v1-db PATH --url URL --api-key KEY [--dry-run] [--v1-auth PATH]
 *   ./import.ts --v1-db PATH --url URL --data-dir DIR [--dry-run]   # reads keys.json from DIR
 *
 * Re-running is safe: apps are looked up by (owner, name) and redeployed by ID; manual connect
 * links are reprinted (unanswered links expire; completed ones are left alone).
 */
import { Database } from "bun:sqlite";
import { existsSync, readFileSync } from "node:fs";

// ---------------------------------------------------------------------------
// CLI args
// ---------------------------------------------------------------------------

type Args = {
  v1Db: string;
  v1Auth?: string;
  url: string;
  apiKey?: string;
  dataDir?: string;
  dryRun: boolean;
  owner: string;
};

const parseArgs = (argv: readonly string[]): Args => {
  const flags = new Map<string, string>();
  let dryRun = false;
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === "--dry-run") {
      dryRun = true;
      continue;
    }
    if (arg?.startsWith("--")) {
      const name = arg.slice(2);
      const value = argv[i + 1];
      if (value === undefined || value.startsWith("--")) throw new Error(`--${name} needs a value`);
      flags.set(name, value);
      i++;
    }
  }
  const v1Db = flags.get("v1-db");
  const url = flags.get("url");
  if (!v1Db) throw new Error("--v1-db is required");
  if (!url) throw new Error("--url is required");
  const apiKey = (flags.get("api-key") ?? process.env.EXECUTOR_API_KEY);
  const dataDir = flags.get("data-dir");
  if (!apiKey && !dataDir && !dryRun) throw new Error("--api-key or --data-dir is required (unless --dry-run)");
  return {
    v1Db,
    v1Auth: flags.get("v1-auth"),
    url: url.replace(/\/+$/, ""),
    apiKey,
    dataDir,
    dryRun,
    owner: flags.get("owner") ?? "local",
  };
};

const resolveApiKey = (args: Args): string | undefined => {
  if (args.apiKey) return args.apiKey;
  if (args.dataDir) {
    const keysPath = `${args.dataDir}/keys.json`;
    if (!existsSync(keysPath)) throw new Error(`no keys.json at ${keysPath}`);
    const parsed = JSON.parse(readFileSync(keysPath, "utf8")) as { apiKey?: string };
    if (!parsed.apiKey) throw new Error(`${keysPath} has no apiKey field`);
    return parsed.apiKey;
  }
  return undefined;
};

// ---------------------------------------------------------------------------
// v1 model
// ---------------------------------------------------------------------------

interface V1Integration {
  slug: string;
  name: string | null;
  description: string | null;
  config: {
    transport: string;
    endpoint: string;
    remoteTransport?: string;
    authenticationTemplate: ReadonlyArray<{
      slug: string;
      kind: "none" | "apikey" | "header" | "oauth2" | "token";
      label?: string;
      placements?: ReadonlyArray<{ carrier: string; name: string; prefix?: string }>;
    }>;
  };
}

interface V1Connection {
  integration: string;
  name: string;
  template: string;
  identity_label: string | null;
  oauth_client: string | null;
  item_ids: Record<string, string>;
}

interface V1ToolPolicy {
  pattern: string;
  action: "approve" | "require_approval" | "block";
  position: string;
}

// Bun's sqlite driver sometimes hands back a TEXT column as a raw Uint8Array instead of a
// string (observed with ORDER BY on this db's text-affinity columns). Normalize defensively.
const asText = (value: unknown): string =>
  typeof value === "string" ? value : Buffer.from(value as Uint8Array).toString("utf8");

const loadV1 = (dbPath: string) => {
  const db = new Database(dbPath, { readonly: true });
  const integrations = db
    .query<{ slug: string; name: string | null; description: string | null; config: string }, []>(
      `select slug, name, description, config from integration order by slug`,
    )
    .all()
    .map((row): V1Integration => ({
      slug: asText(row.slug),
      name: row.name === null ? null : asText(row.name),
      description: row.description === null ? null : asText(row.description),
      config: JSON.parse(asText(row.config)),
    }));

  const connections = db
    .query<
      { integration: string; name: string; template: string; identity_label: string | null; oauth_client: string | null; item_ids: string },
      []
    >(`select integration, name, template, identity_label, oauth_client, item_ids from connection order by integration, name`)
    .all()
    .map((row): V1Connection => ({
      integration: asText(row.integration),
      name: asText(row.name),
      template: asText(row.template),
      identity_label: row.identity_label === null ? null : asText(row.identity_label),
      oauth_client: row.oauth_client === null ? null : asText(row.oauth_client),
      item_ids: JSON.parse(asText(row.item_ids)),
    }));

  const toolCounts = db
    .query<{ integration: string; connection: string; n: number }, []>(
      `select integration, connection, count(*) as n from tool group by integration, connection`,
    )
    .all()
    .map((row) => ({ integration: asText(row.integration), connection: asText(row.connection), n: row.n }));

  const policies = db
    .query<{ pattern: string; action: string; position: string }, []>(
      `select pattern, action, position from tool_policy order by position`,
    )
    .all()
    .map((row): V1ToolPolicy => ({ pattern: asText(row.pattern), action: asText(row.action) as V1ToolPolicy["action"], position: asText(row.position) }));

  db.close();
  return { integrations, connections, toolCounts, policies };
};

// v1 tool path: `<integration>.<owner>.<connection>.<toolName>`; policy patterns wildcard the
// owner/connection segments and match the integration + tool name (or `<integration>.*` for an
// integration-wide default).
const policyForIntegration = (policies: readonly V1ToolPolicy[], integration: string) => {
  const perTool: Record<string, "always" | "never"> = {};
  let defaultAction: "approve" | "require_approval" | undefined;
  const unsupported: V1ToolPolicy[] = [];
  for (const policy of policies) {
    const segments = policy.pattern.split(".");
    if (segments[0] !== integration) continue;
    if (policy.action === "block") {
      unsupported.push(policy);
      continue;
    }
    const verdict = policy.action === "approve" ? "never" : "always";
    if (segments.length === 2 && segments[1] === "*") {
      defaultAction = policy.action;
      continue;
    }
    const toolName = segments[segments.length - 1];
    if (segments.length !== 4 || toolName === "*") {
      unsupported.push(policy);
      continue;
    }
    perTool[toolName] = verdict;
  }
  return { perTool, defaultAction, unsupported };
};

// ---------------------------------------------------------------------------
// v2 source generation (mirrors packages/app-templates/src/implementation/{mcp,protocol-apps}.ts
// at executor@2.0.0-beta.23: generateMcpSource / mcpAppSource, read not imported)
// ---------------------------------------------------------------------------

const APPS_VERSION = "0.0.1-beta.92"; // from the running release's node_modules/apps/package.json

const packageFile = (name: string) =>
  JSON.stringify({ name, private: true, type: "module", dependencies: { apps: APPS_VERSION } }, null, 2) + "\n";

/** `tools.ts`: per-tool approval overrides, mirroring protocol-apps.ts's toolsFile(). */
const toolsFile = (approvals: Record<string, "always" | "never">) => {
  if (Object.keys(approvals).length === 0) return undefined;
  return `import { always, never } from "apps/operations/approval"

const omitted = new Set<string>([])

/** The name each tool is exposed under. Omitted tools are left out. */
export const exposedName = (name: string): string | undefined => {
  const exposed = name
  return omitted.has(exposed) ? undefined : exposed
}

const approvals: Record<string, "always" | "never"> = ${JSON.stringify(
    Object.fromEntries(Object.entries(approvals).sort(([a], [b]) => (a < b ? -1 : 1))),
    null,
    2,
  )}

/** A tool's own approval rule, by exposed name, or undefined to use the app's default. */
export const approval = (name: string) =>
  approvals[name] === "always" ? always() : approvals[name] === "never" ? never() : undefined
`;
};

interface SourceFile {
  path: string;
  content: string;
}

/** A public (no-account) server: either plain, or carrying fixed non-secret headers (v1's
 * literal `Account: delivery`-style routing headers, which are selectors, not credentials). */
const publicApp = (
  appName: string,
  url: string,
  options: {
    headers?: Record<string, string>;
    approvals?: Record<string, "always" | "never">;
    defaultRule?: "destructive" | "never" | "always";
    // Skip mcpRouter's own persistent catalog cache (packages/apps/src/implementation/
    // catalog-cache.ts: passing no `cache` keeps discovery invocation-local, i.e. live every
    // evaluation). Needed for an integration like snippets whose tool set changes on every
    // save; v1's /api/connections/.../refresh has no v2 equivalent endpoint, and the host's own
    // separate EXECUTOR_TOOL_LISTING_FRESH_SECONDS/MAX_AGE_SECONDS cadence still governs how
    // often the app is re-evaluated at all, so this alone isn't sufficient for sub-30s freshness
    // unless that host config is also lowered -- see the script's --fast-listing notes.
    noCache?: boolean;
  },
): SourceFile[] => {
  const tools = toolsFile(options.approvals ?? {});
  const defaultRule =
    options.defaultRule === "never"
      ? "undefined"
      : options.defaultRule === "always"
        ? "always()"
        : "toolAnnotations(tool)?.destructiveHint === true ? always() : undefined";
  const headerOpt = Object.keys(options.headers ?? {}).length > 0 ? `headers: ${JSON.stringify(options.headers)}, ` : "";
  const cacheOpt = options.noCache ? "" : "cache, ";
  const routerExpr = `await mcpRouter({ url: ${JSON.stringify(url)}, ${headerOpt}${cacheOpt}signal })`;
  const wrapped = tools
    ? `withApprovals(renameTools(${routerExpr}, exposedName), (tool, name) => approval(name) ?? (${defaultRule}))`
    : `withApprovals(${routerExpr}, (tool) => (${defaultRule}))`;
  const contextArgs = options.noCache ? "{ signal }" : "{ signal, cache }";
  const index = `import { defineApp, toolAnnotations, withApprovals${tools ? ", renameTools" : ""} } from "apps"
import { mcpRouter } from "apps/mcp"
import { always } from "apps/operations/approval"
${tools ? `import { approval, exposedName } from "./tools.ts"\n` : ""}
export default defineApp({}, async (${contextArgs}) => ({
  tools: ${wrapped},
}))
`;
  const files: SourceFile[] = [{ path: "index.ts", content: index }];
  if (tools) files.push({ path: "tools.ts", content: tools });
  files.push({ path: "package.json", content: packageFile(appName) });
  return files;
};

/** A known sign-in method (API key / bearer header / token). This is a single-user local
 * install, so this uses one shared app-scope account (`app.accounts.service`, cardinality
 * "one"), as generateMcpSource's non-"methods" access="app" branch does: its managers link the
 * one account for everyone, and every call and tool input stay plain -- no accountId wrapping,
 * matching how v1 called these tools and how existing agents/snippets call them today. */
const secretsApp = (
  appName: string,
  url: string,
  host: string,
  method: { label: string; headerName: string; prefix?: string },
  options: { approvals?: Record<string, "always" | "never">; defaultRule?: "destructive" | "never" | "always" },
): SourceFile[] => {
  const tools = toolsFile(options.approvals ?? {});
  const defaultRule =
    options.defaultRule === "never"
      ? "undefined"
      : options.defaultRule === "always"
        ? "always()"
        : "toolAnnotations(tool)?.destructiveHint === true ? always() : undefined";
  const routerExpr = `await mcpRouter({ url, account: app.accounts.service, cache, headers: headers(app.accounts.service), signal })`;
  const wrapped = tools
    ? `withApprovals(renameTools(${routerExpr}, exposedName), (tool, name) => approval(name) ?? (${defaultRule}))`
    : `withApprovals(${routerExpr}, (tool) => (${defaultRule}))`;
  const index = `import { defineApp, toolAnnotations, withApprovals${tools ? ", renameTools" : ""} } from "apps"
import { mcpRouter } from "apps/mcp"
import { always } from "apps/operations/approval"
import { headers, provider, url } from "./provider.ts"
${tools ? `import { approval, exposedName } from "./tools.ts"\n` : ""}
// One service account for the whole app: its managers link it for everyone, and every call uses it.
export default defineApp({ app: { accounts: { service: provider } } }, async ({ app, signal, cache }) => ({
  tools: ${wrapped},
}))
`;
  const prefixLit = JSON.stringify(method.prefix ?? "");
  const valueExpr = method.prefix ? `${prefixLit} + account.fields["token"]` : `account.fields["token"]`;
  const provider = `import { defineProvider, object, secrets, string } from "apps"

export const url = ${JSON.stringify(url)}

export const provider = defineProvider({
  name: ${JSON.stringify(appName)},
  // Credentials are only ever sent to the service itself.
  hosts: [${JSON.stringify(host)}],
  auth: {
    token: secrets({ label: ${JSON.stringify(method.label)}, fields: object({ token: string({ minLength: 1 }) }) }),
  },
})

/** The one shared account. */
export type Account = { readonly method: "token"; readonly fields: { readonly token: string } }

/** The headers that send the account's credentials. */
export const headers = (account: Account) => ({
  ${JSON.stringify(method.headerName)}: ${valueExpr},
})
`;
  const files: SourceFile[] = [
    { path: "index.ts", content: index },
    { path: "provider.ts", content: provider },
  ];
  if (tools) files.push({ path: "tools.ts", content: tools });
  files.push({ path: "package.json", content: packageFile(appName) });
  return files;
};

/** OAuth2, discovered from the server itself. One account for the whole app, like secretsApp,
 * so tools take the server's own input instead of `{ accountId, input }`. */
const oauthApp = (appName: string, url: string, host: string): SourceFile[] => {
  const index = `import { defineApp, toolAnnotations, withApprovals } from "apps"
import { mcpRouter } from "apps/mcp"
import { always } from "apps/operations/approval"
import { headers, provider } from "./provider.ts"

// One account for the whole app: its managers link it for everyone, and every call uses it.
export default defineApp({ app: { accounts: { service: provider } } }, async ({ app, signal, cache }) => ({
  tools: withApprovals(await mcpRouter({
    url: ${JSON.stringify(url)},
    account: app.accounts.service,
    cache,
    headers: headers(app.accounts.service),
    signal,
  }), (tool) => (toolAnnotations(tool)?.destructiveHint === true ? always() : undefined)),
}))
`;
  const provider = `import { defineProvider, oauth2 } from "apps"
import { mcpHealth } from "apps/mcp"

export const url = ${JSON.stringify(url)}

/** The headers that send an account's token to the server. */
export const headers = (account: { fields: { access_token: string } }) => ({
  Authorization: "Bearer " + account.fields.access_token,
})

export const provider = defineProvider({
  name: ${JSON.stringify(appName)},
  hosts: [${JSON.stringify(host)}],
  auth: {
    oauth: oauth2({ discover: ${JSON.stringify(url)} })
  },
  health: (check) => mcpHealth(check, { url, headers: headers(check.account) }),
})
`;
  return [
    { path: "index.ts", content: index },
    { path: "provider.ts", content: provider },
    { path: "package.json", content: packageFile(appName) },
  ];
};

// ---------------------------------------------------------------------------
// v2 HTTP client
// ---------------------------------------------------------------------------

class V2Client {
  constructor(private readonly baseUrl: string, private readonly apiKey: string) {}

  private async request<T>(method: string, path: string, body?: unknown): Promise<T> {
    const response = await fetch(`${this.baseUrl}${path}`, {
      method,
      headers: {
        Authorization: `Bearer ${this.apiKey}`,
        ...(body === undefined ? {} : { "Content-Type": "application/json" }),
      },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    const text = await response.text();
    const parsed = text.length > 0 ? JSON.parse(text) : undefined;
    if (!response.ok) throw new Error(`${method} ${path} -> ${response.status}: ${JSON.stringify(parsed)}`);
    return parsed as T;
  }

  listApps() {
    return this.request<ReadonlyArray<{ id: string; slug: string; owner: string; name: string; activeVersion: string | null }>>(
      "GET",
      "/v1/apps",
    );
  }

  async deployApp(owner: string, name: string, files: readonly SourceFile[]) {
    const existing = (await this.listApps()).find((app) => app.owner === owner && app.name === name);
    const payload = existing ? { owner, app: existing.id, files } : { owner, name, files };
    return this.request<{ app: { id: string; slug: string }; version: { id: string } }>(
      "POST",
      "/v1/apps/deploy",
      payload,
    );
  }

  listTools(app: string, cursor?: string) {
    const query = new URLSearchParams({ app, limit: "200", ...(cursor ? { cursor } : {}) });
    return this.request<{ items: ReadonlyArray<{ name: string }>; next?: { cursor?: string } | null }>(
      "GET",
      `/v1/tools?${query}`,
    );
  }

  async allTools(app: string) {
    const items: { name: string }[] = [];
    let cursor: string | undefined;
    for (;;) {
      const page = await this.listTools(app, cursor);
      items.push(...page.items);
      if (!page.next?.cursor) break;
      cursor = page.next.cursor;
    }
    return items;
  }

  // --- MCP: execute() for account-connect links and verification tool calls ---

  private mcpSession: string | undefined;

  private async mcpRequest(body: unknown): Promise<any> {
    const headers: Record<string, string> = {
      Authorization: `Bearer ${this.apiKey}`,
      "Content-Type": "application/json",
      Accept: "application/json, text/event-stream",
    };
    if (this.mcpSession) headers["mcp-session-id"] = this.mcpSession;
    const response = await fetch(`${this.baseUrl}/mcp`, { method: "POST", headers, body: JSON.stringify(body) });
    const session = response.headers.get("mcp-session-id");
    if (session) this.mcpSession = session;
    const text = await response.text();
    if (!response.ok) throw new Error(`MCP ${body?.method ?? "?"} -> ${response.status}: ${text}`);
    return text.length > 0 ? JSON.parse(text) : undefined;
  }

  private mcpId = 0;
  private async mcpInit() {
    if (this.mcpSession) return;
    await this.mcpRequest({
      jsonrpc: "2.0",
      id: ++this.mcpId,
      method: "initialize",
      params: { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "v1-import", version: "0.0.1" } },
    });
    await this.mcpRequest({ jsonrpc: "2.0", method: "notifications/initialized" });
  }

  async execute(code: string): Promise<unknown> {
    await this.mcpInit();
    const result = await this.mcpRequest({
      jsonrpc: "2.0",
      id: ++this.mcpId,
      method: "tools/call",
      params: { name: "execute", arguments: { code } },
    });
    const text = result?.result?.content?.[0]?.text;
    if (!text) throw new Error(`unexpected execute() response: ${JSON.stringify(result)}`);
    const parsed = JSON.parse(text);
    if (parsed.status !== "completed" || parsed.execution?.ok !== true) {
      throw new Error(`execute() failed: ${JSON.stringify(parsed)}`);
    }
    return parsed.execution.value;
  }

  /** A user-scope connect link: each member links their own account (oauth-manual apps only). */
  async userConnectLink(app: string, requirement: string) {
    return this.execute(
      `return await tools.executor.appAccounts.userConnect({ path: { app: ${JSON.stringify(app)}, requirement: ${JSON.stringify(
        requirement,
      )} }, body: {} });`,
    ) as Promise<{ url: string; connection: string; expiresAt: string }>;
  }

  /** An app-scope connect link: one shared account its managers link for everyone. */
  async appConnectLink(app: string, requirement: string) {
    return this.execute(
      `return await tools.executor.appAccounts.appConnect({ path: { app: ${JSON.stringify(app)}, requirement: ${JSON.stringify(
        requirement,
      )} }, body: {} });`,
    ) as Promise<{ url: string; connection: string; expiresAt: string }>;
  }

  /**
   * The same submission the dashboard's own connect form makes (owner-authenticated, loopback
   * only). Callers must never log or print `fields`. Not in /openapi.json (dashboard routes
   * aren't part of the documented SDK group) but reachable with the bearer key, same as the
   * README's "Dashboard data requires the same bearer key" routes. `scope` is "app" for the one
   * shared account our secret-backed apps use, or "user" for an oauth-manual app's own account.
   */
  async submitAccountConnection(
    app: string,
    scope: "app" | "user",
    requirement: string,
    method: string,
    label: string,
    fields: Record<string, string>,
  ) {
    return this.request<{ id: string }>(
      "POST",
      `/dashboard/api/apps/${app}/accounts/${scope}/${requirement}/connections`,
      { method, label, fields },
    );
  }

  async callTool(path: string, inputJsExpr: string) {
    return this.execute(`return await tools.${path}(${inputJsExpr});`);
  }
}

// ---------------------------------------------------------------------------
// Plan: per-integration handling, driven by the known v1 inventory of this instance.
// ---------------------------------------------------------------------------

type Plan =
  | { kind: "public"; integration: string; apps: ReadonlyArray<{ appName: string }> }
  | {
      kind: "secrets";
      integration: string;
      appName: string;
      label: string;
      headerName: string;
      prefix?: string;
      // Either a real secret, identified only by its v1 vault key (never read/printed), or a
      // non-secret literal value (a routing label like "delivery") that is safe to print.
      credential: { kind: "vault"; vaultKey: string } | { kind: "literal"; value: string };
    }
  | { kind: "oauth-manual"; integration: string; appName: string; note: string };

const buildPlans = (integrations: readonly V1Integration[], connections: readonly V1Connection[]): Plan[] => {
  const plans: Plan[] = [];
  for (const integration of integrations) {
    const slug = integration.slug;
    const conns = connections.filter((c) => c.integration === slug);
    const url = integration.config.endpoint;
    const methods = integration.config.authenticationTemplate;
    const hasKind = (kind: string) => methods.some((m) => m.kind === kind);

    if (slug === "outsmartly") {
      plans.push({
        kind: "oauth-manual",
        integration: slug,
        appName: "outsmartly",
        note: "oauth2 via 'vercel' client; v2 has no path to import an existing grant, needs fresh interactive sign-in",
      });
      continue;
    }

    // Two connections of one integration whose only "credential" is a literal routing value
    // equal to the connection's own name, sent in a header named "Account" (v1's
    // apikey-with-header-"Account" pattern). It is not a secret, but this v2 build's mcpRouter
    // refuses a non-empty `headers` option unless an account is linked (catalogScope treats any
    // header as "a credential without an account" -- see packages/apps/src/implementation/
    // catalog-cache.ts's catalogScope), so a real (non-secret) account per connection is used
    // instead of a fixed header on a public app.
    const apikeyAccountHeader = methods.find(
      (m) => m.kind === "apikey" && m.placements?.some((p) => p.name === "Account"),
    );
    if (conns.length > 1 && apikeyAccountHeader) {
      for (const conn of conns) {
        plans.push({
          kind: "secrets",
          integration: slug,
          appName: `${slug.replace(/_/g, "-")}-${conn.name}`,
          label: conn.identity_label ?? conn.name,
          headerName: "Account",
          credential: { kind: "literal", value: conn.name },
        });
      }
      continue;
    }

    const headerMethod = methods.find(
      (m) =>
        (m.kind === "header" || m.kind === "token" || m.kind === "apikey") &&
        !m.placements?.some((p) => p.name === "Account"),
    );
    if (headerMethod && conns.length > 0) {
      const placement = headerMethod.placements?.[0];
      const conn = conns[0];
      plans.push({
        kind: "secrets",
        integration: slug,
        appName: slug.replace(/_/g, "-"),
        label: headerMethod.label ?? integration.name ?? slug,
        headerName: placement?.name ?? "Authorization",
        prefix: placement?.prefix,
        credential: { kind: "vault", vaultKey: Object.values(conn.item_ids)[0] ?? "(no item id on this connection)" },
      });
      continue;
    }

    if (hasKind("none") || methods.length === 0) {
      plans.push({ kind: "public", integration: slug, apps: [{ appName: slug.replace(/_/g, "-") }] });
      continue;
    }

    // Fallback: unknown shape -- surface it rather than silently guessing.
    throw new Error(`no plan rule matched integration ${slug} (methods: ${JSON.stringify(methods)})`);
  }
  return plans;
};

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

const main = async () => {
  const args = parseArgs(process.argv.slice(2));
  const v1 = loadV1(args.v1Db);

  // Loaded only to feed the one dashboard call that submits an account's fields; never logged,
  // printed, or included in the report. Without --v1-auth, secret-backed connections fall back
  // to printing a one-use connect link for the user to complete by hand.
  const vault: Record<string, unknown> | undefined = args.v1Auth
    ? JSON.parse(readFileSync(args.v1Auth, "utf8"))
    : undefined;
  if (vault) {
    for (const conn of v1.connections) {
      for (const itemId of Object.values(conn.item_ids)) {
        if (!(itemId in vault)) console.warn(`warning: v1 connection ${conn.integration}/${conn.name} references missing vault key ${itemId}`);
      }
    }
  }

  const plans = buildPlans(v1.integrations, v1.connections);

  const toolCountFor = (integration: string, connection?: string) =>
    v1.toolCounts
      .filter((row) => row.integration === integration && (connection === undefined || row.connection === connection))
      .reduce((sum, row) => sum + row.n, 0);

  type Report = { app: string; status: "deployed" | "manual" | "skipped" | "dry-run"; detail: string; v1Tools: number; v2Tools?: number };
  const report: Report[] = [];

  const apiKey = args.dryRun ? undefined : resolveApiKey(args);
  const client = args.dryRun ? undefined : new V2Client(args.url, apiKey!);

  for (const plan of plans) {
    if (plan.kind === "public") {
      for (const app of plan.apps) {
        const integration = v1.integrations.find((i) => i.slug === plan.integration)!;
        const files = publicApp(app.appName, integration.config.endpoint, {
          ...policyFiles(v1.policies, plan.integration),
          // Saved-snippet tool sets change on every save; v1's refresh POST has no v2
          // equivalent, so skip the app-level catalog cache (still bounded by the host's
          // EXECUTOR_TOOL_LISTING_FRESH_SECONDS/MAX_AGE_SECONDS; see publicApp's doc comment).
          noCache: plan.integration === "snippets",
        });
        const v1Tools = toolCountFor(plan.integration);
        if (args.dryRun) {
          report.push({ app: app.appName, status: "dry-run", detail: `public app, url=${integration.config.endpoint}`, v1Tools });
          continue;
        }
        const deployed = await client!.deployApp(args.owner, app.appName, files);
        const tools = await client!.allTools(deployed.app.id);
        report.push({ app: app.appName, status: "deployed", detail: `app ${deployed.app.id}`, v1Tools, v2Tools: tools.length });
      }
      continue;
    }

    if (plan.kind === "secrets") {
      const integration = v1.integrations.find((i) => i.slug === plan.integration)!;
      const host = new URL(integration.config.endpoint).host;
      const files = secretsApp(
        plan.appName,
        integration.config.endpoint,
        host,
        { label: plan.label, headerName: plan.headerName, prefix: plan.prefix },
        policyFiles(v1.policies, plan.integration),
      );
      // The "Account"-selector connections (literal, non-secret values) are split per v1
      // connection; a real header/apikey secret has exactly one connection for its integration.
      const connName = plan.credential.kind === "literal" ? plan.credential.value : undefined;
      const v1Tools = toolCountFor(plan.integration, connName);
      const credentialHint =
        plan.credential.kind === "literal"
          ? `value to enter: ${JSON.stringify(plan.credential.value)} (not a secret -- a v1 routing label)`
          : `paste the value from v1 auth.json key "${plan.credential.vaultKey}" (this script never reads or prints it)`;
      if (args.dryRun) {
        report.push({ app: plan.appName, status: "dry-run", detail: `secrets app, header ${plan.headerName}, ${credentialHint}`, v1Tools });
        continue;
      }
      const deployed = await client!.deployApp(args.owner, plan.appName, files);

      // A literal (non-secret) value or a vault-backed secret (with --v1-auth) can be submitted
      // the same way the dashboard's own connect form does; `value` is never logged.
      const value: string | undefined =
        plan.credential.kind === "literal"
          ? plan.credential.value
          : vault && typeof vault[plan.credential.vaultKey] === "string"
            ? (vault[plan.credential.vaultKey] as string)
            : undefined;

      if (value !== undefined) {
        await client!.submitAccountConnection(deployed.app.id, "app", "service", "token", plan.label, { token: value });
        const tools = await client!.allTools(deployed.app.id);
        report.push({ app: plan.appName, status: "deployed", detail: `app ${deployed.app.id}; account connected`, v1Tools, v2Tools: tools.length });
        continue;
      }

      const tools = await client!.allTools(deployed.app.id);
      const link = await client!.appConnectLink(deployed.app.id, "service");
      report.push({
        app: plan.appName,
        status: "manual",
        detail: `deployed ${deployed.app.id}; open ${link.url} and ${credentialHint}`,
        v1Tools,
        v2Tools: tools.length,
      });
      continue;
    }

    if (plan.kind === "oauth-manual") {
      const integration = v1.integrations.find((i) => i.slug === plan.integration)!;
      const host = new URL(integration.config.endpoint).host;
      const files = oauthApp(plan.appName, integration.config.endpoint, host);
      const v1Tools = toolCountFor(plan.integration);
      if (args.dryRun) {
        report.push({ app: plan.appName, status: "dry-run", detail: plan.note, v1Tools });
        continue;
      }
      const deployed = await client!.deployApp(args.owner, plan.appName, files);
      const tools = await client!.allTools(deployed.app.id);
      const link = await client!.appConnectLink(deployed.app.id, "service");
      report.push({
        app: plan.appName,
        status: "manual",
        detail: `deployed ${deployed.app.id}; ${plan.note}; sign in at ${link.url}`,
        v1Tools,
        v2Tools: tools.length,
      });
    }
  }

  // Artifacts: task allows "skip and list" instead of building upstream's undeployed-app repair
  // scaffold; a later task owns porting their code, so list them without touching artifact code.
  const artifactsDb = new Database(args.v1Db, { readonly: true });
  const artifacts = artifactsDb
    .query<{ id: string; title: string }, []>(`select id, title from artifact order by title`)
    .all()
    .map((row) => ({ id: asText(row.id), title: asText(row.title) }));
  artifactsDb.close();
  for (const artifact of artifacts) {
    report.push({ app: artifact.title, status: "skipped", detail: `artifact ${artifact.id}; left for the later artifacts task, code not ported`, v1Tools: 0 });
  }

  // Policies whose integration isn't part of this inventory (e.g. a removed/renamed integration)
  // can't be mapped to any app.
  const knownIntegrations = new Set(v1.integrations.map((i) => i.slug));
  const orphanedIntegrations = new Set(
    v1.policies.map((p) => p.pattern.split(".")[0]).filter((slug) => slug !== undefined && !knownIntegrations.has(slug)),
  );
  for (const slug of orphanedIntegrations) {
    const rules = v1.policies.filter((p) => p.pattern.split(".")[0] === slug);
    report.push({
      app: slug,
      status: "skipped",
      detail: `${rules.length} tool_policy row(s) reference integration "${slug}", which has no current v1 integration row: ${rules.map((r) => r.pattern).join(", ")}`,
      v1Tools: 0,
    });
  }

  console.log("\n=== Import report ===");
  for (const row of report) {
    console.log(`[${row.status}] ${row.app}  v1 tools=${row.v1Tools}${row.v2Tools !== undefined ? ` v2 tools=${row.v2Tools}` : ""}`);
    console.log(`  ${row.detail}`);
  }
};

/** Build approvals/defaultRule options for a given integration from v1 tool_policy rows. */
const policyFiles = (policies: readonly V1ToolPolicy[], integration: string) => {
  const { perTool, defaultAction } = policyForIntegration(policies, integration);
  return {
    approvals: perTool,
    defaultRule: defaultAction === "approve" ? ("never" as const) : defaultAction === "require_approval" ? ("always" as const) : undefined,
  };
};

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
