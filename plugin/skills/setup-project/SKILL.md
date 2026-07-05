---
name: setup-project
description: Finish installing the just-claude configuration in the current project — run once after installing the plugin (or after install.sh). Detects install mode, writes project-side settings (permissions, memory dir, output style), fills cc-config.env, routes CLAUDE.md creation/adaptation, verifies MCP servers and hooks. Use when asked to "finish setup", "set up claude config", or right after installation.
allowed-tools: Read, Write, Edit, Grep, Glob, Bash, AskUserQuestion
---

# Project Setup Orchestrator

The plugin (or installer) ships files; THIS skill adapts them to the project.
The split is deliberate: file distribution is deterministic, but understanding
a codebase needs a model — so the intelligence lives here. Run once per
project; safe to re-run (idempotent — existing values are reviewed, not
clobbered).

## Step 0 — Detect install mode and locate config root

- **Classic mode**: `.claude/hooks/bash-guards-dispatcher.sh` exists in the
  project → CONFIG_ROOT is `.claude/`.
- **Plugin mode**: no project hooks dir → the config runs from the plugin
  installation. Locate PLUGIN_ROOT:
  `find ~/.claude/plugins -maxdepth 6 -type f -name "bash-guards-dispatcher.sh" 2>/dev/null | head -1`
  (its parent's parent is PLUGIN_ROOT). If not found, ask the user to confirm
  the plugin is installed (`/plugin` → installed list).

Plugin mode requires project-side files the plugin cannot ship (permissions,
memory settings, stack config) — Steps 2–4 create them.

## Step 1 — Detect project facts

Auto-detect first; ask only what detection can't answer:

| Fact | Detection |
|---|---|
| Package manager | `pnpm-lock.yaml` → pnpm; `yarn.lock` → yarn; `package-lock.json` → npm |
| Monorepo tool | `nx.json` → nx; `turbo.json` / `lerna.json` / workspaces → their modes |
| Framework | package.json deps (nestjs / express / fastify / koa); tsconfig presence |
| ORM / migrations | deps: typeorm / prisma / sequelize / knex |
| Validate commands | package.json scripts: lint, typecheck, build, test |
| Serena availability | `claude mcp list` / plugin MCP status |

## Step 2 — Project settings (`.claude/settings.json`)

The plugin cannot ship permissions, `autoMemoryDirectory`, or a default output
style — write them project-side. If `.claude/settings.json` exists, MERGE
(deny rules win; never remove existing entries); otherwise create:

```json
{
  "outputStyle": "comm",
  "autoMemoryDirectory": ".cc_settings/.memory",
  "permissions": {
    "allow": [
      "mcp__serena__*",
      "mcp__basic-memory__*",
      "Read(.cc_settings/.memory/**)",
      "Write(.cc_settings/.memory/**)",
      "Edit(.cc_settings/.memory/**)",
      "Read(.cc_settings/_inbox/**)",
      "Bash(ls:*)", "Bash(find:*)", "Bash(grep:*)", "Bash(wc:*)", "Bash(pwd:*)",
      "Bash(git status:*)", "Bash(git diff:*)", "Bash(git log:*)"
    ],
    "deny": [
      "Read(.env)", "Write(.env)", "Read(**/.env)", "Write(**/.env)",
      "Read(**/.env.*)", "Write(**/.env.*)",
      "Read(**/*.key)", "Write(**/*.key)", "Read(**/*.pem)", "Write(**/*.pem)",
      "Read(**/*.cert)", "Write(**/*.cert)", "Read(**/*.p12)", "Write(**/*.p12)",
      "Read(**/credentials*)", "Write(**/credentials*)",
      "Read(**/secrets*)", "Write(**/secrets*)",
      "Write(.claude/settings.local.json)"
    ]
  }
}
```

In classic mode `settings.json` was already installed from the template —
verify it instead of rewriting. (Classic installs also wire hooks in this file;
plugin installs get hooks from the plugin — do NOT add hook entries in plugin
mode.)

## Step 3 — Stack config (`.claude/cc-config.env`)

Create from Step 1 findings (skip if exists — then review values with the
user). Template (also at `PLUGIN_ROOT`'s repo `templates/cc-config.env.example`,
or `CONFIG_ROOT/cc-config.env.example` in classic mode):

```bash
CC_PKG_MANAGER="npm"            # npm | pnpm | yarn — the allowed one
CC_VALIDATE_MODE="off"          # nx | command | off
CC_VALIDATE_CMD=""              # when mode=command, e.g. "npm run lint && npm run typecheck"
CC_MIGRATION_GUARD="off"        # on | off (TypeORM/Prisma/etc. detected → on)
CC_MEMORY_NUDGE_REGEX=""        # e.g. "[a-z-]*-svc"; empty disables
CC_NAV_GUARD="on"               # off if Serena is not available
CC_SOURCE_DIRS="src"            # actual top-level source dirs, pipe-separated
CC_PROTECTED_WRITE_DIRS="src/"  # dirs where bash writes are hard-blocked
CC_STATE_DIR=".cc_settings"
```

Also ensure: `.cc_settings/.memory/` and `.cc_settings/_inbox/` exist, and
`.gitignore` covers `.cc_settings/.memory/`, `.cc_settings/_inbox/*` (keep
`.gitkeep`/README), `.claude/settings.local.json`, `.claude/cc-config.env`.

## Step 4 — Response language + project-owned support files

1. Ask which language Claude should use for conversation (code/commits stay
   English). Copy `comm.md` from the plugin's `output-styles/` (or verify the
   classic copy) into the project's `.claude/output-styles/comm.md` and set its
   `RESPONSE_LANGUAGE:` line. The project copy exists so plugin updates never
   reset the user's language choice.
2. Copy `rules/learning.md` from the plugin into `.claude/rules/learning.md`
   (the lesson-capture convention must be project-visible).

## Step 5 — CLAUDE.md routing

- No `CLAUDE.md` at repo root → invoke **bootstrapping-claude-md** and follow
  it to the end.
- `CLAUDE.md` exists (or AGENTS.md / AI docs) → invoke **adapting-claude-md**.
Never overwrite an existing CLAUDE.md outside that adaptation flow.

## Step 6 — MCP verification

Plugin mode: serena, basic-memory, and context7 ship with the plugin and start
automatically — check `/mcp` status. Failures usually mean a missing runtime:
serena/basic-memory need `uv` (uvx), context7 needs node/npx. Report what's
missing with install pointers; if Serena cannot run, set `CC_NAV_GUARD="off"`.
Classic mode: run `.claude/setup/configure-mcp.sh` (idempotent).

## Step 7 — Smoke test + report

1. Pipe a test payload through the dispatcher (use the hooks path located in
   Step 0): a `cat src/<some-file>` command must be denied by read-guard;
   `git status` must pass.
2. Validate `.claude/settings.json` with `node -e "JSON.parse(...)"`.
3. Report: install mode, detected facts, cc-config.env values, settings
   written, CLAUDE.md action taken, MCP status, smoke-test results — and
   remind the user to restart the session so settings load.
