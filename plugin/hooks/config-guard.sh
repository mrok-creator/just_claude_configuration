#!/usr/bin/env bash
set -euo pipefail

# PreToolUse guard: protect SENSITIVE config files from silent agent edits.
# Exit 0 = allow (auto-approve), JSON output = ask user (prompt Yes/No).
# Matcher: Write|Edit|MultiEdit|NotebookEdit
#
# ASK only for files whose modification changes what code gets executed or
# what the agent is permitted to do:
#   - .claude/settings*.json   (hook wiring, permissions)
#   - .claude/hooks/**         (guard scripts themselves)
#   - .claude/setup/**         (executable scripts invoked by workflows)
#   - .mcp.json                (MCP server definitions = external processes)
# Everything else under .claude/ (docs/, rules/, skills/, agents/, commands/,
# workflow/, output-styles/) is ALLOWED — enables autonomous doc/rule upkeep.
# No AI_FLOW_ROLE bypass: role-fenced sessions never legitimately write the
# sensitive set, so the ask must hold there too.

PAYLOAD="$(cat 2>/dev/null || true)"
if [[ -z "$PAYLOAD" ]]; then
  exit 0
fi

read -r TOOL_NAME FILE_PATH < <(printf '%s' "$PAYLOAD" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    tool = data.get('tool_name', '')
    inp = data.get('tool_input', {})
    path = inp.get('file_path', inp.get('path', inp.get('old_file_path', inp.get('new_file_path', ''))))
    print(tool, path)
except Exception:
    print(' ')
" 2>/dev/null || echo " ")

case "$TOOL_NAME" in
  Write|Edit|MultiEdit|NotebookEdit) ;;
  *) exit 0 ;;
esac

if [[ -z "$FILE_PATH" ]]; then
  exit 0
fi

# Normalize to a project-relative view for matching (absolute paths keep
# their tail after /.claude/ or /.mcp.json).
SENSITIVE=0
case "$FILE_PATH" in
  .claude/settings*.json|*/.claude/settings*.json) SENSITIVE=1 ;;
  .claude/hooks/*|*/.claude/hooks/*)               SENSITIVE=1 ;;
  .claude/setup/*|*/.claude/setup/*)               SENSITIVE=1 ;;
  .mcp.json|*/.mcp.json)                           SENSITIVE=1 ;;
esac

if [[ "$SENSITIVE" -ne 1 ]]; then
  exit 0
fi

# Sensitive config edit detected — prompt user for approval
echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"ask\",\"permissionDecisionReason\":\"Sensitive config (settings/hooks/setup/.mcp.json) — approve to modify: ${FILE_PATH}\"}}"
exit 0
