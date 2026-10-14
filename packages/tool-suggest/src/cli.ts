#!/usr/bin/env bun

// Host entry for claude-code hooks: reads one hook event JSON from stdin,
// prints {"hookSpecificOutput":{...,"additionalContext":...}} on stdout,
// exits 0 silently on any failure (hooks must never fail the turn). The
// opencode shim uses the same contract via the `text` field. Subcommands:
// `build` pre-warms the vector cache, `selftest` checks the pure helpers.

import { readFileSync } from "node:fs";
import { build, selftest, suggest } from "./engine.ts";

type HookInput = {
  hook_event_name?: string;
  prompt?: string;
  transcript_path?: string;
  session_id?: string;
  text?: string;
  used_tools?: string[];
};

// Claude's PostToolBatch supplies the transcript path instead of the text;
// walk it backwards for the last assistant message with text content (same
// walk as the former lib-transcript.nu last-assistant-text).
function lastAssistantText(transcriptPath: string): string {
  if (!transcriptPath) return "";
  let lines: string[];
  try {
    lines = readFileSync(transcriptPath, "utf8").split("\n").reverse();
  } catch {
    return "";
  }
  for (const line of lines) {
    if (!line) continue;
    let parsed: {
      message?: { role?: string; content?: { type?: string; text?: string }[] };
    };
    try {
      parsed = JSON.parse(line);
    } catch {
      continue;
    }
    if (parsed.message?.role !== "assistant") continue;
    const text = (parsed.message.content ?? [])
      .filter((c) => c.type === "text" && c.text)
      .map((c) => c.text)
      .join("\n");
    if (text.trim()) return text;
  }
  return "";
}

async function stdinJson(): Promise<HookInput> {
  try {
    return JSON.parse(await new Response(Bun.stdin).text()) as HookInput;
  } catch {
    return {};
  }
}

async function main() {
  // Compiled binaries keep bun's 3-element prefix (["bun", "/$bunfs/root/cli",
  // ...args]), so argv[2:] is user args in both modes.
  const cmd = Bun.argv[2];

  if (cmd === "build") {
    await build();
    return;
  }
  if (cmd === "selftest") {
    selftest();
    console.log("ok");
    return;
  }

  const input = await stdinJson();
  const event = input.hook_event_name ?? "";
  const text =
    event === "UserPromptSubmit"
      ? (input.prompt ?? "")
      : event === "PostToolBatch"
        ? lastAssistantText(input.transcript_path ?? "")
        : (input.text ?? "");

  const context = await suggest({
    event,
    sessionId: input.session_id ?? "unknown",
    text,
    usedTools: input.used_tools,
  });
  if (context) {
    console.log(
      JSON.stringify({
        hookSpecificOutput: {
          hookEventName: event,
          additionalContext: context,
        },
      }),
    );
  }
}

main().catch(() => {});
