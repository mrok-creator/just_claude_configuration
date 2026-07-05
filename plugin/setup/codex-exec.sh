#!/usr/bin/env bash
#
# codex-exec.sh — Codex executor-swap wrapper for the /feature workflow.
#
# Codex is OPTIONAL: the /feature workflow uses it only when the user passes
# --codex AND the `codex` CLI is installed. Without it, the Test Author and
# CC-reviewer subagents own these steps (that is the default).
#
# WHAT IT DOES (spec §5):
#   --codex does NOT add steps; it swaps the EXECUTOR of two steps:
#     step 4 (tests)  -> Codex writes the tests
#     step 8 (review) -> Codex Verifier produces the verification report
#   This wrapper assembles the required context (intake.md + plan.md are
#   mandatory on BOTH steps, plus diff/rules as available), feeds it
#   to `codex exec`, and captures a STRUCTURED report via `--output-schema`.
#
# AVAILABILITY DETECT + FALLBACK (spec §5):
#   If the `codex` CLI is not on PATH, this wrapper exits 3 (EX_CODEX_UNAVAIL)
#   without doing anything. The /feature command treats exit 3 as the signal to
#   fall back to Claude Code (Test Author for step 4 / CC-reviewer for step 8)
#   and to note the fallback as a warning in summary.md.
#
# USAGE:
#   bash .claude/setup/codex-exec.sh --task <slug> --step tests   [--diff <file>]
#   bash .claude/setup/codex-exec.sh --task <slug> --step review  [--diff <file>]
#   bash .claude/setup/codex-exec.sh --check        # availability probe only (exit 0/3)
#
# OUTPUT:
#   step review -> writes <task-dir>/review-report.json  (printed path on stdout)
#   step tests  -> writes <task-dir>/codex-tests-report.json (Codex narrates the
#                  test files it authored; the files themselves land in the repo)
#
# EXIT CODES:
#   0  success
#   2  usage / argument error
#   3  codex CLI unavailable (caller must fall back to Claude Code)
#   4  required context missing (intake.md / plan.md absent)
#   5  codex exec returned a non-zero status
#
set -uo pipefail

readonly EX_USAGE=2
readonly EX_CODEX_UNAVAIL=3
readonly EX_CONTEXT_MISSING=4
readonly EX_CODEX_FAIL=5

log()  { printf '\033[1;34m[codex-exec]\033[0m %s\n' "$*" >&2; }
warn() { printf '\033[1;33m[codex-exec]\033[0m %s\n' "$*" >&2; }
fail() { printf '\033[1;31m[codex-exec]\033[0m %s\n' "$*" >&2; }

# --- Resolve repo root (works from main repo or any worktree) -----------------
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$REPO_ROOT" ]; then
  REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi

# --- Availability probe -------------------------------------------------------
codex_available() {
  command -v codex >/dev/null 2>&1
}

# --- Parse args ---------------------------------------------------------------
TASK_SLUG=""
STEP=""
DIFF_FILE=""
CHECK_ONLY=0

while [ $# -gt 0 ]; do
  case "$1" in
    --task)  TASK_SLUG="${2:-}"; shift 2 ;;
    --step)  STEP="${2:-}"; shift 2 ;;
    --diff)  DIFF_FILE="${2:-}"; shift 2 ;;
    --check) CHECK_ONLY=1; shift ;;
    -h|--help)
      sed -n '2,44p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) fail "Unknown argument: $1"; exit $EX_USAGE ;;
  esac
done

# --- --check: availability probe only -----------------------------------------
if [ "$CHECK_ONLY" -eq 1 ]; then
  if codex_available; then
    log "codex CLI available: $(command -v codex)"
    exit 0
  fi
  warn "codex CLI NOT available — caller should fall back to Claude Code."
  exit $EX_CODEX_UNAVAIL
fi

# --- Availability gate (spec §5: detect on start, fall back to CC) -------------
if ! codex_available; then
  warn "codex CLI not found on PATH. Falling back to Claude Code (Test Author / CC-reviewer)."
  exit $EX_CODEX_UNAVAIL
fi

# --- Validate args ------------------------------------------------------------
if [ -z "$TASK_SLUG" ]; then
  fail "--task <slug> is required."; exit $EX_USAGE
fi
case "$STEP" in
  tests|review) ;;
  *) fail "--step must be 'tests' or 'review' (got: '${STEP:-}')."; exit $EX_USAGE ;;
esac

# Task artifacts are project-local under .cc_settings/.memory/tasks/<slug>/
# (spec §10; matches feature.md / lead.md / presets.yml). The planner/architect
# already wrote intake.md + plan.md there, so Codex reads them in place and
# writes its report alongside.
TASK_DIR="$REPO_ROOT/.cc_settings/.memory/tasks/$TASK_SLUG"

INTAKE="$TASK_DIR/intake.md"
PLAN="$TASK_DIR/plan.md"

# --- Mandatory context: intake.md + plan.md (spec §5) -------------------------
if [ ! -f "$INTAKE" ] || [ ! -f "$PLAN" ]; then
  fail "Mandatory Codex context missing. Both must exist:"
  fail "  intake.md: $INTAKE  ($( [ -f "$INTAKE" ] && echo present || echo MISSING ))"
  fail "  plan.md:   $PLAN    ($( [ -f "$PLAN" ] && echo present || echo MISSING ))"
  exit $EX_CONTEXT_MISSING
fi

# --- Working files ------------------------------------------------------------
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/codex-exec.XXXXXX")"
cleanup() { rm -rf "$WORK_DIR"; }
trap cleanup EXIT

SCHEMA_FILE="$WORK_DIR/output-schema.json"
PROMPT_FILE="$WORK_DIR/prompt.md"

# --- Output schema for the structured report (--output-schema) ----------------
cat > "$SCHEMA_FILE" <<'JSON'
{
  "type": "object",
  "additionalProperties": false,
  "required": ["step", "verdict", "checks", "findings", "summary"],
  "properties": {
    "step": { "type": "string", "enum": ["tests", "review"] },
    "verdict": { "type": "string", "enum": ["PASS", "WARNINGS", "BLOCKED"] },
    "checks": {
      "type": "array",
      "items": {
        "type": "object",
        "additionalProperties": false,
        "required": ["name", "status", "detail"],
        "properties": {
          "name": { "type": "string" },
          "status": { "type": "string", "enum": ["pass", "fail", "skipped"] },
          "detail": { "type": ["string", "null"] }
        }
      }
    },
    "findings": {
      "type": "array",
      "items": {
        "type": "object",
        "additionalProperties": false,
        "required": ["severity", "area", "message", "route_to"],
        "properties": {
          "severity": { "type": "string", "enum": ["blocking", "warning", "info"] },
          "area": { "type": "string", "enum": ["architecture", "requirements", "tests", "bug", "docs"] },
          "message": { "type": "string" },
          "route_to": { "type": ["string", "null"], "enum": ["architect", "planner", "test-author", "executor", "lead", null] }
        }
      }
    },
    "summary": { "type": "string" }
  }
}
JSON

# --- Assemble the prompt + context -------------------------------------------
{
  if [ "$STEP" = "tests" ]; then
    cat <<EOF
You are the Codex test author for an independent test-writing pass in this
repository. Translate the APPROVED acceptance criteria and test intent into
tests. Create or adjust fixtures/mocks only. Do NOT write production code, edit
configuration, alter migrations, or weaken tests to match existing logic. Stop
when the tests encode the approved behavior. Return the structured report
describing the test files you authored and why; verdict PASS when the test set
faithfully encodes the intent, BLOCKED if the intent is under-specified.
EOF
  else
    cat <<EOF
You are the Codex Verifier performing INDEPENDENT verification (spec §4/§8).
Read the architecture (plan.md), acceptance criteria + test intent (intake.md),
and the diff. Verify:
  - the implementation matches the approved architecture and acceptance criteria;
  - Test Author did not touch business logic and Executor did not modify test files.
Run your own build/lint/tests where possible and record them under "checks".
Do NOT silently change code or tests. Do NOT approve when checks are missing or
ambiguous. Classify findings (blocking/warning/info) and route each blocking
finding to the owner role. verdict: PASS / WARNINGS / BLOCKED.
EOF
  fi

  echo
  echo "===== CONTEXT: intake.md (step 1) ====="
  cat "$INTAKE"
  echo
  echo "===== CONTEXT: plan.md (step 2) ====="
  cat "$PLAN"

  # Project rules give Codex the architecture conventions to verify against.
  if [ -d "$REPO_ROOT/.claude/rules" ]; then
    echo
    echo "===== CONTEXT: project rule files (names) ====="
    ls -1 "$REPO_ROOT/.claude/rules" 2>/dev/null || true
  fi

  # Diff: explicit file if given, else live working-tree diff.
  echo
  echo "===== CONTEXT: diff ====="
  if [ -n "$DIFF_FILE" ] && [ -f "$DIFF_FILE" ]; then
    cat "$DIFF_FILE"
  else
    git -C "$REPO_ROOT" diff HEAD 2>/dev/null || echo "(no diff available)"
  fi
} > "$PROMPT_FILE"

# --- Decide where the structured report goes ----------------------------------
if [ "$STEP" = "review" ]; then
  REPORT_OUT="$TASK_DIR/review-report.json"
else
  REPORT_OUT="$TASK_DIR/codex-tests-report.json"
fi
mkdir -p "$TASK_DIR"

# --- Invoke codex exec --------------------------------------------------------
# `codex exec` runs non-interactively; --output-schema constrains the final
# message to our JSON schema. Flags kept minimal/portable; prompt on stdin.
log "Running codex exec for step '$STEP' (task: $TASK_SLUG)"
set +e
if [ "$STEP" = "tests" ]; then
  codex exec \
    --sandbox workspace-write \
    --output-schema "$SCHEMA_FILE" \
    --output-last-message "$REPORT_OUT" \
    - < "$PROMPT_FILE"
else
  codex exec \
    --output-schema "$SCHEMA_FILE" \
    --output-last-message "$REPORT_OUT" \
    - < "$PROMPT_FILE"
fi
CODEX_STATUS=$?

if [ "$CODEX_STATUS" -ne 0 ]; then
  fail "codex exec returned status $CODEX_STATUS."
  exit $EX_CODEX_FAIL
fi

if [ ! -s "$REPORT_OUT" ]; then
  fail "codex exec produced no report at $REPORT_OUT."
  exit $EX_CODEX_FAIL
fi

log "Structured report written: $REPORT_OUT"
printf '%s\n' "$REPORT_OUT"
exit 0
