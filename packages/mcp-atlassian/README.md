# mcp-atlassian

Nix packaging of upstream
[`sooperset/mcp-atlassian`](https://github.com/sooperset/mcp-atlassian) — an
MCP server for Jira and Confluence. The source comes from the
`mcp-atlassian-src` flake input; `default.nix` only handles the build.

## Packaging notes

Built against `python313Packages` from nixpkgs-bleeding (3.14's `fastmcp` is
broken). Notable workarounds:

- **`lupa` pinned to 2.5** — bleeding's 2.8 build ships a single combined
  module, but `py-key-value-aio` does `import lupa.lua51`, which needs the
  per-Lua-version submodule layout the 2.5 recipe produces.
- **`markdown-to-confluence`** and **`types-cachetools`** are built here
  (absent from nixpkgs); the latter uses the wheel because its sdist has a
  hyphenated package-data key newer setuptools rejects.
- `urllib3` is relaxed from `>=2.6.3` to bleeding's 2.6.0 (bugfix-only gap).
