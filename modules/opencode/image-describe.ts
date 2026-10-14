#!/usr/bin/env bun

// Vision shim for text-only coding models: pasted images are described by a
// vision-capable sibling model (zai-coding-plan/glm-5.3-flash) and the
// description replaces the image before the turn runs. The user's
// accompanying message text is sent to the describer so the reading focuses
// on what was asked. Native vision models are left untouched. Descriptions
// are cached by image+prompt hash. The API key comes from opencode's own
// credential store (auth.json); the describer model is configured by the
// constants below — this file is deployed as a live-editable symlink.
//
// Dual entrypoint: OpenCode V2 calls setup() (prompt admission rewrites
// text/files before they are persisted); V1 1.18.29+ calls server()
// (chat.message part replacement). Keep both until the V2 move is proven.

import { createHash, randomUUID } from "node:crypto";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { Plugin } from "@opencode/plugin";

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

// File parts may carry a data: URL or a path to the attachment on disk; the
// V2 prompt hook hands over file URIs before resolution.
async function dataUrlOf(source: string, mime: string): Promise<string | null> {
  if (source.startsWith("data:")) return source;
  try {
    const bytes = readFileSync(
      decodeURIComponent(source.replace(/^file:\/\//, "")),
    );
    return `data:${mime || "image/png"};base64,${Buffer.from(bytes).toString("base64")}`;
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

const describeBlock = async (
  source: string,
  mime: string,
  name: string,
  prompt: string,
): Promise<string> => {
  try {
    const key = apiKey();
    if (!key) throw new Error("no describer key");
    const dataUrl = await dataUrlOf(source, mime);
    if (!dataUrl) throw new Error("unreadable image");
    const description = await describeCached(dataUrl, prompt, key);
    return `Image ${name} described by ${DESCRIBE_MODEL} (the model in this session cannot see images):\n${description}`;
  } catch (error) {
    return `Image ${name} was attached but automatic description failed (${error instanceof Error ? error.message : "unknown error"}); ask the user to describe it if it matters.`;
  }
};

const imageMimeOf = (uri: string, mime?: string): string | null => {
  if (mime?.startsWith("image/")) return mime;
  if (uri.startsWith("data:image/")) return uri.slice(5, uri.indexOf(";"));
  if (/\.(png|jpe?g|gif|webp|bmp|svg)$/i.test(uri)) return "image/*";
  return null;
};

const fileNameOf = (uri: string, name?: string): string =>
  name ?? uri.split("/").pop() ?? "(pasted)";

// V2: does this model accept image input? Field shape is defensive because
// Model.Info capabilities are provider-sourced.
const modelSeesImages = (model: {
  providerID?: string;
  id?: string;
  capabilities?: { input?: unknown };
  attachment?: boolean;
}): boolean => {
  const input = model.capabilities?.input;
  if (Array.isArray(input))
    return input.some((s) => String(s).includes("image"));
  if (input && typeof input === "object")
    return Object.entries(input as Record<string, unknown>).some(
      ([k, v]) => k.includes("image") && Boolean(v),
    );
  if (model.attachment === true) return true;
  return false;
};

const v2 = Plugin.define({
  id: "opencode.image-describe",
  async setup(ctx) {
    let visionModels: Set<string> | null = null;
    const loadVision = async (): Promise<Set<string> | null> => {
      try {
        const models = await ctx.model.list();
        const set = new Set<string>();
        for (const m of models)
          if (modelSeesImages(m)) set.add(`${m.providerID}/${m.id}`);
        return set;
      } catch {
        return null;
      }
    };

    const sessionModelSees = async (
      sessionID: string | undefined,
    ): Promise<boolean> => {
      visionModels ??= await loadVision();
      if (!visionModels || visionModels.size === 0) return false;
      try {
        const session = await ctx.session.get({ sessionID: sessionID ?? "" });
        const providerID = session?.model?.providerID;
        const modelID = session?.model?.id ?? session?.model?.modelID;
        if (providerID && modelID)
          return visionModels.has(`${providerID}/${modelID}`);
      } catch {}
      return false;
    };

    // Runs before attachment resolution and durable admission: image files
    // become text blocks in the canonical persisted prompt for text-only
    // models, and are left untouched for vision-capable ones.
    await ctx.session.hook("prompt", async (event) => {
      try {
        const prompt = event.prompt;
        const files = prompt?.files ?? [];
        const images = files.filter((f: { uri?: string; mime?: string }) =>
          imageMimeOf(f.uri ?? "", f.mime),
        );
        if (images.length === 0) return;
        if (await sessionModelSees(event.sessionID)) return;
        const blocks: string[] = [];
        for (const f of images) {
          const mime = imageMimeOf(f.uri ?? "", f.mime)!;
          blocks.push(
            await describeBlock(
              f.uri ?? "",
              mime,
              fileNameOf(f.uri ?? "", f.name),
              prompt.text ?? "",
            ),
          );
        }
        prompt.files = files.filter((f) => !images.includes(f));
        prompt.text = `${prompt.text ?? ""}${prompt.text ? "\n\n" : ""}${blocks.join("\n\n")}`;
      } catch {}
    });
  },
});

// V1 entrypoint (OpenCode 1.x): chat.message fires with resolved parts; image
// parts are swapped in place for synthetic text parts.
async function server() {
  return {
    "chat.message": async (
      input: { sessionID: string },
      output: { message: { id: string }; parts: (FilePart | TextPart)[] },
    ) => {
      try {
        const images = output.parts.filter(
          (p) => p.type === "file" && p.mime.startsWith("image/"),
        );
        if (images.length === 0) return;
        const prompt = output.parts
          .filter((p) => p.type === "text")
          .map((p) => p.text)
          .join("\n");
        for (let i = 0; i < output.parts.length; i++) {
          const part = output.parts[i];
          if (part.type !== "file" || !part.mime.startsWith("image/")) continue;
          output.parts[i] = {
            id: partId(),
            sessionID: input.sessionID,
            messageID: output.message.id,
            type: "text",
            synthetic: true,
            text: await describeBlock(
              part.url,
              part.mime,
              part.filename ?? "(pasted)",
              prompt,
            ),
          };
        }
      } catch {}
    },
  };
}

export default { ...v2, server };
