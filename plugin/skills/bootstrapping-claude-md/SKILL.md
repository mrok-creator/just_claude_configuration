---
name: bootstrapping-claude-md
description: Generate a high-quality CLAUDE.md for a repository that has no Claude Code documentation yet — analyze the codebase (stack, structure, commands, conventions) and produce a thin-router CLAUDE.md of verified facts. Use when a repo needs its first CLAUDE.md, or when asked to "describe this repo for Claude".
allowed-tools: Read, Write, Grep, Glob, Bash, AskUserQuestion
---

# Bootstrapping CLAUDE.md

A good CLAUDE.md is a **thin router of verified facts**, not an essay. Every
line must be checkable against the repo; anything generic ("write clean code")
is noise that costs tokens on every prompt. Target: under ~150 lines.

## Step 1 — Analyze (read-only; do not guess)

1. **Manifest**: package.json (name, scripts, deps), lockfile, engines; monorepo
   config (nx.json / turbo.json / workspaces).
2. **Structure**: top-level dirs; where source lives; one representative feature
   module read end-to-end to learn the layering.
3. **Commands that actually work**: derive dev/build/lint/test from scripts;
   VERIFY the main ones run (at minimum `--help` / dry variants) before
   documenting them.
4. **Conventions**: naming patterns, path aliases (tsconfig), DI style, error
   handling, DTO/validation approach — from code, not assumption.
5. **Infra**: DB/queue/cache clients in deps; docker-compose; CI workflows
   (.github/workflows) for the real validation pipeline.
6. **Boundaries**: anything that looks forbidden by design (e.g. layers that
   never import each other) — candidate "forbidden patterns".

If the repo is too large to scan, sample: manifest + one feature slice per
top-level area. Ask the user only what code cannot answer (e.g. "which module
is the canonical example to imitate?").

## Step 2 — Write CLAUDE.md (structure contract)

Use exactly this section skeleton (proven shape — router first, details on demand):

```markdown
# CLAUDE.md

Thin router. Keep execution targeted and the smallest valid change first.

## 1. Project truths
- stack line (framework, language, versions)
- package manager: <detected> (never <the others>)
- structure line (monorepo tool / layout)
- canonical example feature: <path>       ← the module new code should imitate
- 3–7 more verified, load-bearing facts

## 2. Working mode
- context discipline (read minimal set; canonical example first)
- decisions from verified facts only; ask when ambiguous
- verification means verification (independent re-check, never assert-to-please)
- simplicity first: reuse → framework feature → fewest lines

## 3. Forbidden patterns
- 5–12 bullets, each derived from a REAL boundary found in Step 1

## 4. Commands
- dev / build / lint / test — only commands verified to exist

## 5. Validation
- what runs on Stop (matches cc-config.env), what to run manually

## 6. Doc & skill routing
- table pointing to .claude/docs/* and skills — only entries that exist

## Self-maintenance
- when to update this file (structural changes only)
```

## Step 3 — Quality gate (before finishing)

- Every command in §4 exists in package.json scripts or was executed.
- Every path mentioned exists (`ls` them).
- No generic filler: delete any line that would be true of EVERY project.
- No duplication with what path-scoped rules/skills already say.
- Present the draft to the user with a one-paragraph summary of what was
  detected; apply their corrections before writing the final file.
