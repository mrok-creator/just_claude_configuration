---
description: Promote captured lessons from the session buffer into long-term basic-memory, then clear the buffer.
---

# /learn-process — Learning Buffer Promotion

Read `.cc_settings/.memory/buffer.md`, classify and promote entries to basic-memory via `mcp__basic-memory__write_note`, then clear the buffer.

---

## Procedure

### Step 0 — Orphan-checkpoint sweep

Before processing the buffer, check `.cc_settings/.memory/checkpoints/` for un-consolidated session checkpoints.

1. `Glob` `.cc_settings/.memory/checkpoints/*.jsonl` — collect all checkpoint files  
   - Format: `pre-compact-<session-id>-<UTC>.jsonl`, `on-clear-<session-id>-<UTC>.jsonl`
2. If the glob returns no files, skip checkpoint sweep.
3. Group files by session id (36-char UUID embedded in the filename between the first and second `-`). Files sharing the same session id belong to one session.
4. For each session group:
   - Extract the lexicographically newest UTC stamp from that group's filenames (e.g., `2026-06-24T123137Z`)
   - Check whether `.cc_settings/.memory/session-<newest-UTC>.md` already exists
   - **Exists → skip** (already consolidated by `/end-session`)
   - **Missing → orphan** (session crashed or closed without `/end-session`)
     - Follow the extraction procedure from Steps 3–5 of `/end-session`: `Grep` for `"role":"user"` and `"role":"assistant"` lines, `Read` with `limit=80` as fallback — NO python, NO bash pipelines with parsers
     - Synthesize a minimal session snapshot (Summary, Decisions, Lessons, Current state, Next step — omit empty sections)
     - Write snapshot to `.cc_settings/.memory/session-<newest-UTC>.md`
     - Append one entry to `.cc_settings/.memory/index.md`: `- session-<newest-UTC>.md — <≤60-char summary>`
     - **Do NOT delete** the checkpoint files — deletion is owned by `/end-session`

If any orphans were consolidated, report "Consolidated N orphan session(s):" with their stamp(s).

**Session orphan sweep:**

After checkpoint sweep, check for orphaned `session-*.md` files (written by `/end-session` but not listed in `index.md`).

1. `Glob` `.cc_settings/.memory/session-*.md` — collect all session snapshot files
2. `Read` `.cc_settings/.memory/index.md` → extract list of indexed sessions (parse lines containing `session-`, extract stamp between `session-` and `.md`)
3. Diff: `all_sessions (glob) — indexed_sessions (index.md)` = orphaned
4. For each orphan:
   - Append entry to `.cc_settings/.memory/index.md` via `Edit`: `- session-<stamp>.md — orphaned snapshot (recovered)`
   - These orphans will be processed in Step 1a

Continue to Step 1.

---

### Step 1 — Read buffer

Read `.cc_settings/.memory/buffer.md` in full. If it is empty or missing, skip to Step 1a.

---

### Step 1a — Process session snapshots

Read `.cc_settings/.memory/index.md` to get the list of session-*.md files.

For each `session-<stamp>.md`:

1. **Read** the snapshot file.

2. **Classify:**
   - **Substantive** — has at least one `## Decisions` or `## Lessons` section with real content (not empty, not a placeholder like "none"/"N/A")
   - **Thin** — state-only snapshot (no Decisions/Lessons, or all sections empty/placeholder)

3. **Substantive → decompose and reconcile:**
   
   For each bullet in `## Decisions` and `## Lessons`:
   
   a. **Extract topic and classify type:**
      - Source `## Decisions` → `type: decision`
      - Source `## Lessons`:
        - Contains "pitfall" / "discovered" / "breaks at runtime" / "compiles but" / "silent" → `type: pitfall`
        - Contains "user corrected" / "feedback" / "wrong" → `type: correction`
        - Contains "mistake" / "error" / "failed" → `type: mistake`
        - Default → `type: decision`
   
   b. **Determine destination:**
      - `type: decision` + bullet mentions a specific service/module (e.g. `your-service`) → `decisions/<svc>`
      - `type: decision` + no specific service → `decisions/cross`
      - `type: pitfall` → `pitfalls`
      - `type: correction` + **domain/code knowledge** → `corrections`
      - `type: correction` + **behavioral/workflow preference** (how the user wants Claude to work — commit style, tool choice, language, process; NOT project knowledge) → **native user memory**, not basic-memory: write `feedback-<slug>.md` into the Claude Code auto-memory directory (`~/.claude/projects/<project-slug>/memory/`) and append an index line to its `MEMORY.md`
      - `type: mistake` → `mistakes`
   
   c. **Reconcile against existing basic-memory:**
      - Extract key terms from bullet (first 3-5 significant words, excluding stop words like "the", "a", "is", "was", "that")
      - Search basic-memory: `mcp__basic-memory__search_notes(query=<key terms>, metadata_filters={folder: <target folder>}, page_size=3)`
      - **If relevant existing note found** (topic match — judge semantic overlap via search result relevance or manual judgment):
        - Read existing note content via `mcp__basic-memory__read_note`
        - Merge new session bullet content into existing note (append under new heading `### Update from session <stamp>` or integrate inline if highly similar)
        - Update note via `mcp__basic-memory__write_note` with merged content
      - **If no relevant note found:**
        - Create new note with:
          - `title`: first 80 characters of the bullet text (strip markdown bold markers `**`)
          - `folder`: per classification above
          - `content`:
            ```markdown
            **Source: session <stamp>**

            <full bullet text>

            **Session context:** <1-line summary from the snapshot's ## Summary section>
            ```
   
   **SKIP `## Open threads` entirely** — that is working state, not durable knowledge.

4. **Mark processed:** after handling all bullets from a session, add the stamp to an in-memory set `processed_sessions`.

**Thin sessions:** skip promotion, but the stamp is still added to `processed_sessions` (the file will be deleted as stale).

**After processing all session-*.md:**

5. **Delete processed files:**
   ```bash
   rm -f .cc_settings/.memory/session-<stamp1>.md .cc_settings/.memory/session-<stamp2>.md ...
   ```
   List all stamps from `processed_sessions` explicitly as literal paths, zero glob expansion.

6. **Update index.md via Edit tool:**
   - Read current `.cc_settings/.memory/index.md` content
   - Filter out lines containing `session-<stamp>.md` where stamp is in `processed_sessions`
   - `Edit(file_path=".cc_settings/.memory/index.md", old_string=<current content>, new_string=<filtered content>)`

If no session files exist or all were thin, report "No substantive sessions to promote." and continue to Step 2.

---

### Step 2 — Classify and decide for each buffer entry

For each entry in `buffer.md` (delimited by `---`), inspect **type** and **generalization**:

| type | rule |
|---|---|
| `architecture` | **Always promote** → basic-memory folder `architecture-decisions` |
| `pitfall` | **Always promote** → basic-memory folder `pitfalls` |
| `correction` | **Always promote**; show to user. Domain/code knowledge → basic-memory folder `corrections`; behavioral/workflow preference → native user memory `feedback-<slug>.md` + `MEMORY.md` index line (see Step 1a destination rules) |
| `mistake (candidate)` | Promote → `mistakes` if the mistake class is avoidable; if a similar entry already exists in `mistakes` → **escalate**: propose adding a rule or hook to prevent recurrence; show to user |
| `deviation` | Promote only if 3+ similar entries found (otherwise **hold** — keep in buffer) |
| any type with `generalization: one-off, no generalization` | **Drop** — do not promote, remove from buffer |
| any type with `generalization: TODO — fill on promotion` | **Drop** unless you can fill in the generalization from conversation context; if context is available → complete the entry then promote |

Dedup: if two entries have near-identical summaries, merge into one before promoting.

### Step 3 — Write to basic-memory

For each entry to promote: call `mcp__basic-memory__write_note` with:
- `title` = entry **summary**
- `folder` = folder per the table above
- `content` = all entry fields formatted as a note

### Step 4 — Clear buffer

Overwrite `.cc_settings/.memory/buffer.md` with only **held** entries (those waiting for the repetition threshold). If nothing is held, write an empty file. Do not leave promoted or dropped entries in the buffer.

### Step 5 — Promotion summary

Show the user a table:

| status | entries |
|---|---|
| Promoted (buffer) | [buffer summary list] |
| Promoted (sessions — new notes) | [count + sample titles] |
| Merged (sessions → existing notes) | [count + sample titles] |
| Deleted (thin sessions) | [list stamps] |
| Escalated to rule/hook | [if any] |
| Dropped (one-off / no generalization) | [buffer list] |
| Held (repetition threshold not met) | [buffer list] |

---

## Constraints

- Write to basic-memory via `mcp__basic-memory__write_note` only — no other persistence. **Single exception:** behavioral/workflow preferences go to native user memory (`feedback-<slug>.md` + `MEMORY.md` index) per the destination rules above — never both stores for the same fact
- **Memory layering contract:** basic-memory = domain knowledge; native user memory = behavioral preferences only; `.cc_settings/.memory` = ephemeral session state
- Write to `.claude/rules` **only** under `CC_SETUP=1` and with explicit user approval (config-guard active)
- Do not promote entries that belong to `.cc_settings/.memory/tasks/<slug>/` (one-off task context)
- Do not create duplicate library entries — check if a similar note already exists in the target folder before writing
