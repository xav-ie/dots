#!/usr/bin/env bun

// Thin opencode adapter for the shared tool-suggest engine: marshals opencode
// events into the claude-hook JSON contract, spawns the compiled binary at
// ~/.local/bin/tool-suggest (fallback: PATH), and injects the returned
// additionalContext as a synthetic text part. No suggestion logic lives here
// — the binary in packages/tool-suggest is the one true source, so claude and
// opencode always run identical code. Config (mode/threshold) lives in
// ~/.config/tool-suggest/config.json, read by the engine itself.

import { spawn } from "node:child_process";
import { randomUUID } from "node:crypto";
import { homedir } from "node:os";
import { join } from "node:path";

const BINARY = join(homedir(), ".local", "bin", "tool-suggest");
const TIMEOUT_MS = 3000;

type TextPart = {
  id: string;
  sessionID: string;
  messageID: string;
  type: "text";
  text: string;
  synthetic: true;
};

// Mirrors what opencode saves for editor-context injections: synthetic parts
// ride along in the user message and reach the model, but are marked as
// non-typed text. opencode rejects part ids that don't start with "prt"
// (core/src/id), so ids are prefixed.
function part(sessionID: string, messageID: string, text: string): TextPart {
  return {
    id: `prt_${randomUUID().replaceAll("-", "")}`,
    sessionID,
    messageID,
    type: "text",
    text,
    synthetic: true,
  };
}

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

export const ToolSuggest = async () => {
  // Executor tools this session already called, from tool.execute.after.
  const used = new Map<string, Set<string>>();
  const recordUsed = (sessionID: string, tool: string) => {
    if (!sessionID || !tool) return;
    const set = used.get(sessionID);
    if (set) set.add(tool);
    else used.set(sessionID, new Set([tool]));
  };
  const suggestFor = (event: string, sessionID: string, text: string) =>
    runEngine({
      hook_event_name: event,
      session_id: sessionID,
      text,
      used_tools: [...(used.get(sessionID) ?? [])],
    });

  return {
    // Claude's UserPromptSubmit: appended parts persist as part of the user
    // turn (synthetic, so the TUI can tell them apart from typed text).
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
        );
        if (!context) return;
        output.parts.push(part(input.sessionID, output.message.id, context));
      } catch {}
    },
    // Claude's PostToolBatch: before each model call, suggest from the
    // agent's latest text and attach the picks to the last user message
    // (in-memory only — nothing is persisted by this hook).
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
            (p) =>
              p.type === "text" &&
              p.text?.startsWith("Possibly relevant executor tools"),
          )
        )
          return;
        const context = await suggestFor(
          "opencode.messages.transform",
          target.info.sessionID,
          textOf(assistant.parts),
        );
        if (!context) return;
        target.parts.push(part(target.info.sessionID, target.info.id, context));
      } catch {}
    },
    "tool.execute.after": async (input: {
      sessionID: string;
      tool: string;
    }) => {
      recordUsed(input.sessionID, input.tool);
    },
  };
};
