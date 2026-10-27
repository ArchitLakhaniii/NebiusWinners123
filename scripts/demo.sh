#!/usr/bin/env bash
# Starts the demo portal on :4318 and launches BrowserSkills pointed at it.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[ -d "$ROOT/build/BrowserSkills.app" ] || "$ROOT/scripts/build.sh"
if ! curl -fsS http://127.0.0.1:4318/health >/dev/null 2>&1; then
  node "$ROOT/demo-portal/server.mjs" > "$ROOT/build/demo-portal.log" 2>&1 &
  echo "demo portal pid $! (log: build/demo-portal.log)"
  sleep 1
fi
open "$ROOT/build/BrowserSkills.app"
