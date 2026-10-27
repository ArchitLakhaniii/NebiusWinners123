#!/usr/bin/env bash
# Checks everything BrowserSkills needs. Never prints secrets.
DIR="${BROWSERSKILLS_HOME:-$HOME/Library/Application Support/BrowserSkills}"
PORT="${BROWSERSKILLS_MCP_PORT:-4317}"
ok() { printf "  \033[32m✓\033[0m %s\n" "$1"; }; bad() { printf "  \033[31m✗\033[0m %s\n" "$1"; }
echo "BrowserSkills doctor"
[ "$(uname -s)" = Darwin ] && ok "macOS $(sw_vers -productVersion) $(uname -m)" || bad "needs macOS"
command -v swift >/dev/null && ok "$(swift --version 2>/dev/null | head -1)" || bad "swift not found (install Xcode)"
command -v node >/dev/null && ok "node $(node --version)" || bad "node not found (demo portal + stdio shim need it)"
curl -fsS http://127.0.0.1:4318/health >/dev/null 2>&1 && ok "demo portal on :4318" || bad "demo portal not running (scripts/demo.sh)"
if [ -f "$DIR/mcp-token" ]; then
  TOKEN="$(cat "$DIR/mcp-token")"
  CODE=$(curl -s -o /dev/null -w '%{http_code}' -X POST "http://127.0.0.1:$PORT/mcp" -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d '{"jsonrpc":"2.0","id":1,"method":"ping"}')
  [ "$CODE" = 200 ] && ok "MCP server answering on :$PORT" || bad "MCP server not answering on :$PORT (is the app running?)"
else bad "no MCP token yet (launch the app once)"; fi
KEY="${NEBIUS_API_KEY:-}"
[ -z "$KEY" ] && [ -f "$DIR/settings.json" ] && KEY="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("apiKey",""))' "$DIR/settings.json" 2>/dev/null)"
if [ -n "$KEY" ]; then
  CODE=$(curl -s -o /dev/null -w '%{http_code}' https://api.tokenfactory.nebius.com/v1/models -H "Authorization: Bearer $KEY")
  [ "$CODE" = 200 ] && ok "Nebius Token Factory key works" || bad "Nebius Token Factory rejected the key (HTTP $CODE)"
else bad "no Nebius API key: compiler runs in fixture mode, assistant disabled"; fi
