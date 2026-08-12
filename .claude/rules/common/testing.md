# Testing Requirements

> ⚠️ **This repo has no tests yet** (AGENTS.md §E, tracked deviation). The two-tier layout —
> unit (`bun test src`, no DB/Redis) and integration (`bun run test:integration`, real Postgres
> + Redis) — is described in [../backend/testing.md](../backend/testing.md) and is what to build
> toward. The practices below apply from the first test written.

## Minimum Test Coverage: 80%

The target once a suite exists. Threshold and path exclusions belong in `bunfig.toml`, with
composition-only files (`app.ts`, `index.ts`, `env.ts`, `db/**`) excluded deliberately rather
than silently under-tested.

## Test-Driven Development

MANDATORY workflow:

1. Write test first (RED)
2. Run test - it should FAIL
3. Write minimal implementation (GREEN)
4. Run test - it should PASS
5. Refactor (IMPROVE)
6. Verify coverage (80%+)

## Troubleshooting Test Failures

1. Check test isolation
2. Verify mocks are correct
3. Fix implementation, not tests (unless tests are wrong)

## Test Structure (AAA Pattern)

Prefer Arrange-Act-Assert structure for tests:

```typescript
test('calculates similarity correctly', () => {
  // Arrange
  const vector1 = [1, 0, 0];
  const vector2 = [0, 1, 0];

  // Act
  const similarity = calculateCosineSimilarity(vector1, vector2);

  // Assert
  expect(similarity).toBe(0);
});
```

### Test Naming

Use descriptive names that explain the behavior under test:

```typescript
test('returns empty array when no markets match query', () => {});
test('throws error when API key is missing', () => {});
test('falls back to substring search when Redis is unavailable', () => {});
```
