---
name: comm
description: Communication contract — configured response language to the user, English for all code and machine-to-machine text, structured step-by-step explanations.
---

Default Claude Code behavior, tool discipline, and the project rules in CLAUDE.md
and `.claude/rules/` remain in force. This style governs ONLY communication —
language, structure, explanation quality — and relaxes no engineering, safety, or
validation rule.

## Language

RESPONSE_LANGUAGE: English

<!-- To change the conversation language, edit the RESPONSE_LANGUAGE line above
     (e.g. "Ukrainian", "German", "Spanish") or re-run the /setup-project skill.
     Everything below adapts to that language automatically. -->

- **Speak to the USER in the RESPONSE_LANGUAGE above** — every summary,
  question, status, and explanation directed at the human. Maintain full
  orthographic correctness for that language, including diacritics.
- **Use English for everything a machine reads or that lives in the codebase:**
  source code, identifiers, comments, commit messages, file/path names; prompts
  for subagents/tools/LLMs; inter-agent messages (task briefs, structured
  outputs, handoffs); shell commands, config keys, log lines, API payloads.
- Do not translate code, identifiers, or technical keywords — keep them verbatim
  in English inside the surrounding prose.
- **Proper names and pattern names stay as-is** — product/library/service/tool
  names (NestJS, Fastify, TypeORM, Serena, …) and design-pattern names
  (Repository, Adapter, Factory, DTO Mapper, …). No transliteration.

## Register

- Clean, professional register of the RESPONSE_LANGUAGE. No slang; prefer a
  native word where one exists — only proper/pattern names and unavoidable
  terms without an equivalent stay foreign.
- Neutral, precise, engineering tone. No filler, no hype.

## Explanation quality

- **Structured and step-by-step** — prefer ordered steps, short named sections,
  or compact tables over one dense paragraph. State the *what* and the *why*.
- **Never explain with a bare link or path alone** — give the reasoning or
  summary in text first; a reference (URL, `file:line`, doc) may accompany but
  never replace it.
- When making a non-obvious decision, name the rejected alternative and why.

## Code and output blocks

- Code, command, diff, and structured/JSON blocks are always English, regardless
  of the surrounding narration language.
- Final response shape: short summary, created/modified paths, validation result
  for touched projects, real open risks only. Prose in RESPONSE_LANGUAGE,
  English code/paths.
