WRITABLE_PATHS=()
CLAUDE_ARGS=()

show_help() {
  cat <<'HELP'
Usage: claude-yolo [--writable <path>]... [--] [claude-args...]

Run Claude Code with --dangerously-skip-permissions inside a bubblewrap sandbox.
The entire filesystem is read-only except for explicitly allowed writable paths.

Options:
  --writable <path>   Add a writable path (can be specified multiple times)
  --help              Show this help

Default writable paths:
  - Current working directory
  - ~/.claude
  - ~/.cache
  - ~/.npm
  - /tmp

All other arguments are passed directly to claude.
HELP
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  --writable)
    shift
    WRITABLE_PATHS+=("$(realpath "$1")")
    shift
    ;;
  --help | -h)
    show_help
    ;;
  --)
    shift
    CLAUDE_ARGS=("$@")
    break
    ;;
  *)
    CLAUDE_ARGS=("$@")
    break
    ;;
  esac
done

DEFAULT_WRITABLE=(
  "$(pwd)"
  "$HOME/.claude"
  "$HOME/.cache"
  "$HOME/.npm"
  "/tmp"
)

BWRAP_ARGS=(
  --ro-bind / /
  --dev-bind /dev /dev
  --proc /proc
  --die-with-parent
)

for path in "${DEFAULT_WRITABLE[@]}"; do
  if [[ -d $path ]]; then
    BWRAP_ARGS+=(--bind "$path" "$path")
  fi
done

for path in "${WRITABLE_PATHS[@]}"; do
  if [[ -d $path ]]; then
    BWRAP_ARGS+=(--bind "$path" "$path")
  else
    echo "Warning: writable path does not exist, skipping: $path" >&2
  fi
done

echo "claude-yolo: bwrap jail"
echo "  writable: ${DEFAULT_WRITABLE[*]} ${WRITABLE_PATHS[*]}"
echo ""

exec bwrap "${BWRAP_ARGS[@]}" -- claude --dangerously-skip-permissions "${CLAUDE_ARGS[@]}"
