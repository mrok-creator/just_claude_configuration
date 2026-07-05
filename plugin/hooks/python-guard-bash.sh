#!/usr/bin/env bash
set -uo pipefail

# PreToolUse guard: block agent Bash tool calls that invoke python or python3.
# Exit 0 = allow, Exit 2 = block (REJECT tool use).
# Matcher: Bash
#
# DENY when a command segment's actual COMMAND TOKEN invokes the python
# interpreter — python, python3, python2, versioned (python3.11) or full-path
# (/usr/bin/python3) forms. Segments are split on newlines, ; && || and pipe |,
# so `grep ... | python3 -c "..."` is detected — the python3 segment is
# evaluated separately from the grep segment.
#
# Detection is quote-aware: it checks the first real (non env-var-assignment)
# shlex token of each segment, not a substring scan of the raw text — so a
# command that merely MENTIONS "python3" inside a quoted string (e.g.
# echo "migrate from python3 to node") is not mistaken for an invocation.
#
# SCOPE: applies ONLY to agent Bash TOOL calls. Event-triggered hooks
# (pre-compact-save.sh, save-on-clear.sh) run as shell scripts, NOT via Bash tool,
# so they are NOT intercepted and remain allowed.

PAYLOAD="$(cat 2>/dev/null || true)"
if [[ -z "$PAYLOAD" ]]; then
  exit 0
fi

source "$(dirname "${BASH_SOURCE[0]}")/lib/denial-cap.sh"

main() {
python3 - "$PAYLOAD" <<'PY'
import json, re, shlex, sys

payload = sys.argv[1]
try:
    data = json.loads(payload)
    command = data.get('tool_input', {}).get('command', '')
except Exception:
    sys.exit(0)

if not command:
    sys.exit(0)

def deny(reason):
    sys.stderr.write(f"[python-guard-bash] {reason}\n")
    sys.exit(2)

def split_segments(cmd):
    """Split a command string into independent execution segments.

    Splits on newlines first, then on ; && || and PIPE | within each line.
    Comment-only lines and blank lines are discarded.
    Result: flat list of segments each containing one simple command.
    """
    segments = []
    for line in cmd.splitlines():
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        # Split on ; && || and pipe |
        parts = re.split(r'\s*(?:;|&&|\|\||\|)\s*', line)
        segments.extend(p.strip() for p in parts if p.strip())
    return segments

def find_command_token(segment):
    """Return the segment's actual command token (quote-aware via shlex),
    skipping leading VAR=value environment-variable-assignment prefixes."""
    try:
        tokens = shlex.split(segment)
    except Exception:
        tokens = segment.split()
    for tok in tokens:
        if re.match(r'^[A-Za-z_][A-Za-z0-9_]*=', tok):
            continue
        return tok
    return None

def is_python_invocation(token):
    """True for python, python3, python2, versioned (python3.11), or a
    full-path invocation (/usr/bin/python3)."""
    if not token:
        return False
    base = token.rsplit('/', 1)[-1]
    return bool(re.match(r'^python[23]?(?:\.\d+)?$', base))

for segment in split_segments(command):
    cmd_token = find_command_token(segment)
    if is_python_invocation(cmd_token):
        deny(
            "Do not use python in Bash. Available alternatives: Serena "
            "(find_symbol / find_referencing_symbols) for code navigation, "
            "Read for file contents, Write/Edit for authoring, and plain "
            "bash grep/awk for text filtering."
        )

sys.exit(0)
PY

_guard=$?
[[ $_guard -eq 2 ]] && exit 2
exit 0
}

SIG="$(denial_cap_signature "$PAYLOAD")"
exec 3>&1
if OUT="$(main 2>&1 1>&3)"; then CODE=0; else CODE=$?; fi
exec 3>&-
denial_cap_gate "python-guard-bash" "$SIG" "security" "$CODE" "$OUT"
