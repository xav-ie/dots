---
description: Bump claude-code package sources to latest (or a pinned version)
allowed-tools: Bash
---

Run the claude-code update script to bump the package sources.

If `$ARGUMENTS` is non-empty, treat it as a version string to pin (pass it as
the positional arg). Otherwise bump to the latest stable release.

```bash
claude-code-update --force $ARGUMENTS
```

After it finishes, show me the changelog output and the resulting version
numbers. Do NOT commit — I will review and commit myself.
