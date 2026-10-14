#!/usr/bin/env bash
# secrets-diff: see what actually changed in encrypted files.
#
# Decrypts sops files (yaml/json/env/ini) and plain age files (*.age) at two
# git revisions and diffs the plaintext. Defaults to HEAD vs the working
# tree, i.e. exactly "what is my dirty secrets update changing".
#
# Usage:
#   secrets-diff [OLD-REF] [NEW-REF] <file>...
#   OLD-REF defaults to HEAD, NEW-REF to "worktree" (the on-disk copy).
#   A "--" before the files is accepted but never required; arguments that
#   exist as files are always treated as files.
#
#   What the committed secrets update changed:
#     secrets-diff 1bfd2141^ 1bfd2141 -- secrets/main.yaml secrets/executor.json snippets/snippets.age
#
# Decryption uses the sops-nix host identity at /etc/age/keys.txt, so it runs
# under sudo and may prompt for a password. Plaintext is printed to the
# terminal: run somewhere private.
set -euo pipefail

usage() {
  sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

[ $# -eq 0 ] && usage 0
case "$1" in
-h | --help) usage 0 ;;
esac

# Optional leading OLD-REF and NEW-REF, then files (a "--" separator is
# accepted but never required). An argument that exists as a file on disk is
# always a file, so bare filenames can never be mistaken for refs.
OLD=HEAD
NEW=worktree
old_set=0
new_set=0
files=()
while [ $# -gt 0 ]; do
  case "$1" in
  -h | --help) usage 0 ;;
  --)
    shift
    files+=("$@")
    break
    ;;
  esac
  if [ -e "$1" ] || {
    [ "$old_set" -eq 1 ] && [ "$new_set" -eq 1 ]
  }; then
    files+=("$1")
    shift
  elif [ "$old_set" -eq 0 ]; then
    OLD=$1
    old_set=1
    shift
  else
    NEW=$1
    new_set=1
    shift
  fi
done
[ ${#files[@]} -gt 0 ] || {
  echo "no files given" >&2
  usage 1
}

KEY_FILE=${SOPS_AGE_KEY_FILE:-/etc/age/keys.txt}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
chmod 700 "$TMP"

fetch() { # fetch <rev> <file> <out>; rev "worktree" reads the disk copy
  if [ "$1" = "worktree" ]; then
    cat "$2" >"$3"
  else
    git show "$1:$2" >"$3"
  fi
}

decrypt() { # decrypt <encrypted-file> <orig-name> <out>
  case "$2" in
  *.age) sudo age -d -i "$KEY_FILE" "$1" >"$3" ;;
  *) sudo env SOPS_AGE_KEY_FILE="$KEY_FILE" sops -d "$1" >"$3" ;;
  esac
}

for f in "${files[@]}"; do
  echo "== $f  ($OLD -> $NEW)"
  # Keep the original suffix on the scratch copies: sops picks its parser by
  # file extension and does not sniff content on every build.
  ext=${f##*.}
  fetch "$OLD" "$f" "$TMP/o.$ext"
  fetch "$NEW" "$f" "$TMP/n.$ext"
  if ! decrypt "$TMP/o.$ext" "$f" "$TMP/o" 2>"$TMP/o.err"; then
    echo "  old revision failed to decrypt:" >&2
    sed 's/^/  /' "$TMP/o.err" >&2
    continue
  fi
  if ! decrypt "$TMP/n.$ext" "$f" "$TMP/n" 2>"$TMP/n.err"; then
    echo "  new revision failed to decrypt:" >&2
    sed 's/^/  /' "$TMP/n.err" >&2
    continue
  fi
  if diff -u "$TMP/o" "$TMP/n" >"$TMP/d"; then
    echo "  no changes"
  else
    sed 's/^/  /' "$TMP/d"
  fi
done
