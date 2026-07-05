#!/usr/bin/env bash
set -uo pipefail

# UserPromptSubmit soft nudge — long-session hygiene.
# Marathon sessions (1000+ transcript records, multiple compactions) were the
# top source of lost constraints and rework in session analysis. When the
# transcript passes a size threshold, emit a one-line suggestion to close the
# session at the next natural task boundary (/end-session + /clear — state
# persists via save-on-clear + session-rehydrate). Advisory only: never
# blocks, always exit 0. Fires once per threshold step per session.

source "$(dirname "${BASH_SOURCE[0]}")/lib/cc-config.sh"

PAYLOAD="$(cat 2>/dev/null || true)"
if [[ -z "$PAYLOAD" ]]; then
  exit 0
fi

STATE_FILE="${CLAUDE_PROJECT_DIR:-.}/$CC_STATE_DIR/.memory/long-session-nudge-state.json"

python3 - "$PAYLOAD" "$STATE_FILE" <<'PY'
import json, os, sys
from pathlib import Path

try:
    data = json.loads(sys.argv[1])
    transcript = data.get("transcript_path", "")
    session_id = data.get("session_id", "")
except Exception:
    raise SystemExit(0)

state_file = sys.argv[2]

FIRST = int(os.environ.get("LONG_SESSION_FIRST_LINES", "800"))
STEP = int(os.environ.get("LONG_SESSION_STEP_LINES", "500"))
FIRST_MB = float(os.environ.get("LONG_SESSION_FIRST_MB", "3"))
STEP_MB = float(os.environ.get("LONG_SESSION_STEP_MB", "2"))

if not transcript or not Path(transcript).exists():
    raise SystemExit(0)

try:
    size_mb = Path(transcript).stat().st_size / (1024 * 1024)
    with open(transcript, "rb") as f:
        lines = sum(1 for _ in f)
except Exception:
    raise SystemExit(0)

# Marathon detection: record count OR raw size (a 500-record session can
# still carry 10MB of context through huge tool results).
if lines < FIRST and size_mb < FIRST_MB:
    raise SystemExit(0)

state = {}
try:
    with open(state_file) as f:
        state = json.load(f)
except Exception:
    state = {}
if state.get("session_id") != session_id:
    state = {"session_id": session_id, "nudged_at": 0, "nudged_mb": 0}

last = int(state.get("nudged_at", 0))
last_mb = float(state.get("nudged_mb", 0))
grew_lines = lines - last >= STEP
grew_mb = size_mb - last_mb >= STEP_MB
if last and not grew_lines and not grew_mb:
    raise SystemExit(0)

state["nudged_at"] = lines
state["nudged_mb"] = round(size_mb, 2)
try:
    os.makedirs(os.path.dirname(state_file), exist_ok=True)
    tmp = state_file + ".tmp"
    with open(tmp, "w") as f:
        json.dump(state, f)
    os.replace(tmp, state_file)
except Exception:
    pass

print(
    f"[long-session] Transcript at {lines} records / {size_mb:.1f}MB — long sessions lose "
    "constraints at compaction and accumulate errors. When the current task "
    "reaches a natural boundary, suggest to the user: /end-session then /clear "
    "(state persists via save-on-clear + session-rehydrate). Do not interrupt "
    "in-flight work for this."
)
PY
exit 0
