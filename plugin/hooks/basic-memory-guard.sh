#!/usr/bin/env bash
set -uo pipefail

# PreToolUse guard: block raw filesystem access to $CC_CONTEXT_HOME/basic-memory/**
# All basic-memory access must go through mcp__basic-memory__* MCP tools.
# Mirrors nav-guard.sh for Serena — same problem, same pattern.
# Exit 0 = allow, Exit 2 = block.
# Matcher: Read|Write|Edit|Bash

PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
_CC_HOME_FILE="$PROJECT_ROOT/.claude/.cc-context-home"
if [[ -f "$_CC_HOME_FILE" ]]; then
  CC_CONTEXT_HOME="$(sed "s|\$HOME|$HOME|g" "$_CC_HOME_FILE" | tr -d '[:space:]')"
fi
CC_CONTEXT_HOME="${CC_CONTEXT_HOME:-$HOME/Documents/.cc_config}"
export BM_PATH="${CC_CONTEXT_HOME}/basic-memory"

PAYLOAD="$(cat 2>/dev/null || true)"
if [[ -z "$PAYLOAD" || -z "$BM_PATH" ]]; then
  exit 0
fi

echo "$PAYLOAD" | python3 -c '
import json, sys, os

bm_path = os.environ.get("BM_PATH", "")
if not bm_path:
    sys.exit(0)

try:
    data = json.load(sys.stdin)
    tool = data.get("tool_name", "")
    inp  = data.get("tool_input", {})
except Exception:
    sys.exit(0)

def deny():
    msg = (
        "[basic-memory-guard] Direct filesystem access to basic-memory is forbidden.\n"
        "  Use MCP tools instead.\n"
        "  If tools are deferred (not loaded), first load schemas:\n"
        "    ToolSearch(query=\"select:mcp__basic-memory__read_note,mcp__basic-memory__write_note,"
        "mcp__basic-memory__search_notes,mcp__basic-memory__delete_note,"
        "mcp__basic-memory__build_context,mcp__basic-memory__recent_activity\", max_results=6)\n"
        "  Then call the appropriate tool:\n"
        "    read_note (read a note), write_note (create/update), search_notes (find),\n"
        "    delete_note (delete), build_context (gather context), recent_activity (recent changes).\n"
    )
    sys.stderr.write(msg)
    sys.exit(2)

if tool in ("Read", "Write", "Edit"):
    fp = inp.get("file_path", "")
    if fp and fp.startswith(bm_path):
        deny()

elif tool == "Bash":
    cmd = inp.get("command", "")
    if cmd and bm_path in cmd:
        deny()

sys.exit(0)
'

EXIT_CODE=$?
exit $EXIT_CODE
