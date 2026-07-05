# Design rationale

This configuration was not designed on a whiteboard. It was extracted from a
production NestJS monorepo setup and then hardened by a systematic analysis of
50 real working sessions (transcript mining: hook denials, user corrections,
interruptions, compaction losses). Each design decision below traces to an
observed failure mode.

## Why a "dumb installer + smart setup skill" split

A shell script can copy files and detect lockfiles; it cannot understand a
codebase. Every attempt to encode "adapt to the project" into installers ends
as a questionnaire nobody answers correctly. The consumer of this config by
definition has Claude Code — so the installer stays deterministic
(`install.sh`: copy, detect, register MCPs) and the intelligence lives in
skills that Claude executes inside the target repo (`/setup-project` →
`bootstrapping-claude-md` / `adapting-claude-md`). The model reads the actual
code and writes documentation of verified facts, asking the human only what
code cannot answer.

## Why guards are hooks, not instructions

Session evidence: behavioral rules that lived only in CLAUDE.md or memory notes
were violated repeatedly (the model "knows" but drifts, and **subagents never
see user memory at all**). Rules that lived in PreToolUse hooks were followed —
eventually. Instructions inform; hooks enforce. Anything that must ALWAYS hold
(no wrong package manager, no bash writes into source dirs, no secrets in
commits) is a hook. Anything that is judgment ("prefer minimal context") is
an instruction or skill.

## Why the denial cap (anti-loop) exists

Observed: the agent retried an identically-blocked command up to 4 times in a
row, and lessons did not survive session boundaries. The cap
(`lib/denial-cap.sh`) tracks consecutive identical denials per guard: the 2nd
hit escalates the message ("do NOT retry; your next call must be X"), and
soft tool-preference guards auto-allow on the 3rd so a genuine edge case can
never deadlock the session. Security guards (secrets, migrations, config
protection) never auto-allow — they only escalate.

## Why hooks are bash + embedded python3 (and why that's OK despite python-guard)

- Hooks must start in milliseconds, parse JSON reliably, and run everywhere —
  `bash` for plumbing, embedded `python3` for JSON/regex logic is the smallest
  portable combination (Node startup is slower; jq is not universally present;
  pure bash JSON parsing is a bug farm).
- The `python-guard` hook blocks python **in the agent's Bash tool calls** —
  that is a workflow rule for the agent (this stack's projects are Node;
  ad-hoc python scripts rot unreviewed), not a runtime constraint. Hook
  internals are infrastructure, not agent workflow; they are allowed to use
  python3. The apparent contradiction is intentional layering.

## Why session hygiene is automated

The two most expensive failure classes in the analyzed sessions were:

1. **Post-compaction amnesia** — after context compaction the model lost
   mid-session constraints and per-file read state ("File has not been read
   yet" errors, forgotten "don't touch git" instructions). Hence:
   `pre-compact-save.sh` (checkpoint + handoff artifact) and
   `post-compact-guidance.sh` (injects recovery rules right after compaction).
2. **Marathon sessions** — 10MB/1000-record sessions accumulated errors and
   lost constraints across multiple compactions. Hence `long-session-nudge.sh`
   (size- AND record-count-triggered suggestion to close at a natural
   boundary; state survives via `save-on-clear` + `session-rehydrate`).

## Why CLAUDE.md is a "thin router"

Token cost: everything in CLAUDE.md is paid on EVERY prompt. The bundled
`bootstrapping-claude-md` skill therefore generates a router of verified facts
(~150 lines: truths, forbidden patterns, commands, routing tables) and pushes
details into path-scoped rules, on-demand docs, and skills. Generic advice
("write clean code") is banned — if a line would be true in every project, it
carries zero information and nonzero cost.

## Why "verification means verification" is a standing rule

Observed worst-case behavior: asked to re-verify a claim, the model rewrote the
artifact to match the user's assertion instead of independently checking the
sources. The rule (baked into the CLAUDE.md template) requires evidence-based
re-analysis of source artifacts for any verification request — agreement is
not verification.

## Why e2e verification is a skill with per-service references

Live feature verification (start services, bootstrap auth, exercise endpoints)
was reconstructed from scratch twice in the analyzed sessions — same recipe,
same pitfalls, hours lost. The skill splits the stable procedure (generic
SKILL.md) from volatile facts (per-service `references/*.md` accumulated as
you use it) — the recipe is written once and compounds.

## Why GSD is not bundled

It is a separately maintained system with its own update cadence; bundling a
snapshot would go stale, and its stock file-reading idioms conflict with this
config's guards until patched. Integration is documented instead
([gsd-integration.md](gsd-integration.md)) — including the exact override
blocks and the warning that GSD updates overwrite them.
