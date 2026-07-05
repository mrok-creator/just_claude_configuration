#!/usr/bin/env bash
set -euo pipefail

# Secret/token scanner — SECURITY guard (capped via denial-cap.sh: never
# auto-allows, only escalates the message after N consecutive denials).
#
#  - PostToolUse (matcher: Write|Edit|MultiEdit): scans the written file's
#    content for secrets/tokens. Same patterns and skip rules as before.
#  - PreToolUse (matcher: Bash): fires only when the command is `git commit`.
#    Scans STAGED content (`git diff --cached`) with the same patterns; any
#    other Bash command is allowed through untouched (exit 0, no scan).
#
# Exit 0 = clean/allow, Exit 2 = secret detected (blocked).

source "$(dirname "${BASH_SOURCE[0]}")/lib/denial-cap.sh"

PAYLOAD="$(cat 2>/dev/null || true)"
if [[ -z "$PAYLOAD" ]]; then
  exit 0
fi

TOOL_NAME="$(echo "$PAYLOAD" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    print(data.get('tool_name', ''))
except Exception:
    print('')
" 2>/dev/null || true)"

# --- shared pattern scan, reused for both file content and staged diffs ---
scan_content() {
  # $1 = content to scan, $2 = context label for messages.
  local content="$1" label="$2" warnings=""

  if printf '%s' "$content" | grep -qE 'AKIA[0-9A-Z]{16}' 2>/dev/null; then
    warnings="${warnings}[detect-secrets] WARNING: Possible AWS access key found in ${label}\n"
  fi

  if printf '%s' "$content" | grep -qE -- '-----BEGIN (RSA |EC |DSA )?PRIVATE KEY-----' 2>/dev/null; then
    warnings="${warnings}[detect-secrets] WARNING: Private key block found in ${label}\n"
  fi

  if printf '%s' "$content" | grep -qE 'gh[ps]_[A-Za-z0-9_]{36,}' 2>/dev/null; then
    warnings="${warnings}[detect-secrets] WARNING: Possible GitHub token found in ${label}\n"
  fi

  if printf '%s' "$content" | grep -qE 'eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}' 2>/dev/null; then
    warnings="${warnings}[detect-secrets] WARNING: Possible JWT token found in ${label}\n"
  fi

  if printf '%s' "$content" | grep -qE '(mongodb|postgres|mysql|redis)://[^[:space:]"'"'"']*:[^[:space:]"'"'"']*@' 2>/dev/null; then
    warnings="${warnings}[detect-secrets] WARNING: Possible connection string with credentials found in ${label}\n"
  fi

  if printf '%s' "$content" | grep -iqE '(key|token|secret|password|apikey|api_key|auth)[^A-Za-z0-9]*[=:][^A-Za-z0-9]*['"'"'"][A-Za-z0-9_\-]{32,64}['"'"'"]' 2>/dev/null; then
    warnings="${warnings}[detect-secrets] WARNING: Possible API key/secret found near sensitive keyword in ${label}\n"
  fi

  printf '%s' "$warnings"
}

main() {
  case "$TOOL_NAME" in

    Write|Edit|MultiEdit)
      FILE_PATH="$(echo "$PAYLOAD" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    inp = data.get('tool_input', {})
    print(inp.get('file_path', inp.get('path', '')))
except Exception:
    print('')
" 2>/dev/null || true)"

      if [[ -z "$FILE_PATH" ]]; then
        exit 0
      fi

      # Skip non-text files by extension
      case "$FILE_PATH" in
        *.png|*.jpg|*.jpeg|*.gif|*.ico|*.woff|*.woff2|*.ttf|*.eot|*.zip|*.tar|*.gz|*.lock)
          exit 0
          ;;
      esac

      # Scan only the content introduced by THIS tool call (Write content /
      # Edit new_string / MultiEdit edits[].new_string) — never the whole
      # on-disk file, so a pre-existing fixture token does not permanently
      # block every future edit of that file.
      CONTENT="$(echo "$PAYLOAD" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    inp = data.get('tool_input', {})
    parts = []
    if isinstance(inp.get('content'), str):
        parts.append(inp['content'])
    if isinstance(inp.get('new_string'), str):
        parts.append(inp['new_string'])
    for e in inp.get('edits') or []:
        if isinstance(e, dict) and isinstance(e.get('new_string'), str):
            parts.append(e['new_string'])
    print('\n'.join(parts))
except Exception:
    print('')
" 2>/dev/null || true)"

      if [[ -z "$CONTENT" ]]; then
        exit 0
      fi

      # Skip oversized payloads (>500KB)
      if [[ "${#CONTENT}" -gt 512000 ]]; then
        exit 0
      fi

      WARNINGS="$(scan_content "$CONTENT" "$FILE_PATH (written content)")"

      if [[ -n "$WARNINGS" ]]; then
        echo -e "$WARNINGS" >&2
        echo "[detect-secrets] Review the file and remove any real secrets before committing." >&2
        exit 2
      fi

      exit 0
      ;;

    Bash)
      COMMAND="$(echo "$PAYLOAD" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    print(data.get('tool_input', {}).get('command', ''))
except Exception:
    print('')
" 2>/dev/null || true)"

      if [[ -z "$COMMAND" ]]; then
        exit 0
      fi

      # Only git commit invocations are scanned — every other Bash command
      # passes through untouched (no scan, no cap interaction).
      if ! echo "$COMMAND" | grep -qE '\bgit\s+commit\b'; then
        exit 0
      fi

      STAGED_DIFF="$(git -C "${CLAUDE_PROJECT_DIR:-.}" diff --cached 2>/dev/null || true)"
      if [[ -z "$STAGED_DIFF" ]]; then
        exit 0
      fi

      WARNINGS="$(scan_content "$STAGED_DIFF" "git-staged changes")"

      if [[ -n "$WARNINGS" ]]; then
        echo -e "$WARNINGS" >&2
        echo "[detect-secrets] Blocked commit: remove the secret from the staged content — edit the file and 'git add' again, or 'git restore --staged <file>' to unstage it — before committing." >&2
        exit 2
      fi

      exit 0
      ;;

    *)
      exit 0
      ;;
  esac
}

SIG="$(denial_cap_signature "$PAYLOAD")"
exec 3>&1
if OUT="$(main 2>&1 1>&3)"; then CODE=0; else CODE=$?; fi
exec 3>&-
denial_cap_gate "detect-secrets" "$SIG" "security" "$CODE" "$OUT"