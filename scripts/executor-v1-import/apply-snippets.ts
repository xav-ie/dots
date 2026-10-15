#!/usr/bin/env bun
/**
 * Applies a directory of fully v2-adapted snippet files (same format snippet-mcp itself writes:
 * YAML frontmatter + body, one <name>.md per snippet) onto a live snippet-mcp server, via its
 * own `_update` tool. Meant for the v1-v2 cutover, once the adapted set (see
 * scripts/executor-v1-import/V2-SEMANTICS.md and the per-snippet table in the import report) has
 * been reviewed.
 *
 * --dry-run fetches each snippet's current (raw) body via `_get` and prints a unified diff
 * against the local file; it never calls a write tool. --apply calls `_update` with the local
 * file's description/args/tags/kind/integrations/body for every snippet that differs. Neither
 * mode touches a snippet that doesn't already exist on the server (no `_save`) -- this script
 * only updates, it doesn't create or delete.
 *
 * Usage:
 *   ./apply-snippets.ts --dir /tmp/snippets-v2 --mcp-url http://127.0.0.1:38974/mcp --dry-run
 *   ./apply-snippets.ts --dir /tmp/snippets-v2 --mcp-url http://127.0.0.1:38974/mcp --apply
 */
import { readdirSync, readFileSync } from "node:fs";

interface LocalSnippet {
  readonly name: string;
  readonly frontmatter: Record<string, unknown>;
  readonly body: string;
}

/** Parse the on-disk format: `---\n<yaml>---\n\n<body>\n`. Frontmatter is only read back as
 * plain scalars/lists/maps (no YAML library dependency) -- good enough for the fields this
 * script passes through (description, args, tags, kind, integrations), which are never deeply
 * nested beyond one level. snippet-mcp itself is the source of truth for what it accepts; this
 * is a thin bridge, not a YAML implementation. */
const parseSnippetFile = (name: string, text: string): LocalSnippet => {
  const lines = text.split("\n");
  if (lines[0] !== "---") throw new Error(`${name}: missing leading frontmatter delimiter`);
  const closing = lines.indexOf("---", 1);
  if (closing === -1) throw new Error(`${name}: missing closing frontmatter delimiter`);
  const yamlLines = lines.slice(1, closing);
  const body = lines.slice(closing + 1).join("\n").replace(/^\n+/, "").replace(/\n+$/, "");
  const frontmatter = parseSimpleYaml(yamlLines);
  return { name, frontmatter, body };
};

/** A deliberately narrow YAML reader for exactly the shapes snippet-mcp's serde_yaml_ng output
 * uses for this schema: top-level scalar/quoted-scalar/list/map-of-scalar keys, one level of
 * nesting for `args`. Anything else throws rather than silently misreading. */
const parseSimpleYaml = (lines: readonly string[]): Record<string, unknown> => {
  const root: Record<string, unknown> = {};
  let i = 0;
  const unquote = (value: string): unknown => {
    const trimmed = value.trim();
    if (trimmed === "") return undefined;
    if (trimmed.startsWith("'") && trimmed.endsWith("'")) return trimmed.slice(1, -1).replace(/''/g, "'");
    if (trimmed.startsWith('"') && trimmed.endsWith('"')) return JSON.parse(trimmed);
    if (trimmed === "true") return true;
    if (trimmed === "false") return false;
    if (/^-?\d+(\.\d+)?$/.test(trimmed)) return Number(trimmed);
    return trimmed;
  };
  while (i < lines.length) {
    const line = lines[i]!;
    if (line.trim() === "") { i++; continue; }
    const topMatch = /^(\w+):\s*(.*)$/.exec(line);
    if (!topMatch) { i++; continue; }
    const [, key, rest] = topMatch;
    if (rest !== "") {
      root[key!] = unquote(rest!);
      i++;
      continue;
    }
    // Block list (`tags:\n- a\n- b`) or block map (`args:\n  name:\n    type: ...`).
    i++;
    const itemLines: string[] = [];
    while (i < lines.length && /^(-\s|  )/.test(lines[i]!)) {
      itemLines.push(lines[i]!);
      i++;
    }
    if (itemLines.every((l) => l.startsWith("- "))) {
      root[key!] = itemLines.map((l) => unquote(l.slice(2)));
    } else {
      // One level of nested maps (args: { name: { type, description, ... } }).
      const nested: Record<string, Record<string, unknown>> = {};
      let currentKey: string | undefined;
      for (const l of itemLines) {
        const nestedKeyMatch = /^  (\w+):\s*$/.exec(l);
        const fieldMatch = /^    (\w+):\s*(.*)$/.exec(l);
        if (nestedKeyMatch) {
          currentKey = nestedKeyMatch[1];
          nested[currentKey!] = {};
        } else if (fieldMatch && currentKey) {
          nested[currentKey]![fieldMatch[1]!] = unquote(fieldMatch[2]!);
        }
      }
      root[key!] = nested;
    }
  }
  return root;
};

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
  return `--- ${name} (live)\n+++ ${name} (v2 adapted)\n${hunks.join("\n")}\n`;
};

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
          params: { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "apply-snippets", version: "0.0.1" } },
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

  get(name: string): Promise<{ name: string; frontmatter: Record<string, unknown>; body: string }> {
    return this.call("_get", { name });
  }

  update(name: string, fields: Record<string, unknown>) {
    return this.call("_update", { name, ...fields });
  }
}

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
    dir: flags.get("dir") ?? (() => { throw new Error("--dir required"); })(),
    mcpUrl: flags.get("mcp-url") ?? flags.get("url") ?? (() => { throw new Error("--mcp-url required"); })(),
    dryRun,
    apply,
  };
};

const main = async () => {
  const args = parseArgs(process.argv.slice(2));
  if (!args.dryRun && !args.apply) throw new Error("pass --dry-run or --apply");
  const client = new SnippetMcpClient(args.mcpUrl);

  const files = readdirSync(args.dir).filter((f) => f.endsWith(".md"));
  let unchanged = 0;
  let applied = 0;
  let missing = 0;

  for (const file of files) {
    const name = file.replace(/\.md$/, "");
    const local = parseSnippetFile(name, readFileSync(`${args.dir}/${file}`, "utf8"));
    let live: { frontmatter: Record<string, unknown>; body: string };
    try {
      live = await client.get(name);
    } catch {
      console.log(`[missing] ${name} -- not found on the live server, skipped (this script only updates, never creates)`);
      missing++;
      continue;
    }
    if (live.body === local.body && JSON.stringify(live.frontmatter) === JSON.stringify(local.frontmatter)) {
      unchanged++;
      continue;
    }
    const diff = unifiedDiff(name, live.body, local.body);
    if (args.dryRun) {
      if (diff) console.log(diff);
      continue;
    }
    await client.update(name, {
      description: local.frontmatter.description,
      args: local.frontmatter.args,
      tags: local.frontmatter.tags,
      kind: local.frontmatter.kind,
      integrations: local.frontmatter.integrations,
      body: local.body,
    });
    applied++;
  }

  console.log(`\n=== Summary ===`);
  console.log(`files: ${files.length}, unchanged: ${unchanged}, missing on server: ${missing}, ${args.apply ? `applied: ${applied}` : "would change (dry-run)"}`);
};

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
