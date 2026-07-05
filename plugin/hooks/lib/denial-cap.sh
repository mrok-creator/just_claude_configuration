#!/usr/bin/env bash
# Shared helper: consecutive-denial cap for guard hooks (#24327).
# Sourced (not executed) by each guard script — prevents idle-loops where
# the agent keeps retrying the exact same operation against the same guard.
#
# State lives in one JSON file under $CC_STATE_DIR/.memory/ — outside every
# guard's protected scope (protected write dirs, .claude/, .mcp.json), so
# writes here are never themselves intercepted by config-guard-bash.sh or
# read-guard.sh. Tracks, per guard, only the LAST-seen command signature +
# consecutive denial count: a different signature, or a gap longer than the
# time window, resets the streak to 1.
#
# Integration contract (see any guard script for a live example):
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/denial-cap.sh"
#   SIG="$(denial_cap_signature "$PAYLOAD")"
#   exec 3>&1
#   if OUT="$(main 2>&1 1>&3)"; then CODE=0; else CODE=$?; fi
#   exec 3>&-
#   denial_cap_gate "<guard-name>" "$SIG" "<native|security>" "$CODE" "$OUT"
#
# `main` must be a function wrapping the guard's existing classification
# logic verbatim (same exit 0 / exit 2 semantics as before). Running it via
# command substitution puts it in a subshell, so its internal `exit` calls
# only end that subshell — `main`'s real stdout (e.g. a hook JSON decision
# blob) still reaches the real stdout via fd 3, untouched; only stderr text
# is captured for possible cap annotation.
#
# denial_cap_gate is the ONLY exit point after this — it prints the
# (possibly annotated) message and terminates with the final decided code.

source "$(dirname "${BASH_SOURCE[0]}")/cc-config.sh"

DENIAL_CAP_N="${DENIAL_CAP_N:-3}"
DENIAL_CAP_WINDOW_SECONDS="${DENIAL_CAP_WINDOW_SECONDS:-300}"
DENIAL_CAP_PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
DENIAL_CAP_STATE_FILE="${DENIAL_CAP_STATE_FILE:-$DENIAL_CAP_PROJECT_DIR/$CC_STATE_DIR/.memory/denial-cap-state.json}"

# Stable signature for a hook payload — same payload => same signature =>
# counts as "the same op" toward the cap. Different payload (even a
# one-character command change) resets the streak.
denial_cap_signature() {
  local payload="$1"
  if command -v shasum >/dev/null 2>&1; then
    printf '%s' "$payload" | shasum -a 256 2>/dev/null | awk '{print $1}' | cut -c1-16
  elif command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$payload" | sha256sum 2>/dev/null | awk '{print $1}' | cut -c1-16
  else
    printf '%s' "$payload" | cksum | tr ' ' '-'
  fi
}

# Increments (or resets, if the signature changed or the window elapsed)
# the consecutive-denial count for a guard; echoes the resulting count.
denial_cap_bump() {
  local guard="$1" sig="$2"
  python3 - "$DENIAL_CAP_STATE_FILE" "$guard" "$sig" "$DENIAL_CAP_WINDOW_SECONDS" <<'PY'
import json, os, sys, time

state_file, guard, sig, window = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])

state = {}
if os.path.exists(state_file):
    try:
        with open(state_file) as f:
            state = json.load(f)
    except Exception:
        state = {}

now = int(time.time())
entry = state.get(guard)

if entry and entry.get("sig") == sig and (now - entry.get("ts", 0)) <= window:
    count = entry.get("count", 0) + 1
else:
    count = 1

state[guard] = {"sig": sig, "count": count, "ts": now}

try:
    os.makedirs(os.path.dirname(state_file), exist_ok=True)
    tmp = state_file + ".tmp"
    with open(tmp, "w") as f:
        json.dump(state, f)
    os.replace(tmp, state_file)
except Exception:
    pass

print(count)
PY
}

# Clears a guard's tracked streak entirely (called on ALLOW, and after a
# native-first cap auto-allow, so the next denial starts a fresh count).
denial_cap_reset() {
  local guard="$1"
  python3 - "$DENIAL_CAP_STATE_FILE" "$guard" <<'PY'
import json, os, sys

state_file, guard = sys.argv[1], sys.argv[2]
if not os.path.exists(state_file):
    sys.exit(0)
try:
    with open(state_file) as f:
        state = json.load(f)
except Exception:
    sys.exit(0)
if guard in state:
    del state[guard]
    try:
        tmp = state_file + ".tmp"
        with open(tmp, "w") as f:
            json.dump(state, f)
        os.replace(tmp, state_file)
    except Exception:
        pass
PY
}

# denial_cap_gate <guard-name> <signature> <mode: native|security> <core-exit-code> <core-stderr-text>
# Final tail call for a guard script: prints the message(s) to stderr and
# exits with the cap-adjusted decision. Never returns.
#
#   mode=native   — after N consecutive denials of the SAME op: ALLOW
#                   (exit 0) with a "native-first cap reached" note. A soft
#                   tool-preference must not loop forever.
#   mode=security — after N consecutive denials: KEEP blocking (never
#                   auto-allow); only the message escalates, forcing the
#                   agent to stop and surface it instead of silently retrying.
denial_cap_gate() {
  local guard="$1" sig="$2" mode="$3" code="$4" msg="$5"

  if [[ "$code" -ne 2 ]]; then
    # Not a denial this time (allowed, or errored some other way) — clear
    # any streak so a later denial starts counting fresh.
    denial_cap_reset "$guard"
    exit "$code"
  fi

  local count
  count="$(denial_cap_bump "$guard" "$sig")"

  if [[ -n "$msg" ]]; then
    printf '%s\n' "$msg" >&2
  fi

  if (( count == 2 )); then
    echo "[denial-cap] 2nd identical denial on ${guard} — do NOT retry this command (verbatim or lightly modified). Your NEXT call must be the native/Serena tool named above." >&2
  fi

  if (( count >= DENIAL_CAP_N )); then
    if [[ "$mode" == "native" ]]; then
      echo "[denial-cap] native-first cap reached (${count} consecutive denials on ${guard}) — allowing." >&2
      denial_cap_reset "$guard"
      exit 0
    else
      echo "[denial-cap] ESCALATE: ${count} consecutive denials on ${guard} — stop and surface this to the user." >&2
      exit 2
    fi
  fi

  exit 2
}
