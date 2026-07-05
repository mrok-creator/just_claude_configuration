# Changelog

All notable changes to this project are documented here.
Format: [Keep a Changelog](https://keepachangelog.com/), versioning: [SemVer](https://semver.org/).

## [0.2.0] — 2026-07-05

### Changed
- Converted to a native Claude Code **plugin marketplace**: install with
  `/plugin marketplace add mrok-creator/just_claude_configuration` +
  `/plugin install just-claude@just-claude-configuration` — no cloning needed.
- `payload/claude/` → `plugin/` (plugin layout: `.claude-plugin/plugin.json`,
  `hooks/hooks.json` with `${CLAUDE_PLUGIN_ROOT}` wiring, bundled `.mcp.json`
  auto-starting serena/basic-memory/context7 with `${CLAUDE_PROJECT_DIR}`).
- Settings a plugin cannot ship (permissions, `autoMemoryDirectory`, output
  style default, `rules/learning.md`, language choice) moved into
  `/setup-project`, which writes them project-side; templates kept in
  `templates/` for the classic path.
- `install.sh` retained as the classic (vendored) install, now assembling from
  `plugin/` + `templates/`.

## [0.1.0] — 2026-07-05

### Added
- Initial extraction from a production monorepo Claude Code setup.
- Guard hook layer with denial-cap anti-loop (read-guard, nav-guard,
  python-guard, config-guard, package-manager-guard, migration guards,
  detect-secrets, network-guard, basic-memory-guard) — parameterized via
  `cc-config.env`.
- Session hygiene: pre-compact save, post-compact guidance, long-session
  nudge, session rehydrate, save-on-clear.
- Memory contour: learn-capture buffer, memory nudges, `/learn-process`,
  `/end-session`.
- `/feature` workflow engine with role-fenced agents (planner, architect,
  test-author, executor, lead, cc-reviewer, optional codex-verifier).
- Cross-cutting skills: loading-minimal-context, refactoring-existing-code,
  reviewing-changes-targetedly, writing-project-documentation, tdd-workflow,
  e2e-feature-verification, editing-claude-config, cc-footprint-measure.
- Setup skills: `setup-project`, `bootstrapping-claude-md`,
  `adapting-claude-md`.
- One-command installer (`install.sh`) with stack auto-detection and MCP
  registration (serena, basic-memory, context7).
- Language-parameterized output style (`comm`).
- Documentation: architecture, customization, design rationale, optional GSD
  integration.
