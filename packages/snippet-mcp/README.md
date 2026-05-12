# snippet-mcp

MCP server that turns each markdown file in `$SNIPPET_DIR` (default
`/var/lib/snippet-mcp/snippets`) into a searchable MCP tool. Designed to be
registered as a remote source inside [executor](https://github.com/RhysSullivan/executor)
so saved workflows show up alongside slack/jira/etc. in `tools.search(...)`.

Written in Rust on the official [rmcp](https://github.com/modelcontextprotocol/rust-sdk)
SDK — single static binary, ~10 MB resident.

## Run locally

```sh
cargo run --release -- --stdio
# or HTTP:
cargo run --release -- --http --port 38973 --host 127.0.0.1
```

Env:

- `SNIPPET_DIR` — snippets directory (default `/var/lib/snippet-mcp/snippets`)
- `EXECUTOR_REFRESH_URL` — POSTed after writes to force a catalog refresh in
  executor. Leave unset for local dev.
- `RUST_LOG` — tracing filter, default `snippet_mcp=info`.

## Snippet format

See `../../snippets/README.md`.
