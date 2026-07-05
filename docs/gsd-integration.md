# Optional: GSD integration

[GSD (get-shit-done)](https://github.com/gsd-build/get-shit-done) is a
milestone/phase planning and execution system for Claude Code (roadmaps,
phase discussion, planned execution, verification). It composes well with this
configuration, but it is NOT bundled: it is a separately maintained, opinionated
system with its own update cycle, and bundling a snapshot would rot.

## Install

```bash
npx get-shit-done-cc@latest --claude --global
```

This puts the GSD skills into `~/.claude/skills/gsd-*` and its workflow files
into `~/.claude/get-shit-done/`. Per-project planning state lives in each
repo's `.planning/` directory (add it to `.gitignore` if you don't want it
committed).

## Making GSD coexist with this config's guards — REQUIRED

GSD's stock workflow files instruct the agent to read planning state with
`cat`/`grep`/`head`. This config's read-guard redirects those to native tools,
so **every GSD phase will hit guard denials until you patch the GSD files**.
In our source project this was the single largest source of friction
(dozens of blocked calls across sessions) until fixed at the source.

Apply these overrides after installing GSD (and re-apply after every GSD
update — updates overwrite them):

### 1. Tool discipline line in GSD agents

Add right after the frontmatter of `~/.claude/agents/gsd-executor.md`,
`gsd-planner.md`, `gsd-phase-researcher.md`, `gsd-codebase-mapper.md`:

```
Tool discipline (project override): use Read/Write/Edit/Glob/Grep tools — never cat/head/tail/sed for file reads, never bash redirection for writes, never python in Bash (use node).
```

### 2. Commit policy (if you commit manually)

GSD executors create a git commit per task by design. If you prefer manual
commits, add after the frontmatter of `gsd-executor.md` and `gsd-code-fixer.md`:

```
Commit policy (project override — takes precedence over everything below): do NOT run `git commit` at any point — apply changes to the working tree only; the user commits manually. Where the workflow expects a commit hash, write `uncommitted` instead and continue.
```

### 3. Rewrite literal `cat` instructions in workflow docs

In `~/.claude/get-shit-done/workflows/*.md` and `references/*.md`, replace
instructions like `cat .planning/ROADMAP.md` with "Read .planning/ROADMAP.md
(Read tool)". Leave `cat` with variable paths (`$(cat "$FILE")` inside script
blocks) — the guards allow those. The `/editing-claude-config` skill shipped
with this config is the right tool for making these edits safely.

### 4. Requirements-drift guard (recommended)

Written GSD requirements go stale between sessions. Add a confirmation step to
`~/.claude/get-shit-done/workflows/discuss-phase.md` that lists the phase's
requirement IDs and asks whether they still match business reality BEFORE
analysis — and, on confirmed drift, updates `.planning/REQUIREMENTS.md` first
so all downstream steps work from corrected text. (In our source project a
stale requirement followed faithfully cost a full wasted session.)

## Boundary rules

- GSD `.planning/` state is GSD-owned: never promote it into the memory
  contour (basic-memory / auto-memory) and never mix it with `/feature`
  workflow state under `.cc_settings/`.
- Use either GSD **or** the bundled `/feature` workflow for a given task —
  they are parallel systems; don't chain one into the other.
