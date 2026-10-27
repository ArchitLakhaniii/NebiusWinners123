#!/usr/bin/env bash
# Licensed under GPL-3.0. See LICENSE.
#
# End-to-end smoke test: builds the app, starts the demo portal, launches build/BrowserSkills.app, waits for
# the MCP token, then drives the server over Streamable HTTP with curl:
#   initialize -> tools/list -> browser_open -> page_describe -> page_act(fill) -> page_act(click) -> page_read
# against http://127.0.0.1:4318/orders and asserts that #order-status is non-empty. Exits non-zero on any failure.
# Never prints the bearer token.
#
# Env: SMOKE_SKIP_BUILD=1 reuses build/BrowserSkills.app, SMOKE_KEEP=1 leaves the portal and app running,
#      BROWSERSKILLS_MCP_PORT overrides the MCP port (default 4317).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/BrowserSkills.app"
BIN="$APP/Contents/MacOS/BrowserSkills"
PORTAL="http://127.0.0.1:4318"
PORT="${BROWSERSKILLS_MCP_PORT:-4317}"
MCP="http://127.0.0.1:$PORT/mcp"
TOKEN_FILE="${BROWSERSKILLS_HOME:-$HOME/Library/Application Support/BrowserSkills}/mcp-token"
ORDER="A-1042"
STARTED_PORTAL=""
STARTED_APP=""

log() { printf '\033[36m[smoke]\033[0m %s\n' "$*"; }
fail() { printf '\033[31m[smoke] FAIL:\033[0m %s\n' "$*" >&2; exit 1; }
cleanup() {
  [ -n "${SMOKE_KEEP:-}" ] && return 0
  if [ -n "$STARTED_APP" ]; then pkill -f "$BIN" 2>/dev/null || true; fi
  if [ -n "$STARTED_PORTAL" ]; then kill "$STARTED_PORTAL" 2>/dev/null || true; fi
}
trap cleanup EXIT

command -v node >/dev/null || fail "node is required (brew install node)"
command -v curl >/dev/null || fail "curl is required"

# JSON helper: json '<expr>' reads JSON on stdin, evaluates the JS expression against it as `j` and prints the result.
json() { node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{let j;try{j=JSON.parse(s)}catch(e){process.stderr.write("invalid JSON: "+s.slice(0,300)+"\n");process.exit(2)}const v=eval(process.argv[1]);process.stdout.write(v===undefined||v===null?"":(typeof v==="string"?v:JSON.stringify(v)))})' "$1"; }

# 1. Build
if [ -z "${SMOKE_SKIP_BUILD:-}" ] || [ ! -x "$BIN" ]; then
  log "building $APP"
  "$ROOT/scripts/build.sh" >/dev/null
fi
[ -x "$BIN" ] || fail "missing $BIN"

# 2. Demo portal
if ! curl -fsS "$PORTAL/health" >/dev/null 2>&1; then
  mkdir -p "$ROOT/build"
  node "$ROOT/demo-portal/server.mjs" >"$ROOT/build/smoke-portal.log" 2>&1 &
  STARTED_PORTAL=$!
  log "started demo portal (pid $STARTED_PORTAL)"
fi
for _ in $(seq 1 50); do curl -fsS "$PORTAL/health" >/dev/null 2>&1 && break; sleep 0.2; done
curl -fsS "$PORTAL/health" >/dev/null || fail "demo portal did not come up on $PORTAL"

# 3. Launch the app (unless an instance already answers on the MCP port)
mcp_code() { curl -s -o /dev/null -w '%{http_code}' --max-time 5 -X POST "$MCP" "$@" -H 'Content-Type: application/json' -d '{"jsonrpc":"2.0","id":0,"method":"ping"}' 2>/dev/null || true; }
if ! [ -f "$TOKEN_FILE" ] || ! [ "$(mcp_code -H "Authorization: Bearer $(cat "$TOKEN_FILE")")" = 200 ]; then
  pkill -f "$BIN" 2>/dev/null || true
  rm -f "$TOKEN_FILE"
  open -g "$APP" || fail "could not launch $APP"
  STARTED_APP=1
  log "launched $APP"
fi

# 4. Wait for the token file and for the server to answer with it
log "waiting for $TOKEN_FILE"
for _ in $(seq 1 300); do [ -s "$TOKEN_FILE" ] && break; sleep 0.2; done
[ -s "$TOKEN_FILE" ] || fail "MCP token did not appear within 60s"
TOKEN="$(cat "$TOKEN_FILE")"
for _ in $(seq 1 100); do [ "$(mcp_code -H "Authorization: Bearer $TOKEN")" = 200 ] && break; sleep 0.2; done
[ "$(mcp_code -H "Authorization: Bearer $TOKEN")" = 200 ] || fail "MCP server on :$PORT did not answer ping with the token"
log "MCP server is up on :$PORT"

# 5. Security checks
[ "$(mcp_code)" = 401 ] || fail "request without bearer token was not rejected with 401"
[ "$(mcp_code -H 'Authorization: Bearer nope')" = 401 ] || fail "request with a wrong bearer token was not rejected with 401"
[ "$(mcp_code -H "Authorization: Bearer $TOKEN" -H 'Origin: https://evil.example')" = 403 ] || fail "non-loopback Origin was not rejected with 403"
[ "$(mcp_code -H "Authorization: Bearer $TOKEN" -H 'Origin: http://127.0.0.1')" = 200 ] || fail "loopback Origin was rejected"
log "auth and Origin checks pass"

# rpc <id> <method> <params-json>: POSTs a JSON-RPC request, asserts HTTP 200 and no JSON-RPC error, prints the result.
rpc() {
  local id="$1" method="$2" params="${3:-{\}}" body status
  body="$(curl -sS --max-time 60 -w '\n%{http_code}' -X POST "$MCP" -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
          -H 'Accept: application/json, text/event-stream' -H 'Origin: http://127.0.0.1' \
          -d "{\"jsonrpc\":\"2.0\",\"id\":$id,\"method\":\"$method\",\"params\":$params}")"
  status="${body##*$'\n'}"; body="${body%$'\n'*}"
  [ "$status" = 200 ] || fail "$method returned HTTP $status: ${body:0:300}"
  local err; err="$(printf '%s' "$body" | json 'j.error ? JSON.stringify(j.error) : ""')"
  [ -z "$err" ] || fail "$method returned a JSON-RPC error: $err"
  [ "$(printf '%s' "$body" | json 'String(j.id)')" = "$id" ] || fail "$method response id mismatch: ${body:0:300}"
  printf '%s' "$body" | json 'JSON.stringify(j.result)'
}
# tool <id> <name> <arguments-json>: tools/call that must not return isError; prints the result.
tool() {
  local result; result="$(rpc "$1" tools/call "{\"name\":\"$2\",\"arguments\":$3}")"
  [ "$(printf '%s' "$result" | json 'j.isError === true ? "1" : ""')" = "" ] || fail "$2 returned isError: $(printf '%s' "$result" | json 'j.content.map(c=>c.text).join(" ")')"
  printf '%s' "$result"
}

# 6. initialize + notifications/initialized
INIT="$(rpc 1 initialize '{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"smoke","version":"1"}}')"
[ -n "$(printf '%s' "$INIT" | json 'j.protocolVersion')" ] || fail "initialize returned no protocolVersion: $INIT"
[ -n "$(printf '%s' "$INIT" | json 'j.capabilities && j.capabilities.tools ? "1" : ""')" ] || fail "initialize did not advertise tools: $INIT"
log "initialize ok: $(printf '%s' "$INIT" | json 'j.serverInfo.name + " " + j.serverInfo.version + ", protocol " + j.protocolVersion')"
CODE="$(curl -s -o /dev/null -w '%{http_code}' -X POST "$MCP" -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d '{"jsonrpc":"2.0","method":"notifications/initialized"}')"
[ "$CODE" = 202 ] || fail "notification returned HTTP $CODE instead of 202"

# 7. tools/list
TOOLS="$(rpc 2 tools/list '{}' | json 'j.tools.map(t=>t.name).join(" ")')"
for t in browser_open page_describe page_act page_read; do
  case " $TOOLS " in *" $t "*) ;; *) fail "tools/list is missing $t (got: $TOOLS)";; esac
done
log "tools/list ok: $TOOLS"

# 8. browser_open -> page_describe -> page_act(fill) -> page_act(click) -> page_read
OPEN="$(tool 3 browser_open "{\"url\":\"$PORTAL/orders\"}")"
log "browser_open: $(printf '%s' "$OPEN" | json 'j.content[0].text')"

DESC="$(tool 4 page_describe '{}')"
FORM="$(printf '%s' "$DESC" | json 'JSON.stringify((j.structuredContent.forms||[]).find(f=>f.fields.some(x=>x.name==="order"))||null)')"
[ -n "$FORM" ] && [ "$FORM" != null ] || fail "page_describe found no form with an order field: $(printf '%s' "$DESC" | json 'j.content[0].text')"
FIELD_REF="$(printf '%s' "$FORM" | json 'j.fields.find(x=>x.name==="order").ref')"
SUBMIT_REF="$(printf '%s' "$FORM" | json 'j.submit && j.submit.ref')"
[ -n "$FIELD_REF" ] && [ -n "$SUBMIT_REF" ] || fail "page_describe returned no refs for the order form: $FORM"
log "page_describe: field ref $FIELD_REF, submit ref $SUBMIT_REF"

FILL="$(tool 5 page_act "{\"ref\":\"$FIELD_REF\",\"action\":\"fill\",\"value\":\"$ORDER\"}")"
log "page_act(fill): $(printf '%s' "$FILL" | json 'j.content[0].text')"
CLICK="$(tool 6 page_act "{\"ref\":\"$SUBMIT_REF\",\"action\":\"click\"}")"
log "page_act(click): $(printf '%s' "$CLICK" | json 'j.content[0].text')"

READ="$(tool 7 page_read '{"selector":"#order-status"}')"
STATUS="$(printf '%s' "$READ" | json 'j.structuredContent && typeof j.structuredContent.value === "string" ? j.structuredContent.value.trim() : ""')"
[ -n "$STATUS" ] || fail "#order-status is empty: $READ"
log "page_read #order-status = \"$STATUS\""

URL_NOW="$(tool 8 page_read '{"selector":"#order-id"}' | json 'j.structuredContent.value')"
[ "$URL_NOW" = "$ORDER" ] || fail "expected #order-id to be $ORDER, got \"$URL_NOW\""

log "PASS: order $ORDER status is \"$STATUS\""
