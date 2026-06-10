---
description: Save this Claude Code session to ~/Sessions/ as a resumable note
allowed-tools: Bash, Write
---

Save the **current** Claude Code session to `~/Sessions/` so it can be resumed
later. This is a **checkpoint**, not a one-shot — re-run it periodically as the
session evolves so the saved note reflects the latest state, and update the
existing file in place rather than spawning a new one (see "Update vs. create").

## Gather the facts

Run these to discover the session's identity (do NOT quit the session):

```bash
mkdir -p ~/Sessions
sid="$CLAUDE_CODE_SESSION_ID"
# The transcript filename is always <id>.jsonl, in whichever project folder
# this session was started from — glob by id so it works from anywhere.
f=$(find ~/.claude/projects -name "$sid.jsonl" 2>/dev/null | head -1)
# Launch directory = first recorded cwd in the transcript.
dir=$(grep -o '"cwd":"[^"]*"' "$f" | head -1 | cut -d'"' -f4)
echo "sid=$sid"; echo "dir=$dir"
```

## Choose a name and description

- Pick a short **kebab-case slug** for the filename, based on what this session
  worked on (e.g. `hyprlock-weather-widget-tweaks`).
- Write a **semi-detailed, outline-style** description of this session — sparse
  but specific, NOT one fat paragraph. Use this shape:
  - A 1-2 line lead summarizing the overall goal/area (name the key file(s)).
  - A short bullet list of the concrete things worked on (decisions, fixes,
    files touched).
  - A final `Status:` section saying where things were left off
    - applied? committed? rebuilt? what's the next step(s)?
    - prs in-progress/done? prs todo?

## Update vs. create

Before writing, check whether this session was already saved — grep `~/Sessions`
for the current `$sid`:

```bash
grep -rl "$sid" ~/Sessions/ 2>/dev/null
```

- If a file matches, **update that existing file in place** (keep its slug/name)
  — refresh the description and `Status:` to reflect current progress.
- Otherwise, create a new `~/Sessions/<slug>.md`.

## Write the file

Write `~/Sessions/<slug>.md` in EXACTLY this format — outline description first,
then the resume command in a fenced code block. Substitute the real `$dir` and
`$sid` values (not the literal variable names):

````
<lead summary line(s)>

- <bullet>
- <bullet>

Status:
<where things were left off>

\```
cd <dir>; claude --resume <sid>
\```
````

If `$ARGUMENTS` is non-empty, use it as a hint for the slug and/or emphasis of
the description.

Finally, print the saved file path and its contents back to me.
