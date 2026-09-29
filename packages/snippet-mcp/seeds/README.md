# Snippet seeds

Markdown snippets that ship with the `snippet-mcp` package. On first activation
the NixOS module copies any file in this directory into
`/var/lib/snippet-mcp/snippets/` _if and only if_ the target doesn't already
exist — runtime saves are never overwritten.

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

const res = await tools["slack.org.workspace.conversations_add_message"]({
channel_id: {{json channel_id}},
text: {{json message}},
})
if (!res.ok) return `FAILED ${res.error.code}: ${res.error.message}`
return res.data
```

## Rules

- **Filename** = tool name. Must match `^[a-z][a-z0-9_]*$`. `README.md` is ignored.
- **description** (required) — specific; this is what `tools.search(...)` scores against.
- **args** (optional) — `name → { type, description?, optional?, default? }`. Types: `string`, `number`, `boolean`.
- **tags** (optional) — boost search relevance.
- **kind** (optional, default `code`) — `code` or `instructions`. Both are just returned-text; the kind is a hint.
- **Tool paths** — always the full `<integration>.<owner>.<connection>.<tool>` address from `tools.search()` / `tools.describe.tool()`; short aliases like `tools.slack.<tool>` don't resolve. Calls return `{ ok, data }` or `{ ok: false, error }`, so check `ok` before using `data`.

## Templating

- `{{json key}}` → `JSON.stringify(args.key)`. Use this for TS string/object/array literals.
- `{{raw key}}` → `String(args.key)`. Use sparingly; never for user-supplied strings inside JS source.

Unknown placeholders, missing required args, or extra args cause the call to fail loudly — intentional.

## Editing the live store

```sh
sudo -u snippet-mcp $EDITOR /var/lib/snippet-mcp/snippets/<name>.md
```

Or use the MCP tools through executor: `_list`, `_get`, `_save`, `_update`, `_delete`.
