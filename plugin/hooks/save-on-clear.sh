#!/usr/bin/env bash
set -uo pipefail

# SessionEnd hook (matcher: clear) — RAW TRANSCRIPT SAFETY COPY ONLY.
#
# This hook is a fallback for bare /clear without /end-session.
# If /end-session wrote a snapshot within the last 30 min, skip (no duplicate).
# Otherwise, copies the transcript to $CC_STATE_DIR/.memory/checkpoints/ as
# on-clear-<session-id>-<UTC>.jsonl.
# It does NOT write session summaries — that is owned by the /end-session skill.
#
# Style: bash wrapper + embedded python3 for JSON.

source "$(dirname "${BASH_SOURCE[0]}")/lib/cc-config.sh"

PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
PAYLOAD="$(cat 2>/dev/null || true)"

python3 - "$PROJECT_ROOT" "$PAYLOAD" <<'PY'
import json
import os
import shutil
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

project  = Path(sys.argv[1])
payload  = sys.argv[2].strip()

try:
    data = json.loads(payload) if payload else {}
except Exception:
    data = {}

state_dir = os.environ.get("CC_STATE_DIR", ".cc_settings")
mem_dir = project / state_dir / ".memory"

# Skip if /end-session already wrote a fresh snapshot (< 30 min ago).
if mem_dir.exists():
    snaps = sorted(mem_dir.glob("session-*.md"), key=lambda f: f.stat().st_mtime)
    if snaps and (time.time() - snaps[-1].stat().st_mtime) < 1800:
        sys.exit(0)

stamp      = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H%M%SZ")
transcript = data.get("transcript_path", "")

if transcript and Path(transcript).exists():
    try:
        session_id = Path(transcript).stem
        ckpt_dir = mem_dir / "checkpoints"
        ckpt_dir.mkdir(parents=True, exist_ok=True)
        shutil.copy2(Path(transcript), ckpt_dir / f"on-clear-{session_id}-{stamp}.jsonl")
    except Exception:
        pass

PY

exit 0
