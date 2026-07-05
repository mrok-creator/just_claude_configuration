#!/usr/bin/env bash
set -uo pipefail

# PreToolUse guard: block network exfiltration, remote-code execution and
# secret-file access from agent Bash commands.
# Exit 0 = allow, Exit 2 = block (REJECT tool use).
# Matcher: Bash (via bash-guards-dispatcher.sh)
#
# DENY:
#   1. Raw network transports: nc / ncat / netcat / telnet (always),
#      scp / sftp (always), rsync with a remote spec (host: or rsync://).
#   2. curl / wget to any non-local host — localhost/127.0.0.1/::1/0.0.0.0
#      are allowed (local service testing); everything else must go through
#      WebFetch or be run by the user. Upload/exfil flags make no difference:
#      the host rule covers both directions.
#   3. Pipe-to-interpreter: curl/wget or base64 -d output piped into
#      sh/bash/zsh/dash/node/npx — the classic remote-code-execution vector.
#   4. Package execution/installation of arbitrary packages:
#      npx/npm exec with a package outside the workspace allowlist,
#      npm install/i/add with named packages (bare `npm install` / `npm ci`
#      from the lockfile are allowed), pip/uv/uvx installs.
#   5. Secret-file paths as command arguments: .env / .env.* / *.pem / *.key /
#      *.p12 / *.pfx / *.cert / credentials* / secrets* (mirrors the
#      settings.json Read/Write deny globs, closing the bash side-channel:
#      `cat .env`, `base64 .env`, `cp .env /tmp` etc.).
#
# mode=security: never auto-allows; after repeated denials the message
# escalates (see lib/denial-cap.sh). If a blocked operation is genuinely
# needed, the agent must stop and ask the user to run it.

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
    sys.stderr.write(
        f"[network-guard] {reason} "
        "If this operation is genuinely required, stop and ask the user to run or approve it.\n"
    )
    sys.exit(2)

LOCAL_HOSTS = {'localhost', '127.0.0.1', '0.0.0.0', '::1', '[::1]'}
NPX_ALLOW = {'nx', 'tsc', 'jest', 'eslint', 'typeorm', 'prettier', 'ts-node'}

def split_segments(cmd):
    """Flat list of simple-command segments (split on newline ; && || |)."""
    segments = []
    for line in cmd.splitlines():
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        parts = re.split(r'\s*(?:;|&&|\|\||\|)\s*', line)
        segments.extend(p.strip() for p in parts if p.strip())
    return segments

def tokens_of(segment):
    try:
        return shlex.split(segment)
    except Exception:
        return segment.split()

def command_token_index(toks):
    """Index of the real command token, skipping VAR=value prefixes."""
    for i, tok in enumerate(toks):
        if re.match(r'^[A-Za-z_][A-Za-z0-9_]*=', tok):
            continue
        return i
    return None

def base_name(tok):
    return tok.rsplit('/', 1)[-1]

def extract_hosts(toks):
    """Best-effort host extraction from URL-ish / host-ish argument tokens."""
    hosts = []
    for tok in toks[1:]:
        m = re.match(r'^[a-zA-Z][a-zA-Z0-9+.-]*://([^/:?#]+)', tok)
        if m:
            hosts.append(m.group(1))
            continue
        # bare host or host:port (domain-like or IP) as a standalone arg
        if re.match(r'^([a-zA-Z0-9-]+\.)+[a-zA-Z]{2,}(:\d+)?(/|$)', tok):
            hosts.append(tok.split('/', 1)[0].rsplit(':', 1)[0])
            continue
        if re.match(r'^\d{1,3}(\.\d{1,3}){3}(:\d+)?(/|$)', tok):
            hosts.append(tok.split('/', 1)[0].rsplit(':', 1)[0])
    return hosts

SECRET_BASENAME = re.compile(
    r'^(\.env(\..*)?|.*\.(pem|key|p12|pfx|cert)|credentials.*|secrets.*)$',
    re.IGNORECASE,
)

# ── 3. Pipe-to-interpreter (raw line scan: pipes are lost after segmenting) ──
for line in command.splitlines():
    if re.search(r'\b(curl|wget)\b[^|]*\|.*\b(sh|bash|zsh|dash|node|npx)\b', line):
        deny("Piping downloaded content into an interpreter (curl/wget | sh/node) is blocked — remote-code-execution vector.")
    if re.search(r'\bbase64\b\s+(-d|--decode)[^|]*\|.*\b(sh|bash|zsh|dash|node|npx)\b', line):
        deny("Piping base64-decoded content into an interpreter is blocked — obfuscated-execution vector.")

for segment in split_segments(command):
    toks = tokens_of(segment)
    if not toks:
        continue
    ci = command_token_index(toks)
    if ci is None:
        continue
    cmd_toks = toks[ci:]
    cmd_name = base_name(cmd_toks[0])

    # ── 5. Secret-file paths as arguments to ANY command ──
    for tok in cmd_toks[1:]:
        if tok.startswith('-'):
            continue
        bn = base_name(tok)
        # Only path-like tokens (contain / or a dot in basename) — bare words
        # like a grep term "secrets" are not files and stay allowed.
        if ('/' in tok or '.' in bn) and SECRET_BASENAME.match(bn):
            deny(f"Command references secret-holding file '{tok}' — bash access to .env/keys/credentials is blocked (mirrors settings.json deny globs).")

    # ── 1. Raw network transports ──
    if cmd_name in ('nc', 'ncat', 'netcat', 'telnet'):
        deny(f"'{cmd_name}' is blocked — raw network transport (exfiltration vector).")
    if cmd_name in ('scp', 'sftp'):
        deny(f"'{cmd_name}' is blocked — remote file transfer (exfiltration vector).")
    if cmd_name == 'rsync':
        for tok in cmd_toks[1:]:
            if tok.startswith('-'):
                continue
            if tok.startswith('rsync://') or re.match(r'^[^/]+@[^/]+:', tok) or re.match(r'^[a-zA-Z0-9._-]+:[^=]', tok):
                deny("rsync with a remote destination/source is blocked — remote file transfer (exfiltration vector). Local rsync is allowed.")

    # ── 2. curl / wget host allowlist (localhost only) ──
    if cmd_name in ('curl', 'wget'):
        hosts = extract_hosts(cmd_toks)
        remote = [h for h in hosts if h not in LOCAL_HOSTS]
        if remote:
            deny(f"curl/wget to non-local host '{remote[0]}' is blocked — use the WebFetch tool for web content, or ask the user to run this transfer.")

    # ── 4. Arbitrary package execution / installation ──
    if cmd_name in ('npx',) or (cmd_name == 'npm' and len(cmd_toks) > 1 and cmd_toks[1] == 'exec'):
        args = cmd_toks[1:] if cmd_name == 'npx' else cmd_toks[2:]
        target = None
        skip_next = False
        for tok in args:
            if skip_next:
                skip_next = False
                continue
            if tok in ('-p', '--package', '-c', '--call'):
                skip_next = True
                continue
            if tok == '--':
                continue
            if tok.startswith('-'):
                continue
            target = tok
            break
        if target and base_name(target) not in NPX_ALLOW:
            deny(f"npx/npm exec of arbitrary package '{target}' is blocked — remote-code-execution vector. Allowed targets: {', '.join(sorted(NPX_ALLOW))}.")
    if cmd_name == 'npm' and len(cmd_toks) > 1 and cmd_toks[1] in ('install', 'i', 'add'):
        named = [t for t in cmd_toks[2:] if not t.startswith('-')]
        if named:
            deny(f"npm install of named package(s) {named} is blocked — supply-chain vector. Lockfile installs (bare `npm install`, `npm ci`) are allowed; ask the user to add new dependencies.")
    if cmd_name in ('pip', 'pip2', 'pip3', 'uvx') or (cmd_name == 'uv' and len(cmd_toks) > 1 and cmd_toks[1] in ('pip', 'tool', 'run', 'add')):
        deny(f"'{' '.join(cmd_toks[:2])}' is blocked — arbitrary package execution/installation.")

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
denial_cap_gate "network-guard" "$SIG" "security" "$CODE" "$OUT"