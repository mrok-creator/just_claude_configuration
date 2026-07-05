#!/usr/bin/env bash
#
# new-worktree.sh — Spin up a git worktree for a feature with the full Claude
#                   Code foundation ready in one command.
#
# WHY THIS EXISTS:
#   `git worktree add` only checks out TRACKED files. The project's Claude
#   foundation is gitignored (`.claude/*` and `.cc_settings/*`), so a fresh
#   worktree is missing CLAUDE.md, the whole .claude/ dir (rules, docs, hooks,
#   skills, setup, .env, .cc-mode, .cc-context-home), .cc_settings/ (runtime
#   state), and .serena/. This copies that out-of-git config from the main
#   repo, copies .mcp.json, then REWRITES the worktree-specific paths (serena
#   --project, .env PROJECT_ROOT) so the worktree has a working foundation
#   immediately — no `claude mcp add`, no network.
#
#   WHAT IS COPIED vs EXCLUDED:
#     .claude/           — whole tree EXCEPT:
#       worktrees/       — per-repo worktree tracking; not relevant in a worktree
#     .cc_settings/      — runtime state (memory, inbox, flow-state), copied EXCEPT:
#       .memory/         — per-session state (buffer, STATE, checkpoints); worktree
#                          starts fresh; harness creates the dir on first write
#     .serena/           — project config EXCEPT:
#       cache/           — LSP symbol index; path-bound to main repo; Serena rebuilds
#                          it automatically on first use in the worktree
#
#   SERENA_HOME and BASIC_MEMORY_HOME point at the shared CC_CONTEXT_HOME library
#   (same machine), so they stay valid in the worktree and are NOT rewritten.
#   .cc-context-home is carried inside .claude/ and is $HOME-relative, so it is
#   already correct in the worktree.
#
# USAGE (run from anywhere inside the repo or a worktree):
#   bash .claude/setup/new-worktree.sh <branch> [dir-name]
#
# EXAMPLE:
#   bash .claude/setup/new-worktree.sh feat/ABC-123--my-feature ABC-123
#
# Overrides (optional env, else read from .claude/setup/.env):
#   WT_BASE / WORKTREE_BASE   default: <parent-of-main-repo>/<repo-name>-worktrees
#
set -euo pipefail

BRANCH="${1:-}"
[ -n "$BRANCH" ] || { echo "Usage: new-worktree.sh <branch> [dir-name]" >&2; exit 2; }

# Worktree dir name: arg2, else branch with '/' and spaces collapsed to '-'
DIRNAME="${2:-$(printf '%s' "$BRANCH" | tr '/ ' '--')}"

log()  { printf '\033[1;34m[worktree]\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m[worktree]\033[0m %s\n' "$*" >&2; exit 1; }

command -v git >/dev/null 2>&1 || fail "git not found."

# Resolve the MAIN repo root (source of gitignored config), even when invoked
# from inside another worktree (git-common-dir points at the main .git).
GIT_COMMON="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" \
  || fail "Not inside a git repository."
MAIN_REPO="$(cd "$(dirname "$GIT_COMMON")" && pwd)"
REPO_NAME="$(basename "$MAIN_REPO")"
log "Main repo: $MAIN_REPO"

# Load .env from the main repo to resolve WORKTREE_BASE (falls back gracefully).
ENV_FILE="$MAIN_REPO/.claude/setup/.env"
if [ -f "$ENV_FILE" ]; then
  set -a; # shellcheck disable=SC1090
  . "$ENV_FILE"; set +a
fi
WT_BASE="${WT_BASE:-${WORKTREE_BASE:-}}"
[ -n "$WT_BASE" ] || WT_BASE="$(dirname "$MAIN_REPO")/${REPO_NAME}-worktrees"
WT_DIR="$WT_BASE/$DIRNAME"
mkdir -p "$WT_BASE"
[ -e "$WT_DIR" ] && fail "Target already exists: $WT_DIR"

# ---------------------------------------------------------------------------
# 1. Create the worktree (new branch, or attach existing branch)
# ---------------------------------------------------------------------------
if git -C "$MAIN_REPO" show-ref --verify --quiet "refs/heads/$BRANCH"; then
  log "Branch '$BRANCH' exists — attaching worktree."
  git -C "$MAIN_REPO" worktree add "$WT_DIR" "$BRANCH"
else
  log "Creating worktree + new branch '$BRANCH'."
  git -C "$MAIN_REPO" worktree add -b "$BRANCH" "$WT_DIR"
fi

# ---------------------------------------------------------------------------
# 2. Copy gitignored Claude foundation from main repo -> worktree
# ---------------------------------------------------------------------------
log "Copying gitignored foundation from main repo..."

# Helper: copy a simple file or dir (no exclusion needed)
copy_item() {
  local rel="$1"
  [ -e "$MAIN_REPO/$rel" ] || return 0
  local destdir="$WT_DIR/$(dirname "$rel")"
  mkdir -p "$destdir"
  if command -v rsync >/dev/null 2>&1; then
    rsync -a "$MAIN_REPO/$rel" "$destdir/"
  else
    cp -R "$MAIN_REPO/$rel" "$destdir/"
  fi
  log "  copied: $rel"
}

# 2a. CLAUDE.md
copy_item "CLAUDE.md"

# 2b. .claude/ — copy entire tree EXCEPT worktrees/
#     worktrees/ = per-repo worktree tracking data — not meaningful inside a worktree
if [ -d "$MAIN_REPO/.claude" ]; then
  mkdir -p "$WT_DIR/.claude"
  if command -v rsync >/dev/null 2>&1; then
    rsync -a \
      --exclude='worktrees/' \
      "$MAIN_REPO/.claude/" "$WT_DIR/.claude/"
  else
    cp -R "$MAIN_REPO/.claude/" "$WT_DIR/.claude/"
    rm -rf "$WT_DIR/.claude/worktrees"
  fi
  mkdir -p "$WT_DIR/.claude/worktrees"
  log "  copied: .claude/"
  log "    included: rules/ docs/ skills/ hooks/ commands/ agents/ setup/ output-styles/"
  log "              workflow/ settings.json settings.local.json"
  log "    excluded: worktrees/ (tracking data — not applicable inside a worktree)"
fi

# 2b2. .cc_settings/ — runtime state (memory, inbox, flow-state); copy entire
#      tree EXCEPT .memory/
#      .memory/ = per-session state (buffer, STATE, checkpoints) — worktree starts fresh
if [ -d "$MAIN_REPO/.cc_settings" ]; then
  mkdir -p "$WT_DIR/.cc_settings"
  if command -v rsync >/dev/null 2>&1; then
    rsync -a \
      --exclude='.memory/' \
      "$MAIN_REPO/.cc_settings/" "$WT_DIR/.cc_settings/"
  else
    cp -R "$MAIN_REPO/.cc_settings/" "$WT_DIR/.cc_settings/"
    rm -rf "$WT_DIR/.cc_settings/.memory"
  fi
  # Create fresh empty dir so harness tools can write without checking existence
  mkdir -p "$WT_DIR/.cc_settings/.memory"
  log "  copied: .cc_settings/"
  log "    included: _inbox/ .flow-state.json"
  log "    excluded: .memory/ (session state — worktree starts fresh)"
fi

# 2c. .mcp.json — carried, then serena --project rewritten below
copy_item ".mcp.json"

# 2d. .serena/ — project config EXCEPT cache/ (LSP index is path-bound to main repo)
if [ -d "$MAIN_REPO/.serena" ]; then
  mkdir -p "$WT_DIR/.serena"
  if command -v rsync >/dev/null 2>&1; then
    rsync -a \
      --exclude='cache/' \
      "$MAIN_REPO/.serena/" "$WT_DIR/.serena/"
  else
    cp -R "$MAIN_REPO/.serena/" "$WT_DIR/.serena/"
    rm -rf "$WT_DIR/.serena/cache"
  fi
  log "  copied: .serena/"
  log "    included: project.yml project.local.yml memories/"
  log "    excluded: cache/ (LSP symbol index — rebuilt automatically by Serena)"
fi

# ---------------------------------------------------------------------------
# 3. Rewrite worktree-specific paths so the foundation points at THIS worktree
# ---------------------------------------------------------------------------
# 3a. .mcp.json: serena --project -> worktree path (preserve everything else).
if [ -f "$WT_DIR/.mcp.json" ]; then
  # Use sed to rewrite the serena --project path inline (avoids python dependency)
  # Strategy: find the line containing the main repo path in the args array and replace it.
  ESCAPED_MAIN="$(printf '%s\n' "$MAIN_REPO" | sed 's|[[\.*^$()+?{|]|\\&|g')"
  ESCAPED_WT="$(printf '%s\n' "$WT_DIR" | sed 's|[&/]|\\&|g')"
  sed -i.bak "s|\"$ESCAPED_MAIN\"|\"$WT_DIR\"|g" "$WT_DIR/.mcp.json" \
    && rm -f "$WT_DIR/.mcp.json.bak"
  log "  rewrote: .mcp.json serena --project -> $WT_DIR"
else
  log "  note: no .mcp.json in main repo to copy; configure MCP in the worktree manually."
fi

# 3b. .env: PROJECT_ROOT default -> worktree path (so later setup in the
#     worktree derives the right project). Keeps the ${PROJECT_ROOT:-...} form.
WT_ENV="$WT_DIR/.claude/setup/.env"
if [ -f "$WT_ENV" ]; then
  ESCAPED_WT_SED="$(printf '%s\n' "$WT_DIR" | sed 's|[&/]|\\&|g')"
  sed -i.bak \
    "s|^PROJECT_ROOT=.*$|PROJECT_ROOT=\"\${PROJECT_ROOT:-$ESCAPED_WT_SED}\"|" \
    "$WT_ENV" && rm -f "$WT_ENV.bak"
  log "  rewrote: .claude/setup/.env PROJECT_ROOT -> $WT_DIR"
fi

# 3c. .serena/project.yml: rewrite project_name so the worktree gets a unique
#     Serena project slot. Serena keys projects by name — leaving it as the main
#     repo's name causes the worktree and main repo to collide.
SERENA_PROJECT_YML="$WT_DIR/.serena/project.yml"
if [ -f "$SERENA_PROJECT_YML" ]; then
  WT_PROJECT_NAME="${REPO_NAME}-${DIRNAME}"
  sed -i.bak "s|^project_name:.*$|project_name: \"$WT_PROJECT_NAME\"|" \
    "$SERENA_PROJECT_YML" && rm -f "$SERENA_PROJECT_YML.bak"
  log "  rewrote: .serena/project.yml project_name -> $WT_PROJECT_NAME"
fi

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
echo
log "============================================================"
log "DONE — worktree is ready."
log "============================================================"
log "  Worktree : $WT_DIR"
log "  Branch   : $BRANCH"
echo
log "Next steps:"
log "  cd \"$WT_DIR\" && bash .claude/setup/cc-mode.sh   (launch in recorded mode)"
log "  cat \"$WT_DIR/.mcp.json\"                          (verify serena --project)"
echo
log "Serena: project_name rewritten to \"${REPO_NAME}-${DIRNAME}\" (unique slot)."
log "        Onboarding memories copied from main repo."
log "        .serena/cache/ was excluded — Serena rebuilds it on first use."
log "        If Serena misbehaves, delete \"$WT_DIR/.serena/\" and let it re-onboard."
echo
log "Teardown: bash .claude/setup/remove-worktree.sh \"$DIRNAME\""
