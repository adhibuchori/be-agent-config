# AGENTS.md — <Project Name> BE

> Enforced guardrails. Read §A and the Compliance Status table below before touching any code.

Every rule below is falsifiable and carries an **Enforcement** column: a lint rule name, a CI step,
a hook script, or the literal tag `advisory` (checked by code review or the reviewer subagent, not
by a machine). A rule that only lives in prose is a wish — see `.claude/anti-patterns/` for what
happens when one gets skipped.

> **If several repos share this numbering**, say so here and never renumber locally — only append.
> A review citing "Rule 12" otherwise means two different things depending on who is reading, and
> the rule-drift CI check will disagree with both.

---

## Compliance Status — read this first

> **Fill this table in honestly before you use this document.** It is the single highest-value
> section here, and the one most often skipped.

Most repos adopt rules **after** growing a real domain. Some sections will describe what the code
already does; others describe a target it has not reached. Stating which is which is what keeps the
whole document trustworthy — an agent that cites a rule for a file that does not exist wastes a
session, and after that it stops trusting any rule in the file.

| Section | Status | What that means here |
|---|---|---|
| §A Protocol | `<Enforced / Partial / Not met>` | `<what applies as written>` |
| §B Layer boundaries | `<status>` | `<name the specific rules enforced, and by what>` |
| §C Error contract | `<status>` | `<if a target shape is not yet implemented, say so and name the shape to follow in the meantime>` |
| §D Database | `<status>` | `<...>` |
| §E Testing | `<status>` | `<if no suite exists, say so plainly — "apply to new code where practical" is honest, silence is not>` |
| §F Security | `<status>` | `<...>` |
| §G Code quality | `<status>` | `<mark aspirational rules as aspirational>` |
| §H Query & performance | `<status>` | `<...>` |
| §I Runtime hardening | `<status>` | `<...>` |

Three conventions that make this table work:

**Three states, not two.** "Partial" carries most of the value — a section where two rules bind and
one does not is the common case, and collapsing it to Enforced or Not met loses exactly the detail
someone needs.

**Say what to do in the meantime.** A section marked Not met should name the shape to follow until
the migration lands. Otherwise each contributor invents a third shape, and the migration gets
harder rather than easier.

**List the follow-up work in order.** A numbered list below the table, each entry naming the
section it unblocks, turns a list of deviations into a plan.

Tracked follow-up work, in the order it should happen:

1. `<work item>` — unblocks §`<section>`
2. `<work item>` — unblocks §`<section>`

Finally, record any **known behaviour that looks like a bug and is not**. Something like a health
endpoint reporting a failed dependency inside a 200 response is the kind of thing that gets
"fixed" by someone who does not know it was deliberate — one sentence here prevents that.

---

## §A. Protocol

| # | Rule | Enforcement |
|---|------|-------------|
| 1 | **Read first.** Identify every file a change touches before writing code. State what will change and why if the approach isn't obvious. This repo's commit convention is `type: description` (no scope) — deliberately different from the FE fleet's `type(scope): subject`, because that FE format is itself inconsistent across its own docs (see the refactor plan); picking one clean format here rather than propagating the ambiguity. | advisory |
| 2 | **Simplicity first.** Minimal change that achieves the goal. Do not add abstractions — a repository layer, a shared test helper, a new lib module — that nothing currently needs. | advisory / `agents-reviewer` |
| 3 | **Surgical changes.** Do not touch files outside the task's scope, including reformatting code you didn't otherwise change. | advisory / `agents-reviewer` |
| 4 | **Service layer is mandatory. Repository is added only on escalation.** Default shape is `handler → service → db`. Add `<module>.repository.ts` only when at least one holds: the service coordinates multiple queries/tables · it needs a transaction · it holds policy worth unit-testing without a DB · the same query bundle is reused elsewhere · direct Drizzle access is hurting readability. Do not add a repository mechanically for single-query CRUD. | advisory / `agents-reviewer` |

---

## §B. Layer Boundaries

**Rule 5 — Layer ownership**

| Layer | File | Responsibility | Present here? |
|-------|------|-----------------|---|
| Routes | `<module>.routes.ts` | `createRoute()` specs + `app.openapi(route, handler)` binding. Declares every `responses` entry the handler can actually return. | yes |
| Handler | `<module>.handler.ts` | HTTP glue. Reads `c.req.valid(...)`, calls the service (or, today, the repository), shapes the response. ≤15 lines (Rule 28). | yes |
| Service | `<module>.service.ts` | Pure business logic. Never imports `Context`. Dependencies injected via default parameters. | **only `modules/meta`** — see Compliance Status |
| Repository | `<module>.repository.ts` | DB access. Owns transaction boundaries. | yes (auth·courses·payments) |
| Schema | `<module>.schema.ts` | Zod request/response schemas. | yes |
| Errors | `<module>.errors.ts` | Module-specific `DomainError` subclasses. | **no — §C deviation** |
| Index | `index.ts` | Barrel — the ONLY file another module or `app.ts` may import from. | yes |

The existing modules skip the service layer and call the repository straight from the handler.
That is the deviation recorded above, not a licence to add more of it: **a new module gets a
service.** `src/modules/meta/` is the one module in this repo built to the full shape — copy it,
not `courses/`.

Enforcement: `.oxlintrc.json` overrides for `src/modules/*/**`.

**Rule 6 — Handlers: ALLOWED / FORBIDDEN**

```ts
// FORBIDDEN — handler reaching into the DB directly
import { db } from "../../db/index.ts";
export const getThing: RouteHandler<typeof getThingRoute, AppEnv> = async (c) => {
  const row = await db.select()... // no — this belongs in the service
  return c.json(row, 200);
};

// ALLOWED — thin glue, service owns the logic
import { getThingReport } from "./thing.service.ts";
export const getThing: RouteHandler<typeof getThingRoute, AppEnv> = async (c) => {
  const report = await getThingReport();
  return c.json(report, 200);
};
```

Enforcement: `.oxlintrc.json` — `src/modules/*/*.handler.ts` forbids importing `drizzle-orm`,
`postgres`, or anything under `**/db/**`.

**Rule 7 — Services are pure**

No `Context` import, ever. Dependencies come in as default parameters so a test can override
them with a plain object — no container, no mocking library:

```ts
// src/modules/meta/meta.service.ts — the reference example
export async function getHealthReport(
  deps: { db?: DbLike; redis?: RedisLike } = {},
): Promise<HealthResponse> {
  const dbClient = deps.db ?? db;
  const redisClient = deps.redis ?? redis;
  // ...
}
```

Enforcement: advisory / `agents-reviewer`.

**Rule 8 — Cross-module imports go through `index.ts` only**

```ts
// FORBIDDEN — reaching into another module's internals
import { getHealthReport } from "../meta/meta.service.ts";

// ALLOWED — the module's public barrel
import { metaRouter } from "../meta/index.ts";
```

Enforcement: `.oxlintrc.json` — `src/modules/*/**` forbids `../*/[!index]*`.

**Rule 9 — `lib/` and `middlewares/` never import from `modules/`**

The dependency direction is one-way: `modules/* → lib/*, db/*, middlewares/*`. Reversing it
creates a cycle the moment two modules share infrastructure.

Enforcement: `.oxlintrc.json` — `src/lib/**` and `src/middlewares/**` forbid `**/modules/**`.

**Rule 10 — Repository escalation criteria** — see Rule 4. Do not pre-build a repository
"in case it's needed later" (YAGNI) — add it the commit a real escalation condition is met.
Enforcement: advisory / `agents-reviewer`.

---

## §C. Errors — RFC 9457 `application/problem+json`

> ⚠️ **TARGET STATE, NOT CURRENT STATE.** None of `lib/errors.ts`, `lib/problem.ts`, or
> `DomainError` exists in this repo yet. Today `middlewares/error.middleware.ts` maps errors to
> `{ success: false, error }` and some handlers build 404 bodies inline. Read this section to
> know where the repo is heading and to review the migration PR — but while writing code today,
> **match the existing envelope**. Introducing a third error shape is strictly worse than
> either one consistently. Rule numbers are kept aligned with the fleet; see Compliance Status.

**Rule 11 — Every thrown error is a `DomainError` subclass or a Hono `HTTPException`.** Never
hand-roll a JSON error body (`c.json({ error: "..." }, 400)`) in a handler or service — that's
exactly the four-envelope drift this contract replaced. `src/lib/problem.ts`'s
`handleAppError` (wired via `app.onError` in `src/app.ts`) is the only place a thrown error
becomes a response. Enforcement: advisory / `agents-reviewer`.

**Rule 12 — `userMessage` is client-safe. The second constructor argument (`internalDetail`)
is logs-only and must never contain IDs, stack traces, or internals that could help an
attacker.**

```ts
// src/modules/meta/meta.errors.ts — the reference example
export class HealthCheckFailedError extends ServiceUnavailableError {
  constructor(report: { database: string; redis: string }) {
    super(
      "One or more dependencies are unhealthy.",       // userMessage -> client
      `database=${report.database} redis=${report.redis}`, // internalDetail -> logs only
      "META_HEALTH_UNHEALTHY",                          // stable machine code
    );
  }
}
```

Enforcement: advisory / `agents-reviewer`.

**Rule 13 — Every route declares the error responses its service can actually throw**, via
`errorResponses(...)` from `src/lib/problem.ts`, plus `422` (the shared `defaultHook` can fire
on any route with request validation). A route whose `responses` map only lists `200` is lying
to the OpenAPI spec the moment its service throws anything. Enforcement: advisory (no automated
OpenAPI-vs-service-throws diff exists yet — flag in review).

**Rule 14 — A new HTTP status needs a new base class in `src/lib/errors.ts`,** not a one-off
inline error shape. The five bases (`NotFoundError`, `ValidationError`, `ForbiddenError`,
`ConflictError`, `ServiceUnavailableError`) cover 404/400/403/409/503; extend `DomainError`
directly for anything else. Enforcement: advisory.

---

## §D. Database

**Rule 15 — Never import `drizzle-orm`, `postgres`, or `src/db/**` in a `*.handler.ts`.**
Enforcement: `.oxlintrc.json` (see Rule 6).

**Rule 16 — Never hand-edit `src/db/migrations/`.** Generated by `bun run db:generate` only.
Enforcement: `.claude/hooks/migration-guard.sh` (blocking) + `scripts/check-migrations.sh` in CI
(fails the PR if the migrations directory is out of date with the schema).

**Rule 17 — `src/db/index.ts` holds the one real connection pool for the running app.**
`{ max: 1 }` belongs only in `src/db/migrate.ts`, where a migration run genuinely needs a
single serialized connection. See `.claude/anti-patterns/postgres-max-1-pool.md`. Enforcement:
advisory / `agents-reviewer`.

**Rule 18 — Transaction boundaries live in the repository** (`db.transaction(async (tx) => ...)`)
when one exists — never spread a multi-statement transaction across a service function.
Enforcement: advisory.

---

## §E. Testing

> ⚠️ **TARGET STATE, NOT CURRENT STATE.** This repo has **no tests at all** — no `test` script,
> no `bunfig.toml`, no `__tests__/` directory, and `src/test/config.ts` does not exist. The
> rules below describe the tiering to build toward, and they are already followed by
> `src/modules/meta/meta.service.ts` (dependencies injected via default parameters, so it is
> unit-testable the moment a runner exists). Do not cite these rules to block a PR until the
> suite is bootstrapped; do write new services so they *can* be tested.

**Rule 19 — Every module's service ships with unit tests and a local
`__tests__/helpers.ts`** exposing mock builders (`createXMock(overrides)`) before the module is
considered done. Keep helpers module-local until duplication across modules proves a shared
helper is worth it (see `src/modules/meta/__tests__/helpers.ts`). Enforcement: advisory /
`agents-reviewer`.

**Rule 20 — Unit tests (`bun test src`) never touch real Postgres or Redis.** Anything that
needs a live dependency is a `*.integration.test.ts` file gated by
`shouldRunIntegrationTests()` (`src/test/config.ts`):

```ts
const testIntegration = shouldRunIntegrationTests() ? test : test.skip;
testIntegration("persists a row", async () => { /* real db */ });
```

Enforcement: CI runs the two tiers as separate jobs (`bun run test` vs.
`bun run test:integration`, the latter with Postgres 17 + Redis 7 service containers).

**Rule 21 — Route-level tests import the real `handleAppError`** from `src/lib/problem.ts`
(via `app.ts`), never redeclare an inline error mapper — otherwise the test can pass while the
real mapping has silently drifted. Enforcement: advisory / `agents-reviewer`.

---

## §F. Security

**Rule 22 — Never read `process.env` outside `src/env.ts`.** It is the only file that
validates and re-exports environment variables. Enforcement: advisory.

**Rule 23 — Never `console.*`.** Use `src/lib/logger.ts` (Pino). Enforcement:
`.oxlintrc.json` `no-console: error` (exempted only in `src/env.ts` and `src/db/migrate.ts`,
which run before the logger can exist).

**Rule 24 — In `rate-limit.middleware.ts`, `await next()` must never sit inside the Redis
try/catch.** Only the Redis bookkeeping is allowed to fail open; the request's own
allow/deny decision must be resolved before `next()` runs, exactly once. See
`.claude/anti-patterns/rate-limit-double-next.md`. Enforcement: advisory / `agents-reviewer`.

**Rule 25 — No `.env` file or secret is ever committed.** Enforcement: `quality-gate.yaml`
secret scan (gitleaks) + `.env`-committed check, both diffing the actual PR range.

---

## §G. Code Quality

**Rule 26 — Max 200 lines per file (error, not warning).** Split into smaller files —
service, repository, sub-handler — before it grows past this. Enforcement: `.oxlintrc.json`
`max-lines: ["error", { max: 200 }]`.

**Rule 27 — No `oxlint-disable` comments.** Fix the underlying issue instead of suppressing
the lint. Enforcement: advisory / `agents-reviewer`.

**Rule 28 — Handlers stay ≤15 lines.** If a handler grows past that, the excess is business
logic that belongs in the service. Enforcement: advisory / `agents-reviewer`.

---

## §H. Query & Performance

The deeper reference for everything here is `.claude/rules/backend/drizzle.md` (schema, index,
and query patterns) and `.claude/rules/backend/performance.md` (caching, budgets, N+1
checklist). This section is the enforced, numbered subset.

**Rule 29 — No unbounded reads.** Every list query carries an explicit `.limit()`, and every
list endpoint is paginated. **Keyset is the default** — it stays O(1) at any depth and, unlike
`OFFSET`, cannot skip or duplicate rows when the underlying data changes mid-traversal:

```ts
// keyset — needs a composite index on (created_at DESC, id DESC), see Rule 32
const page = await db
  .select({ id: things.id, name: things.name, createdAt: things.createdAt })
  .from(things)
  .where(cursor ? lt(things.createdAt, cursor) : undefined)
  .orderBy(desc(things.createdAt), desc(things.id))
  .limit(limit);
```

`.offset()` is allowed only for an admin table that is known to stay small and genuinely needs
jump-to-page; when you use it, write the row ceiling you are assuming in a comment.
Enforcement: advisory / `agents-reviewer`.

**Rule 30 — Select columns explicitly.** `db.select({ id: t.id, name: t.name })`, never a bare
`db.select()` on a table carrying `text`, `jsonb`, or array columns — a bare select ships every
byte of those columns over the wire on every request. In the relational query builder use
`columns: {...}`, which Drizzle applies as a partial select at the query level (no extra data
leaves Postgres). Enforcement: advisory / `agents-reviewer`.

**Rule 31 — No query inside a loop (N+1).** Batch with `inArray()`, a join, or the relational
query builder's `with:` — Drizzle emits that as a single statement using `LEFT JOIN LATERAL` +
`json_agg`, not one query per parent row. Independent queries go in `Promise.all`:

```ts
// FORBIDDEN — one round trip per id
for (const id of ids) rows.push(await db.select().from(things).where(eq(things.id, id)));

// ALLOWED — one round trip
const rows = await db.select().from(things).where(inArray(things.id, ids));
```

Enforcement: `.oxlintrc.json` `no-await-in-loop: error`.

**Rule 32 — Every column you filter, sort, or join on is indexed, in the same PR as the
query.** Foreign key columns are always indexed — Postgres creates an index for a PRIMARY KEY
but **not** for a `REFERENCES` column. Composite index column order is equality columns first,
then the range/sort column. Use a partial index when the query always carries the same constant
predicate. Enforcement: `scripts/check-index-coverage.sh` (CI) + `agents-reviewer`.

**Rule 33 — A query against a table expected to exceed ~100k rows ships with `EXPLAIN (ANALYZE,
BUFFERS)` output in the PR.** A `Seq Scan` on a request-path query is a blocker unless the PR
says why it is acceptable. Enforcement: `.github/PULL_REQUEST_TEMPLATE/dev.md` checklist.

**Rule 34 — Hot-path queries use prepared statements** — `.prepare("name")` plus
`sql.placeholder()`, so the SQL is concatenated once and Postgres reuses the parsed plan. Do
not prepare one-off or admin queries: prepared statements only pay off on repeated execution,
and they buy nothing when the query is slow to *execute* rather than slow to *parse*. Behind a
transaction-mode pooler (PgBouncer, Supabase pooler) server-side prepared statements break
outright — that deployment requires `DB_PREPARE=false` (Rule 38). Enforcement: advisory.

**Rule 35 — Transactions are short and live in the repository.** No HTTP call, no Redis round
trip, no non-DB `await` inside `db.transaction()` — every one of those holds a connection and a
row lock open for the duration of something the database cannot see. The upper bound is
enforced by `statement_timeout` and `idle_in_transaction_session_timeout` on the pool (Rule 38).
Enforcement: advisory / `agents-reviewer`.

**Rule 36 — Writes are batched.** One `db.insert(t).values([...])` for N rows, never N inserts.
Upsert via `.onConflictDoUpdate()` — a select-then-insert is a race, not an upsert.
Enforcement: `no-await-in-loop` + `agents-reviewer`.

**Rule 37 — Every Drizzle query is awaited.** Drizzle's query builders are *thenables*: a
missing `await` returns a builder object that type-checks fine and silently never runs. This is
the most expensive class of bug available in this stack, and it is invisible without type-aware
linting. Enforcement: `.oxlintrc.json` `typescript/no-floating-promises`,
`typescript/no-misused-promises`, `typescript/await-thenable` — all type-aware, which is why
`bun run lint` passes `--type-aware` and `oxlint-tsgolint` is a required devDependency.

---

## §I. Runtime & HTTP Hardening

**Rule 38 — The connection pool is configured, never left at defaults.** `src/db/index.ts` sets
`max`, `idle_timeout`, `connect_timeout`, `max_lifetime`, and — the one that actually prevents
an outage — `connection.statement_timeout` plus `idle_in_transaction_session_timeout`. Without
those, one stuck query holds a pooled connection forever. `max` × replica count must stay under
Postgres's `max_connections`. This does **not** repeal Rule 17: what is forbidden there is
`max: 1`, not explicit configuration. Enforcement: `quality-gate.yml` greps `src/db/index.ts`
for a pool cap of 1 or 2.

**Rule 39 — CORS is an allowlist, never a bare `cors()`.** Bare `cors()` sends
`Access-Control-Allow-Origin: *`. This is an internal admin API; origins come from
`env.CORS_ORIGINS`. Enforcement: `quality-gate.yml` greps `src/app.ts` for `cors()` with no
argument.

**Rule 40 — Every request carries a correlation ID.** `requestId()` is the first middleware
registered; the ID goes into every Pino line and out on the `X-Request-Id` response header, so
a client-reported failure can be traced to its log lines. Enforcement: advisory / `agents-reviewer`.

**Rule 41 — `/api/*` has a request budget: `bodyLimit`, `timeout`, and `secureHeaders`.** The
middleware order in `src/app.ts` is part of the contract, not a preference — it is documented
inline there and in `.claude/rules/backend/hono.md`. Enforcement: `quality-gate.yml` greps
`src/app.ts` for all three.

---

## How to Add a New Module

Copy `src/modules/meta/` — it is the one module here built to the full shape (service with
injected dependencies, thin handler, route owning the OpenAPI contract). Do **not** copy
`courses/` or `payments/`: they predate these rules and skip the service layer.

**Step 1 — Directory:** `src/modules/<name>/`

**Step 2 — Schema** (`<name>.schema.ts`)

```ts
import { z } from "@hono/zod-openapi";

export const thingResponseSchema = z
  .object({ id: z.string(), name: z.string() })
  .openapi("Thing");

// Rule 29: list endpoints are keyset-paginated. See courses.schema.ts for a
// worked example (ListCoursesQuerySchema / CourseListResponseSchema).
```

**Step 3 — Service** (`<name>.service.ts`) — pure logic, dependencies as default parameters so
it is testable without a live DB (Rule 7). Never imports Hono; `.oxlintrc.json` enforces that.

**Step 4 — Repository** (`<name>.repository.ts`) — DB access and transaction boundaries.
Explicit column projection (Rule 30), an explicit `.limit()` (Rule 29), and an index for every
filtered/sorted/joined column committed in the same PR (Rule 32).

**Step 5 — Handler** (`<name>.handler.ts`)

```ts
import type { RouteHandler } from "@hono/zod-openapi";
import { getThing } from "./thing.service.ts";
import type { getThingRoute } from "./thing.routes.ts";

export const handleGetThing: RouteHandler<typeof getThingRoute> = async (c) => {
  const { id } = c.req.valid("param");
  const thing = await getThing(id);
  return c.json(thing, 200);
};
```

**Step 6 — Routes** (`<name>.routes.ts`)

```ts
import { OpenAPIHono, createRoute, z } from "@hono/zod-openapi";
import { handleGetThing } from "./thing.handler.ts";
import { thingResponseSchema } from "./thing.schema.ts";

export const thingApp = new OpenAPIHono();

export const getThingRoute = createRoute({
  method: "get",
  path: "/{id}",
  request: { params: z.object({ id: z.string() }) },
  responses: {
    200: { content: { "application/json": { schema: thingResponseSchema } }, description: "OK" },
    // Rule 13: declare every status the handler can actually return, including
    // the error shapes. Once §C lands this becomes errorResponses(404, 422).
  },
});

thingApp.openapi(getThingRoute, handleGetThing);
```

**Step 7 — Index** (`index.ts`)

```ts
export { thingApp } from "./thing.routes.ts";
```

**Step 8 — Mount in `src/app.ts`**

```ts
import { thingApp } from "./modules/thing/index.ts";
app.route("/api/things", thingApp);
```

Mount under `/api/*` unless there is a reason not to — that prefix is what carries the request
budget and rate limiting (Rule 41). `modules/meta` is mounted at `/` precisely because a health
check must answer even when rate limiting would not let it.

**Step 9 — Verify:** `bun run fl && bun run type-check && bun run build`
(no `bun test` yet — see §E.)

---

## Core Files — Handle With Care

| File | What It Controls | Risk of a Bad Change |
|------|--------------------|------------------------|
| `src/app.ts` | Middleware order, error handler wiring, route mounts | Breaks all HTTP routing; reordering the chain silently removes the request budget |
| `src/env.ts` | Validated env vars — process exits if the schema doesn't match | Breaks startup for everyone |
| `src/db/index.ts` | The app's real connection pool | Reintroducing `{ max: 1 }` here serializes every request onto one connection again — that is exactly what this repo was just fixed out of |
| `src/db/schema/*.ts` | Table definitions and every index | A dropped index turns a hot query into a sequential scan with no other symptom |
| `src/middlewares/error.middleware.ts` | The current error envelope for every route | Changing the shape breaks every FE error path at once |
| `src/lib/auth.ts` | better-auth configuration | Breaks every authenticated route |

AI agents: do not modify these files unless the task explicitly requires it. Prefer adding a
new module over changing shared infrastructure.
