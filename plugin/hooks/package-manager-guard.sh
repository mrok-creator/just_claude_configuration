#!/usr/bin/env bash
set -uo pipefail

# PreToolUse guard: exactly one package manager is allowed in this workspace
# (CC_PKG_MANAGER, see lib/cc-config.sh) — the others are assumed not
# installed and will fail. Block any Bash command that invokes a non-allowed
# manager (npm/pnpm/yarn) as a command (not as a mere word inside quoted text).
# Matcher: Bash. Exit 0 = allow, exit 2 = block.

source "$(dirname "${BASH_SOURCE[0]}")/lib/cc-config.sh"

PAYLOAD="$(cat 2>/dev/null || true)"
if [[ -z "$PAYLOAD" ]]; then
  exit 0
fi

# Managers to deny = {npm, pnpm, yarn} minus the allowed one.
CC_PM_DENY=""
for _pm in npm pnpm yarn; do
  if [[ "$_pm" != "$CC_PKG_MANAGER" ]]; then
    CC_PM_DENY="${CC_PM_DENY:+$CC_PM_DENY|}$_pm"
  fi
done
export CC_PM_DENY

if [[ -z "$CC_PM_DENY" ]]; then
  exit 0
fi

RESULT="$(printf '%s' "$PAYLOAD" | python3 -c "
import json, os, re, shlex, sys

denied = set(filter(None, os.environ.get('CC_PM_DENY', '').split('|')))
if not denied:
    print('ALLOW'); raise SystemExit(0)

try:
    cmd = json.load(sys.stdin).get('tool_input', {}).get('command', '')
except Exception:
    print('ALLOW'); raise SystemExit(0)

denied_re = r'\b(' + '|'.join(re.escape(d) for d in sorted(denied)) + r')\b'
if not cmd or not re.search(denied_re, cmd):
    print('ALLOW'); raise SystemExit(0)

# Quote-aware: only flag denied managers in COMMAND position (segment start or
# after env assignments / command separators resolved by shlex tokenization).
for line in cmd.splitlines():
    try:
        toks = shlex.split(line)
    except Exception:
        toks = line.split()
    expect_cmd = True
    for t in toks:
        if t in (';', '&&', '||', '|', '&'):
            expect_cmd = True
            continue
        if expect_cmd:
            if re.match(r'^[A-Za-z_][A-Za-z0-9_]*=', t):
                continue  # env assignment prefix
            base = t.rsplit('/', 1)[-1]
            if base in denied:
                print('BLOCK:' + base); raise SystemExit(0)
            expect_cmd = False
print('ALLOW')
" 2>/dev/null || echo ALLOW)"

if [[ "$RESULT" == BLOCK:* ]]; then
  PM="${RESULT#BLOCK:}"
  echo "[package-manager-guard] '${PM}' is not the package manager of this workspace — it uses '${CC_PKG_MANAGER}' only. Use '${CC_PKG_MANAGER}' instead." >&2
  exit 2
fi
exit 0
