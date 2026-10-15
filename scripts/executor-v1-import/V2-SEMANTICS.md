# v2 `execute` semantics, as observed

Checked live against a scratch v2 instance (2.0.0-beta.23), calling real deployed apps
(`tools["atlassian-delivery"].jira_get_issue`, `tools.slack.channels_list`, `tools.tasks.list_tasks`,
`tools.github.get_me`) with real and deliberately-bad input. No personal data below; issue keys,
error strings and field names are either synthetic or already public (nonexistent ticket number,
a missing required field).

v1's `{ ok, data }` / `{ ok: false, error }` envelope does not exist in v2. There is no `.ok` and
no `.data`. A v2 tool call is a plain `await tools.<app>.<tool>(input)` that either:

## 1. Resolves normally (success or an upstream/tool-level error)

```ts
await tools.tasks.list_tasks({ limit: 1 })
// -> { content: [{ type: "text", text: "{\n  \"tasks\": []\n}" }], isError: false }
```

Some tools also carry `structuredContent` alongside `content` (the parsed-object form of the
same payload), when the tool declares an output schema:

```ts
await tools["atlassian-delivery"].jira_search({ jql: "...", limit: 1 })
// -> { content: [{ type: "text", text: "<JSON string>" }], structuredContent: {...same, parsed...}, isError: false }
```

`structuredContent` is not universal (`tools.tasks.list_tasks` above has none). `content[0].text`
is always present on success, so parsing it (`JSON.parse(r.content[0].text)`) is the portable path
-- same as v1's `JSON.parse(r.data.content[0].text)`, just without the `.data`.

When the call fails at the *tool* level (a real request was made, the upstream service or MCP
server reported a failure, e.g. "not found"), the shape doesn't change -- only `isError` flips, and
`content[0].text` becomes a plain human-readable message, not JSON:

```ts
await tools["atlassian-delivery"].jira_get_issue({ issue_key: "DEL-999999999" })
// -> {
//   content: [{ type: "text", text: "Error calling tool 'get_issue': Issue DEL-999999999 not found. Verify the issue key and project access." }],
//   isError: true
// }
```

So: **check `r.isError`, not `r.ok`.** There is no separate `.error` field on a tool-level
failure; the message is `r.content[0].text` itself.

## 2. Throws (input validation / transport failure)

A call whose *input* fails schema validation (missing/extra/mistyped fields), or that otherwise
can't be sent (bad auth, etc.), throws a plain JS `Error` rather than resolving. Its `.message` is
a JSON-encoded string:

```ts
await tools.slack.channels_list({}) // missing required channel_types
// throws Error whose .message is:
// {"code":"InputInvalid","status":422,"message":"Input failed validation: input.channel_types: Missing key. Expected string","recovery":{"action":"...","instructions":"..."},"retryable":false}
```

Uncaught, this surfaces at the outer `execute` level as
`{ status: "completed", execution: { ok: false, error: { kind: "ToolFailure", message, response } }, toolCalls: [{ outcome: "failure", ... }] }`
-- but that's what the *caller of `execute`* sees, not something a snippet's own code can read
unless it wraps the call in `try/catch` itself:

```ts
try {
  return await tools.slack.channels_list({});
} catch (e) {
  // e.message is the JSON string above; JSON.parse(e.message).message is the plain reason
  return { error: e.message };
}
```

## Net effect for rewriting a v1 snippet

v1's `.data` was literally the same raw MCP result v2 now returns directly, so:
- `r.ok` -> `!r.isError` (tool ran, check whether it reported failure)
- `r.data.content[0].text` -> `r.content[0].text` (drop `.data`, nothing else changes)
- `r.data.structuredContent` -> `r.structuredContent` (same)
- `r.error` (v1's synthesized error) -> no direct equivalent on an `isError:true` result; use
  `r.content[0].text` (human-readable) instead. For a thrown validation/transport error, wrap the
  call in `try/catch` and use `e.message` (or `JSON.parse(e.message).message` for just the reason).

## `tools.search`

Unchanged in shape from what v1 called `tools.search` for -- returns
`{ items: [{ path, description, input/signature }], namespaces: [{ path, app, accounts? }], remaining, next? }`.
Paths are now `<appSlug>.<tool>` (bracket-quoted when the slug has a hyphen) instead of
`<integration>.<owner>.<connection>.<tool>`; see path-map.json.
