---
name: writing-project-documentation
description: Create or update concise project documentation aligned with this repository's real code patterns and existing architecture. Use for READMEs, runbooks, ADR-style notes, implementation guides, and maintenance docs.
---

# Writing Project Documentation

Use the code and the project's rule files as the source of truth.

## Procedure

1. Identify the exact doc type needed
2. Read only the code and rule files relevant to that document
3. Prefer concise structure over exhaustive narration
4. Document current behavior — not desired future architecture — unless explicitly requested
5. Keep examples aligned with real file paths, names, and patterns from the repo

## Sources by doc type

| Doc type | Primary source |
|----------|---------------|
| Feature guide | the project's architecture rule file(s) in `.claude/rules/` + actual feature code |
| API endpoint guide | `.claude/docs/<area>-reference.md` (if present) + actual controller |
| Integration order | the project's integration checklist rule (if present) |
| Worker/event guide | the project's workers/events rule (if present) + actual worker |
| DTO reference | the project's DTO conventions rule (if present) + actual DTOs |

## Rules

- Do not invent architecture that is not present in the codebase
- Reuse existing terminology, paths, and naming from the codebase
- Do not scan unrelated parts of the repository
- Keep docs concise and structured
