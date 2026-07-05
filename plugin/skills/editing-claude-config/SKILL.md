---
name: editing-claude-config
description: Audit or modify this repo's Claude Code configuration — hooks, rules, agents, commands, skills, workflow presets, or settings.json. Use for any change under .claude/ (hook logic, guard behavior, rule text, agent definitions, permissions). Enforces the intake template, read-only audit before edit, and a verification pass after.
allowed-tools: Read, Write, Edit, Grep, Glob, Bash
---

# Editing Claude Code Config

Session analysis showed config-engineering sessions that follow this shape have
near-zero corrections; free-form config prompts produce rework. This skill
institutionalizes the working shape.

## Step 1 — Intake (before touching anything)

Restate the request in this template and confirm it matches the user's intent
(skip confirmation only when the user already supplied all four fields):

```
GOAL:        one sentence — the end state, not the mechanism
CONTEXT:     which config surface(s): hooks | rules | agents | commands | skills | settings | workflow presets
CONSTRAINTS: what must NOT change (guard semantics, permission mode, contracts with other hooks)
CHECKS:      how success will be verified (see Step 4)
```

If GOAL or CONSTRAINTS cannot be filled from the request — ask, do not guess.

## Step 2 — Read-only audit

- Read the target file(s) and every file that interacts with them BEFORE editing:
  a hook change → also `settings.json` registration + the guard dispatcher
  ordering + shared hook-lib contracts; a rule change → CLAUDE.md routing;
  an agent change → the command/workflow that spawns it.
- State the current behavior in one or two sentences and what will change.
- Config surfaces and their interaction points:

| Surface | Also check |
|---|---|
| `.claude/hooks/*.sh` | settings.json hook registration; dispatcher prefilters; shared hook-lib contracts |
| `.claude/rules/*.md` | CLAUDE.md routing table; path-scoping frontmatter |
| `.claude/agents/*.md` | spawning command/preset; role fences (guard-test-author/guard-executor) |
| `.claude/commands/*.md` | `workflow/presets.yml`; agents it spawns |
| `.claude/settings.json` | permission precedence vs `settings.local.json` (deny wins); hook timeouts |

Plugin-mode caveat: if this config was installed as a PLUGIN, hooks/skills/
agents live in the plugin cache, not `.claude/` — edits there are LOST on
plugin update. Durable customization goes into project-side files
(`cc-config.env`, `settings.json`, project output-style copy) or upstream via a
fork of the config repo. Only edit plugin-cache files as a temporary experiment
and say so in the report.

## Step 3 — Edit

- Write/Edit tools only — never bash redirection (config-guard blocks it anyway).
- Smallest diff; do not reflow unrelated text.
- Hooks: keep the established style (bash wrapper + embedded python3, exit 0
  non-blocking for nudges, exit 2 for guards, denial-cap integration for guards).
- Never edit `settings.local.json` (deny-listed) — propose the change to the user instead.

## Step 4 — Verification pass (mandatory)

- Shell syntax: `bash -n <hook>.sh` for every touched hook.
- JSON validity: `node -e "JSON.parse(...)"` for settings changes.
- Behavior smoke test: pipe a representative payload into the hook and assert
  the expected ALLOW/DENY/output (use a scratchpad state file via the hook's
  env override to avoid polluting real denial-cap/nudge state).
- Guard changes: test BOTH directions — a case that must still block and a case
  that must now pass.
- Report the before/after behavior in the final summary.

## Hard limits

- Never weaken a security-mode guard (config-guard, migration-safety,
  detect-secrets, network-guard) as a side effect of a usability fix.
- Never delete another hook's state files while testing.
