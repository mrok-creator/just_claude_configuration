#!/usr/bin/env bash
set -euo pipefail

# PostToolUse hook (matcher: Write|Edit|MultiEdit) — track service/lib doc drift.
# If touched file is under apps/<svc>/ or libs/<lib>/, append <svc>/<lib> to
# $CC_STATE_DIR/.memory/doc-drift.md (deduplicated).
# Mechanical, no LLM. exit 0 always (non-blocking).

source "$(dirname "${BASH_SOURCE[0]}")/lib/cc-config.sh"

PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
DOC_DRIFT_FILE="$PROJECT_ROOT/$CC_STATE_DIR/.memory/doc-drift.md"

mkdir -p "$(dirname "$DOC_DRIFT_FILE")"

PAYLOAD="$(cat 2>/dev/null || true)"
if [[ -z "$PAYLOAD" && $# -gt 0 ]]; then
  PAYLOAD="$1"
fi

python3 - "$PROJECT_ROOT" "$DOC_DRIFT_FILE" "$PAYLOAD" <<'PY'
import json
import re
import sys
from pathlib import Path
from datetime import datetime, timezone

project_root = Path(sys.argv[1]).resolve()
drift_file = Path(sys.argv[2])
payload = sys.argv[3].strip()

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
services = set()

for raw in candidates:
    p = Path(raw)
    if not p.is_absolute():
        p = (project_root / p).resolve()
    try:
        rel = p.relative_to(project_root).as_posix()
    except Exception:
        continue

    # Match apps/<svc>/ or libs/<lib>/
    m = re.match(r"apps/([^/]+)/", rel)
    if m:
        services.add(m.group(1))
        continue
    m = re.match(r"libs/([^/]+)/", rel)
    if m:
        services.add(m.group(1))
        continue

if not services:
    raise SystemExit(0)

existing = {}
if drift_file.exists():
    for line in drift_file.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split(maxsplit=1)
        if parts:
            existing[parts[0]] = line

timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
for svc in sorted(services):
    if svc not in existing:
        existing[svc] = f"{svc} {timestamp}"

merged = sorted(existing.values())
drift_file.write_text("\n".join(merged) + "\n")
print(f"[doc-drift-mark] tracked: {', '.join(sorted(services))}")
PY

exit 0
