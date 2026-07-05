#!/usr/bin/env bash
set -uo pipefail

# PreToolUse guard: block Bash commands that WRITE TO or DELETE project source.
# Protected paths: .claude/**, .mcp.json, and the dirs listed in
# CC_PROTECTED_WRITE_DIRS (lib/cc-config.sh; default "apps/|libs/").
# Exit 0 = allow, Exit 2 = block (REJECT tool use).
# Matcher: Bash
#
# DENY only when a protected path is the actual WRITE TARGET:
#   - redirect target:        echo x > <protected>/file.ts
#   - tee destination:        tee <protected>/file.ts
#   - cp/mv/install/ln DEST:  cp src <protected>/dest   (last non-flag arg)
#   - sed -i target:          sed -i 's/x/y/' <protected>/file.ts
#   - truncate/dd of= target: truncate -s 0 <protected>/file.ts
#
# Redirect detection is quote-aware (shlex tokens): a `>` appearing inside a
# quoted string (e.g. echo "see docs: output > notes.txt") is text, not
# a real shell redirect, and is not blocked.
#
# mv SOURCE is also checked: moving a delete-protected file (.claude/**,
# .mcp.json) OUT to an unprotected destination is equivalent to deleting it
# from there, so it is blocked same as `rm` would be. cp source is NOT
# checked — cp leaves the source intact, so reading from a protected path
# via cp is safe (see ALLOW list below).
#
# rm / git rm is a special case: deletion has no native tool equivalent
# (Write/Edit only author content), so it is DENIED only for .claude/**
# and .mcp.json. rm/git rm under the protected write dirs is
# ALLOWED — blocking it just forces evasive workarounds (inline python,
# find -delete) instead of preventing anything.
#
# ALLOW read/execute from protected paths:
#   - bash .claude/hooks/x.sh
#   - cat <protected>/file.ts
#   - cp <protected>/src /dest   (source only, destination is safe)
#   - rm <protected>/file.ts     (deletion allowed under the write dirs)
#   - rm /tmp/x                  (not a protected path)
#
# NO AI_FLOW_ROLE bypass: native-first (Write/Edit) applies to role-fenced
# subagents too, and a bash-redirection escape would also evade the
# guard-test-author/guard-executor fences (they only match Write/Edit).
#
# Each command is split into independent SEGMENTS on newlines and ; && ||
# so that a .claude/ path in one segment (e.g. as a bash source) does not
# cause a false-positive in a different segment (e.g. rm /tmp/file on the
# next line).

source "$(dirname "${BASH_SOURCE[0]}")/lib/cc-config.sh"

PAYLOAD="$(cat 2>/dev/null || true)"
if [[ -z "$PAYLOAD" ]]; then
  exit 0
fi

source "$(dirname "${BASH_SOURCE[0]}")/lib/denial-cap.sh"

main() {
python3 - "$PAYLOAD" "${CLAUDE_PROJECT_DIR:-}" <<'PY'
import json, os, re, shlex, sys

payload = sys.argv[1]
project_dir = sys.argv[2].rstrip('/') if len(sys.argv) > 2 else ''
try:
    data = json.loads(payload)
    command = data.get('tool_input', {}).get('command', '')
except Exception:
    sys.exit(0)

if not command:
    sys.exit(0)

# Protected write dirs from configuration, e.g. ["apps", "libs"].
PROTECTED_DIRS = [d.strip('/') for d in os.environ.get('CC_PROTECTED_WRITE_DIRS', 'apps/|libs/').split('|') if d.strip('/')]
PROTECTED_LABEL = ', '.join([d + '/' for d in PROTECTED_DIRS] + ['.claude/', '.mcp.json'])

def is_source_dir(path, dirname):
    """True if dirname/ is a top-level project source dir in path.

    Matches:
      - relative paths starting with dirname/  (e.g. apps/foo/bar.ts)
      - absolute paths under project_dir/dirname/
    Does NOT match dirname/ that appears inside dist/, coverage/, node_modules/, build caches.
    """
    # Relative path anchored at start
    if re.search(r'^' + re.escape(dirname) + r'/', path):
        return True
    # Absolute path: project_dir/dirname/
    if project_dir and path.startswith(project_dir + '/' + dirname + '/'):
        return True
    return False

def is_project_claude(path):
    """PROJECT-root .claude only — never the user-global ~/.claude tree.

    Matches relative ".claude/..." (optionally "./"-prefixed) and absolute
    paths under <project_dir>/.claude/. A bare "/.claude/" substring match
    would wrongly protect ~/.claude/** (user config, not project source).
    """
    if re.match(r'^(\./)?\.claude(/|$)', path):
        return True
    if project_dir and (path == project_dir + '/.claude' or path.startswith(project_dir + '/.claude/')):
        return True
    return False

def is_protected(path):
    """True if path targets project source (.claude/**, .mcp.json, protected write dirs)."""
    if not path:
        return False
    if is_project_claude(path):
        return True
    if path == '.mcp.json' or re.search(r'(?:^|/)\.mcp\.json$', path):
        return True
    for d in PROTECTED_DIRS:
        if is_source_dir(path, d):
            return True
    return False

def is_delete_protected(path):
    """True if path is protected against DELETION specifically.

    Unlike is_protected(), this excludes the protected write dirs: deletion
    has no native tool equivalent (Write/Edit only author content), so
    rm/git rm there is allowed and must be redirected nowhere. Only
    .claude/** and .mcp.json remain delete-protected.
    """
    if not path:
        return False
    if is_project_claude(path):
        return True
    if path == '.mcp.json' or re.search(r'(?:^|/)\.mcp\.json$', path):
        return True
    return False

def deny(reason):
    sys.stderr.write(f"[config-guard-bash] {reason}\n")
    sys.exit(2)

def split_segments(cmd):
    """Split a multi-line command string into independent execution segments.

    Quote-aware: splits on newline, ;, &&, || only OUTSIDE quoted strings, so
    a commit message like `git commit -m "fix; rm .claude/x"` stays one
    segment and its quoted body cannot false-positive a later rule.
    Comment-only segments and blank segments are discarded.
    Pipe | is NOT a split point because it passes output, not control flow,
    and tee/redirect within a pipe still matters.
    """
    segments = []
    buf = []
    q = None
    esc = False
    i = 0
    n = len(cmd)

    def flush():
        seg = ''.join(buf).strip()
        if seg and not seg.startswith('#'):
            segments.append(seg)
        buf.clear()

    while i < n:
        c = cmd[i]
        if esc:
            buf.append(c); esc = False; i += 1; continue
        if q:
            if c == '\\' and q == '"':
                buf.append(c); esc = True; i += 1; continue
            buf.append(c)
            if c == q:
                q = None
            i += 1; continue
        if c == '\\':
            buf.append(c); esc = True; i += 1; continue
        if c in ('"', "'"):
            q = c; buf.append(c); i += 1; continue
        if c == '\n' or c == ';':
            flush(); i += 1; continue
        if cmd[i:i + 2] in ('&&', '||'):
            flush(); i += 2; continue
        buf.append(c); i += 1
    flush()
    return segments

def find_redirect_targets(segment):
    """Return real shell-redirect destinations, ignoring `>`/`>>` inside quotes.

    Uses shlex tokens (which already resolve quoting) rather than a raw regex
    scan, so a `>` embedded in a quoted string (e.g. an echo message that
    merely mentions a path) is not mistaken for an actual redirect.
    """
    try:
        tokens = shlex.split(segment)
    except Exception:
        return []
    targets = []
    i = 0
    while i < len(tokens):
        tok = tokens[i]
        if tok in ('>', '>>'):
            if i + 1 < len(tokens):
                targets.append(tokens[i + 1])
            i += 2
            continue
        m = re.match(r'^(?:>>|>)(.+)$', tok)
        if m:
            targets.append(m.group(1))
            i += 1
            continue
        i += 1
    return targets

for segment in split_segments(command):

    # 1. Redirect operators: > .claude/file  or  >> .claude/file (quote-aware)
    for target in find_redirect_targets(segment):
        if is_protected(target):
            deny(f"Bash redirection to project source ({PROTECTED_LABEL}) is blocked. Use Write or Edit tools instead.")

    # 2. tee DESTINATION (tee writes to its arguments, not stdin source)
    for m in re.finditer(r'\btee\b((?:\s+\S+)+?)(?=\s*[|;&]|$)', segment):
        try:
            tee_args = shlex.split(m.group(1))
        except Exception:
            tee_args = m.group(1).split()
        for arg in tee_args:
            if not arg.startswith('-') and is_protected(arg):
                deny(f"Bash tee targeting project source ({PROTECTED_LABEL}) is blocked. Use Write or Edit tools instead.")

    # 3. cp / mv / install / ln — deny only when DESTINATION (last non-flag arg) is protected
    for op in ('cp', 'mv', 'install', 'ln'):
        if not re.search(r'(?:^|\s)' + re.escape(op) + r'(?:\s|$)', segment):
            continue
        try:
            tokens = shlex.split(segment)
        except Exception:
            tokens = segment.split()
        i = 0
        while i < len(tokens):
            if tokens[i] == op:
                args = []
                j = i + 1
                while j < len(tokens):
                    tok = tokens[j]
                    if tok in ('&&', '||', ';', '|'):
                        break
                    args.append(tok)
                    j += 1
                non_flags = [a for a in args if not a.startswith('-')]
                if non_flags and is_protected(non_flags[-1]):
                    deny(
                        f"Bash {op} destination targeting project source ({PROTECTED_LABEL}) is blocked. "
                        "Use Write or Edit tools instead."
                    )
                # mv SOURCE check: moving a delete-protected file OUT is
                # equivalent to deleting it from its protected location.
                if op == 'mv' and len(non_flags) >= 2:
                    for src in non_flags[:-1]:
                        if is_delete_protected(src):
                            deny(
                                f"Bash mv source '{src}' is delete-protected (.claude/, .mcp.json) — moving it "
                                "out is equivalent to deleting it. Use Write/Edit to author content at the "
                                "destination instead, or ask for explicit approval to relocate this file."
                            )
                i = j
            else:
                i += 1

    # 4. rm / git rm — deny only if a target is delete-protected (.claude/, .mcp.json).
    #    Deletion under the protected write dirs is ALLOWED here: there is no
    #    native delete tool (Write/Edit only author content), so blocking it
    #    forces evasive workarounds (inline python, find -delete). Content-
    #    authoring writes there still redirect via the other checks in this script.
    if re.search(r'(?:^|\s)rm(?:\s|$)', segment):
        try:
            tokens = shlex.split(segment)
        except Exception:
            tokens = segment.split()
        in_rm = False
        for tok in tokens:
            if tok == 'rm':
                in_rm = True
                continue
            if in_rm:
                if tok in ('&&', '||', ';', '|'):
                    in_rm = False
                    continue
                if not tok.startswith('-') and is_delete_protected(tok):
                    deny("Bash rm targeting .claude/ or .mcp.json is blocked. Use Write or Edit tools instead.")

    # 5. sed -i targeting a protected path (in-place edit is a write)
    if re.search(r'\bsed\b', segment) and re.search(r'\s-\S*i\S*\s|\s-i\b', segment):
        try:
            tokens = shlex.split(segment)
        except Exception:
            tokens = segment.split()
        in_sed = False
        skip_next = False
        for tok in tokens:
            if tok == 'sed':
                in_sed = True
                continue
            if in_sed:
                if tok in ('&&', '||', ';', '|'):
                    in_sed = False
                    continue
                if skip_next:
                    skip_next = False
                    continue
                if tok in ('-e', '-f', '-n'):
                    skip_next = True
                    continue
                if tok.startswith('-'):
                    continue
                if is_protected(tok):
                    deny(f"Bash sed -i targeting project source ({PROTECTED_LABEL}) is blocked. Use Edit tool instead.")

    # 6. truncate targeting a protected path
    if re.search(r'\btruncate\b', segment):
        try:
            tokens = shlex.split(segment)
        except Exception:
            tokens = segment.split()
        in_trunc = False
        skip_next = False
        for tok in tokens:
            if tok == 'truncate':
                in_trunc = True
                continue
            if in_trunc:
                if tok in ('&&', '||', ';', '|'):
                    in_trunc = False
                    continue
                if skip_next:
                    skip_next = False
                    continue
                if tok in ('-s', '--size', '-r', '--reference', '-o', '--io-blocks'):
                    skip_next = True
                    continue
                if tok.startswith('-'):
                    continue
                if is_protected(tok):
                    deny(f"Bash truncate targeting project source ({PROTECTED_LABEL}) is blocked. Use Write or Edit tools instead.")

    # 7. dd of=<protected path>
    m = re.search(r'\bdd\b.*\bof=([^\s]+)', segment)
    if m and is_protected(m.group(1)):
        deny(f"Bash dd targeting project source ({PROTECTED_LABEL}) is blocked. Use Write or Edit tools instead.")

    # 8. Inline Python/Perl write detection
    inline_parts = [re.escape(d) + '/' for d in PROTECTED_DIRS] + [r'\.claude/', r'\.mcp\.json']
    if re.search(r'(?:python|perl).*open\(.*(?:' + '|'.join(inline_parts) + r').*["\x27]w', segment):
        deny(f"Inline Python/Perl writes to project source ({PROTECTED_LABEL}) are blocked. Use Write or Edit tools instead.")

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
denial_cap_gate "config-guard-bash" "$SIG" "security" "$CODE" "$OUT"
