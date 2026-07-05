---
name: loading-minimal-context
description: Load the smallest useful context for work in this repository. Use when a task risks broad repo scans, repeated pattern rediscovery, or unnecessary token use.
allowed-tools: Read, Grep, Glob, Bash
---

# Loading Minimal Context

## Goal

Solve the task with the minimum context that still preserves correctness.

## Procedure

1. Start with the exact file paths or feature names from the user request
2. Read only the touched file + nearest module/wiring file + one closest existing reference feature
3. Load one rule file from `.claude/rules/` only when the task actually needs that domain knowledge
4. Do not read unrelated modules, migrations, or broad architectural notes
5. Stop loading more context as soon as the implementation path is clear

## Hard limits

- One primary reference feature maximum
- One secondary reference only if the first is clearly insufficient
- If the correct reference is unclear — delegate discovery to the `repo-explorer` subagent
- Never read a full root module/wiring file — only the imports section if needed
- Never read a full constants/pattern registry file — only the relevant section
- Never read all migrations — only the relevant entity/schema definition
