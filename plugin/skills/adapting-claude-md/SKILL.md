---
name: adapting-claude-md
description: Merge this configuration into a project that ALREADY has a CLAUDE.md or other AI instructions (AGENTS.md, .cursorrules, docs/ai) — preserve the project's established rules, add this config's routing sections, resolve conflicts with the user. Use during setup when an existing CLAUDE.md is detected.
allowed-tools: Read, Write, Edit, Grep, Glob, Bash, AskUserQuestion
---

# Adapting an Existing CLAUDE.md

The existing file encodes decisions someone already made — losing them silently
is the worst failure mode of an automated setup. Nothing gets deleted without
the user seeing it.

## Step 1 — Inventory existing instructions

- Read root `CLAUDE.md`, plus any of: `AGENTS.md`, `.cursorrules`,
  `.github/copilot-instructions.md`, `docs/` AI-guideline files.
- Classify every statement into:
  - **KEEP** — project-specific, still true (verify spot-checks against code:
    named paths exist, commands exist);
  - **STALE** — contradicts current code (note the evidence);
  - **OVERLAP** — restates something this config now provides (hooks, skills,
    validation, memory) — the config version wins to avoid double instructions;
  - **CONFLICT** — contradicts this config's conventions (e.g. mandates bash
    file reads that hooks now block, different state directory, different
    package manager than detected).

## Step 2 — Resolve

- KEEP items: carry into the merged file verbatim (their original wording).
- STALE items: list with evidence; ask the user — fix or drop.
- OVERLAP items: replace with a pointer to the config feature; mention the
  replacement in the report.
- CONFLICT items: never decide silently — present each via AskUserQuestion
  ("existing rule says X, this config does Y — which wins?"). If the existing
  rule wins, adjust `cc-config.env` / hook toggles to match it, not just the text.

## Step 3 — Merge

- Back up the original: `CLAUDE.md` → `CLAUDE.md.pre-setup.bak` (tell the user;
  suggest deleting after review).
- Produce the merged CLAUDE.md using the section skeleton from the
  `bootstrapping-claude-md` skill, with KEEP content placed into the matching
  sections (project truths, forbidden patterns, commands...) rather than
  appended as a blob.
- If the existing file is already excellent (thin, verified, structured), do
  the MINIMAL thing instead: append only the routing sections this config
  needs (validation behavior, skill/doc routing) and report that the original
  structure was preserved.

## Step 4 — Report

Summarize: kept / replaced / dropped / conflicts and their resolutions, backup
location, and any cc-config.env values changed to honor existing conventions.
