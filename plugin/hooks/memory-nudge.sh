#!/usr/bin/env bash
set -uo pipefail

# UserPromptSubmit soft nudge — enforces the project's long-term-memory read
# contract. If the prompt names a service/module (matched by
# CC_MEMORY_NUDGE_REGEX, e.g. "[a-z-]*-svc"), emit a one-line reminder
# (~30 tokens) to query basic-memory before planning. Advisory only:
# never blocks, always exit 0. Skips when the prompt already mentions
# basic-memory (contract is being followed).
# An empty CC_MEMORY_NUDGE_REGEX disables the nudge entirely.
#
# Deduplicated with a sliding window: a service is re-nudged only if it has
# not been nudged within the last NUDGE_WINDOW prompts of this session (state
# in $CC_STATE_DIR/.memory/memory-nudge-state.json). This keeps the read-
# contract reminder alive across a long session (a service touched again
# after many turns is a likely new task) without spamming every prompt.
# The displayed list is capped at 5 services to bound token cost.

source "$(dirname "${BASH_SOURCE[0]}")/lib/cc-config.sh"

if [[ -z "$CC_MEMORY_NUDGE_REGEX" ]]; then
  exit 0
fi

PAYLOAD="$(cat 2>/dev/null || true)"
if [[ -z "$PAYLOAD" ]]; then
  exit 0
fi

STATE_FILE="${CLAUDE_PROJECT_DIR:-.}/$CC_STATE_DIR/.memory/memory-nudge-state.json"

python3 - "$PAYLOAD" "$STATE_FILE" <<'PY'
import json, os, re, sys

try:
    data = json.loads(sys.argv[1])
    prompt = data.get("prompt", "")
    session_id = data.get("session_id", "")
except Exception:
    raise SystemExit(0)

state_file = sys.argv[2]

if not prompt or "basic-memory" in prompt.lower():
    raise SystemExit(0)

svc_regex = os.environ.get("CC_MEMORY_NUDGE_REGEX", "")
if not svc_regex:
    raise SystemExit(0)

try:
    svcs = sorted({m.group(0) for m in re.finditer(r"\b(?:" + svc_regex + r")\b", prompt.lower())})
except re.error:
    raise SystemExit(0)
if not svcs:
    raise SystemExit(0)

NUDGE_WINDOW = int(os.environ.get("MEMORY_NUDGE_WINDOW", "5"))

# Load per-session nudge state; a different session_id resets it.
# services maps svc -> prompt counter at which it was last nudged.
state = {}
try:
    with open(state_file) as f:
        state = json.load(f)
except Exception:
    state = {}
if state.get("session_id") != session_id or not isinstance(state.get("services"), dict):
    state = {"session_id": session_id, "counter": 0, "services": {}}

counter = int(state.get("counter", 0)) + 1
state["counter"] = counter
last = state["services"]

# Re-nudge a service only if never nudged or last nudge was > window ago.
fresh = [s for s in svcs if s not in last or (counter - last[s]) > NUDGE_WINDOW]
if not fresh:
    try:
        os.makedirs(os.path.dirname(state_file), exist_ok=True)
        tmp = state_file + ".tmp"
        with open(tmp, "w") as f:
            json.dump(state, f)
        os.replace(tmp, state_file)
    except Exception:
        pass
    raise SystemExit(0)

for s in fresh:
    last[s] = counter
try:
    os.makedirs(os.path.dirname(state_file), exist_ok=True)
    tmp = state_file + ".tmp"
    with open(tmp, "w") as f:
        json.dump(state, f)
    os.replace(tmp, state_file)
except Exception:
    pass

shown = fresh[:5]
more = len(fresh) - len(shown)
listing = ", ".join(shown) + (f" (+{more} more)" if more > 0 else "")
print(
    f"[memory-nudge] Prompt names {listing} — per the project memory read contract, "
    "query basic-memory (search_notes, types decision/pitfall/mistake/correction) "
    "for these services BEFORE planning any coding task."
)
PY
exit 0
