#!/usr/bin/env bash
set -euo pipefail

# PostToolUse hook (matcher: Write|Edit) — record what the session touched,
# for validate-on-stop.sh. Behavior follows CC_VALIDATE_MODE (lib/cc-config.sh):
#   nx      — resolve the touched file to its Nx PROJECT name (nearest
#             project.json) and record that.
#   command — record the project-relative FILE path (any tracked file
#             triggers the single validation command on Stop).
#   off     — no tracking at all.
# State: $CC_STATE_DIR/.touched-projects (deduplicated, sorted).

source "$(dirname "${BASH_SOURCE[0]}")/lib/cc-config.sh"

if [[ "$CC_VALIDATE_MODE" == "off" ]]; then
  exit 0
fi

PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
STATE_DIR="$PROJECT_ROOT/$CC_STATE_DIR"
TOUCHED_FILE="$STATE_DIR/.touched-projects"

mkdir -p "$STATE_DIR"

PAYLOAD="$(cat 2>/dev/null || true)"
if [[ -z "$PAYLOAD" && $# -gt 0 ]]; then
  PAYLOAD="$1"
fi

python3 - "$PROJECT_ROOT" "$TOUCHED_FILE" "$PAYLOAD" <<'PY'
import json
import os
import re
import sys
from pathlib import Path

project_root = Path(sys.argv[1]).resolve()
out_file = Path(sys.argv[2])
payload = sys.argv[3].strip()

mode = os.environ.get("CC_VALIDATE_MODE", "off")
src_dirs = [d for d in os.environ.get("CC_SOURCE_DIRS", "apps|libs|tools|src|config").split("|") if d]
state_dir = os.environ.get("CC_STATE_DIR", ".cc_settings").strip("/")

if not payload:
    raise SystemExit(0)

try:
    data = json.loads(payload)
except Exception:
    raise SystemExit(0)

candidates = []
KEYS = {"file_path", "path", "old_file_path", "new_file_path"}

def walk(obj):
    if isinstance(obj, dict):
        for k, v in obj.items():
            if k in KEYS and isinstance(v, str):
                candidates.append(v)
            walk(v)
    elif isinstance(obj, list):
        for item in obj:
            walk(item)

walk(data)
entries = set()

def resolve_project_name(rel):
    # Folder name != Nx project name. Walk up from the touched file to the
    # nearest project.json and use its "name" field; fall back to the
    # top-level folder name.
    parts = rel.split("/")
    if len(parts) < 2 or parts[0] not in src_dirs:
        return None
    top = project_root / parts[0] / parts[1]
    p = (project_root / rel).parent
    while True:
        pj = p / "project.json"
        if pj.is_file():
            try:
                name = json.loads(pj.read_text()).get("name")
                if isinstance(name, str) and name.strip():
                    return name.strip()
            except Exception:
                pass
            return p.name
        if p == top or p == project_root or p.parent == p:
            break
        p = p.parent
    return parts[1]

def is_tracked_file(rel):
    # command mode: any project file counts, except harness/VCS state.
    skip_prefixes = (state_dir + "/", ".claude/", ".git/", "node_modules/", ".planning/")
    return not rel.startswith(skip_prefixes)

for raw in candidates:
    p = Path(raw)
    if not p.is_absolute():
        p = (project_root / p).resolve()
    try:
        rel = p.relative_to(project_root).as_posix()
    except Exception:
        continue

    if mode == "nx":
        name = resolve_project_name(rel)
        if name:
            entries.add(name)
    else:  # command
        if is_tracked_file(rel):
            entries.add(rel)

if not entries:
    raise SystemExit(0)

existing = set()
if out_file.exists():
    existing = {line.strip() for line in out_file.read_text().splitlines() if line.strip()}

merged = sorted(existing | entries)
out_file.write_text("\n".join(merged) + "\n")
print(f"[track-touched] tracked: {', '.join(sorted(entries))}")
PY
