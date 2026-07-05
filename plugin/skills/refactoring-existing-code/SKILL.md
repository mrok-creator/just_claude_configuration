---
name: refactoring-existing-code
description: Refactor touched code for clarity, maintainability, or typing without changing architecture or widening scope. Use when cleaning up current code, removing duplication, or applying a targeted refactor.
---

# Refactoring Existing Code

Follow the project's architecture rules in `.claude/rules/` (if present).

## Procedure

1. Define the exact refactor scope from the touched file(s)
2. Preserve current contracts, naming, DI tokens, DTO shapes, and message patterns
3. Make mechanical changes first — behavioral changes require separate task
4. Validate only the touched project (run the project's validate command — see `.claude/cc-config.env`: `CC_VALIDATE_CMD`)

## Safe without approval

- Adding explicit return types
- Replacing `any` with proper types (flag if interface is complex)
- Extracting magic strings to existing constants
- Adding `private readonly`
- Removing dead code (`// todo DELETE`, unused imports)
- Splitting long private methods into private helpers within same class

## Requires approval before applying

- Renaming files, classes, methods, tokens, patterns, interfaces
- Moving files between directories
- Changing base class or interface contract
- Splitting or merging modules
- Changing existing endpoint response DTO shape

## Never as part of another task

- Rewriting business logic
- Altering migration files
- Removing providers/imports without impact check
- Changing `any` in shared base classes used across the codebase
