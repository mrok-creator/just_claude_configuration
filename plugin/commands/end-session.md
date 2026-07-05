---
name: end-session
description: Produces a rich, synthesized session snapshot before a boundary (clear or exit).
argument-hint: "[--clear | --exit]"
---

# /end-session — End Session

Produces a rich, synthesized session snapshot before a boundary (clear or exit).
This is the **quality save** — synthesized by Claude from checkpoint data + state files.

`save-on-clear.sh` is a bare safety copy only; this skill is the authoritative save path.
Checkpoint lifecycle is owned here: after consolidating the **current session's** checkpoints into a snapshot,
this skill prunes ONLY those now-consolidated checkpoints. Un-consolidated checkpoints (from other sessions) survive.
A global safety copy (the time-newest checkpoint across all sessions) is always kept.
Checkpoints live in `.cc_settings/.memory/checkpoints/` (co-located with snapshots).

## Arguments

- `--clear` — save snapshot, then instruct the user to run `/clear`
- `--exit` — save snapshot, then confirm safe to close
- *(no argument)* — save snapshot only

---

## Procedure

### Step 1 — Collect and group checkpoints (Glob only)

`Glob` `.cc_settings/.memory/checkpoints/*.jsonl`
— files named `pre-compact-<session-id>-<UTC>.jsonl` and `on-clear-<session-id>-<UTC>.jsonl`

**Group by session id** (extract from filename):
- Format: `pre-compact-<session-id>-<UTC>.jsonl` → extract `<session-id>` (36-char UUID between first `-` and second `-`)

For **the CURRENT session only** (the session id that appears in this conversation's system context):
- Collect ALL checkpoints for this session (all pre-compact + on-clear files with matching session id)
- Sort them lexicographically by filename (chronological order)
- Hold as the **session checkpoint set** for consolidation

**Un-consolidated checkpoints** (other sessions, or no session files at all): skip Step 2, proceed with state-context only.

If the current session has no checkpoints, skip Step 2 and proceed with state-context only.

### Step 2 — Extract conversation signal (Grep + bounded Read)

For each checkpoint in the **session checkpoint set** (oldest first):

**Primary — Grep:**
```
Grep pattern='"role":"user"'     in <checkpoint-file>
Grep pattern='"role":"assistant"' in <checkpoint-file>
```
Each matched line is a full JSONL record. Extract the `"text"` content from each by reading the JSON structure yourself.
**Never run python or pipe Grep output to any parser/shell to extract fields — parse the matched JSONL lines directly.**
Skip tool_use/tool_result lines and lines shorter than ~40 characters.
Collect the extracted text; discard duplicate paragraphs across checkpoints.

**Fallback (if Grep output is too large or truncated):**
`Read` each checkpoint with `limit=80` — first 80 JSONL lines capture the early session.
For multi-compact sessions, also `Read` with `offset=<midpoint>` + `limit=40` to sample middle.

Aim to collect: first 2–3 user messages (session goal), last 3–4 assistant messages (what was done),
all user corrections and objections (highest priority → record as Lessons).

### Step 3 — Read state context (Read only)

- `Read` `.cc_settings/.memory/STATE.md` (limit=80)
- `Read` `.cc_settings/.memory/handoff-latest.md` (limit=120)

These are authoritative for current task state and completed work.

### Step 4 — Synthesize snapshot

Using all collected data, produce ONE coherent snapshot. **Omit any section that has nothing real to say.**

Signal hierarchy:
1. `handoff-latest.md` + `STATE.md` — authoritative for current state and completed work
2. Final assistant messages — summarize what was built/changed
3. User corrections / objections — always record as Lessons
4. First user message — defines the session goal for Summary

**Strip entirely:** short narration lines ("Reading the file…", "Running…"), raw bash output unless it
reveals a decision, repeated status lines, tool invocation acknowledgements.

```
# Session — <stamp>

## Summary
<!-- 3–6 bullets: main task, what changed, what was discovered -->

## Decisions
<!-- Non-obvious architectural decisions, design choices — one bullet each: what + why -->
<!-- If none, omit section -->

## Lessons
<!-- User corrections received, pitfalls discovered, mistakes + fix — format: what happened → fix -->
<!-- If none, omit section -->

## Current state
<!-- Where things stand: built, tested, pending — pull from STATE.md / handoff-latest.md if richer -->

## Next step
<!-- The single most important thing to pick up next session -->

## Open threads
<!-- Unresolved questions, deferred items, flagged risks -->
<!-- If none, omit section -->
```

### Step 5 — Derive stamp & prune consolidated checkpoints (approval-free)

**Derive stamp (zero bash):**
- Take the newest checkpoint filename from the **session checkpoint set** (Step 1)
- Extract the UTC portion: e.g., `pre-compact-e0ec05ae-abd3-44dc-94a7-08df5e8db727-2026-06-24T123137Z.jsonl` → `2026-06-24T123137Z`
- Use that as `<stamp>` for the snapshot filename
- If no checkpoints exist, synthesize stamp from visible file timestamps in this conversation (e.g., last STATE.md mtime)

**Prune consolidated checkpoints (ONE Bash call, zero command substitution):**

Only if the **session checkpoint set** is non-empty, run:
```bash
rm -f <absolute-path-to-checkpoint-1> <absolute-path-to-checkpoint-2> ... <absolute-path-to-checkpoint-N>
```
Substitute each `<absolute-path-to-checkpoint-X>` with the actual full path from Step 1 (e.g., `.cc_settings/.memory/checkpoints/pre-compact-e0ec05ae-2026-06-24T122419Z.jsonl`).

**No `$(...)` substitution, no glob expansion** — list each file explicitly as a literal string. This ensures zero approval prompts.

**Global safety copy:** if ALL checkpoints across all sessions would be deleted, keep the time-newest one. Check before building the rm command: if `len(all_checkpoints) == len(session_checkpoint_set)`, omit the newest file from the rm list.

### Step 6 — Write snapshot

Write the synthesized content (from Step 5) to:
```
.cc_settings/.memory/session-<stamp>.md
```
(use the `stamp` value from Step 5)

### Step 7 — Update index

Append one line to `.cc_settings/.memory/index.md`:
```
- session-<stamp>.md — <one-line summary ≤60 chars>
```

**Verify** the written snapshot file is non-empty (size > 100 bytes) before reporting success.

### Step 8 — Boundary action

**`--exit` or no flag:** Report `Snapshot saved at .cc_settings/.memory/session-<stamp>.md`.
For `--exit` add: "Safe to close Claude Code."

**`--clear`:** After confirming the snapshot file is non-empty, tell the user:
"Snapshot saved. Run `/clear` to complete the boundary."

The quality save must be confirmed written **before** any boundary action.
