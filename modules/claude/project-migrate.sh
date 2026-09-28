# claude-project-migrate [--apply]: move sessions + memory from Claude's
# path-encoded project folders (~/.claude/projects/-Users-x-...) into the
# $HOME-relative names claude-project-name produces. Dry run by default.
#
# Old names can't be decoded ("-" may have been "/", "." or "-"), so each
# transcript's own recorded "cwd" decides where it goes. Never overwrites:
# existing targets are reported and left in place. Sessions touched in the
# last 10 minutes are skipped (a running Claude appends by path, so moving a
# live transcript would split it) — quit Claude and rerun to catch them.

projects="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects"
apply=0
case "${1:-}" in
--apply) apply=1 ;;
"") ;;
*)
  echo "usage: claude-project-migrate [--apply]" >&2
  exit 2
  ;;
esac

run() { if [ "$apply" = 1 ]; then "$@"; fi; }
declare -A target # old folder -> new name, learned from its transcripts
moved=0 skipped=0 kept=0 conflicts=0

shopt -s nullglob
for d in "$projects"/-*/; do
  d=${d%/}
  old=${d##*/}
  for f in "$d"/*.jsonl; do
    id=$(basename "$f" .jsonl)
    cwd=$(grep -m20 '"cwd":"' "$f" | jq -r 'select(.cwd) | .cwd' 2>/dev/null | head -n1 || true)
    if [ -z "$cwd" ]; then
      echo "skip   $old/$id: no cwd recorded"
      skipped=$((skipped + 1))
      continue
    fi
    if [ ! -d "$cwd" ]; then
      echo "skip   $old/$id: $cwd no longer exists"
      skipped=$((skipped + 1))
      continue
    fi
    new=$(claude-project-name "$cwd")
    if [ -z "$new" ]; then
      kept=$((kept + 1)) # outside $HOME: Claude keeps using the old folder
      continue
    fi
    if [ -n "$(find "$f" -mmin -10)" ]; then
      echo "skip   $old/$id: active in the last 10 min"
      skipped=$((skipped + 1))
      continue
    fi
    target[$old]=$new
    echo "move   $old/$id -> $new/"
    run mkdir -p "$projects/$new"
    # <id>.jsonl, sidecars like <id>.jsonl.wakatime, and the <id>/ subagent dir
    for p in "$d/$id".* "$d/$id"; do
      [ -e "$p" ] || continue
      if [ -e "$projects/$new/${p##*/}" ]; then
        echo "EXISTS $new/${p##*/} (left in $old)"
        conflicts=$((conflicts + 1))
      else
        run mv "$p" "$projects/$new/"
      fi
    done
    moved=$((moved + 1))
  done

  [ -d "$d/memory" ] || continue
  new=${target[$old]:-}
  if [ -z "$new" ]; then
    echo "keep   $old/memory: no movable session says which project it belongs to"
    continue
  fi
  run mkdir -p "$projects/$new/memory"
  for m in "$d"/memory/*; do
    t="$projects/$new/memory/${m##*/}"
    if [ ! -e "$t" ]; then
      echo "move   $old/memory/${m##*/} -> $new/memory/"
      run mv "$m" "$t"
    elif cmp -s "$m" "$t"; then
      echo "same   $old/memory/${m##*/} (identical copy already in $new)"
    else
      echo "MERGE  $old/memory/${m##*/} differs from $new/memory/${m##*/} — merge by hand"
      conflicts=$((conflicts + 1))
    fi
  done
done

if [ "$apply" = 1 ]; then
  # Drop old folders only once they're empty.
  for d in "$projects"/-*/; do
    rmdir "${d%/}/memory" 2>/dev/null || true
    rmdir "${d%/}" 2>/dev/null || true
  done
fi

echo
verb="to move"
if [ "$apply" = 1 ]; then verb=moved; fi
echo "sessions: $moved $verb, $skipped skipped, $kept outside \$HOME (unchanged); $conflicts need attention"
if [ "$apply" = 0 ]; then echo "dry run — rerun with --apply (after quitting Claude) to do it"; fi
