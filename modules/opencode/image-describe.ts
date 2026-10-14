#!/usr/bin/env bun

// Vision shim for text-only coding models: pasted images are described by a
// vision-capable sibling model (zai-coding-plan/glm-5.3-flash) and the
// description replaces the image part before the turn runs. The user's
// accompanying message text is sent to the describer so the reading focuses
// on what was asked. Native vision models are left untouched. Descriptions
// are cached by image+prompt hash. The API key comes from opencode's own
// credential store (auth.json); the describer model is configured by the
// constants below — this file is deployed as a live-editable symlink.

import { createHash, randomUUID } from "node:crypto";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

const DESCRIBE_MODEL = "glm-5.3-flash";
const DESCRIBE_PROVIDER = "zai-coding-plan";
const DESCRIBE_URL = "https://api.z.ai/api/coding/paas/v4/chat/completions";
const CACHE_DIR = join(homedir(), ".cache", "opencode", "image-describe");
const TIMEOUT_MS = 60_000;

const DESCRIBE_PROMPT = [
  "You are describing an image for a coding agent that cannot see images.",
  "Describe everything relevant in full detail: UI layout, text content, code,",
  "error messages, diagrams, values, colors, and positions. Write it as a",
  "factual reference for the agent, not a reply to the user. The user's",
  "message that accompanies this image follows; use it to focus the",
  "description, but still cover anything else the agent might need.",
  "",
  "User's message:",
].join("\n");

type FilePart = {
  id: string;
  sessionID: string;
  messageID: string;
  type: "file";
  url: string;
  mime: string;
  filename?: string;
};

type TextPart = {
  id: string;
  sessionID: string;
  messageID: string;
  type: "text";
  text: string;
  synthetic?: boolean;
};

function apiKey(): string | null {
  try {
    const auth = JSON.parse(
      readFileSync(
        join(homedir(), ".local", "share", "opencode", "auth.json"),
        "utf8",
      ),
    );
    const entry = auth[DESCRIBE_PROVIDER];
    return entry?.key ?? entry?.api_key ?? null;
  } catch {
    return null;
  }
}

// opencode rejects part ids that don't start with "prt" (core/src/id).
const partId = (): string => `prt_${randomUUID().replaceAll("-", "")}`;

// File parts may carry a data: URL or a path to the attachment on disk.
async function dataUrlOf(part: FilePart): Promise<string | null> {
  if (part.url.startsWith("data:")) return part.url;
  try {
    const bytes = readFileSync(part.url.replace(/^file:\/\//, ""));
    return `data:${part.mime};base64,${Buffer.from(bytes).toString("base64")}`;
  } catch {
    return null;
  }
}

async function describe(
  dataUrl: string,
  prompt: string,
  key: string,
): Promise<string> {
  const res = await fetch(DESCRIBE_URL, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      authorization: `Bearer ${key}`,
    },
    body: JSON.stringify({
      model: DESCRIBE_MODEL,
      messages: [
        {
          role: "user",
          content: [
            { type: "text", text: `${DESCRIBE_PROMPT}\n${prompt || "(none)"}` },
            { type: "image_url", image_url: { url: dataUrl } },
          ],
        },
      ],
    }),
    signal: AbortSignal.timeout(TIMEOUT_MS),
  });
  if (!res.ok) throw new Error(`describe http ${res.status}`);
  const json = (await res.json()) as {
    choices: { message: { content: string } }[];
  };
  const text = json.choices?.[0]?.message?.content?.trim();
  if (!text) throw new Error("describe empty response");
  return text;
}

// Cached by image + accompanying prompt: the same picture re-pasted under a
// different question deserves a fresh reading.
async function describeCached(
  dataUrl: string,
  prompt: string,
  key: string,
): Promise<string> {
  const file = join(
    CACHE_DIR,
    `${createHash("sha256").update(`${dataUrl}\n${prompt}`).digest("hex").slice(0, 32)}.txt`,
  );
  try {
    return readFileSync(file, "utf8");
  } catch {}
  const text = await describe(dataUrl, prompt, key);
  try {
    mkdirSync(CACHE_DIR, { recursive: true });
    writeFileSync(file, text);
  } catch {}
  return text;
}

export const ImageDescribe = async ({
  client,
}: {
  client: {
    provider: {
      list: () => Promise<{
        all?: {
          id: string;
          models?: Record<string, { attachment?: boolean }>;
        }[];
      }>;
    };
  };
}) => {
  // Provider registry (models.dev data) fetched once; null while unknown.
  let attachmentCapable: Set<string> | null = null;
  const loadCapabilities = async (): Promise<Set<string> | null> => {
    try {
      const res = await client.provider.list();
      const set = new Set<string>();
      for (const p of res.all ?? [])
        for (const [id, m] of Object.entries(p.models ?? {}))
          if (m.attachment) set.add(`${p.id}/${id}`);
      return set;
    } catch {
      return null;
    }
  };

  const modelCanSee = async (model?: {
    providerID: string;
    modelID: string;
  }): Promise<boolean> => {
    if (model) {
      attachmentCapable ??= await loadCapabilities();
      if (attachmentCapable?.has(`${model.providerID}/${model.modelID}`))
        return true;
    }
    return false;
  };

  return {
    "chat.message": async (
      input: {
        sessionID: string;
        model?: { providerID: string; modelID: string };
      },
      output: { message: { id: string }; parts: (FilePart | TextPart)[] },
    ) => {
      try {
        const images = output.parts.filter(
          (p) => p.type === "file" && p.mime.startsWith("image/"),
        );
        if (images.length === 0) return;
        if (await modelCanSee(input.model)) return;

        const key = apiKey();
        const prompt = output.parts
          .filter((p) => p.type === "text")
          .map((p) => p.text)
          .join("\n");

        for (let i = 0; i < output.parts.length; i++) {
          const part = output.parts[i];
          if (part.type !== "file" || !part.mime.startsWith("image/")) continue;
          const replacement: TextPart = {
            id: partId(),
            sessionID: input.sessionID,
            messageID: output.message.id,
            type: "text",
            synthetic: true,
            text: "",
          };
          try {
            const dataUrl = await dataUrlOf(part);
            if (!dataUrl) throw new Error("unreadable image");
            const description = key
              ? await describeCached(dataUrl, prompt, key)
              : "";
            if (!description) throw new Error("no describer key");
            replacement.text = `Image ${part.filename ?? "(pasted)"} described by ${DESCRIBE_MODEL} (the model in this session cannot see images):\n${description}`;
          } catch (error) {
            replacement.text = `Image ${part.filename ?? "(pasted)"} was attached but automatic description failed (${error instanceof Error ? error.message : "unknown error"}); ask the user to describe it if it matters.`;
          }
          output.parts[i] = replacement;
        }
      } catch {}
    },
  };
};
