# just_claude_configuration

A complete, battle-tested Claude Code configuration for backend projects —
guard hooks, session hygiene, a persistent memory contour, a plan→test→code→review
workflow engine, and self-installing setup skills. Install it as a plugin with
two commands and let Claude adapt it to your repository.

Every piece of this config was extracted from a production monorepo setup and
hardened by analyzing real usage: 50 working sessions were mined for failure
patterns (hook-block loops, lost constraints after context compaction, stale
requirements, marathon sessions), and each finding became a guard, a nudge, or
a skill. See [docs/design-rationale.md](docs/design-rationale.md).

## What's inside

| Layer | What it does |
|---|---|
| **Guard hooks** | Redirect shell file reads to native tools, symbol greps to Serena (LSP), block the wrong package manager, protect `.claude/` and migrations, scan commits for secrets — with an anti-loop denial cap that escalates on repeated identical blocks |
| **Session hygiene** | Pre-compaction state save, post-compaction recovery guidance, long-session `/clear` nudges, session rehydration on start |
| **Memory contour** | Lesson capture buffer + promotion pipeline (`/learn-process`) into [basic-memory](https://github.com/basicmachines-co/basic-memory); session state survives `/clear` |
| **/feature workflow** | An 11-step plan→test→code→review→commit pipeline with role-fenced subagents (planner, architect, test-author, executor, reviewer) and optional [Codex](https://github.com/openai/codex) cross-verification |
| **Cross-cutting skills** | Minimal-context loading, targeted refactoring/review, TDD, live e2e feature verification, config self-editing, config token-footprint measurement |
| **Setup skills** | `/setup-project` — Claude finishes its own installation: generates a quality `CLAUDE.md` for undocumented repos or safely merges with an existing one |

## Quick start (plugin — recommended)

Inside Claude Code, in your project, send these as separate prompts:

```
/plugin marketplace add mrok-creator/just_claude_configuration
```

```
/plugin install just-claude@just-claude-configuration
```

```
/setup-project
```
If the short form does not resolve (another plugin also ships a
`setup-project` skill), use the namespaced form:

```
/just-claude:setup-project
```

No cloning, no forks. The plugin ships the hooks, skills, agents, the /feature
workflow, the output style, and the MCP servers (serena, basic-memory,
context7 — started automatically). `/setup-project` then does the part that
needs intelligence: detects your stack into `.claude/cc-config.env`, writes the
project-side settings a plugin cannot ship (permissions, memory directory,
output style), and generates — or conflict-aware-merges — your `CLAUDE.md`.

Updates: `/plugin marketplace update just-claude-configuration` (or enable
auto-update in `/plugin` → Marketplaces). Your project-side files
(`cc-config.env`, `settings.json`, language choice, CLAUDE.md) survive updates.

## Alternative: classic install (no plugin system)

For CI images, air-gapped setups, or if you prefer files vendored into the repo:

```bash
git clone https://github.com/mrok-creator/just_claude_configuration.git
bash just_claude_configuration/install.sh /path/to/your/project
# then, inside your project, open Claude Code and run:  /setup-project
```

`install.sh` copies everything into `<project>/.claude/`, auto-detects the
stack, and registers MCP servers via `claude mcp add`. Existing files are never
overwritten (`--force` to override); an existing `CLAUDE.md` is merged via the
same conflict-aware flow, never replaced.

## Requirements

- **macOS or Linux** (Windows: WSL — see [Windows](#windows))
- `bash`, `python3` (hooks runtime), `node` (utilities)
- [Claude Code](https://claude.com/claude-code) CLI
- Optional but recommended: [`uv`](https://docs.astral.sh/uv/) (for the Serena
  MCP — semantic code navigation). Without it, set `CC_NAV_GUARD="off"`.

## MCP servers

| Server | Purpose | Runtime needed |
|---|---|---|
| serena | LSP-backed symbol navigation — the target of nav-guard redirects | `uv` (uvx) |
| basic-memory | long-term knowledge store for the memory contour | `uv` (uvx) |
| context7 | up-to-date library documentation lookup | node (npx) |

Plugin install: all three ship with the plugin and start automatically
(`--project` for serena is wired to your project dir; data homes in the
plugin's persistent data directory). If a runtime is missing the server just
fails to start — check `/mcp`, install the runtime, or disable the piece
(`CC_NAV_GUARD="off"` for a Serena-less setup).

Classic install: `install.sh` (or `.claude/setup/configure-mcp.sh` standalone)
registers the same three via `claude mcp add`, idempotently. Hosted MCPs that
need interactive auth must be authenticated inside Claude Code (`/mcp`) — that
step cannot be scripted.

## Configuration

All stack-specific behavior lives in one file: `.claude/cc-config.env`
(auto-generated at install, human-editable, gitignored). Package manager,
validation strategy for the Stop hook, migration guard, source-dir roots,
nav-guard symbol heuristics — see [docs/customization.md](docs/customization.md)
for the full variable table.

**Response language** is parameterized: Claude talks to you in the language set
in `.claude/output-styles/comm.md` (`RESPONSE_LANGUAGE:` line, default English —
`/setup-project` asks), while code, commits, and machine-to-machine text stay
English. Details in [docs/customization.md](docs/customization.md#language).

## Windows

Supported via **WSL2 only**. The hook layer is bash + python3 and the installer
is a shell script; native Windows (PowerShell/cmd) is not supported. To run on
Windows: install WSL2 with Ubuntu, install Claude Code, `python3`, `node`, and
`uv` inside WSL, keep your projects on the WSL filesystem, and follow the Linux
quick start unchanged. Porting natively would require rewriting all hooks
(PowerShell or Node) and the installer — contributions welcome.

## Optional: GSD integration

[GSD (get-shit-done)](https://github.com/gsd-build/get-shit-done) is a
milestone/phase planning system that pairs well with this config but is
**deliberately not bundled** — it is a separate, opinionated workflow with its
own update cycle. If you want it, follow
[docs/gsd-integration.md](docs/gsd-integration.md): it covers installation and,
critically, the project-override blocks you should add to GSD agents (tool
discipline, commit policy) so GSD does not fight this config's guards — plus
the warning that GSD updates overwrite those overrides.

## Documentation

- [docs/architecture.md](docs/architecture.md) — anatomy of every hook, skill, agent, and the workflow engine
- [docs/customization.md](docs/customization.md) — cc-config.env reference, language, permissions, disabling parts
- [docs/design-rationale.md](docs/design-rationale.md) — why it is built this way (evidence from session analysis)
- [docs/gsd-integration.md](docs/gsd-integration.md) — optional GSD setup

## License & authorship

MIT — see [LICENSE](LICENSE). Copyright (c) 2026 Kasianenko Oleksandr.
Contributions are welcome under the same license.
