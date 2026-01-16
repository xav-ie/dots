# Ralph Module

Autonomous AI agent loop for completing PRDs using Claude Code.

## Skills

### `/prd` - Create a Product Requirements Document

Generates a structured PRD from a feature description. It will:

1. Ask 3-5 clarifying questions with lettered options
2. Generate a detailed PRD with user stories
3. Save to `tasks/prd-[feature-name].md`

### `/ralph` - Convert PRD to prd.json

Converts an existing PRD to the `prd.json` format that Ralph uses for autonomous execution.

## Typical Workflow

1. **Plan your feature** in Claude Code:

   ```
   /prd Add dark mode support to my app
   ```

   Answer the clarifying questions, get a PRD saved to `tasks/prd-dark-mode.md`

2. **Convert to Ralph format**:

   ```
   /ralph
   ```

   This creates `prd.json` with small, iteration-sized user stories

3. **Run Ralph** from your terminal:

   ```bash
   ralph        # runs 10 iterations
   ralph 5      # runs 5 iterations
   ```

   Ralph will autonomously:
   - Create a feature branch
   - Pick the highest priority incomplete story
   - Implement it
   - Run checks (typecheck, lint, test)
   - Commit if passing
   - Mark the story as `passes: true`
   - Repeat until all stories are done or iterations exhausted

4. **Check progress** via `progress.txt` and `prd.json` in your project

## Key Concept

Each Ralph iteration is a fresh Claude instance with no memory. State persists only through:

- Git commits
- `progress.txt` (append-only learnings)
- `prd.json` (story completion status)

## Story Sizing

Stories must be small enough to complete in one iteration (one context window):

**Good (right-sized):**

- Add a database column and migration
- Add a UI component to an existing page
- Update a server action with new logic

**Bad (too big - split these):**

- "Build the entire dashboard"
- "Add authentication"
- "Refactor the API"

## Links

- [Ralph repository](https://github.com/snarktank/ralph)
- [Geoffrey Huntley's Ralph pattern](https://ghuntley.com/ralph/)
