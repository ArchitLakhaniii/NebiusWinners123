#!/usr/bin/env bash
# Deletes skills, runs, traces and evidence. Keeps settings.json and the MCP token.
set -euo pipefail
DIR="${BROWSERSKILLS_HOME:-$HOME/Library/Application Support/BrowserSkills}"
pkill -x BrowserSkills 2>/dev/null || true
rm -f "$DIR"/browserskills.sqlite* && rm -rf "$DIR/artifacts"
echo "Reset $DIR"
