#!/usr/bin/env bun
/**
 * Builds scripts/executor-v1-import/path-map.json: every v1 tool address an agent used to call
 * (`tools.<integration>.org.<connection>.<tool>` -- v1's full form; see executor.ts's
 * `parseToolAddress`/`toolAddress` at v1.6.10, there is no shorter accepted form, every call
 * names owner and connection) mapped to the exact v2 address agents call now. v2 names are read
 * live from the running scratch instance's /v1/tools and tools.search, never guessed.
 *
 * Usage: ./build-path-map.ts --v1-db PATH --url URL --data-dir DIR [--out path-map.json]
 */
import { Database } from "bun:sqlite";
import { readFileSync, writeFileSync } from "node:fs";

const asText = (value: unknown): string =>
  typeof value === "string" ? value : Buffer.from(value as Uint8Array).toString("utf8");

const parseArgs = (argv: readonly string[]) => {
  const flags = new Map<string, string>();
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg?.startsWith("--")) {
      flags.set(arg.slice(2), argv[i + 1]!);
      i++;
    }
  }
  return {
    v1Db: flags.get("v1-db") ?? (() => { throw new Error("--v1-db required"); })(),
    url: (flags.get("url") ?? (() => { throw new Error("--url required"); })()).replace(/\/+$/, ""),
    dataDir: flags.get("data-dir"),
    apiKey: (flags.get("api-key") ?? process.env.EXECUTOR_API_KEY),
    out: flags.get("out") ?? "path-map.json",
  };
};

// Same (integration, connection) -> v2 app slug rule as import.ts's buildPlans. Kept in sync by
// hand since this is a small, fixed, already-deployed inventory, not re-derived generically.
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

const main = async () => {
  const args = parseArgs(process.argv.slice(2));
  const apiKey = args.apiKey ?? JSON.parse(readFileSync(`${args.dataDir}/keys.json`, "utf8")).apiKey;

  const db = new Database(args.v1Db, { readonly: true });
  const v1Tools = db
    .query<{ integration: string; connection: string; name: string }, []>(
      `select integration, connection, name from tool order by integration, connection, name`,
    )
    .all()
    .map((row) => ({ integration: asText(row.integration), connection: asText(row.connection), name: asText(row.name) }));
  db.close();

  const headers = { Authorization: `Bearer ${apiKey}` };
  const apps = (await (await fetch(`${args.url}/v1/apps`, { headers })).json()) as ReadonlyArray<{ id: string; slug: string }>;
  const appBySlug = new Map(apps.map((app) => [app.slug, app.id]));

  // Live v2 tool names per app, paginated. v1 stored some servers' tool names lowercased (its
  // own normalization, e.g. "calendar_createevent" for the live "calendar_createEvent"), while
  // v2 preserves the server's real casing -- same tool, so match case-insensitively and report
  // v2's real casing.
  const v2ToolNames = new Map<string, Map<string, string>>();
  for (const [slug, id] of appBySlug) {
    const names = new Map<string, string>();
    let cursor: string | undefined;
    for (;;) {
      const query = new URLSearchParams({ app: id, limit: "200", ...(cursor ? { cursor } : {}) });
      const page = (await (await fetch(`${args.url}/v1/tools?${query}`, { headers })).json()) as {
        items: ReadonlyArray<{ name: string }>;
        next?: { cursor?: string } | null;
      };
      for (const item of page.items) names.set(item.name.toLowerCase(), item.name);
      if (!page.next?.cursor) break;
      cursor = page.next.cursor;
    }
    v2ToolNames.set(slug, names);
  }

  // A valid JS identifier can stay as `tools.slug.tool`; anything else (every app slug here with
  // a hyphen: atlassian-delivery/product, google-workspace-personal/work, browser-session,
  // proton-mail) is not valid after a dot, so agents write the bracket form `tools["slug"].tool`
  // instead -- v2's execute.ts sandbox supports that statically. All of our tool names happen to
  // already be valid identifiers, so only the slug needs this check.
  const isIdentifier = (value: string) => /^[A-Za-z_$][A-Za-z0-9_$]*$/.test(value);
  const callExpression = (slug: string, tool: string) =>
    isIdentifier(slug) ? `tools.${slug}.${tool}` : `tools[${JSON.stringify(slug)}].${tool}`;

  type Entry = { v1: string; v2: string | null; v2Path: string | null; app: string; note?: string };
  const entries: Entry[] = [];
  for (const tool of v1Tools) {
    const key = `${tool.integration}/${tool.connection}`;
    const slug = APP_SLUG[key];
    const v1Path = `tools.${tool.integration}.org.${tool.connection}.${tool.name}`;
    if (!slug) {
      entries.push({ v1: v1Path, v2: null, v2Path: null, app: key, note: "no v2 app mapping found" });
      continue;
    }
    const names = v2ToolNames.get(slug);
    if (names === undefined) {
      entries.push({ v1: v1Path, v2: null, v2Path: null, app: slug, note: "app not found live" });
      continue;
    }
    if (names.size === 0) {
      entries.push({ v1: v1Path, v2: null, v2Path: null, app: slug, note: "no account connected yet (manual oauth); v2 tools not discoverable until then" });
      continue;
    }
    // v2 auto-prefixes an underscore on names that would otherwise collide with a reserved/
    // method-like word (observed: delete/get/list/save/update -> _delete/_get/_list/_save/
    // _update on the snippets app). Try that rename before concluding the tool is gone.
    const liveName = names.get(tool.name.toLowerCase()) ?? names.get(`_${tool.name.toLowerCase()}`);
    if (liveName === undefined) {
      entries.push({ v1: v1Path, v2: null, v2Path: null, app: slug, note: "tool not present in current v2 catalog (upstream server drift, not a rename)" });
      continue;
    }
    entries.push({ v1: v1Path, v2: callExpression(slug, liveName), v2Path: `${slug}.${liveName}`, app: slug });
  }

  writeFileSync(
    args.out,
    JSON.stringify(
      {
        generatedAt: new Date().toISOString(),
        note:
          "v1 had no shorter accepted form than tools.<integration>.org.<connection>.<tool> " +
          "(see executor.ts's parseToolAddress at v1.6.10: owner and connection are always required " +
          "segments, there is no tools.<integration>.<tool> shortcut). v2Path is the canonical " +
          "<appSlug>.<tool> path (what tools.search and the usage log show); v2 is the exact " +
          "expression an agent writes -- tools.<appSlug>.<tool> when the slug is a valid JS " +
          "identifier, or tools[\"<appSlug>\"].<tool> otherwise (every slug with a hyphen: " +
          "atlassian-delivery/product, google-workspace-personal/work, browser-session, " +
          "proton-mail). Every v1 and v2 call is plain input, no accountId.",
        entries,
      },
      null,
      2,
    ) + "\n",
  );
  console.log(`wrote ${entries.length} entries to ${args.out}`);
  console.log(`  mapped: ${entries.filter((e) => e.v2 !== null).length}`);
  console.log(`  unmapped: ${entries.filter((e) => e.v2 === null).length}`);
};

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
