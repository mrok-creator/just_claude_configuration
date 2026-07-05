#!/usr/bin/env bash
# PreToolUse guard for AI_FLOW_ROLE=test-author.
# Denies Write/Edit/MultiEdit on any path outside the allowed test scope.
#
# Input: JSON on stdin from Claude Code PreToolUse hook event.
# Output: exit 0 = allow; exit 2 = deny (stderr reason surfaces to the agent).
#
# Allowed write paths (any of these globs match relative-to-repo path):
#   tests/**
#   **/*.spec.ts
#   **/*.unit-spec.ts
#   **/*.integration-spec.ts
#   **/*.e2e-spec.ts
#   **/fixtures/**
#   **/mocks/**
#   **/__mocks__/**
#   **/__fixtures__/**
#   **/mock-factories/**
#   **/test-utils/**
#   $CC_STATE_DIR/**  (workflow state — see below)

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

if [[ "$_FLOW_ROLE" != "test-author" ]]; then
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

# $CC_STATE_DIR/ is exempt: workflow state (flow-state.json) and task
# artifacts live there — without this the Lead cannot clear the role file
# while the fence is active (verified deadlock).
_STATE_DIR_RE="${CC_STATE_DIR//./\\.}"
allowed_re="^(${_STATE_DIR_RE}/|tests/|.*/fixtures/|.*/mocks/|.*/__mocks__/|.*/__fixtures__/|.*/mock-factories/|.*/test-utils/)|.*\.(unit-|integration-|e2e-)?spec\.ts\$"

if [[ "$rel" =~ $allowed_re ]]; then
  exit 0
fi

deny_msg="[guard-test-author] DENIED write to non-test path: $rel (role: test-author). Allowed: tests/**, **/*.spec.ts, **/*.{unit-,integration-,e2e-}spec.ts, **/fixtures/**, **/mocks/**, **/__mocks__/**, **/mock-factories/**, **/test-utils/**. If production code must change, this is Executor's job — halt and route to Lead."
cat >&2 <<EOF
[guard-test-author] DENIED write to non-test path.
  path: $rel
  role: test-author
  allowed: tests/**, **/*.spec.ts, **/*.unit-spec.ts, **/*.integration-spec.ts,
           **/*.e2e-spec.ts, **/fixtures/**, **/mocks/**, **/__mocks__/**,
           **/__fixtures__/**, **/mock-factories/**, **/test-utils/**
  Action: if production code must change, this is Executor's job. Halt and
          ask Lead to route the need accordingly.
EOF
printf '{"decision":"block","reason":"%s"}\n' "$deny_msg"
exit 2
}

SIG="$(denial_cap_signature "$payload")"
exec 3>&1
if OUT="$(main 2>&1 1>&3)"; then CODE=0; else CODE=$?; fi
exec 3>&-
denial_cap_gate "guard-test-author" "$SIG" "security" "$CODE" "$OUT"
