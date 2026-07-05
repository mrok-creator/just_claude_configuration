#!/usr/bin/env bash
# PreToolUse guard for AI_FLOW_ROLE=executor.
# Denies Write/Edit/MultiEdit on test file paths.
# The test-file fence is enforced by path patterns — no checkpoint file needed.
#
# Required signal (one of):
#   AI_FLOW_ROLE=executor              (env var)
#   $CC_STATE_DIR/.flow-state.json {"role":"executor"}   (written by Lead before spawn)
#
# Input: JSON on stdin from Claude Code PreToolUse.
# Output: exit 0 = allow; exit 2 = deny.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/cc-config.sh"

# Primary signal: env var. Fallback: role-state file written by the /feature
# orchestrator (Lead) before spawning this subagent, because subagent spawns
# via Agent() cannot carry env vars.
_FLOW_ROLE="${AI_FLOW_ROLE:-}"
if [[ -z "$_FLOW_ROLE" ]]; then
  _STATE_FILE="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}/$CC_STATE_DIR/.flow-state.json"
  if [[ -f "$_STATE_FILE" ]]; then
    _FLOW_ROLE="$(jq -r '.role // empty' "$_STATE_FILE" 2>/dev/null || true)"
  fi
fi

if [[ "$_FLOW_ROLE" != "executor" ]]; then
  exit 0
fi

payload="$(cat)"
tool_name="$(printf '%s' "$payload" | jq -r '.tool_name // empty')"
case "$tool_name" in
  Write|Edit|MultiEdit|NotebookEdit) ;;
  *) exit 0 ;;
esac

file_path="$(printf '%s' "$payload" | jq -r '.tool_input.file_path // .tool_input.path // empty')"
if [[ -z "$file_path" ]]; then
  exit 0
fi

source "$(dirname "${BASH_SOURCE[0]}")/lib/denial-cap.sh"

main() {
# Normalize to repo-relative if absolute path inside the worktree.
rel="$file_path"
if [[ "$file_path" = /* ]]; then
  repo_root="$(git -C "$(dirname "$file_path")" rev-parse --show-toplevel 2>/dev/null || true)"
  if [[ -n "$repo_root" ]]; then
    rel="${file_path#"$repo_root"/}"
  fi
fi

# Block writes to test file paths — same globs as guard-test-author.sh allows.
test_re='^(tests/|.*/fixtures/|.*/mocks/|.*/__mocks__/|.*/__fixtures__/|.*/mock-factories/|.*/test-utils/)|.*\.(unit-|integration-|e2e-)?spec\.ts$'

if [[ "$rel" =~ $test_re ]]; then
  deny_msg="[guard-executor] DENIED write to test file: $file_path (role: executor). Tests are frozen — the Executor must NOT modify test files. Halt, report to Lead; Lead routes back to Test Author."
  cat >&2 <<EOF
[guard-executor] DENIED write to test file.
  path: $file_path
  role: executor
  Tests are frozen after the Test Author step. The Executor must NOT touch test
  files. Halt and report to Lead; Lead routes back to Test Author with
  justification. (enforced by guard-executor.sh — path guard)
EOF
  printf '{"decision":"block","reason":"%s"}\n' "$deny_msg"
  exit 2
fi

exit 0
}

SIG="$(denial_cap_signature "$payload")"
exec 3>&1
if OUT="$(main 2>&1 1>&3)"; then CODE=0; else CODE=$?; fi
exec 3>&-
denial_cap_gate "guard-executor" "$SIG" "security" "$CODE" "$OUT"
