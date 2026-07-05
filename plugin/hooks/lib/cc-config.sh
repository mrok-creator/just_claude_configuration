#!/usr/bin/env bash
# Shared configuration loader for all hooks — SOURCE this file, do not execute.
#
# Loads "$CLAUDE_PROJECT_DIR/.claude/cc-config.env" if present, then fills in
# safe defaults for every CC_* knob. Values already present in the environment
# or set by cc-config.env win over the defaults below.
#
# Idempotent: safe to source multiple times within one hook invocation
# (guard scripts and lib/denial-cap.sh may both source it).

if [[ -n "${_CC_CONFIG_LOADED:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
_CC_CONFIG_LOADED=1

_CC_CONFIG_PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
_CC_CONFIG_FILE="$_CC_CONFIG_PROJECT_DIR/.claude/cc-config.env"

if [[ -f "$_CC_CONFIG_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$_CC_CONFIG_FILE"
fi

# ── Defaults (documented in cc-config.env.example) ──────────────────────────
# Allowed package manager; the guard denies the other ones.
: "${CC_PKG_MANAGER:=npm}"
# Stop-hook validation strategy: nx | command | off.
: "${CC_VALIDATE_MODE:=off}"
# Command to run when CC_VALIDATE_MODE=command.
: "${CC_VALIDATE_CMD:=}"
# TypeORM/SQL migration safety guard: on | off.
: "${CC_MIGRATION_GUARD:=off}"
# Regex for service names in prompts; empty disables memory-nudge.
: "${CC_MEMORY_NUDGE_REGEX:=}"
# Serena symbol-search redirect: on | off (off if Serena is not installed).
: "${CC_NAV_GUARD:=on}"
# Class-like suffixes that mark a grep pattern as a code symbol.
: "${CC_NAV_GUARD_SUFFIXES:=Service|Controller|Repository|Module|Entity|Dto|Port|Mapper|Guard|Interceptor|Producer|Consumer|Provider|Factory|Strategy|Decorator|Pipe|Filter|Exception|Middleware|Adapter|Client|Worker|Task|Job|Event}"
# Leading camelCase verbs that mark a grep pattern as a method-name symbol.
: "${CC_NAV_GUARD_VERBS:=find|get|create|update|delete|remove|set|has|is|prepare|build|make|to|from|validate|normalize|parse|resolve|extract|generate|handle|process|execute|register|add|apply|check|ensure|load|save|fetch|convert|map|transform|filter|sort|merge|split|format|emit|dispatch|enqueue|publish|subscribe|reset|init|bootstrap|compute}"
# Project source-tree roots (pipe-separated) for read-guard.
: "${CC_SOURCE_DIRS:=apps|libs|tools|src|config}"
# Dirs (pipe-separated, trailing slash) where bash writes are hard-blocked.
: "${CC_PROTECTED_WRITE_DIRS:=apps/|libs/}"
# Harness state home inside the project (denial-cap state, memory buffers,
# touched-file list, flow-state).
: "${CC_STATE_DIR:=.cc_settings}"

export CC_PKG_MANAGER CC_VALIDATE_MODE CC_VALIDATE_CMD CC_MIGRATION_GUARD \
  CC_MEMORY_NUDGE_REGEX CC_NAV_GUARD CC_NAV_GUARD_SUFFIXES CC_NAV_GUARD_VERBS \
  CC_SOURCE_DIRS CC_PROTECTED_WRITE_DIRS CC_STATE_DIR
