#!/usr/bin/env bash
#
# configure-mcp.sh — register the MCP servers this configuration relies on.
# Idempotent: already-registered servers are skipped.
#
# Servers:
#   serena       (project scope) — semantic code navigation (LSP); nav-guard
#                redirects symbol searches here. Requires `uv` (uvx).
#   basic-memory (user scope)    — long-term knowledge store used by the
#                memory contour (/learn-process). Requires basic-memory CLI
#                or runs via uvx.
#   context7     (user scope)    — up-to-date library documentation lookup.
#                Requires node/npx.
#
# Data homing: serena and basic-memory support relocating their data via env
# vars baked into the registration. Default home: ~/.cc_home (override with
# CC_HOME_DIR=... before running).
#
# USAGE (from the target repo root):
#   bash .claude/setup/configure-mcp.sh [--no-context7] [--no-basic-memory]
set -euo pipefail

log()  { printf '\033[1;34m[mcp]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[mcp]\033[0m %s\n' "$*" >&2; }
fail() { printf '\033[1;31m[mcp]\033[0m %s\n' "$*" >&2; exit 1; }

NO_CONTEXT7=0 ; NO_BM=0
for arg in "$@"; do
  case "$arg" in
    --no-context7)     NO_CONTEXT7=1 ;;
    --no-basic-memory) NO_BM=1 ;;
    *) fail "Unknown flag: $arg" ;;
  esac
done

command -v claude >/dev/null 2>&1 || fail "'claude' CLI not found — install Claude Code first."
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$REPO_ROOT"

CC_HOME_DIR="${CC_HOME_DIR:-$HOME/.cc_home}"
SERENA_HOME_DIR="$CC_HOME_DIR/serena"
BM_HOME_DIR="$CC_HOME_DIR/basic-memory/knowledge"

mcp_exists() { claude mcp list 2>/dev/null | grep -qiE "(^|[[:space:]])$1([[:space:]:]|$)"; }

# --- serena (project scope) -------------------------------------------------
if mcp_exists "serena"; then
  log "serena already registered — skipping."
elif ! command -v uv >/dev/null 2>&1 && ! command -v uvx >/dev/null 2>&1; then
  warn "uv/uvx not found — skipping serena. Install uv (https://docs.astral.sh/uv/), then re-run."
  warn "Note: with serena absent, set CC_NAV_GUARD=\"off\" in .claude/cc-config.env."
else
  mkdir -p "$SERENA_HOME_DIR"
  log "Registering serena (SERENA_HOME -> $SERENA_HOME_DIR, project: $REPO_ROOT)..."
  claude mcp add serena -e SERENA_HOME="$SERENA_HOME_DIR" -- \
    uvx --from git+https://github.com/oraios/serena \
    serena start-mcp-server --context ide-assistant --project "$REPO_ROOT"
  log "serena registered. First start indexes the repo (one-time)."
fi

# --- basic-memory (user scope) ----------------------------------------------
if [ "$NO_BM" -eq 1 ]; then
  log "Skipping basic-memory (--no-basic-memory). The memory contour (/learn-process) will be inactive."
elif mcp_exists "basic-memory"; then
  log "basic-memory already registered — skipping."
elif command -v basic-memory >/dev/null 2>&1; then
  mkdir -p "$BM_HOME_DIR"
  log "Registering basic-memory (BASIC_MEMORY_HOME -> $BM_HOME_DIR)..."
  claude mcp add basic-memory -s user -e BASIC_MEMORY_HOME="$BM_HOME_DIR" -- basic-memory mcp
elif command -v uvx >/dev/null 2>&1; then
  mkdir -p "$BM_HOME_DIR"
  log "Registering basic-memory via uvx (BASIC_MEMORY_HOME -> $BM_HOME_DIR)..."
  claude mcp add basic-memory -s user -e BASIC_MEMORY_HOME="$BM_HOME_DIR" -- uvx basic-memory mcp
else
  warn "basic-memory CLI and uvx not found — skipping. Install basic-memory (https://github.com/basicmachines-co/basic-memory), then re-run."
fi

# --- context7 (user scope) ---------------------------------------------------
if [ "$NO_CONTEXT7" -eq 1 ]; then
  log "Skipping context7 (--no-context7)."
elif mcp_exists "context7"; then
  log "context7 already registered — skipping."
elif command -v npx >/dev/null 2>&1; then
  log "Registering context7 (library docs lookup)..."
  claude mcp add context7 -s user -- npx -y @upstash/context7-mcp
else
  warn "npx not found — skipping context7."
fi

echo
log "Verify with: claude mcp list"
log "Servers needing interactive auth (if you add any later, e.g. hosted MCPs)"
log "must be authenticated inside Claude Code via /mcp — that step cannot be automated."
