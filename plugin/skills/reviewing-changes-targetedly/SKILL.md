---
name: reviewing-changes-targetedly
description: Review only the changed files and their direct dependencies for correctness, architecture alignment, DTO contract issues, and unnecessary complexity. Use after code changes or before final delivery.
allowed-tools: Read, Grep, Glob, Bash
---

# Reviewing Changes Targetedly

Use the project's architecture rules in `.claude/rules/` (if present) as the authority.

## Review scope

- Changed files first
- Direct dependencies only when needed to verify contracts
- One similar reference feature only when a pattern check is required
- Do not perform repo-wide audits

## Review checklist

(Example items for a NestJS-style backend — adapt to your project's rules.)

- Correct layer boundaries (controller → allowed layers only)
- No repository injection directly in business services
- No raw SQL outside repository implementations
- Message payloads have typed DTOs
- No domain/ORM entities returned from controllers
- Message patterns referenced via constants — no string literals
- No `any` in new or touched code
- Error handling follows per-layer rules
- Module wiring complete (providers registered, module imported)
- No dead code

## Output

Return only concrete file-specific findings and the smallest safe fix.
Do not suggest architectural redesigns unless a hard rule is violated.
