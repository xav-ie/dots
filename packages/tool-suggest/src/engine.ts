// The one true source for executor tool suggestions (ported from the former
// modules/claude/tool-suggest.nu). Two hosts share this code through the
// compiled binary: claude's hooks pipe their event JSON straight into it
// (src/cli.ts), and the opencode plugin shim (src/opencode-plugin.ts) spawns
// it per event and injects the returned additionalContext.
//
// Every run appends a line to ~/.local/state/tool-suggest/suggestions.jsonl
// (hash + length of the text, never the text itself). Any failure (no embed
// service, no executor, no token: e.g. on nox) is swallowed by the caller.
//
// Knobs: $XDG_CONFIG_HOME/tool-suggest/config.json ({ mode, threshold,
// embedUrl, executorUrl }, all optional — deployed from modules/tool-suggest),
// falling back to built-in defaults: mode inject, cosine threshold 0.67
// (harrier-oss-v1-0.6b), the local embed + executor endpoints.

import { spawn } from "node:child_process";
import { createHash } from "node:crypto";
import {
  existsSync,
  readFileSync,
  writeFileSync,
  appendFileSync,
  mkdirSync,
  statSync,
  renameSync,
  unlinkSync,
  readdirSync,
} from "node:fs";
import { homedir } from "node:os";
import { join, dirname } from "node:path";

const INSTRUCT =
  "Instruct: Given a user request, retrieve the tool that can fulfill it\nQuery: ";
const CACHE = join(homedir(), ".cache", "tool-suggest");
const LOG = join(
  homedir(),
  ".local",
  "state",
  "tool-suggest",
  "suggestions.jsonl",
);
const CATALOG_TTL = 10 * 60_000;
const MAX_SUGGEST = 3;

export const MARKER = "Possibly relevant executor tools";

export type Tool = {
  path: string;
  name: string;
  description: string;
};

export type Config = {
  mode: string;
  threshold: number;
  embed: string;
  executor: string;
  /** A/B test: the share of events that inject; the rest only log. Unset = always inject. */
  abInject?: number;
};

type FileConfig = {
  mode?: unknown;
  threshold?: unknown;
  embedUrl?: unknown;
  executorUrl?: unknown;
  abInject?: unknown;
};

const str = (v: unknown): string | undefined =>
  typeof v === "string" && v !== "" ? v : undefined;
const num = (v: unknown): number | undefined =>
  typeof v === "number" && Number.isFinite(v) ? v : undefined;

// Bad or missing JSON is never fatal — defaults apply for every absent key.
const fileConfig = (): FileConfig => {
  try {
    const file = join(
      process.env.XDG_CONFIG_HOME ?? join(homedir(), ".config"),
      "tool-suggest",
      "config.json",
    );
    return JSON.parse(readFileSync(file, "utf8")) as FileConfig;
  } catch {
    return {};
  }
};

export const cfg = (): Config => {
  const file = fileConfig();
  return {
    mode: str(file.mode) ?? "inject",
    threshold: num(file.threshold) ?? 0.67,
    embed: str(file.embedUrl) ?? "http://127.0.0.1:38978/v1/embeddings",
    executor: str(file.executorUrl) ?? "http://127.0.0.1:38972",
    abInject: num(file.abInject),
  };
};

// `integration.name`, so `tools.outsmartly.start_build` and
// `outsmartly.org.outsmartlyoauth.start_build` compare equal.
export const shortPath = (p: string): string => {
  const parts = canonical(p).split(".");
  return `${parts[0]}.${parts[parts.length - 1]}`;
};

// v2's search returns the tool expression agents write (`tools.github.get_me`,
// `tools["atlassian-delivery"].jira_search`); the catalog keeps the canonical
// `slug.tool` form, and render() turns it back into an expression.
export const canonical = (p: string): string =>
  p.replace(/\["([^"]+)"\]/g, ".$1").replace(/^tools\./, "");

export const expression = (p: string): string =>
  `tools${p
    .split(".")
    .map((s) => (/^[A-Za-z_$][\w$]*$/.test(s) ? `.${s}` : `["${s}"]`))
    .join("")}`;

export const docText = (tool: Tool): string =>
  `${tool.path}\n${tool.name.replaceAll("_", " ")}\n${tool.description.slice(0, 2000)}`;

export const normalize = (v: number[]): number[] => {
  const norm = Math.hypot(...v);
  return v.map((x) => x / norm);
};

export async function embed(
  c: Config,
  texts: string[],
  timeoutMs = 1000,
): Promise<number[][]> {
  const res = await fetch(c.embed, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ input: texts }),
    signal: AbortSignal.timeout(timeoutMs),
  });
  if (!res.ok) throw new Error(`embed http ${res.status}`);
  const json = (await res.json()) as {
    data: { index: number; embedding: number[] }[];
  };
  return json.data
    .sort((a, b) => a.index - b.index)
    .map((d) => normalize(d.embedding));
}

const mcpHeaders = () => ({
  "content-type": "application/json",
  accept: "application/json, text/event-stream",
  authorization: `Bearer ${process.env.EXECUTOR_AUTH_TOKEN ?? ""}`,
  "cf-access-client-id": process.env.CF_ACCESS_CLIENT_ID ?? "",
  "cf-access-client-secret": process.env.CF_ACCESS_CLIENT_SECRET ?? "",
});

// v2's /mcp speaks JSON-RPC over streamable HTTP: a single response can come
// back as plain JSON or as one `data: ` SSE frame, depending on the call.
const mcpParse = async (res: Response): Promise<unknown> => {
  const text = await res.text();
  const line = text
    .split("\n")
    .find((l) => l.startsWith("data: "))
    ?.slice("data: ".length);
  return JSON.parse(line ?? text);
};

async function mcpSession(c: Config, timeoutMs: number): Promise<string> {
  const res = await fetch(`${c.executor}/mcp`, {
    method: "POST",
    headers: mcpHeaders(),
    signal: AbortSignal.timeout(timeoutMs),
    body: JSON.stringify({
      jsonrpc: "2.0",
      id: 1,
      method: "initialize",
      params: {
        protocolVersion: "2025-06-18",
        capabilities: {},
        clientInfo: { name: "tool-suggest", version: "1" },
      },
    }),
  });
  if (!res.ok) throw new Error(`mcp initialize http ${res.status}`);
  await mcpParse(res);
  const sessionId = res.headers.get("mcp-session-id");
  if (!sessionId) throw new Error("mcp initialize: no session id");
  return sessionId;
}

// Walks tools.search with no query across every reachable namespace (the
// MCP equivalent of v1's `/api/tools` dump — see the SearchInput/SearchResult
// contracts: omitting both `query` and `namespace` lists every app's tools in
// name order, paginated via `next`). Replaces v1's plain-GET catalog route,
// which v2 has no equivalent for.
const CATALOG_FILE = join(CACHE, "catalog.json");

const mcpCall = async (
  c: Config,
  sessionId: string,
  id: number,
  name: string,
  args: Record<string, unknown>,
) => {
  const res = await fetch(`${c.executor}/mcp`, {
    method: "POST",
    headers: { ...mcpHeaders(), "mcp-session-id": sessionId },
    signal: AbortSignal.timeout(15_000),
    body: JSON.stringify({
      jsonrpc: "2.0",
      id,
      method: "tools/call",
      params: { name, arguments: args },
    }),
  });
  if (!res.ok) throw new Error(`${name} http ${res.status}`);
  const body = (await mcpParse(res)) as {
    result?: { structuredContent?: unknown };
    error?: { message: string };
  };
  if (body.error) throw new Error(`${name} mcp error: ${body.error.message}`);
  if (!body.result?.structuredContent)
    throw new Error(`${name}: no structuredContent`);
  return body.result.structuredContent;
};

// Lists every tool unscoped search reaches (executor's own exclusions apply),
// then reads full descriptions with describe: search pages carry only each
// description's first line, which embeds far worse.
export async function fetchCatalog(c: Config): Promise<Tool[]> {
  const sessionId = await mcpSession(c, 5000);
  let id = 2;
  const paths: string[] = [];
  let params: Record<string, unknown> = {};
  // A hard page cap keeps a pathological catalogue from hanging the build.
  for (let page = 0; page < 50; page++) {
    const result = (await mcpCall(c, sessionId, id++, "search", {
      limit: 200,
      ...params,
    })) as {
      items: Array<{ path: string }>;
      next: Record<string, unknown> | null;
    };
    paths.push(...result.items.map((i) => i.path));
    if (!result.next) break;
    params = result.next;
  }
  const tools: Tool[] = [];
  // describe takes at most 20 paths per call.
  for (let i = 0; i < paths.length; i += 20) {
    const result = (await mcpCall(c, sessionId, id++, "describe", {
      paths: paths.slice(i, i + 20),
    })) as { items: Array<{ path: string; description?: string }> };
    for (const item of result.items) {
      const path = canonical(item.path);
      tools.push({
        path,
        name: path.split(".").at(-1) ?? path,
        description: item.description ?? "",
      });
    }
  }
  return tools;
}

const cachedCatalog = (): Tool[] | null => {
  try {
    return JSON.parse(readFileSync(CATALOG_FILE, "utf8")) as Tool[];
  } catch {
    return null;
  }
};

// Cache key: the embed endpoint (stands in for the model) plus every doc text.
const vectorsFile = (c: Config, texts: string[]): string => {
  const key = createHash("sha256")
    .update([c.embed, ...texts].join("\n"))
    .digest("hex")
    .slice(0, 16);
  return join(CACHE, `vectors-${key}.json`);
};

// The compiled binary re-execs itself for the detached build; under the
// pinned-bun wrapper the entry script (cli.ts, not this module) is re-passed.
// $bunfs only exists in compiled form.
export const selfCommand = (): string[] =>
  import.meta.url.includes("$bunfs")
    ? [process.execPath]
    : [process.execPath, Bun.main];

// Hands the catalogue refresh and embedding to a detached `build` run, at most
// one at a time: describing and embedding every tool outlasts a hook.
const startBuild = (): void => {
  const lock = join(CACHE, "build.lock");
  if (existsSync(lock) && Date.now() - statSync(lock).mtimeMs < 2 * 60_000)
    return;
  mkdirSync(CACHE, { recursive: true });
  writeFileSync(lock, "");
  const self = selfCommand();
  spawn(self[0]!, [...self.slice(1), "build"], {
    detached: true,
    stdio: "ignore",
  }).unref();
};

// Doc vectors for this exact catalogue, or null while a build makes them.
function docVectors(c: Config, tools: Tool[]): number[][] | null {
  const file = vectorsFile(c, tools.map(docText));
  if (existsSync(file)) return JSON.parse(readFileSync(file, "utf8"));
  startBuild();
  return null;
}

// Executor tools this session already called, in any spelling: MCP flattens
// `a.b.tool_name` to `a_b_tool_name` (sometimes prefixed with the server
// name), and claude's transcripts carry dotted short-paths.
export const isUsed = (path: string, used: readonly string[]): boolean => {
  if (used.length === 0) return false;
  const flat = path.replaceAll(".", "_");
  return (
    used.includes(flat) ||
    used.includes(path) ||
    used.includes(shortPath(path)) ||
    used.some((u) => u.endsWith(`_${flat}`))
  );
};

export const render = (picks: Tool[]): string =>
  [
    `${MARKER} (optional, use only if they fit the task):`,
    ...picks.map(
      (p) =>
        `- ${expression(p.path)}: ${(p.description.split("\n")[0] ?? "").slice(0, 140)}`,
    ),
  ].join("\n");

export type SuggestInput = {
  event: string;
  sessionId: string;
  text: string;
  usedTools?: readonly string[];
};

// Returns the additionalContext to inject, or null. Every call is logged;
// failures propagate to the caller (hooks swallow them).
export async function suggest(input: SuggestInput): Promise<string | null> {
  const c = cfg();
  if (c.mode === "off" || !process.env.EXECUTOR_AUTH_TOKEN) return null;
  const text = input.text.trim();
  if (text.length < 8) return null;

  // A stale catalogue keeps serving while a build refreshes it in the
  // background, so a hook never waits on describe calls.
  const tools = cachedCatalog();
  if (!tools || Date.now() - statSync(CATALOG_FILE).mtimeMs > CATALOG_TTL)
    startBuild();
  if (!tools) return null;
  const vectors = docVectors(c, tools);
  if (!vectors) return null;
  const q = (await embed(c, [INSTRUCT + text.slice(0, 2000)]))[0]!;

  const ranked = tools
    .map((tool, i) => ({
      tool,
      score: vectors[i]!.reduce((s, x, j) => s + x * q[j]!, 0),
    }))
    .sort((a, b) => b.score - a.score);

  const stateFile = join(CACHE, "sessions", `${input.sessionId}.json`);
  let suggested: string[] = [];
  try {
    suggested = JSON.parse(readFileSync(stateFile, "utf8"));
  } catch {}
  const skip = new Set(suggested);
  const picks = ranked
    .filter(
      (r) =>
        r.score >= c.threshold &&
        // Snippet management (snippets._save, _delete, ...) is never the task.
        !r.tool.path.startsWith("snippets._") &&
        !skip.has(shortPath(r.tool.path)) &&
        !isUsed(r.tool.path, input.usedTools ?? []),
    )
    .slice(0, MAX_SUGGEST)
    .map((r) => r.tool);

  mkdirSync(dirname(stateFile), { recursive: true });
  writeFileSync(
    stateFile,
    JSON.stringify([...suggested, ...picks.map((p) => shortPath(p.path))]),
  );

  // In an A/B test each event with picks is randomly shown them or not, so the
  // two arms' later tool use can be compared; "inject" otherwise.
  const arm =
    c.mode !== "inject" || picks.length === 0
      ? null
      : c.abInject === undefined || Math.random() < c.abInject
        ? "inject"
        : "holdout";

  try {
    mkdirSync(dirname(LOG), { recursive: true });
    appendFileSync(
      LOG,
      `${JSON.stringify({
        ts: new Date().toISOString(),
        session_id: input.sessionId,
        event: input.event,
        mode: c.mode,
        text_sha: createHash("sha256").update(text).digest("hex"),
        text_len: text.length,
        top: ranked.slice(0, 5).map((r) => ({
          path: r.tool.path,
          score: Math.round(r.score * 1e4) / 1e4,
        })),
        would_inject: picks.map((p) => p.path),
        arm,
      })}\n`,
    );
  } catch {}

  return arm === "inject" ? render(picks) : null;
}

// Detached / CLI: embed the current catalogue's docs into the vector cache.
export async function build(): Promise<void> {
  const lock = join(CACHE, "build.lock");
  try {
    const c = cfg();
    const tools = await fetchCatalog(c);
    const texts = tools.map(docText);
    const file = vectorsFile(c, texts);
    if (!existsSync(file)) {
      const vectors: number[][] = [];
      for (let i = 0; i < texts.length; i += 32)
        vectors.push(...(await embed(c, texts.slice(i, i + 32), 60_000)));
      const rounded = vectors.map((v) =>
        v.map((x) => Math.round(x * 1e5) / 1e5),
      );
      mkdirSync(dirname(file), { recursive: true });
      writeFileSync(`${file}.tmp`, JSON.stringify(rounded));
      renameSync(`${file}.tmp`, file);
    }
    // Vectors first, then the catalogue that names them, so a hook never
    // reads a catalogue whose vectors are missing.
    writeFileSync(`${CATALOG_FILE}.tmp`, JSON.stringify(tools));
    renameSync(`${CATALOG_FILE}.tmp`, CATALOG_FILE);
    for (const name of readdirSync(CACHE))
      if (name.startsWith("vectors-") && join(CACHE, name) !== file)
        unlinkSync(join(CACHE, name));
  } finally {
    try {
      unlinkSync(lock);
    } catch {}
  }
}

export function selftest(): void {
  const check = (name: string, got: unknown, want: unknown) => {
    if (JSON.stringify(got) !== JSON.stringify(want)) {
      throw new Error(
        `selftest ${name}: got ${JSON.stringify(got)}, want ${JSON.stringify(want)}`,
      );
    }
  };
  check(
    "short-path tools",
    shortPath("tools.outsmartly.start_build"),
    "outsmartly.start_build",
  );
  check(
    "short-path conn",
    shortPath("outsmartly.org.outsmartlyoauth.start_build"),
    "outsmartly.start_build",
  );
  check(
    "short-path snippet",
    shortPath("tools.snippets.org.workspace.mail_search_read"),
    "snippets.mail_search_read",
  );
  check(
    "canonical bracket",
    canonical('tools["atlassian-delivery"].jira_search'),
    "atlassian-delivery.jira_search",
  );
  check(
    "canonical bracket tool",
    canonical('tools.runpod["describe-tool"]'),
    "runpod.describe-tool",
  );
  check(
    "expression",
    expression("atlassian-delivery.jira_search"),
    'tools["atlassian-delivery"].jira_search',
  );
  check("expression plain", expression("github.get_me"), "tools.github.get_me");
  check("normalize", normalize([3, 4]), [0.6, 0.8]);
  check(
    "used flat",
    isUsed("atlassian.org.delivery.jira_search", [
      "atlassian_org_delivery_jira_search",
    ]),
    true,
  );
  check(
    "used path",
    isUsed("atlassian.org.delivery.jira_search", [
      "atlassian.org.delivery.jira_search",
    ]),
    true,
  );
  check(
    "used short",
    isUsed("atlassian.org.delivery.jira_search", ["atlassian.jira_search"]),
    true,
  );
  check("used prefixed", isUsed("a.b.c_t", ["executor_a_b_c_t"]), true);
  check("used negative", isUsed("a.b.c_t", ["x_y_z"]), false);
  check(
    "render",
    render([{ path: "x.y", name: "y", description: "first line\nsecond" }]),
    [
      "Possibly relevant executor tools (optional, use only if they fit the task):",
      "- tools.x.y: first line",
    ].join("\n"),
  );
}
