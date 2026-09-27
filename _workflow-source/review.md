---
description: Review the staged changes, or else the branch against origin/dev, against this repo's backend rules, and report findings by severity. Reads and reports; changes nothing.
---

<!-- Command: /review -->
<!-- Source: _workflow-source/review.md -->

# /review — Backend Code Review

Delegate the detailed pass to `.claude/agents/agents-reviewer.md`; this command frames what it looks
at and in what order. The human checklist, with the backend checks keyed to `AGENTS.md` rules, is
`.claude/docs/code-review-checklist.md`: read it first.

## Step 1: Scope

```bash
git diff --cached --stat
git fetch origin && git diff origin/dev...HEAD --stat
```

Review the **staged** changes when there are any (`git diff --cached`): that is what `/commit`
and `/ship` hand you. Otherwise review the branch (`git diff origin/dev...HEAD`).

Read the diff unfiltered. An output wrapper or proxy can drop lines without saying so, and a
review of a truncated diff reports "clean".

## Step 2: Security First — Block On These

- Hardcoded secrets or credentials
- Raw SQL string interpolation instead of parameterised Drizzle queries
- A route that reads or writes user data without an authorisation check
- Error responses leaking internal detail (stack traces, driver messages)
- A new endpoint with no rate limiting
- `CORS_ORIGINS` widened, especially to a wildcard — this API serves credentialed requests, and
  an unset value silently falls back to the schema default, which blocks every browser call from
  the real origin while every health check stays green
- A known advisory in the dependencies: run `bun audit` on every review, not only when the
  lockfile changed, and report what it finds

## Step 3: Correctness

- **Missing `await` on a Drizzle query** (Rule 37) — the single most common real bug here. It
  type-checks and returns a Promise that is silently discarded.
- Transaction boundaries: multi-table writes must share one transaction.
- Every FK column indexed (Rule 32) — `bash scripts/check/index-coverage.sh`.
- Migration committed alongside the schema change that requires it.
- Pool sizing: `DB_POOL_MAX` × replica count must stay under Postgres `max_connections`.

## Step 4: Structure

- Files within the 200-line limit (AGENTS.md Rule 26); handlers within 15 lines (Rule 28)
- Layer boundaries respected (AGENTS.md §B)
- No explicit `any` or double assertion (Rule 42); shared literals imported from their one home
  (Rule 43)
- Errors handled explicitly, never swallowed
- Comments use `/* */` or `/** */`, never `//`

## Step 5: Report

Group findings as CRITICAL / HIGH / MEDIUM / LOW. CRITICAL blocks the merge; HIGH should be
fixed before it. State clearly whether the change is approved, approved with warnings, or
blocked.
