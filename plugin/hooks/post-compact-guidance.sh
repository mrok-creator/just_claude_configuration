#!/usr/bin/env bash
set -uo pipefail

# SessionStart hook (matcher: compact) — post-compaction guidance.
# After auto/manual compaction the harness voids per-file read state and the
# summary drops mid-session constraints. Pre-compact artifacts already exist
# (pre-compact-save.sh): a full transcript checkpoint + handoff-latest.md.
# This hook injects a pointer to those artifacts plus the two rules that
# repeatedly cost turns after compaction:
#   1. recover context from the artifacts (grep the checkpoint), not by
#      re-reading whole project files;
#   2. Edit/Write requires a FRESH Read after compaction — read only the
#      target range, then edit.
# exit 0 always (non-blocking).

source "$(dirname "${BASH_SOURCE[0]}")/lib/cc-config.sh"

PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
PAYLOAD="$(cat 2>/dev/null || true)"

python3 - "$PROJECT_ROOT" "$PAYLOAD" <<'PY'
import json
import os
import sys
from pathlib import Path

project = Path(sys.argv[1])
payload = sys.argv[2].strip()

try:
    data = json.loads(payload) if payload else {}
except Exception:
    data = {}

session_id = data.get("session_id", "")
state_dir = os.environ.get("CC_STATE_DIR", ".cc_settings")
mem_dir = project / state_dir / ".memory"

parts = []

ckpt_dir = mem_dir / "checkpoints"
if ckpt_dir.is_dir():
    pattern = f"pre-compact-{session_id}-*.jsonl" if session_id else "pre-compact-*.jsonl"
    ckpts = sorted(ckpt_dir.glob(pattern))
    if ckpts:
        parts.append(f"pre-compact transcript checkpoint: {ckpts[-1]}")

handoff = mem_dir / "handoff-latest.md"
if handoff.exists():
    parts.append(f"handoff: {handoff}")

pointer = (
    "Post-compaction recovery — "
    + ("; ".join(parts) + ". " if parts else "")
    + "Rules: (1) recover lost context (decisions, constraints, file excerpts) "
    "from these artifacts — grep the checkpoint by file path or keyword — "
    "instead of re-reading whole project files; "
    "(2) compaction VOIDS per-file read state: before any Edit/Write, Read the "
    "target file first (only the relevant range), otherwise the edit fails; "
    "(3) user constraints stated mid-session (git handling, scope limits) may "
    "be missing from the summary — check the handoff before assuming none exist."
)

out = {
    "hookSpecificOutput": {
        "hookEventName": "SessionStart",
        "additionalContext": pointer,
    }
}
print(json.dumps(out))
PY

exit 0
