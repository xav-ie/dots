---
description: List what to delete from the current diff
allowed-tools: Bash, Read, Grep, Glob
---

Review for over-engineering only; correctness, security and performance belong to code-reviewer. Scope: `git diff` (staged and unstaged) by default, or a path or ref named in $ARGUMENTS. List findings; apply nothing.

One line per finding, each naming what replaces the code:

`file:L<line>: <tag> <what>. <replacement>.`

- `delete:` dead code, unused flexibility, speculative feature. Replacement: nothing.
- `stdlib:` hand-rolled thing the standard library ships. Name the function.
- `native:` dependency or code doing what the platform already does. Name the feature.
- `yagni:` abstraction with one implementation, config nobody sets, layer with one caller.
- `shrink:` same logic, fewer lines. Show the shorter form.

Hunt: deps the stdlib or platform ships, single-implementation interfaces, factories with one product, wrappers that only delegate, dead flags and config.

Report only cuts you verified (grep for other callers, check the flag is never set). Never flag a requested feature, part of a spec being ported, error handling at trust boundaries, or a single smoke test. End with `net: -<N> lines possible.`, or `Lean already.` if nothing to cut.
