#!/usr/bin/env bash
# End-to-end smoke test: spins up chrome-headless-shell on a random port,
# launches the MCP server pointed at it, drives a session through the full
# tool surface, and tears everything down.
#
# Uses a bash `coproc` for sequential stdio JSON-RPC so dependent requests
# wait for their predecessors' responses (rmcp dispatches concurrently, so
# pipelined requests can race).
#
# Overrides:
#   CHROME_BIN  — path to chrome-headless-shell (default: nix build .#chrome-headless-shell)
#   MCP_BIN     — path to browser-session-mcp   (default: target/release/browser-session-mcp)
set -euo pipefail

cd "$(dirname "$0")/.."

# ---- resolve binaries ----------------------------------------------------

if [[ -z ${CHROME_BIN:-} ]]; then
  echo "+ resolving chrome-headless-shell via nix"
  CHROME_BIN=$(nix build --no-link --print-out-paths \
    "$(git rev-parse --show-toplevel)#chrome-headless-shell")/bin/chrome-headless-shell
fi
if [[ ! -x $CHROME_BIN ]]; then
  echo "CHROME_BIN ($CHROME_BIN) is not executable" >&2
  exit 1
fi

if [[ -z ${MCP_BIN:-} ]]; then
  MCP_BIN="target/release/browser-session-mcp"
fi
if [[ ! -x $MCP_BIN ]]; then
  echo "+ building release binary"
  cargo build --release
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required (used for JSON extraction)" >&2
  exit 1
fi

# ---- tempdir + port ------------------------------------------------------

PORT=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')
TMP=$(mktemp -d /tmp/browser-session-mcp-smoke.XXXXXX)
export STATE_FILE="$TMP/state.json"
export LOGS_DIR="$TMP/logs"
export STATES_DIR="$TMP/states"
export BROWSER_URL="http://127.0.0.1:$PORT"

cleanup() {
  rc=$?
  [[ -n ${SERVER_PID:-} ]] && kill "$SERVER_PID" 2>/dev/null || true
  [[ -n ${CHROME_PID:-} ]] && kill "$CHROME_PID" 2>/dev/null || true
  if ((rc != 0)); then
    echo
    echo "---- chrome log (tail) ----"
    tail -n 40 "$TMP/chrome.log" 2>/dev/null || true
    echo "---- mcp log (tail) ----"
    tail -n 40 "$TMP/mcp.log" 2>/dev/null || true
  fi
  rm -rf "$TMP"
  exit $rc
}
trap cleanup EXIT

# ---- start chrome --------------------------------------------------------

"$CHROME_BIN" \
  --headless \
  --no-sandbox \
  --disable-gpu \
  --disable-dev-shm-usage \
  --remote-debugging-port="$PORT" \
  --user-data-dir="$TMP/chrome-data" \
  >"$TMP/chrome.log" 2>&1 &
CHROME_PID=$!

echo "+ waiting for chrome on :$PORT (pid $CHROME_PID)"
for _ in $(seq 1 40); do
  if curl -fs "http://127.0.0.1:$PORT/json/version" >/dev/null 2>&1; then
    break
  fi
  sleep 0.25
done
if ! curl -fs "http://127.0.0.1:$PORT/json/version" >/dev/null 2>&1; then
  echo "chrome failed to come up" >&2
  exit 1
fi

# ---- start MCP server ----------------------------------------------------

coproc SERVER (exec "$MCP_BIN" 2>"$TMP/mcp.log")
SERVER_PID=$SERVER_PID

req() {
  printf '%s\n' "$1" >&"${SERVER[1]}"
  IFS= read -r -u "${SERVER[0]}" line
  printf '%s' "$line"
}

notify() {
  printf '%s\n' "$1" >&"${SERVER[1]}"
}

# Extract a field from a JSON-RPC response.
# Usage: pluck "$RESP" .result.structuredContent.sessionId
pluck() {
  printf '%s' "$1" | python3 -c "
import json, sys
path = sys.argv[1].split('.')
data = json.load(sys.stdin)
for p in path[1:]:
    data = data[p] if not p.isdigit() else data[int(p)]
print(data)
" "$2"
}

PASS=0
FAIL=0
check() {
  if [[ $2 == *"$3"* ]]; then
    echo "[PASS] $1"
    PASS=$((PASS + 1))
  else
    echo "[FAIL] $1"
    echo "       expected substring: $3"
    echo "       got: $(printf '%s' "$2" | head -c 280)"
    FAIL=$((FAIL + 1))
  fi
}

# ---- protocol handshake --------------------------------------------------

INIT=$(req '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"smoke","version":"0"}}}')
check "initialize" "$INIT" '"browser-session-mcp"'

notify '{"jsonrpc":"2.0","method":"notifications/initialized"}'

LIST=$(req '{"jsonrpc":"2.0","id":2,"method":"tools/list"}')
check "tools/list has open_browser_session" "$LIST" '"open_browser_session"'
check "tools/list has navigate" "$LIST" '"navigate"'
check "tools/list has take_snapshot" "$LIST" '"take_snapshot"'
check "tools/list has save_browser_state" "$LIST" '"save_browser_state"'

# ---- session lifecycle ---------------------------------------------------

OPEN=$(req '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"open_browser_session","arguments":{}}}')
check "open_browser_session returns sessionId" "$OPEN" '"sessionId"'
SID=$(pluck "$OPEN" .result.structuredContent.sessionId)
echo "       session: $SID"

# ---- navigate + snapshot -------------------------------------------------

NAV_REQ=$(python3 -c '
import json,sys
print(json.dumps({"jsonrpc":"2.0","id":4,"method":"tools/call","params":{
  "name":"navigate","arguments":{
    "sessionId": sys.argv[1],
    "url":"data:text/html,<title>hi</title><h1>hello%20smoke</h1>"
  }}}))' "$SID")
NAV=$(req "$NAV_REQ")
check "navigate succeeds" "$NAV" 'Navigated to'

SNAP_REQ=$(python3 -c '
import json,sys
print(json.dumps({"jsonrpc":"2.0","id":5,"method":"tools/call","params":{
  "name":"take_snapshot","arguments":{"sessionId":sys.argv[1]}}}))' "$SID")
SNAP=$(req "$SNAP_REQ")
check "snapshot contains heading text" "$SNAP" 'hello smoke'

# ---- evaluate (both forms) -----------------------------------------------

EVAL_REQ=$(python3 -c '
import json,sys
print(json.dumps({"jsonrpc":"2.0","id":6,"method":"tools/call","params":{
  "name":"evaluate","arguments":{"sessionId":sys.argv[1],"expression":"1 + 1"}}}))' "$SID")
EVAL=$(req "$EVAL_REQ")
check "evaluate bare expression -> 2" "$EVAL" '"result":2'

EVAL2_REQ=$(python3 -c '
import json,sys
print(json.dumps({"jsonrpc":"2.0","id":7,"method":"tools/call","params":{
  "name":"evaluate","arguments":{
    "sessionId":sys.argv[1],
    "expression":"const t = document.title; return t;"
  }}}))' "$SID")
EVAL2=$(req "$EVAL2_REQ")
check "evaluate with explicit return" "$EVAL2" '"hi"'

# Regression: document.returnValue should NOT trigger the "looks-like-return"
# wrap and instead be evaluated as an expression. The page hasn't set that
# property, so the result is undefined -> JSON null. The check is that the
# call succeeds and returns null (not a syntax error from wrapping).
EVAL3_REQ=$(python3 -c '
import json,sys
print(json.dumps({"jsonrpc":"2.0","id":8,"method":"tools/call","params":{
  "name":"evaluate","arguments":{
    "sessionId":sys.argv[1],
    "expression":"document.foo_return_bar === undefined"
  }}}))' "$SID")
EVAL3=$(req "$EVAL3_REQ")
check "evaluate: word-bounded 'return' check" "$EVAL3" '"result":true'

# ---- session listing -----------------------------------------------------

SESS=$(req '{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"list_browser_sessions"}}')
check "list_browser_sessions includes our id" "$SESS" "$SID"

# ---- saved-state round-trip ----------------------------------------------

SAVE_REQ=$(python3 -c '
import json,sys
print(json.dumps({"jsonrpc":"2.0","id":10,"method":"tools/call","params":{
  "name":"save_browser_state","arguments":{
    "sessionId":sys.argv[1],"name":"smoke_test"}}}))' "$SID")
SAVE=$(req "$SAVE_REQ")
check "save_browser_state succeeds" "$SAVE" 'Saved'

STATES=$(req '{"jsonrpc":"2.0","id":11,"method":"tools/call","params":{"name":"list_browser_states"}}')
check "list_browser_states sees smoke_test" "$STATES" 'smoke_test'

LOAD_REQ=$(python3 -c '
import json,sys
print(json.dumps({"jsonrpc":"2.0","id":12,"method":"tools/call","params":{
  "name":"load_browser_state","arguments":{
    "sessionId":sys.argv[1],"name":"smoke_test"}}}))' "$SID")
LOAD=$(req "$LOAD_REQ")
check "load_browser_state succeeds" "$LOAD" 'Loaded'

DEL=$(req '{"jsonrpc":"2.0","id":13,"method":"tools/call","params":{"name":"delete_browser_state","arguments":{"name":"smoke_test"}}}')
check "delete_browser_state succeeds" "$DEL" 'Deleted'

# Disk artifact left over?
if [[ -e "$STATES_DIR/smoke_test.json" ]]; then
  echo "[FAIL] delete_browser_state left smoke_test.json on disk"
  FAIL=$((FAIL + 1))
else
  echo "[PASS] delete_browser_state removed smoke_test.json"
  PASS=$((PASS + 1))
fi

# ---- tabs ----------------------------------------------------------------

NEW_REQ=$(python3 -c '
import json,sys
print(json.dumps({"jsonrpc":"2.0","id":14,"method":"tools/call","params":{
  "name":"new_page","arguments":{
    "sessionId":sys.argv[1],
    "url":"data:text/html,<title>tab2</title>"
  }}}))' "$SID")
NEW=$(req "$NEW_REQ")
check "new_page opens a tab" "$NEW" 'Opened tab'

LIST_PAGES_REQ=$(python3 -c '
import json,sys
print(json.dumps({"jsonrpc":"2.0","id":15,"method":"tools/call","params":{
  "name":"list_pages","arguments":{"sessionId":sys.argv[1]}}}))' "$SID")
LIST_PAGES=$(req "$LIST_PAGES_REQ")
check "list_pages shows both tabs" "$LIST_PAGES" 'tab2'

# ---- close ---------------------------------------------------------------

CLOSE_REQ=$(python3 -c '
import json,sys
print(json.dumps({"jsonrpc":"2.0","id":16,"method":"tools/call","params":{
  "name":"close_browser_session","arguments":{"sessionId":sys.argv[1]}}}))' "$SID")
CLOSE=$(req "$CLOSE_REQ")
check "close_browser_session succeeds" "$CLOSE" 'Closed'

# State file should no longer mention the session.
if [[ -f $STATE_FILE ]] && grep -q "$SID" "$STATE_FILE"; then
  echo "[FAIL] state.json still references closed session"
  FAIL=$((FAIL + 1))
else
  echo "[PASS] state.json cleared closed session"
  PASS=$((PASS + 1))
fi

echo
echo "$PASS pass · $FAIL fail"
exit $((FAIL == 0 ? 0 : 1))
