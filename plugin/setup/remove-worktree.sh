#!/usr/bin/env bash
#
# remove-worktree.sh — Tear down a git worktree cleanly.
#
# Removes the working directory (including gitignored config copies), deregisters
# the worktree from git, and prunes stale entries. Use --force because the worktree
# contains gitignored files (copied .claude/, .mcp.json, .serena/, etc.) that git
# considers untracked.
#
# USAGE:
#   bash .claude/setup/remove-worktree.sh <dir-name-or-full-path>
#
# EXAMPLES:
#   bash .claude/setup/remove-worktree.sh ABC-123
#   bash .claude/setup/remove-worktree.sh /path/to/<repo-name>-worktrees/ABC-123
#
set -euo pipefail

WT_REF="${1:-}"
[ -n "$WT_REF" ] || { echo "Usage: remove-worktree.sh <dir-name-or-full-path>" >&2; exit 2; }

log()  { printf '\033[1;34m[worktree]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[worktree]\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m[worktree]\033[0m %s\n' "$*" >&2; exit 1; }

command -v git >/dev/null 2>&1 || fail "git not found."

# Resolve main repo root (works from any worktree too)
GIT_COMMON="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" \
  || fail "Not inside a git repository."
MAIN_REPO="$(cd "$(dirname "$GIT_COMMON")" && pwd)"
REPO_NAME="$(basename "$MAIN_REPO")"
log "Main repo: $MAIN_REPO"

# Load WT_BASE from .env (same logic as new-worktree.sh)
ENV_FILE="$MAIN_REPO/.claude/setup/.env"
if [ -f "$ENV_FILE" ]; then
  set -a; # shellcheck disable=SC1090
  . "$ENV_FILE"; set +a
fi
WT_BASE="${WT_BASE:-${WORKTREE_BASE:-}}"
[ -n "$WT_BASE" ] || WT_BASE="$(dirname "$MAIN_REPO")/${REPO_NAME}-worktrees"

# Resolve the full worktree path
if [ -d "$WT_REF" ]; then
  WT_DIR="$(cd "$WT_REF" && pwd)"
elif [ -d "$WT_BASE/$WT_REF" ]; then
  WT_DIR="$(cd "$WT_BASE/$WT_REF" && pwd)"
else
  fail "Worktree not found: '$WT_REF'"$'\n'"  Tried: $WT_BASE/$WT_REF"
fi

# Safety: refuse to remove the main repo
[ "$WT_DIR" != "$MAIN_REPO" ] || fail "Refusing to remove the main repository: $MAIN_REPO"

# Confirm the target is a registered git worktree (not an arbitrary directory)
if ! git -C "$MAIN_REPO" worktree list --porcelain | grep -qF "worktree $WT_DIR"; then
  fail "'$WT_DIR' is not a registered git worktree."$'\n'"  Run: git worktree list"
fi

log "Removing worktree: $WT_DIR"

# --force is required because the worktree contains gitignored config copies
# (.claude/, .mcp.json, .serena/, etc.) that git treats as untracked/dirty.
git -C "$MAIN_REPO" worktree remove --force "$WT_DIR"

# Prune any stale worktree metadata in .git/worktrees/
git -C "$MAIN_REPO" worktree prune
log "Pruned stale worktree metadata."

# Verify no leftover
if [ -e "$WT_DIR" ]; then
  warn "Directory still exists (possibly a git worktree remove limitation)."
  warn "Remove manually: rm -rf \"$WT_DIR\""
  exit 1
fi

echo
log "============================================================"
log "DONE — worktree removed cleanly."
log "============================================================"
log "  Removed  : $WT_DIR"
log "  Verified : no leftover directory"
git -C "$MAIN_REPO" worktree list
