# Architecture

What ships in `plugin/` (as a Claude Code plugin, or copied into the target's
`.claude/` by the classic installer) and how the pieces interact. All
stack-specific behavior flows through one project-side file:
`.claude/cc-config.env` (see [customization.md](customization.md)).

## Hook layer

Wired in `settings.json`; every hook is bash + embedded python3.

### Guards (PreToolUse)

One settings entry — `bash-guards-dispatcher.sh` — reads the payload once and
runs each guard only when a cheap prefilter says it could fire:

| Guard | Blocks | Mode |
|---|---|---|
| `read-guard.sh` | `cat/head/tail/less/awk/sed` reads, `touch`, `echo >`, `cp`, editors on source files → native Read/Write/Edit tools | native (auto-allows after N identical denials) |
| `nav-guard.sh` | symbol-shaped `grep/rg/ag/ack` in project code → Serena `find_symbol`; text search always allowed | native |
| `python-guard-bash.sh` | `python` in Bash tool calls (use node) | native |
| `package-manager-guard.sh` | the two package managers that are not `CC_PKG_MANAGER` | security (never auto-allows) |
| `config-guard-bash.sh` | bash writes/deletes into `.claude/`, `.mcp.json`, `CC_PROTECTED_WRITE_DIRS` | security |
| `migration-safety.sh` | destructive DB/migration commands (revert, drop, truncate, unscoped delete) — gated by `CC_MIGRATION_GUARD` | security |
| `detect-secrets.sh` | secrets in `git commit` (and in written files via PostToolUse) | security |
| `network-guard.sh` | unexpected remote transports / secret-file exfil patterns | security |
| `basic-memory-guard.sh` | direct file access to the basic-memory store (MCP tools only) | security |

`lib/denial-cap.sh` gives every guard an anti-loop: 2nd identical denial
escalates the message ("do NOT retry — your next call must be X"), 3rd
auto-allows for native-mode guards so a genuine edge case never deadlocks.

Write/Edit-matcher guards (registered separately): `config-guard.sh`
(protects `.claude/` config via native tools too), `migration-guard.sh`
(migration files are CLI-generated, not hand-written), plus the /feature role
fences `guard-test-author.sh` / `guard-executor.sh` (path-fence subagents by
role recorded in `$CC_STATE_DIR/.flow-state.json`).

### Session hygiene

| Hook | Event | Purpose |
|---|---|---|
| `session-rehydrate.sh` | SessionStart (startup/resume/clear) | inject pointers to saved state (never contents) |
| `pre-compact-save.sh` | PreCompact | checkpoint transcript + build handoff artifact |
| `post-compact-guidance.sh` | SessionStart (compact) | recovery rules: use artifacts, re-Read before Edit, re-check mid-session constraints |
| `long-session-nudge.sh` | UserPromptSubmit | suggest `/end-session` + `/clear` past record-count OR transcript-size thresholds |
| `save-on-clear.sh` | SessionEnd (clear) | persist session state before the context is dropped |

### Memory contour

`learn-capture.sh` + `learn-nudge.sh` + `memory-nudge.sh` maintain a lesson
buffer under `$CC_STATE_DIR/.memory/`; the `/learn-process` command promotes
buffered lessons to basic-memory (long-term) or user memory (behavioral).
`/end-session` writes a rich session snapshot. `track-touched.sh` +
`validate-on-stop.sh` implement Stop-hook validation per `CC_VALIDATE_MODE`
(`nx` per-project, `command` = `CC_VALIDATE_CMD`, or `off`).
`doc-drift-mark.sh` + `doc-sync-nudge.sh` + `/doc-sync` keep `.claude/docs/`
reference files honest after code changes.

## /feature workflow engine

`commands/feature.md` + `workflow/presets.yml` + 12 role agents:
planner → architect → test-author → executor → cc-reviewer, orchestrated by
lead, with build-error-resolver on call. Role fences are enforced by hooks
(test-author cannot touch production code; executor cannot touch tests).
Codex cross-verification (`codex-verifier` + `setup/codex-exec.sh`) is opt-in
via `--codex` and requires the external `codex` CLI.

## Skills

| Skill | Role |
|---|---|
| `setup-project` | post-install orchestrator: detect stack → fill cc-config.env → language → CLAUDE.md routing → MCP check → hook smoke test |
| `bootstrapping-claude-md` | generate a thin-router CLAUDE.md of verified facts for an undocumented repo |
| `adapting-claude-md` | conflict-aware merge with an existing CLAUDE.md (nothing dropped silently; backup kept) |
| `loading-minimal-context` | smallest useful file set for a task |
| `refactoring-existing-code` | scoped refactors without architecture drift |
| `reviewing-changes-targetedly` | review changed files + direct dependencies only |
| `tdd-workflow` | red→green→refactor discipline |
| `e2e-feature-verification` | live endpoint verification; per-service recipes accumulate in `references/` |
| `writing-project-documentation` | READMEs/runbooks aligned with real code |
| `editing-claude-config` | safe self-editing of this config (audit → edit → verify) |
| `cc-footprint-measure` | token-cost report of the config itself (`setup/measure-cc-footprint.mjs`) |

## State layout in a target project

```
<project>/
├── CLAUDE.md                  # generated/adapted by setup skills
├── .claude/
│   ├── settings.json          # written by /setup-project (permissions, memory dir, output style)
│   ├── cc-config.env          # stack parameters (gitignored)
│   ├── settings.local.json    # personal (gitignored)
│   ├── output-styles/comm.md  # project copy — language choice survives plugin updates
│   └── rules/learning.md      # lesson-capture convention
└── .cc_settings/              # CC_STATE_DIR (gitignored)
    ├── .memory/               # buffers, snapshots, denial-cap state, touched list
    └── _inbox/                # task material drop zone (read-only for Claude)
```

Plugin installs keep hooks/skills/agents/commands in the plugin cache and wire
hooks via the plugin's `hooks/hooks.json` (`${CLAUDE_PLUGIN_ROOT}` paths);
classic installs vendor the same files into `<project>/.claude/` and wire hooks
in `settings.json`. Hooks always read the PROJECT's `cc-config.env` via
`$CLAUDE_PROJECT_DIR`, so one plugin installation serves any number of projects
with different stacks.

Note: if you change `CC_STATE_DIR`, also update `autoMemoryDirectory` in
`.claude/settings.json` and the `.gitignore` entries — they carry the default
`.cc_settings` literal.

## Repo layout (this repository)

```
just_claude_configuration/
├── .claude-plugin/marketplace.json   # marketplace manifest (plugin catalog)
├── plugin/                           # THE plugin (hooks, skills, agents, commands, MCP, style)
│   ├── .claude-plugin/plugin.json
│   ├── hooks/hooks.json              # hook wiring (${CLAUDE_PLUGIN_ROOT})
│   └── .mcp.json                     # serena + basic-memory + context7
├── templates/                        # settings templates (classic install / reference)
├── install.sh                        # classic installer (copy + detect + MCP)
├── docs/                             # architecture, customization, rationale, GSD
├── README.md · CHANGELOG.md · LICENSE
```
