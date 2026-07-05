---
name: doc-sync
description: Sync AUTO-MANAGED sections of service/lib docs with current code
---

# /doc-sync — Living documentation sync

On-demand command to refresh AUTO-MANAGED sections in `.claude/docs/<area>-reference.md` files for services/libs modified since last sync.

---

## Workflow

1. Read `.cc_settings/.memory/doc-drift.md` — list of services/libs with modified code.
2. For each entry that has a corresponding `.claude/docs/<area>-reference.md` file:
   - Check if the doc has `<!-- AUTO-MANAGED:start -->…<!-- AUTO-MANAGED:end -->` markers.
   - If markers exist: spawn `doc-updater` subagent to refresh those sections from current code (via Serena/LSP).
   - If no markers: offer to add them (requires user approval); do not retrofit all docs automatically.
3. Remove synced entries from doc-drift.md.
4. Show summary: synced count, skipped (no doc file), skipped (no AUTO markers), errors.

---

## Subagent invocation

```typescript
Agent({
  description: "Sync AUTO sections for <area>",
  subagent_type: "doc-updater",
  prompt: `Refresh AUTO-MANAGED sections in .claude/docs/<area>-reference.md to match current code state. Use Serena/LSP to extract current module structure, providers, controllers, wiring. Do not modify manually-authored sections. If no AUTO markers exist, report that fact and do not add them automatically.`
})
```

---

## No autonomous execution

This command runs in the live session — never via `claude -p` or background cron. It is user-triggered, not automated.

---

## Convention

Docs use `<!-- AUTO-MANAGED:start -->…<!-- AUTO-MANAGED:end -->` pairs to mark sections maintained by `doc-updater`. Apply this convention incrementally — no repo-wide retrofit required now.
