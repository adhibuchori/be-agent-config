# Backend Testing Conventions

> `bunfig.toml` ships in this config layer and already wires `preload`. Copy
> `.claude/test-preload.example.ts` to `src/test/preload.ts` and delete the clients your repo
> does not have. The quality gate runs `bun run test:coverage`; add the three `test` scripts to
> `package.json` (`bun test src`, `bun test src --coverage`, and the `RUN_INTEGRATION_TESTS=1`
> variant).
>
> **Bun enforces `coverageThreshold` per file, not in aggregate.** An 84% overall figure still
> fails the gate if one handler sits at 13%.
>
> **One rule that is not obvious and cost a real network call to learn:** every external client
> is replaced once in `src/test/preload.ts`, never per test file. `mock.module` mutates a
> registry shared by the whole run, so two files mocking the same module is last-write-wins and
> the loser silently inherits the other's mock. Steer through the controls `preload.ts` exports
> (`resendControl`, `redisControl`, `dbControl`, `authControl`, `xenditControl`) and reset with
> `resetExternalMocks()` in `beforeEach`.

Two tiers, both on Bun's built-in runner (`bunfig.toml` scopes discovery to `src/`). See
`AGENTS.md` §E for the enforced, numbered rules — this file is the deeper reference.

## Unit tests — `bun test src`

- Co-located under each module's `__tests__/`, named `<unit>.test.ts`.
- No real Postgres, no real Redis, no network. Services take their dependencies as default
  parameters (see `AGENTS.md` §B Rule 7); tests override them with a plain object.
- Module-local mock builders in `__tests__/helpers.ts`, named `create<Thing>Mock(overrides)`.
  Keep helpers module-local until real duplication across modules justifies a shared helper —
  do not build a generic `test-utils` package speculatively (YAGNI, `common/coding-style.md`).

```ts
// src/modules/meta/__tests__/helpers.ts — the reference example
export function createDbMock(overrides: Partial<DbLike> = {}): DbLike {
  return { execute: async () => undefined, ...overrides };
}
```

## Integration tests — `bun run test:integration`

- File suffix `*.integration.test.ts`.
- Gated by `shouldRunIntegrationTests()` (`src/test/config.ts`), which reads
  `RUN_INTEGRATION_TESTS=1`:

```ts
import { test } from "bun:test";
import { shouldRunIntegrationTests } from "../../test/config.ts";

const testIntegration = shouldRunIntegrationTests() ? test : test.skip;
testIntegration("does the real thing against Postgres", async () => { /* ... */ });
```

- Requires `docker compose up -d` locally (Postgres 17 + Redis 7); CI runs this tier with
  service containers instead.
- Isolate fixtures with UUID-suffixed IDs so parallel test files (or reruns) don't collide on
  the same row.

## Query tests

Anything that runs SQL is integration-tier by definition — a unit test cannot tell you whether
an index is used or a transaction commits.

For a query whose *shape* matters (Rule 32: it was written against a specific index), assert the
generated SQL directly. That test runs in the unit tier and fails the moment someone reorders an
`ORDER BY` or drops a `WHERE` clause the index depended on:

```ts
const { sql, params } = buildThingPageQuery(cursor).toSQL();
expect(sql).toContain('order by "created_at" desc, "id" desc');
expect(params).toEqual([cursor, 51]);
```

Pair it with an integration test that runs the query against real Postgres for correctness.

## Route-level tests

Use `app.request(...)` against the real exported `app` (`src/app.ts`). Import the real
`handleAppError` indirectly through `app.onError` rather than asserting against a hand-rolled
error shape — a route test that redeclares its own error mapper can pass while the real
mapping has drifted.

## Coverage

`bun run test:coverage` (`bun test src --coverage`). Threshold and path exclusions live in
`bunfig.toml` — read the comment there before changing either; it explains why composition-only
files (`app.ts`, `index.ts`, `env.ts`, `db/**`) are excluded from the 80% threshold rather than
just being under-tested.
