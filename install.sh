#!/usr/bin/env bash
#
# install.sh — install just_claude_configuration into a target project.
#
# DESIGN: the installer is deliberately "dumb" — it copies files, auto-detects
# obvious stack facts, and registers MCP servers. Everything that requires
# UNDERSTANDING the codebase (CLAUDE.md generation/merging, convention tuning)
# is done by Claude itself via the /setup-project skill on first run — a model
# is better at reading a codebase than a shell script will ever be.
#
# USAGE:
#   bash install.sh /path/to/target-project [--no-mcp] [--force]
#
#   --no-mcp   skip MCP server registration (claude CLI not needed)
#   --force    overwrite files that already exist in the target's .claude/
#              (default: existing files are kept and reported)
#
# Supported platforms: macOS, Linux. Windows: WSL only (see README).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Classic (non-plugin) install assembles <target>/.claude/ from the plugin
# payload plus the settings templates. Prefer the plugin route when possible:
#   /plugin marketplace add mrok-creator/just_claude_configuration
#   /plugin install just-claude@just-claude-configuration
PAYLOAD="$SCRIPT_DIR/plugin"
TEMPLATES="$SCRIPT_DIR/templates"

log()  { printf '\033[1;34m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[install]\033[0m %s\n' "$*" >&2; }
fail() { printf '\033[1;31m[install]\033[0m %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# 0. Arguments and preconditions
# ---------------------------------------------------------------------------
TARGET="" ; NO_MCP=0 ; FORCE=0
for arg in "$@"; do
  case "$arg" in
    --no-mcp) NO_MCP=1 ;;
    --force)  FORCE=1 ;;
    -*)       fail "Unknown flag: $arg" ;;
    *)        TARGET="$arg" ;;
  esac
done
[ -n "$TARGET" ] || fail "Usage: bash install.sh /path/to/target-project [--no-mcp] [--force]"
[ -d "$TARGET" ] || fail "Target directory does not exist: $TARGET"
[ -d "$PAYLOAD" ] || fail "Payload not found at $PAYLOAD — run from a full clone of this repo."

TARGET="$(cd "$TARGET" && pwd)"
cd "$TARGET"

if ! git -C "$TARGET" rev-parse --show-toplevel >/dev/null 2>&1; then
  warn "Target is not a git repository — continuing, but version control is strongly recommended."
fi

command -v python3 >/dev/null 2>&1 || warn "python3 not found — hooks require python3 at runtime."
command -v node    >/dev/null 2>&1 || warn "node not found — some utilities (footprint measurement) require node."

log "Target project: $TARGET"

# ---------------------------------------------------------------------------
# 1. Copy payload -> .claude/ (skip-existing by default)
#    Plugin manifests (.claude-plugin/, hooks.json, .mcp.json) are plugin-mode
#    artifacts and are NOT copied; settings templates come from templates/.
# ---------------------------------------------------------------------------
COPIED=0 ; SKIPPED=0 ; SKIPPED_LIST=""
copy_one() { # <src> <rel-dst-under-.claude>
  local src="$1" rel="$2" dst="$TARGET/.claude/$2"
  if [ -e "$dst" ] && [ "$FORCE" -eq 0 ]; then
    SKIPPED=$((SKIPPED+1)); SKIPPED_LIST="$SKIPPED_LIST  $rel\n"
    return 0
  fi
  mkdir -p "$(dirname "$dst")"
  cp "$src" "$dst"
  COPIED=$((COPIED+1))
}
while IFS= read -r src; do
  rel="${src#"$PAYLOAD"/}"
  case "$rel" in
    .claude-plugin/*|.mcp.json|hooks/hooks.json) continue ;;
  esac
  copy_one "$src" "$rel"
done < <(find "$PAYLOAD" -type f | sort)
copy_one "$TEMPLATES/settings.json" "settings.json"
copy_one "$TEMPLATES/settings.local.example.json" "settings.local.example.json"
copy_one "$TEMPLATES/cc-config.env.example" "cc-config.env.example"

chmod +x "$TARGET/.claude/hooks/"*.sh "$TARGET/.claude/setup/"*.sh 2>/dev/null || true
log "Copied $COPIED files into .claude/ ($SKIPPED existing kept)."
if [ "$SKIPPED" -gt 0 ] && [ "$FORCE" -eq 0 ]; then
  printf '%b' "$SKIPPED_LIST" | head -20 | sed 's/^/           kept: /'
  log "Re-run with --force to overwrite kept files (review them first)."
fi

# ---------------------------------------------------------------------------
# 2. State home (.cc_settings) + task inbox + .gitignore entries
# ---------------------------------------------------------------------------
mkdir -p .cc_settings/.memory .cc_settings/_inbox
[ -f .cc_settings/_inbox/README.md ] || cat > .cc_settings/_inbox/README.md <<'EOF'
# Task inbox

Drop raw task material here for Claude Code to consume read-only:
specs, requirement notes, code snippets, logs, screenshots.
Contents are gitignored (transient); the folder is kept via .gitkeep.
EOF
: > .cc_settings/_inbox/.gitkeep

ensure_ignore() {
  local line="$1"
  if [ -f .gitignore ] && grep -qxF "$line" .gitignore; then return 0; fi
  echo "$line" >> .gitignore
}
ensure_ignore ".cc_settings/.memory/"
ensure_ignore ".cc_settings/_inbox/*"
ensure_ignore "!.cc_settings/_inbox/.gitkeep"
ensure_ignore "!.cc_settings/_inbox/README.md"
ensure_ignore ".claude/settings.local.json"
ensure_ignore ".claude/cc-config.env"
log "State home .cc_settings/ ready; .gitignore updated."

# ---------------------------------------------------------------------------
# 3. Stack auto-detection -> .claude/cc-config.env
# ---------------------------------------------------------------------------
if [ -f .claude/cc-config.env ] && [ "$FORCE" -eq 0 ]; then
  log "cc-config.env already exists — keeping it."
else
  PKG="npm"
  [ -f pnpm-lock.yaml ] && PKG="pnpm"
  [ -f yarn.lock ] && PKG="yarn"

  VALIDATE_MODE="off" ; VALIDATE_CMD=""
  if [ -f nx.json ]; then
    VALIDATE_MODE="nx"
  elif [ -f package.json ]; then
    HAS_LINT=$(grep -o '"lint"[[:space:]]*:' package.json || true)
    HAS_TSC=$(grep -o '"typecheck"[[:space:]]*:' package.json || true)
    if [ -n "$HAS_LINT$HAS_TSC" ]; then
      VALIDATE_MODE="command"
      [ -n "$HAS_LINT" ] && VALIDATE_CMD="$PKG run lint"
      [ -n "$HAS_TSC" ] && VALIDATE_CMD="${VALIDATE_CMD:+$VALIDATE_CMD && }$PKG run typecheck"
    fi
  fi

  MIGRATION_GUARD="off"
  if [ -f package.json ] && grep -qE '"(typeorm|prisma|sequelize|knex)"' package.json; then
    MIGRATION_GUARD="on"
  fi

  SRC_DIRS=""
  for d in apps libs packages src server tools config; do
    [ -d "$d" ] && SRC_DIRS="${SRC_DIRS:+$SRC_DIRS|}$d"
  done
  [ -n "$SRC_DIRS" ] || SRC_DIRS="src"

  sed -e "s|^CC_PKG_MANAGER=.*|CC_PKG_MANAGER=\"$PKG\"|" \
      -e "s|^CC_VALIDATE_MODE=.*|CC_VALIDATE_MODE=\"$VALIDATE_MODE\"|" \
      -e "s|^CC_VALIDATE_CMD=.*|CC_VALIDATE_CMD=\"$VALIDATE_CMD\"|" \
      -e "s|^CC_MIGRATION_GUARD=.*|CC_MIGRATION_GUARD=\"$MIGRATION_GUARD\"|" \
      -e "s|^CC_SOURCE_DIRS=.*|CC_SOURCE_DIRS=\"$SRC_DIRS\"|" \
      .claude/cc-config.env.example > .claude/cc-config.env
  log "Detected: pkg=$PKG validate=$VALIDATE_MODE${VALIDATE_CMD:+ ($VALIDATE_CMD)} migration-guard=$MIGRATION_GUARD src=[$SRC_DIRS]"
  log "Wrote .claude/cc-config.env (review and adjust — /setup-project will also verify it)."
fi

# ---------------------------------------------------------------------------
# 4. settings.local.json example
# ---------------------------------------------------------------------------
if [ ! -f .claude/settings.local.json ] && [ -f .claude/settings.local.example.json ]; then
  cp .claude/settings.local.example.json .claude/settings.local.json
  log "Created .claude/settings.local.json from example (personal, gitignored)."
fi

# ---------------------------------------------------------------------------
# 5. MCP servers (serena, basic-memory, context7)
# ---------------------------------------------------------------------------
if [ "$NO_MCP" -eq 1 ]; then
  log "Skipping MCP registration (--no-mcp). Run .claude/setup/configure-mcp.sh later."
elif ! command -v claude >/dev/null 2>&1; then
  warn "claude CLI not found — skipping MCP registration. Run .claude/setup/configure-mcp.sh after installing Claude Code."
else
  bash "$TARGET/.claude/setup/configure-mcp.sh" || warn "MCP configuration reported issues — see output above; re-run .claude/setup/configure-mcp.sh."
fi

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
echo
log "DONE. Next steps:"
log "  1. Review .claude/cc-config.env (stack detection results)."
log "  2. Open Claude Code in $TARGET and run: /setup-project"
log "     - generates or adapts CLAUDE.md, sets the response language,"
log "       verifies MCP servers and smoke-tests the hooks."
log "  3. Restart the Claude Code session so settings and hooks load."
