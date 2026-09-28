# claude-project-name [dir]: print a machine-independent Claude project folder
# name for dir (default: $PWD), or nothing if Claude's default should apply.
#
# Claude Code files transcripts + memory under ~/.claude/projects/<name>, where
# <name> defaults to the absolute path encoded ("/home/x/Work/foo" ->
# "-home-x-Work-foo"), so the same repo gets different folders on macOS
# (/Users/x) and Linux (/home/x). The wrapper exports our name as
# CLAUDE_CODE_PROJECT_DIR_NAME instead: the repo's MAIN checkout relative to
# $HOME ("Work-foo"), so every worktree of a repo shares one /resume list and
# one memory, identically on both machines.
#
# Claude silently ignores names that aren't [A-Za-z0-9_-]{1,64}; for those, and
# for anything outside $HOME, print nothing and let Claude use its default.
# ponytail: "a/b-c" and "a-b/c" encode alike — same ambiguity as Claude's own
# scheme; switch the separator if two real repos ever collide.

dir=$(cd "${1:-$PWD}" 2>/dev/null && pwd -P) || exit 0

# --git-common-dir is the main repo's .git even from inside a linked worktree.
if common=$(git -C "$dir" rev-parse --path-format=absolute --git-common-dir 2>/dev/null); then
  case $common in
  */.git) root=${common%/.git} ;;
  # submodule (common dir is <super>/.git/modules/x) | bare repo (/x/foo.git)
  *) root=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) || root=${common%.git} ;;
  esac
else
  root=$dir
fi

home=$(cd "$HOME" && pwd -P)
case "$root" in
"$home") name=home ;;
"$home"/*)
  rel=${root#"$home"/}
  name=${rel//[^A-Za-z0-9_-]/-}
  name=${name/#-/_} # ~/.dir repos: a leading "-" would look like Claude's own path-encoded names
  ;;
*) exit 0 ;;
esac

case ${name,,} in con | prn | aux | nul | com[0-9] | lpt[0-9]) exit 0 ;; esac
if [ ${#name} -le 64 ]; then
  printf '%s\n' "$name"
fi
