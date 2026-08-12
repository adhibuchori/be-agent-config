# Anti-Patterns Index

> Lazy-loaded knowledge base. Load only the file(s) matching your current task.
> Each file is self-contained — root cause + fix + scope.

## Loading Guide

| Trigger / Task                                    | Load                          |
| ---------------------------------------------------- | -------------------------------- |
| Touching `src/db/index.ts` or connection pool config | postgres-max-1-pool.md         |
| Touching `src/middlewares/rate-limit.middleware.ts`   | rate-limit-double-next.md      |

## When to add a new entry

A new anti-pattern qualifies when:

- It cost real debugging time (>30 min)
- The root cause is non-obvious from reading code/docs
- Same trap is likely to recur (vendor bug, environment quirk, tooling gotcha)

If the bug gets fixed upstream, **delete the file** — don't leave stale entries.

## File naming convention

`<scope>-<short-description>.md` — kebab-case, descriptive enough to skip without opening.
