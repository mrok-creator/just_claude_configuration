#!/usr/bin/env bash
#
# cc-mode.sh — Launch `claude` in the mode recorded in .claude/.cc-mode.
#
# WHAT IT DOES:
#   Reads the single source-of-truth file .claude/.cc-mode and starts Claude Code
#   with the model that the mode maps to. Any extra arguments are passed straight
#   through to `claude`.
#
# MODE -> MAIN-LOOP MODEL (this is the ONLY thing the launcher controls):
#   performance -> opus      (newest Opus every turn)
#   balanced    -> opusplan  (Opus plans, Sonnet executes)        [default]
#   efficient   -> sonnet    (Sonnet logic; haiku navigation via subagent
#                             frontmatter; Opus planning on demand)
#
# IMPORTANT — the model is set at LAUNCH, here. A hook CANNOT switch the model of
# a running session; Claude Code fixes the model when it starts. To change the
# model: edit .claude/.cc-mode, then relaunch with this script. The same .cc-mode
# value is also what the workflow engine reads at runtime.
#
# This launcher sets ONLY the main-session model (--model). It deliberately does
# NOT export CLAUDE_CODE_SUBAGENT_MODEL — a global subagent override is avoided
# by convention, so subagent models keep coming from each subagent's own
# frontmatter (navigation = haiku, quality = sonnet) in every mode.
#
# USAGE (from anywhere inside the repo or a worktree):
#   bash .claude/setup/cc-mode.sh              # launch in the recorded mode
#   bash .claude/setup/cc-mode.sh --print      # print resolved mode+model, do not launch
#   bash .claude/setup/cc-mode.sh -- <args>    # forward args to `claude`
#
# Override the mode for a single launch without editing the file:
#   CC_MODE=performance bash .claude/setup/cc-mode.sh
#
set -euo pipefail

log()  { printf '\033[1;34m[cc-mode]\033[0m %s\n' "$*" >&2; }
fail() { printf '\033[1;31m[cc-mode]\033[0m %s\n' "$*" >&2; exit 1; }

# --- Resolve repo root (works from the main repo or any worktree) -------------
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$REPO_ROOT" ]; then
  # Fall back to the directory two levels up from this script (.claude/setup/..).
  REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi

MODE_FILE="$REPO_ROOT/.claude/.cc-mode"
ENV_FILE="$REPO_ROOT/.claude/setup/.env"

# --- Determine the mode -------------------------------------------------------
# Precedence: CC_MODE env override > .cc-mode file > DEFAULT_MODE in .env > balanced
MODE="${CC_MODE:-}"
if [ -z "$MODE" ] && [ -f "$MODE_FILE" ]; then
  MODE="$(tr -d '[:space:]' < "$MODE_FILE")"
fi
if [ -z "$MODE" ] && [ -f "$ENV_FILE" ]; then
  # shellcheck disable=SC1090
  MODE="$(. "$ENV_FILE" >/dev/null 2>&1; printf '%s' "${DEFAULT_MODE:-}")"
fi
MODE="${MODE:-balanced}"

# --- Map mode -> model --------------------------------------------------------
case "$MODE" in
  performance) MODEL="opus" ;;
  balanced)    MODEL="opusplan" ;;
  efficient)   MODEL="sonnet" ;;
  *) fail "Unknown mode '$MODE' in $MODE_FILE (expected: performance | balanced | efficient)" ;;
esac

# --- --print: report and exit without launching ------------------------------
PRINT_ONLY=0
PASSTHROUGH=()
for arg in "$@"; do
  case "$arg" in
    --print) PRINT_ONLY=1 ;;
    --)      ;;                       # separator; ignore
    *)       PASSTHROUGH+=("$arg") ;;
  esac
done

log "mode=$MODE  ->  --model $MODEL   (source: ${MODE_FILE#"$REPO_ROOT"/})"
if [ "$PRINT_ONLY" -eq 1 ]; then
  printf '%s\t%s\n' "$MODE" "$MODEL"
  exit 0
fi

command -v claude >/dev/null 2>&1 || fail "'claude' CLI not found on PATH."

# --- Launch -------------------------------------------------------------------
cd "$REPO_ROOT"
if [ "${#PASSTHROUGH[@]}" -gt 0 ]; then
  exec claude --model "$MODEL" "${PASSTHROUGH[@]}"
else
  exec claude --model "$MODEL"
fi
