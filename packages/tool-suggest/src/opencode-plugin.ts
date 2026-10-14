#!/usr/bin/env bun

// Thin opencode adapter for the shared tool-suggest engine: marshals opencode
// events into the claude-hook JSON contract, spawns the compiled binary at
// ~/.local/bin/tool-suggest (fallback: PATH), and injects the returned
// additionalContext. No suggestion logic lives here — the binary in
// packages/tool-suggest is the one true source, so claude and opencode always
// run identical code. Config (mode/threshold) lives in
// ~/.config/tool-suggest/config.json, read by the engine itself.
//
// Dual entrypoint: OpenCode V2 calls setup() (prompt admission + model-request
// context + tool hooks); V1 1.18.29+ calls server() (chat.message +
// messages.transform + tool.execute.after). Keep both until the V2 move is
// proven, then drop server().

import { spawn } from "node:child_process";
import { randomUUID } from "node:crypto";
import { homedir } from "node:os";
import { join } from "node:path";
import { Plugin } from "@opencode/plugin";

const BINARY = join(homedir(), ".local", "bin", "tool-suggest");
const TIMEOUT_MS = 3000;
const MARKER = "Possibly relevant executor tools";

type TextPart = {
  id: string;
  sessionID: string;
  messageID: string;
  type: "text";
  text: string;
  synthetic: true;
};

// opencode rejects part ids that don't start with "prt" (core/src/id), so ids
// are prefixed.
const partId = (): string => `prt_${randomUUID().replaceAll("-", "")}`;

function runEngine(payload: Record<string, unknown>): Promise<string | null> {
  return new Promise((resolve) => {
    let child: ReturnType<typeof spawn>;
    try {
      child = spawn(BINARY, [], { stdio: ["pipe", "pipe", "ignore"] });
    } catch {
      resolve(null);
      return;
    }
    let out = "";
    const timer = setTimeout(() => {
      child.kill();
      resolve(null);
    }, TIMEOUT_MS);
    child.stdout?.on("data", (chunk) => {
      out += String(chunk);
    });
    child.on("error", () => {
      clearTimeout(timer);
      resolve(null);
    });
    child.on("close", () => {
      clearTimeout(timer);
      try {
        const parsed = JSON.parse(out) as {
          hookSpecificOutput?: { additionalContext?: string };
        };
        resolve(parsed.hookSpecificOutput?.additionalContext ?? null);
      } catch {
        resolve(null);
      }
    });
    child.stdin?.end(JSON.stringify(payload));
  });
}

const textOf = (parts: { type?: string; text?: string }[]): string =>
  parts
    .filter((p) => p.type === "text")
    .map((p) => p.text)
    .join("\n");

// Used-tool bookkeeping shared by both entrypoints.
type UsedMap = Map<string, Set<string>>;

const recordUsed = (used: UsedMap, sessionID: string, tool: string): void => {
  if (!sessionID || !tool) return;
  const set = used.get(sessionID);
  if (set) set.add(tool);
  else used.set(sessionID, new Set([tool]));
};

const suggestFor = (
  event: string,
  sessionID: string,
  text: string,
  used: UsedMap,
) =>
  runEngine({
    hook_event_name: event,
    session_id: sessionID,
    text,
    used_tools: [...(used.get(sessionID) ?? [])],
  });

const v2 = Plugin.define({
  id: "opencode.tool-suggest",
  async setup(ctx) {
    const used: UsedMap = new Map();
    await ctx.tool.hook("execute.after", (event) => {
      recordUsed(used, event.sessionID ?? "*", event.tool);
    });
    // Claude's UserPromptSubmit equivalent: admission-time injection. Edits
    // become the canonical persisted user input.
    await ctx.session.hook("prompt", async (event) => {
      try {
        const text = event.prompt?.text ?? "";
        const context = await suggestFor(
          "opencode.prompt",
          event.sessionID ?? "unknown",
          text,
          used,
        );
        if (!context || text.includes(MARKER)) return;
        event.prompt.text = `${text}\n\n${context}`;
      } catch {}
    });
    // Claude's PostToolBatch equivalent: before each model call, suggest from
    // the agent's latest text and attach the picks to the last user message.
    // Affects only the outgoing model call, never persisted history.
    await ctx.session.hook("context", async (event) => {
      try {
        // V2 messages are flat: role at the top level, parts under `content`
        // (V1 carried info.role + parts — handle both).
        type Msg = {
          info?: { role?: string; id?: string; sessionID?: string };
          role?: string;
          content?: {
            type?: string;
            text?: string;
            id?: string;
            synthetic?: boolean;
          }[];
          parts?: {
            type?: string;
            text?: string;
            id?: string;
            synthetic?: boolean;
          }[];
        };
        const msgs: Msg[] = event.messages ?? [];
        const roleOf = (m: Msg) => m?.info?.role ?? m?.role;
        const partsOf = (m: Msg) => (m.content ??= m.parts ?? []);
        const assistant = msgs.findLast((m) => roleOf(m) === "assistant");
        const target = msgs.findLast((m) => roleOf(m) === "user");
        if (!assistant || !target) return;
        if (
          partsOf(target).some(
            (p) => p.type === "text" && p.text?.startsWith(MARKER),
          )
        )
          return;
        const context = await suggestFor(
          "opencode.context",
          event.sessionID ?? "unknown",
          textOf(partsOf(assistant)),
          used,
        );
        if (!context) return;
        partsOf(target).push({
          id: partId(),
          type: "text",
          text: context,
          synthetic: true,
        });
      } catch {}
    });
  },
});

// V1 entrypoint (OpenCode 1.x): chat.message parts are persisted with the
// user message; messages.transform edits the outgoing model call only.
async function server() {
  const used: UsedMap = new Map();
  const part = (
    sessionID: string,
    messageID: string,
    text: string,
  ): TextPart => ({
    id: partId(),
    sessionID,
    messageID,
    type: "text",
    text,
    synthetic: true,
  });
  return {
    "chat.message": async (
      input: { sessionID: string },
      output: { message: { id: string }; parts: unknown[] },
    ) => {
      try {
        const text = textOf(output.parts as { type?: string; text?: string }[]);
        const context = await suggestFor(
          "opencode.chat.message",
          input.sessionID,
          text,
          used,
        );
        if (!context) return;
        output.parts.push(part(input.sessionID, output.message.id, context));
      } catch {}
    },
    "experimental.chat.messages.transform": async (
      _input: unknown,
      output: {
        messages: {
          info: { id: string; role: string; sessionID: string };
          parts: { type?: string; text?: string }[];
        }[];
      },
    ) => {
      try {
        const msgs = output.messages;
        const assistant = msgs.findLast((m) => m.info.role === "assistant");
        const target = msgs.findLast((m) => m.info.role === "user");
        if (!assistant || !target) return;
        if (
          target.parts.some(
            (p) => p.type === "text" && p.text?.startsWith(MARKER),
          )
        )
          return;
        const context = await suggestFor(
          "opencode.messages.transform",
          target.info.sessionID,
          textOf(assistant.parts),
          used,
        );
        if (!context) return;
        target.parts.push(part(target.info.sessionID, target.info.id, context));
      } catch {}
    },
    "tool.execute.after": async (input: {
      sessionID: string;
      tool: string;
    }) => {
      recordUsed(used, input.sessionID, input.tool);
    },
  };
}

export default { ...v2, server };
