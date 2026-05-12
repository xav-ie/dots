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
  username: { type: string, description: "Slack username, no @" }
  message: { type: string, description: "Message body" }
tags: [slack, dm]
kind: code # or: instructions
---

const user = await tools.slack_mcp_server.users_lookupByName({
name: {{json username}},
})
await tools.slack_mcp_server.chat_postMessage({
channel: user.id,
text: {{json message}},
})
```

## Rules

- **Filename** = tool name. Must match `^[a-z][a-z0-9_]*$`. `README.md` is ignored.
- **description** (required) — specific; this is what `tools.search(...)` scores against.
- **args** (optional) — `name → { type, description?, optional?, default? }`. Types: `string`, `number`, `boolean`.
- **tags** (optional) — boost search relevance.
- **kind** (optional, default `code`) — `code` or `instructions`. Both are just returned-text; the kind is a hint.

## Templating

- `{{json key}}` → `JSON.stringify(args.key)`. Use this for TS string/object/array literals.
- `{{raw key}}` → `String(args.key)`. Use sparingly; never for user-supplied strings inside JS source.

Unknown placeholders, missing required args, or extra args cause the call to fail loudly — intentional.

## Editing the live store

```sh
sudo -u snippet-mcp $EDITOR /var/lib/snippet-mcp/snippets/<name>.md
```

Or use the MCP tools through executor: `_list`, `_get`, `_save`, `_update`, `_delete`.
