#!/usr/bin/env bash
# Sequential stdio JSON-RPC smoke test for snippet-mcp.
# Uses a coproc so dependent requests wait for their predecessors' responses
# (rmcp dispatches tool calls concurrently, so back-to-back pipelined requests
# race against each other).
set -euo pipefail

cd "$(dirname "$0")/.."

DIR="$(mktemp -d /tmp/snippet-mcp-smoke.XXXXXX)"
trap 'rm -rf "$DIR"; [[ -n "${SERVER_PID:-}" ]] && kill "$SERVER_PID" 2>/dev/null || true' EXIT

# Seed a snippet whose body contains a markdown horizontal rule (regression
# coverage for the previously buggy `\n---\n` splitter).
cat >"$DIR/regression_horizontal_rule.md" <<'EOF'
---
description: Snippet whose body contains a markdown horizontal rule. Used to verify the parse() splitter does not truncate on internal `---`.
args:
  who: { type: string }
tags: [test]
kind: instructions
---
Hello {{raw who}}.

---

This sentence comes AFTER an interior `---` line and must survive the round-trip.
EOF

coproc SERVER (
  exec env SNIPPET_DIR="$DIR" target/release/snippet-mcp --mode stdio 2>/dev/null
)
SERVER_PID=$SERVER_PID

req() {
  printf '%s\n' "$1" >&"${SERVER[1]}"
  IFS= read -r -u "${SERVER[0]}" line
  printf '%s' "$line"
}

notify() {
  printf '%s\n' "$1" >&"${SERVER[1]}"
}

PASS=0
FAIL=0
check() {
  if [[ $2 == *"$3"* ]]; then
    echo "[PASS] $1"
    PASS=$((PASS + 1))
  else
    echo "[FAIL] $1 — got: $(printf '%s' "$2" | head -c 240)"
    FAIL=$((FAIL + 1))
  fi
}

INIT=$(req '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"smoke","version":"0"}}}')
check "initialize" "$INIT" '"snippet-mcp"'

notify '{"jsonrpc":"2.0","method":"notifications/initialized"}'

LIST=$(req '{"jsonrpc":"2.0","id":2,"method":"tools/list"}')
check "tools/list has regression tool" "$LIST" 'regression_horizontal_rule'
check "tools/list has management tools" "$LIST" '"_save"'

CALL=$(req '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"regression_horizontal_rule","arguments":{"who":"world"}}}')
check "interior --- survives parse" "$CALL" 'survive the round-trip'
check "raw substitution" "$CALL" 'Hello world'

SAVE=$(req '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"_save","arguments":{"name":"created_via_save","description":"saved via _save","body":"const x = {{json greeting}};","args":{"greeting":{"type":"string"}}}}}')
check "_save creates new snippet" "$SAVE" 'created_via_save'
check "_save reports no error" "$SAVE" '"isError":false'

USE=$(req '{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"created_via_save","arguments":{"greeting":"hi"}}}')
check "saved snippet callable" "$USE" 'const x = \"hi\";'

BAD=$(req '{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"_update","arguments":{"name":"created_via_save","description":""}}}')
check "empty description rejected" "$BAD" 'description must be a non-empty string'

ESC=$(req '{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"_save","arguments":{"name":"../escape","description":"x","body":"y"}}}')
check "name with .. rejected" "$ESC" 'invalid snippet name'

DEL=$(req '{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"_delete","arguments":{"name":"created_via_save"}}}')
check "_delete reports success" "$DEL" 'deleted created_via_save'

if [[ -f "$DIR/created_via_save.md" ]]; then
  echo "[FAIL] _delete left the file on disk"
  FAIL=$((FAIL + 1))
else
  echo "[PASS] _delete removed the file"
  PASS=$((PASS + 1))
fi

if find "$DIR" -name '.*.tmp.*' | grep -q .; then
  echo "[FAIL] atomic-write left a tmp file"
  FAIL=$((FAIL + 1))
else
  echo "[PASS] no stale tmp files"
  PASS=$((PASS + 1))
fi

echo
echo "$PASS pass · $FAIL fail"
exit $((FAIL == 0 ? 0 : 1))
