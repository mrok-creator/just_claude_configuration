#!/usr/bin/env bash
set -uo pipefail

# PreToolUse dispatcher for ALL Bash guards — single settings.json entry
# replacing 9 individual registrations (8-12 python spawns per Bash call).
#
# Reads the payload ONCE, extracts the command string (one python spawn),
# then runs each guard script ONLY when it is enabled by configuration
# (lib/cc-config.sh) AND a cheap superset prefilter says the guard could
# possibly fire. Guard scripts are UNCHANGED (same stdin contract, same exit
# semantics, own denial-cap state) — a prefilter miss is exactly equivalent
# to the guard running and allowing, because every prefilter pattern is a
# superset of the guard's own trigger condition:
#
#   python-guard-bash   denies only python invocations        → 'python'
#   config-guard-bash   denies only protected-path targets    → '.claude|.mcp.json|<CC_PROTECTED_WRITE_DIRS>'
#   migration-safety    denies typeorm revert/drop/truncate/
#                       unscoped delete                       → 'typeorm|drop|truncate|delete'
#   nav-guard           denies only grep/rg/ag/ack symbols    → those verbs
#   read-guard          denies only listed file-op verbs      → those verbs
#   detect-secrets      (Bash path) scans only `git commit`   → 'commit'
#   package-manager     denies only non-allowed managers      → the denied managers
#   basic-memory-guard  denies only paths under */basic-memory → 'basic-memory'
#   network-guard       denies transports/hosts/packages/
#                       secret files                          → union of its triggers
#
# Config toggles (see cc-config.env.example):
#   CC_NAV_GUARD=off        skips nav-guard entirely (no Serena installed)
#   CC_MIGRATION_GUARD=off  skips migration-safety entirely
#   CC_PKG_MANAGER          selects which managers package-manager-guard denies
#
# First guard that exits 2 wins (same as sequential hooks). Guards write
# their denial text to stderr directly (inherited fds).

HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HOOKS_DIR/lib/cc-config.sh"

PAYLOAD="$(cat 2>/dev/null || true)"
if [[ -z "$PAYLOAD" ]]; then
  exit 0
fi

COMMAND="$(printf '%s' "$PAYLOAD" | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
    if data.get("tool_name", "Bash") != "Bash":
        print("")
    else:
        print(data.get("tool_input", {}).get("command", ""))
except Exception:
    print("")
' 2>/dev/null || true)"

if [[ -z "$COMMAND" ]]; then
  exit 0
fi

run_guard() {
  local script="$1" rc=0
  printf '%s' "$PAYLOAD" | bash "$HOOKS_DIR/$script" || rc=$?
  if [[ "$rc" -eq 2 ]]; then
    exit 2
  fi
}

matches() { grep -qiE "$1" <<<"$COMMAND"; }

# Package managers to deny = {npm, pnpm, yarn} minus the allowed one.
PM_DENY=""
for _pm in npm pnpm yarn; do
  if [[ "$_pm" != "$CC_PKG_MANAGER" ]]; then
    PM_DENY="${PM_DENY:+$PM_DENY|}$_pm"
  fi
done

# ── NATIVE-mode guards: run UNCONDITIONALLY (unless config-disabled) ────────
# These use a "N consecutive denials of the SAME payload → auto-allow" cap
# (lib/denial-cap.sh, mode=native). "Consecutive" means the streak MUST reset
# on every allowed bash call. If they were prefilter-gated, a non-matching
# command would skip the guard and skip the reset, so the streak would count
# CUMULATIVE instead of consecutive denials and the guard would auto-surrender
# far too early (observed regression). Running them on every call preserves
# the reset. Still one payload read; ~3 python spawns.
run_guard "python-guard-bash.sh"
if [[ "$CC_NAV_GUARD" == "on" ]]; then
  run_guard "nav-guard.sh"
fi
run_guard "read-guard.sh"

# ── SECURITY-mode guards: prefilter-gate for spawn savings ──────────────────
# These never auto-allow (mode=security), so their denial-cap streak has no
# effect on the allow/block decision — skipping them on non-matching commands
# changes nothing. Gate them by a cheap superset prefilter of their trigger.
matches "\.claude|\.mcp\.json|${CC_PROTECTED_WRITE_DIRS}" \
  && run_guard "config-guard-bash.sh"
if [[ "$CC_MIGRATION_GUARD" == "on" ]]; then
  matches 'typeorm|drop|truncate|delete' \
    && run_guard "migration-safety.sh"
fi
matches 'commit' \
  && run_guard "detect-secrets.sh"
if [[ -n "$PM_DENY" ]]; then
  matches "$PM_DENY" \
    && run_guard "package-manager-guard.sh"
fi
matches 'basic-memory' \
  && run_guard "basic-memory-guard.sh"
matches 'curl|wget|ncat|netcat|telnet|scp|sftp|rsync|npx|npm|pip|uvx|base64|\.env|\.pem|\.key|\.p12|\.pfx|\.cert|credentials|secrets|(^|[^a-zA-Z])(nc|uv)([^a-zA-Z]|$)' \
  && run_guard "network-guard.sh"

exit 0
