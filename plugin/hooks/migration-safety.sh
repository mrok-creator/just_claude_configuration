#!/usr/bin/env bash
set -euo pipefail

# PreToolUse hook: block destructive database commands.
# Enabled only when CC_MIGRATION_GUARD=on (lib/cc-config.sh).
# Exit 0 = allow, Exit 2 = reject (REJECT tool use).
# Matcher: Bash

source "$(dirname "${BASH_SOURCE[0]}")/lib/cc-config.sh"

if [[ "$CC_MIGRATION_GUARD" != "on" ]]; then
  exit 0
fi

PAYLOAD="$(cat 2>/dev/null || true)"
if [[ -z "$PAYLOAD" ]]; then
  exit 0
fi

COMMAND="$(echo "$PAYLOAD" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    inp = data.get('tool_input', {})
    print(inp.get('command', ''))
except Exception:
    print('')
" 2>/dev/null || true)"

if [[ -z "$COMMAND" ]]; then
  exit 0
fi

source "$(dirname "${BASH_SOURCE[0]}")/lib/denial-cap.sh"

main() {
# Preprocess before matching:
#  - strip git-commit message bodies (-m/--message args) so a commit message
#    containing words like "drop table lock fix" is not mistaken for SQL;
#  - collapse all whitespace (incl. newlines) to single spaces so multiline
#    SQL like "DELETE FROM x\nWHERE id=1" is matched as one statement and
#    its WHERE clause is visible to the line-oriented greps below;
#  - lowercase.
CMD_LOWER="$(python3 - "$COMMAND" <<'PY'
import re, shlex, sys

cmd = sys.argv[1]
if re.search(r'\bgit\b[^\n;|&]*\bcommit\b', cmd):
    try:
        toks = shlex.split(cmd)
        out, skip = [], False
        for t in toks:
            if skip:
                skip = False
                continue
            if t in ('-m', '--message', '-am'):
                skip = True
                continue
            if t.startswith('--message='):
                continue
            out.append(t)
        cmd = ' '.join(out)
    except Exception:
        pass  # unbalanced quotes/heredoc — fall back to the raw command
print(re.sub(r'\s+', ' ', cmd).lower())
PY
)"

# --- TypeORM destructive commands ---
if echo "$CMD_LOWER" | grep -qE 'typeorm\s+migration:revert'; then
  cat >&2 <<EOF
[migration-safety] Blocked: typeorm migration:revert is a destructive operation.
  Run manually if needed.
EOF
  exit 2
fi

if echo "$CMD_LOWER" | grep -qE 'typeorm\s+schema:drop'; then
  cat >&2 <<EOF
[migration-safety] Blocked: typeorm schema:drop would destroy the entire database schema.
  If a full local reset is genuinely intended, run this command manually outside the agent session.
EOF
  exit 2
fi

if echo "$CMD_LOWER" | grep -qE 'typeorm\s+query.*drop\s'; then
  cat >&2 <<EOF
[migration-safety] Blocked: typeorm query with DROP is a destructive operation.
  Generate the schema change via the TypeORM migration CLI instead of a raw DROP query.
EOF
  exit 2
fi

if echo "$CMD_LOWER" | grep -qE 'typeorm\s+query.*truncate\s'; then
  cat >&2 <<EOF
[migration-safety] Blocked: typeorm query with TRUNCATE is a destructive operation.
  If clearing table data is genuinely intended, run it manually outside the agent session.
EOF
  exit 2
fi

# --- Raw SQL in shell commands ---
if echo "$CMD_LOWER" | grep -qE 'drop\s+(table|database)\s'; then
  cat >&2 <<EOF
[migration-safety] Blocked: DROP TABLE/DATABASE detected in shell command.
  Use a TypeORM migration for schema changes; run destructive SQL manually outside the agent session if truly intended.
EOF
  exit 2
fi

# TRUNCATE detection — catches both `TRUNCATE TABLE x` and the valid
# Postgres short form `TRUNCATE x` / `TRUNCATE "x" RESTART IDENTITY` (no
# TABLE keyword required).
if echo "$CMD_LOWER" | grep -qE 'truncate\s+(table\s+)?[\\"'"'"'[:space:]]*[a-z_][a-z0-9_.]*'; then
  cat >&2 <<EOF
[migration-safety] Blocked: TRUNCATE detected in shell command.
  If clearing table data is genuinely intended, run it manually outside the agent session.
EOF
  exit 2
fi

# DELETE FROM without WHERE — alias-aware: allows an optional table alias
# (with or without AS) between the table name and WHERE, e.g.
# `delete from users u where u.id=1` is NOT missing a WHERE clause.
if echo "$CMD_LOWER" | grep -qE 'delete\s+from\s' && ! echo "$CMD_LOWER" | grep -qiE 'delete\s+from\s+\S+(\s+(as\s+)?[a-z_][a-z0-9_]*)?\s+where\s'; then
  cat >&2 <<EOF
[migration-safety] Blocked: DELETE FROM without WHERE clause detected.
  This would delete all rows. Add a WHERE clause to scope the delete, or run the full-table delete manually outside the agent session if intended.
EOF
  exit 2
fi

exit 0
}

SIG="$(denial_cap_signature "$PAYLOAD")"
exec 3>&1
if OUT="$(main 2>&1 1>&3)"; then CODE=0; else CODE=$?; fi
exec 3>&-
denial_cap_gate "migration-safety" "$SIG" "security" "$CODE" "$OUT"
