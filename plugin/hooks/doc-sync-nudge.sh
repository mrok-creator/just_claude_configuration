#!/usr/bin/env bash
set -uo pipefail

# SessionStart hook (matcher: startup|resume) — nudge when doc-drift.md has entries.
# Fires once per session start/resume, not on every Stop.
# Emits additionalContext only when drift list is non-empty.
# Never auto-runs /doc-sync. exit 0 always (non-blocking).
# Drift state lives under $CC_STATE_DIR/.memory/; the /doc-sync skill refreshes
# the AUTO-MANAGED sections of the docs under .claude/docs.

source "$(dirname "${BASH_SOURCE[0]}")/lib/cc-config.sh"

PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
DOC_DRIFT_FILE="$PROJECT_ROOT/$CC_STATE_DIR/.memory/doc-drift.md"

python3 - "$DOC_DRIFT_FILE" <<'PY'
import json
import sys
from pathlib import Path

drift_file = Path(sys.argv[1])

if not drift_file.exists():
    raise SystemExit(0)

text = drift_file.read_text().strip()
if not text:
    raise SystemExit(0)

lines = [line.strip() for line in text.splitlines() if line.strip() and not line.strip().startswith("#")]
if not lines:
    raise SystemExit(0)

count = len(lines)
out = {
    "hookSpecificOutput": {
        "hookEventName": "SessionStart",
        "additionalContext": (
            f"{count} service docs may be stale — run /doc-sync to refresh AUTO-MANAGED sections."
        ),
    }
}
print(json.dumps(out))

PY

exit 0
