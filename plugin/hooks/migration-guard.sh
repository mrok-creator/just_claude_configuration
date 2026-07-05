#!/usr/bin/env bash
set -uo pipefail

# PreToolUse guard: migration files are CLI-generated artifacts (e.g. via the
# TypeORM migration CLI), never created manually and never altered as part of
# another task. Any Write/Edit targeting a migrations/ directory under apps/
# → ASK the user for approval.
# Enabled only when CC_MIGRATION_GUARD=on (lib/cc-config.sh).
# Matcher: Write|Edit|MultiEdit|NotebookEdit
#
# Exit 0 + no output = allow; exit 0 + JSON "ask" = prompt user.

source "$(dirname "${BASH_SOURCE[0]}")/lib/cc-config.sh"

if [[ "$CC_MIGRATION_GUARD" != "on" ]]; then
  exit 0
fi

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
    path = inp.get('file_path', inp.get('path', ''))
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

if [[ "$FILE_PATH" == *"/migrations/"* && ( "$FILE_PATH" == *"apps/"* || "$FILE_PATH" == apps/* ) ]]; then
  echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"ask\",\"permissionDecisionReason\":\"Migration file — migrations are CLI-generated, never authored or altered manually. Approve ONLY if the user explicitly asked to modify this migration: ${FILE_PATH}\"}}"
fi
exit 0
