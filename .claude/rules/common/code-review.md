# Code Review Standards

The `agents-reviewer` agent (`.claude/agents/agents-reviewer.md`) checks the enforced `AGENTS.md` rules
mechanically. This file is the human checklist around it.

## When to Review

**MANDATORY review triggers:**

- After writing or modifying code
- Before any commit to a shared branch
- When security-sensitive code changes (auth, user data, anything reading a secret)
- When a new query or schema change lands
- Before merging a pull request

**Before requesting review:** CI is green, conflicts are resolved, the branch is up to date with
its target.

## Review Checklist

Run `bun run fl && bun run type-check && bun run build` first — the machine catches most of the
list below before a human looks at it. (No `bun test` yet; see AGENTS.md §E.) Then check what
it cannot:

**Boundaries and contract**
- [ ] Handler is thin glue, ≤15 lines, no DB access (§B Rule 6, §G Rule 28)
- [ ] Service is pure — no `Context`, dependencies via default parameters (§B Rule 7)
- [ ] Cross-module imports go through `index.ts` (§B Rule 8)
- [ ] Errors use the repo's ONE existing envelope, not a new shape (§C is a tracked deviation —
      `DomainError`/problem+json do not exist here yet)
- [ ] No error response leaks an ID, path, stack, or upstream provider message to the client
- [ ] The route's `responses` map lists every status the handler can actually return (§C Rule 13)

**Query and performance** — the part no linter can fully see
- [ ] Every list query has an explicit `.limit()`; the endpoint is paginated (§H Rule 29)
- [ ] Columns are selected explicitly, not a bare `select()` on a wide table (§H Rule 30)
- [ ] No query in a loop, and no helper that queries called from a loop (§H Rule 31)
- [ ] Every filtered/sorted/joined column is indexed, in this same PR; FK columns always (§H Rule 32)
- [ ] `EXPLAIN (ANALYZE, BUFFERS)` in the PR for any table expected past ~100k rows (§H Rule 33)
- [ ] Transactions contain only DB work — no HTTP, no Redis, no queue publish (§H Rule 35)
- [ ] Writes are batched; upserts use `onConflictDoUpdate` (§H Rule 36)
- [ ] Any new cache entry has a TTL and an invalidation path in the same function

**General**
- [ ] Code is readable and well-named
- [ ] Files stay under 200 lines (§G Rule 26); functions stay focused
- [ ] No nesting past 4 levels — use early returns
- [ ] No `oxlint-disable` comments (§G Rule 27)
- [ ] New services take dependencies as default parameters, so they are testable once a suite
      exists (§B Rule 7) — do not block on missing tests while §E is open

## Security Review Triggers

**STOP and read carefully when the diff touches:** authentication or authorization, user input
handling, raw `sql` template interpolation, an external API call, anything that reads a secret,
or `src/env.ts`.

## Severity Levels

| Level | Meaning | Action |
| --- | --- | --- |
| CRITICAL | Security vulnerability or data loss risk | **BLOCK** — must fix before merge |
| HIGH | Bug or significant quality issue | **WARN** — should fix before merge |
| MEDIUM | Maintainability concern | **INFO** — consider fixing |
| LOW | Style or minor suggestion | **NOTE** — optional |

## Common Issues to Catch

**Security**
- Hardcoded credentials; `process.env` read outside `src/env.ts` (§F Rule 22)
- SQL injection — interpolation into a raw `sql` template outside a repository (CI audits this)
- Error responses leaking internals (§C Rule 12)
- A new endpoint outside `/api/*`, and therefore outside rate limiting and the request budget
- `cors()` without an origin allowlist (§I Rule 39)

**Correctness**
- A Drizzle query that is never awaited (§H Rule 37) — type-aware lint catches this, but check
  it fired: it only runs under `oxlint --type-aware`
- A cache key missing an input that changes the answer
- Select-then-insert where an upsert was meant (a race, not an upsert)

**Performance**
- N+1 access patterns
- Unbounded reads and `OFFSET` deep-paging
- A cache added instead of the missing index

## Approval Criteria

- **Approve** — no CRITICAL or HIGH issues
- **Warning** — only HIGH issues (merge with caution)
- **Block** — CRITICAL issues found

## Related

[testing.md](testing.md) · [security.md](security.md) · [git-workflow.md](git-workflow.md) ·
[../backend/performance.md](../backend/performance.md)
