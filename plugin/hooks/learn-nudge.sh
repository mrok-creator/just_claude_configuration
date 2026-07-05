#!/usr/bin/env bash
set -uo pipefail

# SessionStart hook (matcher: startup|resume) — nudge when learning buffer has entries.
# Emits additionalContext only when buffer.md has >= NUDGE_THRESHOLD entries.
# Never auto-runs /learn-process. exit 0 always (non-blocking).

source "$(dirname "${BASH_SOURCE[0]}")/lib/cc-config.sh"

PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"

python3 - "$PROJECT_ROOT" <<'PY'
import json
import os
import sys
from pathlib import Path

project = Path(sys.argv[1])
state_dir = os.environ.get("CC_STATE_DIR", ".cc_settings")
buffer_file = project / state_dir / ".memory" / "buffer.md"

NUDGE_THRESHOLD = 3

if not buffer_file.exists():
    raise SystemExit(0)

text = buffer_file.read_text().strip()
if not text:
    raise SystemExit(0)

entry_count = text.count("**type:**")
if entry_count < NUDGE_THRESHOLD:
    raise SystemExit(0)

out = {
    "hookSpecificOutput": {
        "hookEventName": "SessionStart",
        "additionalContext": (
            f"Learning buffer has {entry_count} entries — run /learn-process to promote and clear."
        ),
    }
}
print(json.dumps(out))

PY

exit 0
