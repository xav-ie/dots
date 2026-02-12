OVERLAY_DIR="${CLAUDE_OVERLAY_DIR:-$HOME/.claude-overlay}"
CLAUDE_ARGS=()
clean=false

show_help() {
  cat <<'HELP'
Usage: claude-overlay [options] [--] [claude-args...]

Run Claude Code with --dangerously-skip-permissions inside an overlayfs.
The real filesystem is never modified. All writes are captured in an overlay.
After Claude exits, review and selectively apply changes.

Options:
  --overlay-dir <path>   Overlay state directory (default: ~/.claude-overlay)
  --clean                Remove previous overlay state before starting
  --help                 Show this help

Environment:
  CLAUDE_OVERLAY_DIR     Same as --overlay-dir

All other arguments are passed directly to claude.
HELP
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  --overlay-dir)
    shift
    OVERLAY_DIR="$1"
    shift
    ;;
  --clean)
    clean=true
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

UPPER="$OVERLAY_DIR/upper"
WORK="$OVERLAY_DIR/work"
MERGED="$OVERLAY_DIR/merged"

if $clean; then
  echo "Cleaning previous overlay state..."
  rm -rf "$OVERLAY_DIR"
fi

mkdir -p "$UPPER" "$WORK" "$MERGED"

echo "claude-overlay: overlayfs sandbox"
echo "  overlay dir: $OVERLAY_DIR"
echo "  writes go to: $UPPER"
echo "  real filesystem: untouched"
echo ""

# Serialize claude args for passing through unshare -> chroot
CLAUDE_ARGS_STR=""
if [[ ${#CLAUDE_ARGS[@]} -gt 0 ]]; then
  printf -v CLAUDE_ARGS_STR '%q ' "${CLAUDE_ARGS[@]}"
fi

SAVED_CWD="$(pwd)"

# Run inside new mount + user namespace with overlayfs
# --map-root-user: maps current uid to root inside namespace (needed for mount)
# Real filesystem is lowerdir (read-only), all writes land in upperdir
unshare --mount --map-root-user bash <<SANDBOX || true
mount -t overlay overlay \
  -o "lowerdir=/,upperdir=$UPPER,workdir=$WORK" \
  "$MERGED"

# Mount virtual filesystems so Claude/Node.js work properly
mount -t proc proc "$MERGED/proc"
mount --rbind /dev "$MERGED/dev"
mount --rbind /sys "$MERGED/sys"
mount --rbind /run "$MERGED/run" 2>/dev/null || true

# Enter the overlay and run Claude with the original user's environment
chroot "$MERGED" /usr/bin/env \
  HOME="$HOME" \
  USER="$USER" \
  TERM="$TERM" \
  PATH="$PATH" \
  SHELL="$SHELL" \
  XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-}" \
  XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-}" \
  -C "$SAVED_CWD" \
  claude --dangerously-skip-permissions $CLAUDE_ARGS_STR
SANDBOX

echo ""
echo "=== Claude session ended ==="
echo ""

# Ignore overlayfs metadata directories in counts
new_files=$(find "$UPPER" -type f 2>/dev/null | wc -l)
whiteouts=$(find "$UPPER" -type c 2>/dev/null | wc -l)
total=$((new_files + whiteouts))

if [[ $total -eq 0 ]]; then
  echo "No filesystem changes were made."
  rm -rf "$OVERLAY_DIR"
  exit 0
fi

echo "Changes captured:"
echo "  New/Modified: $new_files files"
echo "  Deleted:      $whiteouts files"
echo ""

if [[ $new_files -gt 0 ]]; then
  echo "New/Modified:"
  find "$UPPER" -type f -printf "  /%P\n" 2>/dev/null | head -50
  if [[ $new_files -gt 50 ]]; then
    echo "  ... and $((new_files - 50)) more"
  fi
fi

if [[ $whiteouts -gt 0 ]]; then
  echo ""
  echo "Deleted:"
  find "$UPPER" -type c -printf "  /%P\n" 2>/dev/null | head -50
fi

echo ""

while true; do
  echo "What would you like to do?"
  echo "  [a] Apply all changes to real filesystem"
  echo "  [d] Discard all changes"
  echo "  [i] Inspect overlay (open shell in upper dir)"
  echo "  [k] Keep overlay for later"
  read -rp "> " choice

  case "$choice" in
  a | A)
    echo "Applying changes..."
    # Copy new/modified files, skip device files (whiteouts)
    rsync -a --no-devices "$UPPER/" /
    # Handle deletions (whiteout = char device 0/0)
    find "$UPPER" -type c -printf '%P\n' 2>/dev/null | while IFS= read -r f; do
      if rm -f "/$f" 2>/dev/null; then
        echo "  deleted: /$f"
      else
        echo "  skip (permission denied): /$f" >&2
      fi
    done
    echo "Done."
    rm -rf "$OVERLAY_DIR"
    break
    ;;
  d | D)
    echo "Discarded all changes."
    rm -rf "$OVERLAY_DIR"
    break
    ;;
  i | I)
    echo "Opening shell in: $UPPER"
    echo "  Diff a file: diff /path/to/file $UPPER/path/to/file"
    echo "  Exit shell to return to this prompt."
    (cd "$UPPER" && bash) || true
    ;;
  k | K)
    echo "Overlay preserved at: $OVERLAY_DIR"
    echo "  Inspect:     ls $UPPER"
    echo "  Diff a file: diff /path/to/file $UPPER/path/to/file"
    echo "  Start fresh: claude-overlay --clean"
    break
    ;;
  *)
    echo "Invalid choice. Enter a, d, i, or k."
    ;;
  esac
done
