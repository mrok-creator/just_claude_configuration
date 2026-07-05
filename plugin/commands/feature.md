---
name: feature
description: Run the /feature workflow engine — an 11-step plan→test→code→review→commit pipeline with role subagents, approval gates, rework budget, and learning capture. Presets and flags select scope; --codex optionally swaps the test/review executor to Codex.
argument-hint: "[feature|quick|bugfix|refactor|tests|docs|research|hotfix] [--mode productive|balanced|efficient] [--tests|--no-tests] [--codex|--no-codex] [--auto] [--steps 1,2,…] [inline-instruction]"
---

# /feature — workflow orchestration

You are the **workflow orchestrator** for this command. This file is the complete
orchestration body. **Single source of truth for behavior: this file +
`<config-root>/workflow/presets.yml`.** (`(spec §N)` markers below are retained as
stable section anchors from the original implementation spec, which is no longer
shipped as a separate file — do not look for it.) **Never ask the user a question
that this file already answers** — for any ambiguity take the documented default
and note it in the final summary.

Path note: `<config-root>` is `.claude/` for classic installs, or the plugin
installation root for plugin installs (locate once:
`find ~/.claude/plugins -maxdepth 6 -type f -name "bash-guards-dispatcher.sh" | head -1`
→ its grandparent directory).

Read `<config-root>/workflow/presets.yml` at the start of every run — it holds the
canonical presets, flag defaults, mode table, gates, rework budget, and codex
swap config. The text below mirrors it; if they ever disagree, presets.yml wins.

---

## 0. Resolve paths first

1. All task state lives under `.cc_settings/.memory/tasks/<slug>/`.
2. Read the active mode from `.claude/.cc-mode` (`productive|balanced|efficient`).
   A `--mode` flag on the call overrides it for this run only.
3. The learning buffer is `.cc_settings/.memory/buffer.md` (already exists — append, never recreate).

---

## 1. Parse the invocation — `/feature [preset] [flags] [inline-instruction]`

Apply defaults from `presets.yml.defaults`, then override with whatever is on the call:

| Token | Meaning | Default |
|---|---|---|
| `--tests` / `--no-tests` | author + checkpoint tests | **ON** |
| `--mode productive\|balanced\|efficient` | execution mode | **balanced** |
| `--codex` / `--no-codex` | swap steps 4 & 8 executor to Codex | **OFF** (opt-in; requires the `codex` CLI on PATH; the wrapper auto-falls back to Claude Code when it is not) |
| `--auto` | full automation (gates 3 & 12 auto) | absent ⇒ **controlled** |
| `preset` | one of §8 presets | bare call ⇒ `feature` (full) |
| `--steps 1,2,6,7,12` | explicit step set | overrides the preset's steps |

The remaining free text is the **inline instruction** (the task). Note every
defaulted decision so it can be listed in the summary.

---

## 2. Intake (spec §2)

If an **inline instruction is present**, use it as the task and derive the slug.

If **no inline instruction**:
1. `.cc_settings/_inbox/` has files → show them and ask *"is this the target task?"*
   - **yes** → use them as the task.
   - **no** → open a window for the user to provide context + materials.
2. `.cc_settings/_inbox/` empty → open a window for the task + materials directly.

Exception under `--auto`: if there is **no instruction and no `_inbox` content**,
**stop and report** — do not invent a task.

Derive `<slug>` = kebab-case from the instruction. Create
`.cc_settings/.memory/tasks/<slug>/` and point `.cc_settings/.memory/STATE.md` at the
current task + step. Write every artifact **atomically**.

---

## 3. Resolve the step set (spec §8)

- `--steps` present → use exactly those steps (ordered ascending).
- else → use the preset's `steps` from presets.yml.
- **Conditional step 1** (`refactor`, `hotfix`): run step 1 **only if** `_inbox`,
  memory, or `tasks/` holds relevant business context; otherwise skip it.
- **`refactor` tests posture**: ask the user at start whether tests run; under
  `--auto` default tests **ON**.
- **`docs` step 6** = run `/doc-sync`, not code implementation.
- `--no-tests` / a preset with `tests: off` removes step 4 (and step 8's review
  becomes a diff-only review without test intent verification).

Honor the mode (spec §3):
- **efficient** → roles **disabled**; you (the main session) run the resolved
  steps inline with minimal subagents; ambient default-behavior rules do not
  apply; cheap models; single research pass; Codex only if `--codex` is explicit.
  Essential steps still run: plan, approval, validation, commit.
- **balanced** → V1 roles **enabled and strictly spawned on every call**.
- **productive** → roles enabled; opus everywhere; all checkpoints; deepest analysis.

---

## 4. Spawn roles (spec §3, §4) — from balanced and up

From **balanced** upward, spawn each role as a `Task` subagent in lifecycle order,
one at a time, feeding it its inputs and collecting its artifact. In **efficient**
mode, do the step's work inline instead of spawning.

| Step | Role (subagent) | Artifact |
|---|---|---|
| 1 | `planner` | `intake.md` |
| 2 | `architect` | `plan.md` |
| 3 | **Lead presents GATE 1** | *(in-dialog confirmation)* |
| 4 | `test-author` *(or Codex if `--codex`)* | test files |
| 6 | `executor` | code + `touched.txt` + `decisions.md` |
| 7 | **Lead** validates | `validation.md` |
| 8 | `cc-reviewer` *(default; `codex-verifier` if `--codex`)* | `review-report.json` |
| 9 | **Lead** routes rework | (loops back) |
| 10 | **Lead** writes learning | `.cc_settings/.memory/buffer.md` |
| 11 | **Lead presents GATE 2** | commit message |
| 12 | **Lead** summarizes | `summary.md` |

**Model override — set on every role spawn (never left to frontmatter default):**

| Mode | Primary roles (planner, architect, test-author, executor, cc-reviewer, codex-verifier) |
|---|---|
| `efficient` | `sonnet` (roles disabled; `haiku` for any navigation sub-lookup) |
| `balanced` | `sonnet` |
| `productive` | `opus` |

**Role-fence activation — env vars cannot be propagated to subagent spawns via
`Agent()`.** Instead the Lead writes `.cc_settings/.flow-state.json` before each
fenced spawn and deletes it after. The guards (`guard-test-author.sh`,
`guard-executor.sh`) read this file as a fallback when `AI_FLOW_ROLE` is unset.
The Lead owns the write/delete lifecycle.

Spawn shape:

```typescript
// Resolve model from active mode (see table above).
// Write .cc_settings/.flow-state.json BEFORE spawning fenced roles (steps 4, 6).
Agent({
  description: "<role> for <slug> step <n>",
  subagent_type: "planner",   // planner|architect|test-author|executor|cc-reviewer|codex-verifier
  model: "<sonnet|opus per mode table above>",
  prompt: `Task slug: <slug>. Step <n>. Inputs: <paths to prior artifacts>.
           Produce <artifact> at .cc_settings/.memory/tasks/<slug>/<file>.
           Follow your role's allowed/forbidden boundaries.`
})
// Delete .cc_settings/.flow-state.json AFTER the fenced subagent exits.
```

The Lead role owns orchestration + steps 7, 9, 10, 11, 12 and both gates. It never
implements business logic and never edits tests/code outside its own steps.

---

## 5. The sequential 11-step pass (spec §1)

Run the resolved steps in order. Write each artifact before advancing; update
`STATE.md` to the current step.

> Step ids are the stable integers 1–12 **with no step 5** — it was removed from
> the skeleton (historical intermediate-checkpoint step); ids are kept stable for
> preset/artifact compatibility. 11 steps remain.

1. **Intake/analysis** — `planner`: goal; context: Serena LSP, `_inbox`, working
   memory `.cc_settings/.memory/index.md`, and a **basic-memory query** for the touched
   service/area (`mcp__basic-memory__search_notes`, query=service name,
   type=decision/pitfall/mistake/correction, status=current — bounded top-K, read
   full note on demand only); acceptance criteria, edge cases, test intent → `intake.md`.
2. **Plan/architecture** — `architect`: ordered milestone list; each milestone states what · why · what-for · strategy · conventions · requirements covered; no concrete code solutions → `plan.md`.
3. **GATE 1 — plan approval** — interactive revision loop (see §6).
4. **Tests** — Before spawn: write `{"role":"test-author"}` to
   `.cc_settings/.flow-state.json` (guard-test-author.sh reads this to enforce the
   write fence). Spawn `test-author` to author tests from the **approved** test
   intent → test files. After subagent exits: delete `.cc_settings/.flow-state.json`.
   *(skipped when tests are off; performed by Codex when `--codex`, see §7).*
6. **Code** — Before spawn: write `{"role":"executor"}` to
   `.cc_settings/.flow-state.json` (guard-executor.sh reads this to enforce the
   no-test-edit fence via path-based blocking). Spawn `executor`: minimal
   production logic until the authored tests are green; do not touch test files;
   migrations only via CLI → `touched.txt`. Executor must also append non-obvious
   architectural decisions to `decisions.md`. After subagent exits: delete
   `.cc_settings/.flow-state.json`.
7. **Validation** — run the project's validate command on touched projects
   (see `.claude/cc-config.env`: `CC_VALIDATE_CMD` / `CC_PKG_MANAGER`; e.g.
   `npx nx build`/`lint` in an Nx workspace) + scoped tests → `validation.md`.
8. **Review** — independent verification → `review-report.json`
   (`PASS` / `WARNINGS` / `BLOCKED`). `cc-reviewer` by default, or `codex-verifier` under `--codex`.
9. **Rework if BLOCKED** — route to the owner role; **budget = max 3 cycles per
   step** (see §8). After 3 failed cycles on a step, stop and report.
10. **Learning capture** — distilled knowledge → `.cc_settings/.memory/buffer.md`
    (never basic-memory directly), in the buffer entry format (see §9).
11. **GATE 2 — final approval** (see §6) — controlled: pause and show the commit
    message to the user; `--auto`: auto-approve if review passed. Either way:
    output the Conventional Commits message (ticket parsed from branch name) as a
    code block. **Immediately after gate resolves** (approved, auto, or rejected):
    delete `.cc_settings/.flow-state.json` so the next task starts clean. Step 11 is
    **always present**. No `git add`, no `git commit` — only the message is emitted.
12. **Summary** — what was done, tests, validation, review verdict, the commit
    message from step 11, files, risks → `summary.md`.

---

## 6. Gates (spec §9)

### Gate 1 — plan approval (step 3)

**Controlled (default):** Present the full `plan.md` to the user in-dialog, then
enter an approval loop:
1. Ask: *"Approve this plan, or provide feedback to revise it."*
2. **Approved** → proceed to step 4.
3. **Feedback given** → determine revision scope and re-run only the analyses the
   feedback touches:
   - Requirements gap → re-spawn `planner` with the feedback; update `intake.md`.
   - Architecture/design gap → re-spawn `architect` with the feedback and current
     `intake.md`; update `plan.md`.
   Present the updated plan and return to (1).
4. Loop until the user explicitly approves. No disk artifact is written — approval
   is the in-dialog confirmation.

**`--auto`:** Auto-approve if the plan is within the stated scope; if it exceeds
scope, fall back to the controlled loop above and ask.

---

### Gate 2 — final approval (step 11)

**Controlled (default):** Show a concise account of what was done, why these decisions, why this approach, and how it works — then the validation result, review verdict, and the draft Conventional Commits message (ticket from branch name). Then enter an approval loop:
1. Ask: *"Approve and use this commit message, or provide feedback."*
2. **Approved** → emit the commit message as a code block and proceed to step 12.
3. **Feedback given** → route to the owner step using the rework table (§8):
   - architecture → re-spawn `architect` (step 2).
   - requirements → re-spawn `planner` (step 1).
   - tests → re-spawn `test-author` (step 4).
   - bug → re-spawn `executor` (step 6).
   - docs/context → Lead handles inline.
   Re-run all downstream steps (validation, review) after rework, then return
   to (1). Track rework cycles against the budget (max 3 per step, §8).
4. Loop until the user explicitly approves. No disk artifact is written — approval
   is the in-dialog confirmation.

**`--auto`:** Auto-approve if the review returned `PASS` or `WARNINGS`; if
`BLOCKED`, fall back to the controlled loop above.

After gate 2 resolves (approved, auto, or rejected): **delete
`.cc_settings/.flow-state.json`** unconditionally. No `git add`, no `git commit` —
commit message only.

---

## 7. Codex executor-swap (spec §5) — OPTIONAL

Codex is an **optional** integration: it activates only when the user passes
`--codex` and the `codex` CLI is installed. Without it, `test-author` and
`cc-reviewer` own steps 4 and 8 — that is the default.

`--codex` does **not add steps** — it swaps the **executor** of two steps:
- **Step 4 (tests)** → written by **Codex** (`codex-verifier` agent drives, or call
  the wrapper directly with `--step tests`).
- **Step 8 (review)** → performed by the **Codex Verifier**.

Always pass **`intake.md` (step 1) + `plan.md` (step 2)** to Codex on both steps —
mandatory; Codex misbehaves without them. The wrapper feeds context + diff in and
returns a structured report via `--output-schema`:

```bash
bash <config-root>/setup/codex-exec.sh --task <slug> --step review   # or --step tests
```

**Availability detect:** if `codex` is not on PATH the wrapper exits **3**. On exit
3, fall back to Claude Code (`test-author` for step 4 / `cc-reviewer` for step 8)
and record the fallback as a **warning in `summary.md`**.

---

## 8. Rework budget (spec §1.9, §4)

When step 8 returns **BLOCKED**, route each blocking finding to its owner and
re-run the affected step:

| Finding area | Route to |
|---|---|
| architecture | `architect` (step 2) |
| requirements | `planner` (step 1) |
| tests | `test-author` (step 4) |
| bug | `executor` (step 6) |
| docs / context | Lead |

Track cycles **per step**. **Max 3 rework cycles per step.** If a step is still
BLOCKED after 3 cycles, halt the workflow, write what was reached to `handoff.md`,
and report — do not loop indefinitely.

---

## 9. Step 10 — learning buffer (spec §7)

Append distilled lessons to `.cc_settings/.memory/buffer.md` (preceded by `\n---\n`),
using the buffer entry format:

```
**type:** architecture | pitfall | deviation
**summary:** one line (specific — used for dedup)
**detail:** what happened / what was decided
**root:** why / cause
**resolution:** how resolved
**generalization:** "Going forward: X" OR "one-off, no generalization"
**context:** <slug> / service / module
**destination:** library | rule | hook | ephemeral
**captured:** <ISO-8601 UTC>
```

Record only non-obvious decisions, pitfalls, or conscious deviations — not routine
work. **Do not write to basic-memory** from this step; promotion is the separate
`/learn-process` command.

---

## 10. Step 12 — summary (spec §11)

`summary.md` and the final chat response must be **concise — no rambling**. Answer:
- **what** was done;
- **why** these decisions;
- **why** this approach (and the alternative rejected, where non-obvious);
- **how** it works.

Then add: touched file paths · validation result · review verdict · commit message from step 11 · real open risks only (Codex-fallback warning if applicable). Keep the chat response concise; code, paths, and identifiers stay in English.

---

## 11. Artifacts (spec §10) — written under `.cc_settings/.memory/tasks/<slug>/`

`intake.md` · `plan.md` · `touched.txt` · `validation.md` ·
`review-report.json` · `decisions.md` · `summary.md` · `handoff.md`. Atomic
writes; keep `STATE.md` pointed at the current task/step.

---

## Notes on discipline

- Honor all project hooks and rules (CLAUDE.md, `.claude/rules/`). The Test Author
  and Executor fences are enforced by `guard-test-author.sh` / `guard-executor.sh`.
  Because `Agent()` spawns cannot carry env vars, the fence signals via
  `.cc_settings/.flow-state.json` (Lead writes before spawn, deletes after). The env
  var `AI_FLOW_ROLE` is also accepted (external TDD flows).
  Never fight a block — route the need to the owning role.
- Smallest valid change; preserve contracts, naming, DTO shapes, patterns.
- Never skip step 11 (gate 2). Never bypass a gate in controlled mode.
- **Concurrency constraint:** `.cc_settings/.flow-state.json` is worktree-global —
  run at most ONE /feature workflow per worktree at a time. Parallel tickets go
  in separate git worktrees (the per-ticket worktree layout).
