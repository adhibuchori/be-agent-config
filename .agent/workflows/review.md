---
description: Review staged or branch changes against this repo's backend rules.
---

<!-- Command: /review -->
<!-- Source: _workflow-source/review.md -->

# /review — Backend Code Review

Delegate the detailed pass to `.claude/agents/be-reviewer.md`; this command frames what it looks
at and in what order.

## Step 1: Scope

```bash
git diff dev...HEAD --stat
git diff dev...HEAD
```

## Step 2: Security First — Block On These

- Hardcoded secrets or credentials
- Raw SQL string interpolation instead of parameterised Drizzle queries
- A route that reads or writes user data without an authorisation check
- Error responses leaking internal detail (stack traces, driver messages)
- A new endpoint with no rate limiting
- `CORS_ORIGINS` widened, especially to a wildcard — this API serves credentialed requests, and
  an unset value silently falls back to `http://localhost:3000`, which once caused a one-hour
  production outage

## Step 3: Correctness

- **Missing `await` on a Drizzle query** (Rule 37) — the single most common real bug here. It
  type-checks and returns a Promise that is silently discarded.
- Transaction boundaries: multi-table writes must share one transaction.
- Every FK column indexed (Rule 32) — `bash scripts/check-index-coverage.sh`.
- Migration committed alongside the schema change that requires it.
- Pool sizing: `DB_POOL_MAX` × replica count must stay under Postgres `max_connections`.

## Step 4: Structure

- Files under 150 lines, functions under 50
- Layer boundaries respected (AGENTS.md §B)
- Errors handled explicitly, never swallowed
- Comments use `/* */` or `/** */`, never `//`

## Step 5: Report

Group findings as CRITICAL / HIGH / MEDIUM / LOW. CRITICAL blocks the merge; HIGH should be
fixed before it. State clearly whether the change is approved, approved with warnings, or
blocked.
