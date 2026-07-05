#!/usr/bin/env bash
set -uo pipefail

# SessionStart hook (matcher: startup|resume|clear) — inject saved-context pointer.
# Outputs additionalContext with file locations ONLY — not file contents.
# If no saved state files exist yet, outputs nothing.
# State home comes from CC_STATE_DIR (lib/cc-config.sh).
# exit 0 always (non-blocking).
#
# Style: bash wrapper + embedded python3 for JSON.

source "$(dirname "${BASH_SOURCE[0]}")/lib/cc-config.sh"

PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"

python3 - "$PROJECT_ROOT" <<'PY'
import json
import os
import sys
from pathlib import Path

project = Path(sys.argv[1])
state_dir = os.environ.get("CC_STATE_DIR", ".cc_settings")
mem_dir = project / state_dir / ".memory"

index_yml    = mem_dir / "index.yml"
state_md     = mem_dir / "STATE.md"
memory_index = mem_dir / "index.md"

# Only emit pointer if at least one file exists
if not any(f.exists() for f in [index_yml, state_md, memory_index]):
    raise SystemExit(0)

parts = []
if index_yml.exists():
    parts.append(f"index: {index_yml}")
if state_md.exists():
    parts.append(f"current state: {state_md}")
if memory_index.exists():
    parts.append(f"session buffer index: {memory_index}")

pointer = "Saved context — " + " ; ".join(parts) + ". Read on demand."

out = {
    "hookSpecificOutput": {
        "hookEventName": "SessionStart",
        "additionalContext": pointer,
    }
}
print(json.dumps(out))

PY

exit 0
