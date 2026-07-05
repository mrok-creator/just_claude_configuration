---
name: cc-footprint-measure
description: Measure the token footprint of this repo's Claude Code configuration (CLAUDE.md, rules, skills, agents, commands, docs) — per-file and per-surface byte/token estimates. Use when asked to measure, audit, or reduce config token cost/footprint.
allowed-tools: Bash, Read, Write
---

# CC Config Footprint Measurement

Do NOT hand-roll inline measurement one-liners (they failed repeatedly in past
sessions) — a checked-in script exists.

## Procedure

1. Run the script from the repo root:
   ```bash
   node .claude/setup/measure-cc-footprint.mjs
   ```
   For a persisted snapshot (comparisons over time):
   ```bash
   node .claude/setup/measure-cc-footprint.mjs --json .cc_settings/.memory/footprint-<YYYY-MM-DD>.json
   ```
2. Interpret: only the "always-on" surface plus skill/agent DESCRIPTIONS hit
   every prompt; rule/doc/skill bodies load on demand. Optimize always-on
   first, descriptions second; on-demand bodies only when grossly oversized.
3. When comparing runs, diff the JSON snapshots — do not re-measure by eye.
4. If the script's surface list is missing a config location, extend the
   script (Edit tool), don't work around it inline.

Token estimate is chars/3.7 — a heuristic for RELATIVE comparison, not billing.
