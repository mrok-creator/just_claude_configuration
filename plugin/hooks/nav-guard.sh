#!/usr/bin/env bash
set -euo pipefail

# PreToolUse hook: redirect Bash-shell CODE-SYMBOL searches (grep/rg/ag/ack)
# to Serena/LSP. Plain TEXT search via bash grep/rg is always ALLOWED, never
# redirected — bash grep/rg is the accepted path for anything that isn't a
# code symbol. The TOOL_NAME=="Grep" bypass below is defensive: if a build
# ships a native Grep tool, this guard never processes it.
# Only redirects (to Serena) when the search target is inside this project —
# searches outside the project (other repos, /tmp, system paths) are always
# allowed.
#
# What counts as a "code symbol" is configurable (lib/cc-config.sh):
#   CC_NAV_GUARD_SUFFIXES — class-like name suffixes (e.g. Service|Controller)
#   CC_NAV_GUARD_VERBS    — leading camelCase method verbs (e.g. find|get)
# Disable the whole guard with CC_NAV_GUARD=off if Serena is not installed.
#
# Exit 0 = allow, Exit 2 = reject (deny tool use with redirect message).
# Matcher: Bash, Grep

# Bypass for debugging or contexts without Serena
if [[ "${NAV_GUARD_OFF:-}" == "1" ]]; then
  exit 0
fi

source "$(dirname "${BASH_SOURCE[0]}")/lib/cc-config.sh"

# Config toggle — same effect as NAV_GUARD_OFF, but from cc-config.env.
if [[ "$CC_NAV_GUARD" != "on" ]]; then
  exit 0
fi

PAYLOAD="$(cat 2>/dev/null || true)"
if [[ -z "$PAYLOAD" ]]; then
  exit 0
fi

# Extract tool name first — never process the native Grep tool at all.
TOOL_NAME="$(echo "$PAYLOAD" | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
    print(data.get("tool_name", ""))
except Exception:
    print("")
' 2>/dev/null || echo "")"

if [[ "$TOOL_NAME" == "Grep" ]]; then
  exit 0
fi

if [[ "$TOOL_NAME" != "Bash" ]]; then
  exit 0
fi

source "$(dirname "${BASH_SOURCE[0]}")/lib/denial-cap.sh"

main() {
# Extract pattern + a best-effort out-of-project verdict from the Bash command.
read -r PATTERN OUT_OF_PROJECT < <(echo "$PAYLOAD" | CLAUDE_PROJECT_DIR="${CLAUDE_PROJECT_DIR:-}" python3 -c '
import json, os, re, sys

project_root = os.environ.get("CLAUDE_PROJECT_DIR", "").rstrip("/")

def looks_out_of_project(cmd):
    # Crude scan for any absolute path token that is clearly outside the
    # project (system/temp dirs, or an absolute path not under the project
    # root when the root is known). Relative paths and bare patterns (no
    # path arg — search runs from cwd) are treated as in-project.
    for tok in re.findall(r"(?:^|\s)(/[^\s\"\x27]+)", cmd):
        if re.match(r"^(/tmp|/var|/proc|/sys|/dev|/private/tmp|/etc|/opt|/usr)(/|$)", tok):
            return True
        if project_root and tok.startswith("/") and not tok.startswith(project_root):
            return True
    return False

try:
    data = json.load(sys.stdin)
    inp = data.get("tool_input", {})
    cmd = inp.get("command", "")

    pattern = ""
    segments = re.split(r"[|;&]+", cmd)
    for seg in segments:
        seg = seg.strip()
        match = re.search(r"\b(grep|rg|ag|ack)\s+(?:[^\"\x27]*\s+)?[\"\x27](.*?)[\"\x27]", seg)
        if not match:
            match = re.search(r"\b(grep|rg|ag|ack)\s+(?:-[a-zA-Z]+\s+)*([^\s]+)", seg)
        if match:
            pattern = match.group(2)
            break

    out_of_project = looks_out_of_project(cmd)
    print(pattern if pattern else "NO_PATTERN", out_of_project)
except Exception:
    print("NO_PATTERN", False)
' 2>/dev/null || echo "NO_PATTERN False")

if [[ -z "$PATTERN" || "$PATTERN" == "NO_PATTERN" ]]; then
  exit 0
fi

# ALLOW — search target is outside this project (other repos, /tmp, system paths).
if [[ "$OUT_OF_PROJECT" == "True" ]]; then
  exit 0
fi

# ALLOW — search target is a non-code file/dir (logs, transcripts, planning
# state, memory buffers under CC_STATE_DIR): raw-text search there is
# legitimate; Serena only indexes code. Checked against the full command,
# not the pattern.
if echo "$PAYLOAD" | python3 -c '
import json, os, re, sys
state_dir = os.environ.get("CC_STATE_DIR", ".cc_settings")
data = json.load(sys.stdin)
cmd = data.get("tool_input", {}).get("command", "")
non_code = r"\.jsonl|\.log\b|\.txt\b|\.csv\b|(^|[\s\"\x27=])\.planning/|(^|[\s\"\x27=])" + re.escape(state_dir) + "/"
print(bool(re.search(non_code, cmd)))
' 2>/dev/null | grep -q "True"; then
  exit 0
fi

# --- Classification: code-symbol vs text-search ---

# ALLOW (text search) if pattern is too short (< 3 chars)
if [[ ${#PATTERN} -lt 3 ]]; then
  exit 0
fi

# ALLOW if git grep (history search)
if echo "$PAYLOAD" | python3 -c '
import json, sys
data = json.load(sys.stdin)
cmd = data.get("tool_input", {}).get("command", "")
print("git grep" in cmd)
' 2>/dev/null | grep -q "True"; then
  exit 0
fi

# ALLOW if pattern contains:
# - spaces, quotes
# - regex metacharacters: [](){}|*+?^$\
# - file extensions or globs: *.md, *.json, etc.
# - non-code paths: .claude/, node_modules/, etc.
# - route/env/SQL patterns: contains :, /, =, SCREAMING_SNAKE_CASE
if echo "$PATTERN" | grep -qE '[ "'"'"']|\[|\]|\(|\)|\{|\}|\||\*|\+|\?|\^|\$|\\|\*\.|\.claude|node_modules|::|/|=|TODO|FIXME|ERROR|WARNING'; then
  exit 0
fi

# ALLOW if SCREAMING_SNAKE_CASE (likely env key)
if echo "$PATTERN" | grep -qE '^[A-Z][A-Z0-9_]*$'; then
  exit 0
fi

# ALLOW if pattern contains whitespace — a symbol never has spaces; this is a phrase or text search
if echo "$PATTERN" | grep -q ' '; then
  exit 0
fi

# ALLOW plain lowercase words with no camelCase segments — e.g. "database",
# "component" — these are generic terms, not compound identifiers.
# (Falls through the DENY block below since it requires a compound shape.)

# DENY (redirect to Serena) if pattern looks like code symbol:
# - Compound PascalCase (two humps: BulkImportJob — a single capitalized
#   word like "The", "Partner", "Error" stays a text search: too many
#   false positives on English words), or ends with a configured class-like
#   suffix (CC_NAV_GUARD_SUFFIXES)
# - Or dotted identifier: Namespace.X.Y
# - Or compound camelCase STARTING with a configured code verb
#   (CC_NAV_GUARD_VERBS, e.g. findOneById, prepareQuery) — plain
#   camelCase-shaped raw text that does NOT start with a code verb
#   (e.g. "someRawTextPattern") is left as text search, since word shape
#   alone can't tell a symbol from a phrase.
if echo "$PATTERN" | grep -qE '^[A-Za-z_][A-Za-z0-9_.]*$'; then
  # Check if compound PascalCase or class-like suffix
  if echo "$PATTERN" | grep -qE '^[A-Z][a-z0-9]+[A-Z]' || \
     echo "$PATTERN" | grep -qE "(${CC_NAV_GUARD_SUFFIXES})\$"; then
    cat >&2 <<EOF
[nav-guard] Symbol '$PATTERN' must use Serena (find_symbol / find_referencing_symbols).
  If Serena is not loaded:
    ToolSearch query='select:mcp__serena__find_symbol,mcp__serena__find_referencing_symbols,mcp__serena__get_symbols_overview' max_results:3
  Your NEXT call: mcp__serena__find_symbol with name_path_pattern='$PATTERN' — do not retry grep.
EOF
    exit 2
  fi

  # Check if dotted identifier (Namespace.X.Y style)
  if echo "$PATTERN" | grep -qE '\.' && ! echo "$PATTERN" | grep -qE '\*'; then
    cat >&2 <<EOF
[nav-guard] Symbol '$PATTERN' must use Serena (find_symbol / find_referencing_symbols).
  If Serena is not loaded:
    ToolSearch query='select:mcp__serena__find_symbol,mcp__serena__find_referencing_symbols,mcp__serena__get_symbols_overview' max_results:3
  Your NEXT call: mcp__serena__find_symbol with name_path_pattern='$PATTERN' — do not retry grep.
EOF
    exit 2
  fi

  # Check compound camelCase — only treat as a symbol when the leading
  # segment is a configured code verb (method-name convention).
  if echo "$PATTERN" | grep -qE "^(${CC_NAV_GUARD_VERBS})[A-Z][a-zA-Z0-9]*\$"; then
    cat >&2 <<EOF
[nav-guard] Symbol '$PATTERN' must use Serena (find_symbol / find_referencing_symbols).
  If Serena is not loaded:
    ToolSearch query='select:mcp__serena__find_symbol,mcp__serena__find_referencing_symbols,mcp__serena__get_symbols_overview' max_results:3
  Your NEXT call: mcp__serena__find_symbol with name_path_pattern='$PATTERN' — do not retry grep.
EOF
    exit 2
  fi
fi

# Default: allow
exit 0
}

SIG="$(denial_cap_signature "$PAYLOAD")"
exec 3>&1
if OUT="$(main 2>&1 1>&3)"; then CODE=0; else CODE=$?; fi
exec 3>&-
denial_cap_gate "nav-guard" "$SIG" "native" "$CODE" "$OUT"
