---
name: tdd-workflow
description: Test-driven development workflow — write a failing test first, implement the minimum to make it pass, then refactor. Use when the task explicitly requests tests or when implementing logic with clear input/output contracts (services, mappers, validators, utility functions).
---

# TDD Workflow

Test-driven development workflow for features in this repository.

## When to use

Use when the task explicitly requests tests or when implementing logic with clear input/output contracts (services, mappers, validators, utility functions).

Do NOT use for:
- Pure wiring tasks (module imports, provider registration)
- Mechanical refactors (rename, move, delete dead code)
- Configuration or migration changes

## Workflow

### Step 1 — Identify test scope

Read the feature's existing test files (if any) and follow the repository's
established spec-file placement convention. Example for an Nx monorepo where
spec files live in a `test/` tree mirroring `src/`:

```
apps/<your-service>/test/app/modules/<feature>/**/*.spec.ts
```

Determine what type of test fits:
- **Unit test** — isolated service/entity logic with mocked dependencies
- **Integration test** — repository or module-level with real DB (if test infra exists)

### Step 2 — Write failing test first

Create or update the spec file at the location the repository's convention
dictates (e.g. the `test/` tree mirroring `src/` — check where existing spec
files live and match that layout exactly).

```typescript
describe('FeatureService', () => {
  // Arrange: mock dependencies using jest.fn() or jest.mock()
  // Act: call the method under test
  // Assert: verify output and side effects
});
```

### Step 3 — Run test to confirm failure

Run the project's test command scoped to the new spec (see
`.claude/cc-config.env`: `CC_VALIDATE_CMD` / `CC_PKG_MANAGER` for the project's
configured commands). Example for an Nx workspace:

```bash
npx nx test <project> --testFile=<relative-path-to-spec> --testNamePattern="<test name>"
```

Verify the test fails for the RIGHT reason (missing implementation, not broken setup).

### Step 4 — Implement minimal code

Write the smallest implementation that makes the test pass. Do not add untested behavior.

### Step 5 — Run test to confirm pass

```bash
npx nx test <project> --testFile=<relative-path-to-spec>   # example (Nx)
```

### Step 6 — Refactor

Clean up implementation while keeping tests green. Run tests after each refactor pass.

## Test conventions

### Mocking

- Use `jest.fn()` for service dependencies
- Use `jest.spyOn()` when you need to observe calls on real instances
- Mock repository ports — never use real DB in unit tests
- Mock external services (RPC clients, producers, provider APIs)

### Assertions

- Use `expect(...).toEqual()` for value comparison
- Use `expect(...).toHaveBeenCalledWith()` for interaction verification
- Use `expect(...).rejects.toThrow()` for error paths

### Test structure

```typescript
describe('ClassName', () => {
  let sut: ClassName;
  let dependency: jest.Mocked<DependencyType>;

  beforeEach(() => {
    dependency = { method: jest.fn() } as any;
    sut = new ClassName(dependency);
  });

  describe('methodName', () => {
    it('should do X when Y', async () => {
      // Arrange
      dependency.method.mockResolvedValue(mockData);
      // Act
      const result = await sut.methodName(input);
      // Assert
      expect(result).toEqual(expected);
    });
  });
});
```

### Running tests

- Single file: `npx nx test <project> --testFile=path/to/file.spec.ts` (example — use the project's test command)
- Single test: add `--testNamePattern="test name"`
- Full project: only when explicitly asked

## Guardrails

- Do not write tests for code you did not implement or touch
- Do not test private methods directly — test through public interface
- Do not mock what you own when integration test infra exists
- Keep test files where the repository's convention places them — never invent a new layout
- One describe block per class, nested describe per method
