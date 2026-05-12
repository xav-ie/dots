- please use gh cli when accessing anything from github
- please use #!/usr/bin/env INTERPRETER when creating scripts. I am on Nix, so this is important.
- When accessing anything from github, you must try to use `gh` cli first to find out more. Resort to fetch tool as last resort

## Executor MCP — search first, ask second

When the user references a system, acronym, or workflow you don't
immediately recognise, do not give up, do not pre-ask which system they
mean. Your default first move:

    await tools.search({ query: "<user's words>" })

Pass the user's phrasing through almost unchanged. Don't expand acronyms,
translate jargon, or substitute the technical name of the system you think
they mean — the search scores by tool description across every connected
source and will surface the match. Look at the top 2–3 results, use
`tools.describe.tool({ path })` on the most plausible one, then call it.

**Don't:**
- `tools.executor.sources.list()` "to see what's available" — kilobytes of
  noise. Only useful when you specifically want source-level metadata.
- `tools.search({ namespace, query })` when you don't already know the
  namespace. Namespace filtering helps only after you've identified the
  source.
- Rewrite the user's words into "the technical name of the system" before
  searching. Their phrasing is the signal; preserve it.
- Reply "I don't know what X is" before searching.

Only ask the user if the unfiltered search returns nothing relevant.

`snippets.*` (saved workflows) deliberately rank high — they are workflows
already validated for this setup, so prefer calling a matching snippet over
reassembling raw tool chains.
