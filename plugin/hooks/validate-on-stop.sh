#!/usr/bin/env bash
set -euo pipefail

# Stop hook — validate what the session touched (see track-touched.sh).
# Strategy is selected by CC_VALIDATE_MODE (lib/cc-config.sh):
#   nx      — the touched list holds Nx PROJECT names; run
#             `npx nx build|lint <project>` for each.
#   command — the touched list holds file paths; run CC_VALIDATE_CMD once.
#   off     — no validation, exit 0.
# On failure: exit 2 and PRESERVE the touched list so the next Stop reruns.

source "$(dirname "${BASH_SOURCE[0]}")/lib/cc-config.sh"

if [[ "$CC_VALIDATE_MODE" == "off" ]]; then
  exit 0
fi

PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
TOUCHED_FILE="$PROJECT_ROOT/$CC_STATE_DIR/.touched-projects"

# When this Stop was itself triggered by a previous Stop-hook failure,
# stop_hook_active is true — exit cleanly to avoid an endless
# Stop -> fix -> Stop rebuild loop on pre-existing failures.
PAYLOAD="$(cat 2>/dev/null || true)"
if [[ -n "$PAYLOAD" ]]; then
  ACTIVE="$(printf '%s' "$PAYLOAD" | python3 -c "
import json, sys
try:
    print(str(json.load(sys.stdin).get('stop_hook_active', False)).lower())
except Exception:
    print('false')
" 2>/dev/null || echo false)"
  if [[ "$ACTIVE" == "true" ]]; then
    echo "[validate-on-stop] stop_hook_active=true — skipping revalidation (already reported this Stop cycle)."
    exit 0
  fi
fi

if [[ ! -f "$TOUCHED_FILE" ]]; then
  exit 0
fi

ENTRIES=()
while IFS= read -r line; do
  [[ -n "$line" ]] && ENTRIES+=("$line")
done < <(sort -u "$TOUCHED_FILE")

if [[ ${#ENTRIES[@]} -eq 0 ]]; then
  exit 0
fi

cd "$PROJECT_ROOT"

# ── command mode: run the configured validation command once ────────────────
if [[ "$CC_VALIDATE_MODE" == "command" ]]; then
  if [[ -z "$CC_VALIDATE_CMD" ]]; then
    # Nothing configured to run — treat as pass, but keep no stale state.
    rm -f "$TOUCHED_FILE"
    exit 0
  fi

  echo ""
  echo "[validate-on-stop] files were touched — running: $CC_VALIDATE_CMD"
  if bash -c "$CC_VALIDATE_CMD"; then
    rm -f "$TOUCHED_FILE"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "[validate-on-stop] validation command passed"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    exit 0
  fi

  cat >&2 <<EOF
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[validate-on-stop] Validation command failed: $CC_VALIDATE_CMD
[validate-on-stop] Preserving touched-file list for rerun.
  Fix the failures above, then retry.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF
  exit 2
fi

# ── nx mode: validate each touched Nx project ───────────────────────────────
echo ""
echo "[validate-on-stop] validating touched projects..."
FAILED=()

for PROJECT in "${ENTRIES[@]}"; do
  META="$(npx nx show project "$PROJECT" --json 2>/dev/null || true)"
  if [[ -z "$META" ]]; then
    echo "[validate-on-stop] skip $PROJECT (project metadata not found)"
    continue
  fi

  TARGET="$(python3 - "$META" <<'PY'
import json, sys
try:
    data = json.loads(sys.argv[1])
except Exception:
    print("")
    raise SystemExit(0)

targets = data.get("targets") or {}
if "build" in targets:
    print("build")
elif "lint" in targets:
    print("lint")
else:
    print("")
PY
)"

  if [[ -z "$TARGET" ]]; then
    echo "[validate-on-stop] skip $PROJECT (no build/lint target)"
    continue
  fi

  echo "[validate-on-stop] $PROJECT -> $TARGET"
  if [[ "$TARGET" == "build" ]]; then
    if ! npx nx build "$PROJECT"; then
      FAILED+=("$PROJECT:build")
    fi
  else
    if ! npx nx lint "$PROJECT" --quiet; then
      FAILED+=("$PROJECT:lint")
    fi
  fi
  echo ""
done

if [[ ${#FAILED[@]} -gt 0 ]]; then
  cat >&2 <<EOF
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[validate-on-stop] Failed:
EOF
  printf '  - %s\n' "${FAILED[@]}" >&2
  cat >&2 <<EOF
[validate-on-stop] Preserving touched project list for rerun.
  Fix the failures above, then retry.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF
  exit 2
fi

rm -f "$TOUCHED_FILE"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "[validate-on-stop] all touched projects passed"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
