# `postgres(url, { max: 1 })` outside a migration runner

**Applies to:** Any Bun/Node service using `postgres` (postgres.js) as the Drizzle driver
**Discovered:** 2026-08-01, architecture refactor audit
**Status:** Fixed in this repo (`src/db/index.ts`) — kept as a reference so it isn't reintroduced

## Symptom

Under any real concurrent load, requests queue up and latency climbs roughly linearly with
concurrent request count, even though nothing in the query itself is slow. Looks like a slow
query at first; profiling the query alone shows it's fast — the delay is in acquiring a
connection.

## Root Cause

`postgres(url, { max: 1 })` caps the pool at a single connection. Every concurrent HTTP request
that needs the database serializes onto that one connection — the app can only ever run one DB
query at a time, application-wide, regardless of how many requests arrive concurrently.

`{ max: 1 }` is the *correct* setting in exactly one place: a migration runner
(`src/db/migrate.ts`), where migrations must run one statement after another over a single
connection by design. It was copy-pasted from there (or a template that had it) into
`src/db/index.ts`, the client the running app actually uses for every request.

## Fix

```ts
// src/db/index.ts — the app's real pool. No max override; postgres.js
// defaults to a reasonable pool size (10).
export const client = postgres(env.DATABASE_URL);

// src/db/migrate.ts — its OWN client, separate from db/index.ts, only
// here is { max: 1 } correct.
const migrationClient = postgres(env.DATABASE_URL, { max: 1 });
```

The two clients must be genuinely separate instances — `migrate.ts` must not import and reuse
`db/index.ts`'s pooled client with an override, because postgres.js's `max` option only takes
effect at client construction.

## When to revisit

If postgres.js changes its default pool size behavior, or if a specific deployment target
needs a different pool size (measure first — don't guess a number).
