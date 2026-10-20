---
description: Whole-repo cleanup report: what to delete, plus TODO/FIXME debt
allowed-tools: Bash, Read, Grep, Glob
---

Two sections, both read only; apply nothing and write a file only if asked.

## Cuts

Read `~/.claude/commands/cleanup.md` and apply its review (tags, format, guards) to the whole tracked tree instead of a diff, ranked biggest cut first. Hunt deps the stdlib or platform ships, single-implementation interfaces, factories with one product, wrappers that only delegate, dead flags and config. End with `net: -<N> lines, -<M> deps possible.`, or `Lean already.`

## Debt

```bash
git grep -nIE '\b(TODO|FIXME|HACK|XXX)\b|ponytail:'
```

`ponytail:` catches legacy shortcut notes from a retired plugin; treat them like TODOs. One row per marker, grouped by file: `<file>:<line>: <what is deferred>. trigger: <when to revisit, or none>.` Tag rows with no actionable trigger `vague`. Past about 30, summarize per file and list only FIXME, HACK and the oldest TODOs (`git blame -L<line>,<line> --porcelain` for dates). End with `<N> markers, <M> vague.`, or `No debt.`
