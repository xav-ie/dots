# Snippets

praesidium's `snippet-mcp` store. All snippets live in `snippets.age`, one
age-encrypted JSON object (name → markdown file) encrypted to the sops key in
`/etc/age/keys.txt`, so names stay hidden too. Commit it when it changes.

## Format

```markdown
---
description: One-line summary; this is what tools.search ranks against.
args:
  channel_id: { type: string, description: "Slack channel or DM channel id" }
  message: { type: string, description: "Message body" }
tags: [slack, message]
kind: code # or: instructions
---

const r = await tools.slack.conversations_add_message({
channel_id: {{json channel_id}},
text: {{json message}},
})
if (r.isError) return `FAILED: ${r.content[0].text}`
return r.structuredContent ?? r.content[0].text
```

## Rules

- **Filename** = tool name. Must match `^[a-z][a-z0-9_]*$`. `README.md` is ignored.
- **description** (required) — specific; this is what `tools.search(...)` scores against.
- **args** (optional) — `name → { type, description?, optional?, default? }`. Types: `string`, `number`, `boolean`, `array`, `object`.
- **tags** (optional) — boost search relevance.
- **kind** (optional, default `code`) — `code` runs through executor's `execute` and returns the program's value; `instructions` returns the rendered text.
- **Tool paths** — the exact `tools.<app>.<tool>` path from `tools.search()` / `tools.search.describe()`, e.g. `tools.slack.conversations_add_message`; an app with several accounts has one slug per account, such as `tools["google-workspace-work"]`. Calls return the raw MCP result `{ content, structuredContent?, isError }`: check `isError`, then read `structuredContent` or parse `content[0].text`.

## Templating

- `{{json key}}` → `JSON.stringify(args.key)`. Use this for TS string/object/array literals.
- `{{raw key}}` → `String(args.key)`. Use sparingly; never for user-supplied strings inside JS source.

Unknown placeholders, missing required args, or extra args cause the call to fail loudly — intentional.

## Editing the live store

Use the MCP tools through executor: `_list`, `_get`, `_save`, `_update`, `_delete`.
To read them by hand:

```sh
sudo age -d -i /etc/age/keys.txt snippets/snippets.age
```
