---
description: Show release notes for pending claude-code updates
allowed-tools: Bash
---

Show me what claude-code releases are pending and what they contain.

```bash
claude-code-update
```

Report as scannable markdown, no preamble. Structure:

1. One line: **`<from>` → `<to>`** · 🔒 **GATED** or ✅ **ELIGIBLE**, and why.
2. One line: **Verdict:** — what I actually have to do, if anything.
3. `---`
4. Three `###` sections, in this order, skipping any that ends up empty:

   - `### ⚙️ Needs a decision from you` — anything I must set, unset, or
     brace for. Table: `| ! | What changed | Your move |`.
   - `### ⚠️ Know about it` — things that were quietly broken or that
     tighten what gets auto-approved; no action, but I'd want to check my
     own config against them. Table: `| ! | What changed |`.
   - `### ✅ Just gets better` — pure fixes I get for free. Table:
     `| ! | Area | What changed |`, area being a lowercase one-word tag
     (`data`, `linux`, `mcp`, `crash`, `security`, `sandbox`).

5. `---`
6. One line on the "Upcoming" section: 📭 and its range, or that it's empty.

The `!` column is 🔴 / 🟠 / 🟡 by how much it would affect me. Sort every
table by that column, most severe first. One table row per item, one clause
each — say what broke and what happens now, no second sentence.

Never group or split by version, and never name a version in a row —
version numbers are noise. Use backticks liberally for version numbers in
the header line, env vars, settings keys, tool names, slash commands, and
file paths; that's where the color comes from.

Only include things that would change my day: security fixes, data loss,
crashes, removed/renamed features, defaults that flip, Linux-specific
behavior, MCP behavior. Drop everything else — no
Windows/VSCode/enterprise/gateway items, no cosmetic or UI polish. If
nothing in the range qualifies, say "nothing notable" and stop.

Aim for roughly 20 rows across all three tables; cut the weakest first.
