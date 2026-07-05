#!/usr/bin/env bash
set -euo pipefail

# PreToolUse hook: redirect Bash file reads and authoring to native tools.
# Native-first file ops (reads + authoring) covered here:
#   cat/head/tail/less reading a project file          → Read tool
#   awk/sed reading a project file (no -i)              → Read tool
#   find/ls/tree discovering source files               → soft nudge (see below)
#   touch creating a project file                       → Write tool
#   echo/printf redirecting (>/>>) into a project file   → Write/Edit tool
#   cp of a file within the repo                         → Read + Write tools
#   nano/vim/vi editing a project file                   → Edit tool
# mv is intentionally left alone — there is no native rename/move tool.
# Writes to the protected write dirs (CC_PROTECTED_WRITE_DIRS), .claude/**
# and .mcp.json are already hard-blocked by config-guard-bash.sh — this hook
# does not double-handle those targets; it only redirects the remaining
# in-project file ops config-guard-bash doesn't cover (touch, editors,
# awk/sed reads) or targets outside that protected set (e.g. root-level
# tracked files, cp destinations elsewhere in the repo).
# Exit 0 = allow, Exit 2 = reject (soft redirect with an actionable message).
#
# Project source roots come from CC_SOURCE_DIRS (lib/cc-config.sh).
#
# find/ls/tree source-tree discovery: when Serena is available it is the
# right tool for CODE discovery (list_dir / find_file for structure,
# get_symbols_overview / find_symbol for symbols), so FIND_CODE emits a SOFT
# nudge toward Serena instead of a silent allow — this is a native-mode
# guard, so after N identical denials the denial-cap auto-allows, letting a
# genuine plain-listing need proceed on retry without a deadlock.
# Matcher: Bash

if [[ "${READ_GUARD_OFF:-}" == "1" ]]; then
  exit 0
fi

PAYLOAD="$(cat 2>/dev/null || true)"
if [[ -z "$PAYLOAD" ]]; then
  exit 0
fi

source "$(dirname "${BASH_SOURCE[0]}")/lib/cc-config.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/denial-cap.sh"

main() {
RESULT="$(echo "$PAYLOAD" | python3 -c '
import json, os, sys, re

Q = chr(39)  # single-quote — avoids breaking the outer shell single-quoted string

# Pipe-separated source-tree roots, e.g. "apps|libs|tools|src|config".
SRC_DIRS = os.environ.get("CC_SOURCE_DIRS", "apps|libs|tools|src|config")
# Dirs hard-blocked for writes by config-guard-bash, e.g. "apps/|libs/".
PROT_DIRS = [d.strip("/") for d in os.environ.get("CC_PROTECTED_WRITE_DIRS", "apps/|libs/").split("|") if d.strip("/")]

def strip_quotes(s):
    return s.strip(Q + chr(34))

def is_source_path(p):
    p = strip_quotes(p).rstrip("/")
    # System and temp paths: allow
    if re.match(r"^(/tmp|/var|/proc|/sys|/dev|/usr/|/etc/|/opt/|/private/tmp|node_modules|[.]git)", p):
        return False
    # .claude dotfile state (e.g. .claude/.cc-mode) is harness state, not
    # source — allow shell reads
    if re.match(r"^[.]claude/[.]", p):
        return False
    # Named source-tree directories (from CC_SOURCE_DIRS)
    if re.match(r"^(" + SRC_DIRS + r")/", p):
        return True
    # Well-known repo root config files
    if re.match(r"^(CLAUDE[.]md|package[.]json|tsconfig|jest[.]config|[.]claude)", p):
        return True
    # Any path with a tracked code extension
    if re.search(r"[.](ts|tsx|js|jsx|json|md|yaml|yml|sh|bash|html|css|scss|sass|sql|graphql|proto|toml|conf|xml)$", p, re.IGNORECASE):
        return True
    return False

def is_config_guard_bash_territory(p):
    # Paths config-guard-bash.sh already hard-blocks for writes/deletes —
    # do not double-handle these here (avoid two hooks nagging on the same target).
    p = strip_quotes(p)
    if re.search(r"(?:^|/)[.]claude/", p):
        return True
    if p == ".mcp.json" or re.search(r"(?:^|/)[.]mcp[.]json$", p):
        return True
    for d in PROT_DIRS:
        if re.match(r"^" + re.escape(d) + r"/", p):
            return True
    return False

def split_segments(cmd):
    # Quote-aware split on | ; & backtick newline — separators inside quoted
    # strings (e.g. a commit message mentioning "cat src/x.ts") do not split,
    # so quoted text cannot false-positive the per-segment command matchers.
    DQ = chr(34)
    segs = []
    buf = []
    q = None
    esc = False
    for c in cmd:
        if esc:
            buf.append(c)
            esc = False
            continue
        if q:
            if c == "\\" and q == DQ:
                buf.append(c)
                esc = True
                continue
            buf.append(c)
            if c == q:
                q = None
            continue
        if c == "\\":
            buf.append(c)
            esc = True
            continue
        if c in (Q, DQ):
            q = c
            buf.append(c)
            continue
        if c in "|;&`\n":
            seg = "".join(buf).strip()
            if seg:
                segs.append(seg)
            buf = []
            continue
        buf.append(c)
    seg = "".join(buf).strip()
    if seg:
        segs.append(seg)
    return segs

try:
    data = json.load(sys.stdin)
    cmd = data.get("tool_input", {}).get("command", "").strip()
    if not cmd:
        print("ALLOW")
        sys.exit(0)

    segments = split_segments(cmd)

    for seg in segments:
        seg = seg.strip()
        if not seg:
            continue

        # ── cat / less / more ──────────────────────────────────────────────
        m = re.match(r"^(cat|less|more)\b\s*(.*)", seg)
        if m:
            rest = m.group(2).strip()
            if "<<" in rest:  # heredoc — allow
                continue
            args = re.sub(r"(?:^|\s)-[a-zA-Z]+", " ", rest).strip()
            for token in args.split():
                token = strip_quotes(token)
                if token in ("-", ""):
                    continue
                if is_source_path(token):
                    print("FILE_READ:" + token)
                    sys.exit(0)
            continue

        # ── head / tail ────────────────────────────────────────────────────
        m = re.match(r"^(head|tail)\b\s*(.*)", seg)
        if m:
            verb = m.group(1)
            rest = m.group(2).strip()
            if verb == "tail" and re.search(r"(?:^|\s)-[a-zA-Z]*f", rest):
                continue  # tail -f: log-following — allow
            args = re.sub(r"(?:^|\s)-[a-zA-Z0-9]+", " ", rest).strip()
            for token in args.split():
                token = strip_quotes(token)
                if not token:
                    continue
                if is_source_path(token):
                    print("FILE_READ:" + token)
                    sys.exit(0)
            continue

        # ── awk / sed used to READ a file (no -i) ────────────────────────────
        m = re.match(r"^(awk|sed)\b\s*(.*)", seg)
        if m:
            rest = m.group(2).strip()
            # In-place edit (-i / --in-place) is out of scope here — leave alone.
            if re.search(r"(?:^|\s)-i\b", rest) or re.search(r"(?:^|\s)--in-place\b", rest):
                continue
            tokens = rest.split()
            if tokens:
                last = strip_quotes(tokens[-1])
                if is_source_path(last):
                    print("FILE_READ:" + last)
                    sys.exit(0)
            continue

        # ── find for code discovery ────────────────────────────────────────
        m = re.match(r"^find\b\s+(\S+)(.*)", seg)
        if m:
            search_root = strip_quotes(m.group(1))
            predicates = m.group(2)
            if re.match(r"^(/tmp|/var|/proc|/sys|/dev|node_modules|[.]git)", search_root):
                continue  # non-source root — allow
            ext_pattern = r"-name\s+[" + chr(34) + Q + r"]?\*[.](ts|tsx|js|jsx|json|md|yaml|yml|sh|html|css|scss|sql|graphql)"
            if re.search(ext_pattern, predicates):
                print("FIND_CODE:" + search_root)
                sys.exit(0)
            # -type f scan of a named source dir
            if re.match(r"^(" + SRC_DIRS + r")/", search_root) and "-type f" in predicates:
                print("FIND_CODE:" + search_root)
                sys.exit(0)
            continue

        # ── ls of source-tree directory ────────────────────────────────────
        m = re.match(r"^ls\b\s*(.*)", seg)
        if m:
            ls_rest = m.group(1).strip()
            target = re.sub(r"(?:^|\s)-[a-zA-Z]+", "", ls_rest).strip()
            target = strip_quotes(target).rstrip("/")
            if target and re.match(r"^(" + SRC_DIRS + r")/", target):
                print("FIND_CODE:" + target)
                sys.exit(0)
            continue

        # ── tree of source-tree directory ───────────────────────────────────
        m = re.match(r"^tree\b\s*(.*)", seg)
        if m:
            tree_rest = m.group(1).strip()
            target = re.sub(r"(?:^|\s)-[a-zA-Z]+", " ", tree_rest).strip()
            target = strip_quotes(target).rstrip("/")
            if re.match(r"^(/tmp|/var|/proc|/sys|/dev|/private/tmp|node_modules|[.]git)", target):
                continue  # non-source root — allow
            if not target or target == "." or re.match(r"^(" + SRC_DIRS + r")/", target):
                print("FIND_CODE:" + (target if target and target != "." else "."))
                sys.exit(0)
            continue

        # ── touch creating/touching a project file ──────────────────────────
        m = re.match(r"^touch\b\s*(.*)", seg)
        if m:
            touch_rest = m.group(1).strip()
            args = re.sub(r"(?:^|\s)-[a-zA-Z]+", " ", touch_rest).strip()
            for token in args.split():
                token = strip_quotes(token)
                if token and is_source_path(token):
                    print("TOUCH_WRITE:" + token)
                    sys.exit(0)
            continue

        # ── echo/printf redirecting (>/>>) into a project file ──────────────
        m = re.match(r"^(echo|printf)\b(.*)", seg)
        if m:
            rest = m.group(2)
            redir = re.search(r"(?:>>|>)\s*([^\s|;&<>]+)", rest)
            if redir:
                target = strip_quotes(redir.group(1))
                if is_source_path(target) and not is_config_guard_bash_territory(target):
                    print("REDIRECT_WRITE:" + target)
                    sys.exit(0)
            continue

        # ── cp of a file within the repo ─────────────────────────────────────
        m = re.match(r"^cp\b\s*(.*)", seg)
        if m:
            cp_rest = m.group(1).strip()
            tokens = [strip_quotes(t) for t in re.sub(r"(?:^|\s)-[a-zA-Z]+", " ", cp_rest).split()]
            if len(tokens) >= 2:
                dest = tokens[-1]
                src = tokens[-2]
                if is_source_path(src) and is_source_path(dest) and not is_config_guard_bash_territory(dest):
                    print("CP_READWRITE:" + src + " -> " + dest)
                    sys.exit(0)
            continue

        # ── interactive editors ──────────────────────────────────────────────
        m = re.match(r"^(nano|vim|vi)\b\s*(.*)", seg)
        if m:
            rest = m.group(2).strip()
            args = re.sub(r"(?:^|\s)-[a-zA-Z0-9+]+", " ", rest).strip()
            for token in args.split():
                token = strip_quotes(token)
                if token and is_source_path(token):
                    print("EDITOR_EDIT:" + token)
                    sys.exit(0)
            continue

    print("ALLOW")

except Exception:
    print("ALLOW")
' 2>/dev/null || echo "ALLOW")"

case "$RESULT" in
  FILE_READ:*)
    FILE="${RESULT#FILE_READ:}"
    cat >&2 <<EOF
[read-guard] Use the Read tool instead of cat/head/tail/awk/sed for '${FILE}'.
  Read shows the file with line numbers and is always preferred over shell file reads.
EOF
    exit 2
    ;;
  FIND_CODE:*)
    DIR="${RESULT#FIND_CODE:}"
    cat >&2 <<EOF
[read-guard] Prefer Serena over bash listing of '${DIR}' for code discovery.
  - Directory / file structure: mcp__serena__list_dir or mcp__serena__find_file
  - Symbols in a file or dir:    mcp__serena__get_symbols_overview / find_symbol
  If Serena is not loaded:
    ToolSearch query='select:mcp__serena__get_symbols_overview,mcp__serena__list_dir,mcp__serena__find_symbol' max_results:3
  Soft nudge: if you truly need a plain non-code listing, re-run to proceed.
EOF
    exit 2
    ;;
  TOUCH_WRITE:*)
    FILE="${RESULT#TOUCH_WRITE:}"
    cat >&2 <<EOF
[read-guard] Use the Write tool instead of touch for '${FILE}'.
  Write creates the file with content directly — touch alone leaves it empty and still needs a follow-up edit.
EOF
    exit 2
    ;;
  REDIRECT_WRITE:*)
    FILE="${RESULT#REDIRECT_WRITE:}"
    cat >&2 <<EOF
[read-guard] Use the Write or Edit tool instead of echo/printf redirection for '${FILE}'.
  Write/Edit author file content directly and are always preferred over shell redirection.
EOF
    exit 2
    ;;
  CP_READWRITE:*)
    PAIR="${RESULT#CP_READWRITE:}"
    cat >&2 <<EOF
[read-guard] Use Read + Write instead of cp for '${PAIR}'.
  Read the source file, then Write its content to the destination — both tools are native and always preferred over shell cp within the repo.
EOF
    exit 2
    ;;
  EDITOR_EDIT:*)
    FILE="${RESULT#EDITOR_EDIT:}"
    cat >&2 <<EOF
[read-guard] Use the Edit tool instead of an interactive editor for '${FILE}'.
  Interactive editors (nano/vim/vi) don't work in this non-interactive shell — use Edit for targeted changes or Read to view the file first.
EOF
    exit 2
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
denial_cap_gate "read-guard" "$SIG" "native" "$CODE" "$OUT"
