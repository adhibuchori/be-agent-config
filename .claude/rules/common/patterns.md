# Common Patterns

The concrete, enforced version of everything here is `AGENTS.md`. This file names the patterns
this repo uses and points at where each one is specified.

## Reuse before writing

Before implementing anything non-trivial: check whether `src/modules/meta/` already demonstrates
the shape, check the package registry for a battle-tested library, and check the vendor docs for
the API's actual behavior. Prefer adopting a proven approach over net-new code — but not at the
cost of a dependency this repo does not need (`coding-style.md`, YAGNI).

## Architectural patterns in this repo

| Pattern | Where it is specified |
|---|---|
| Modular monolith — feature verticals with internal layering | `SSOT.md` §Architecture |
| `handler → service → repository → db` for new modules; existing modules skip the service | `AGENTS.md` §B Rule 5 + Compliance Status |
| Dependency injection via default parameters (no container, no mocking library) | `AGENTS.md` §B Rule 7 |
| Module barrel — `index.ts` is a module's only public surface | `AGENTS.md` §B Rule 8 |
| One-way dependency direction: `modules/* → lib/*, db/*, middlewares/*` | `AGENTS.md` §B Rule 9 |
| A single error envelope, today `{ success, error }` from `middlewares/error.middleware.ts` | `AGENTS.md` §C — RFC 9457 problem+json is the target, not the present |
| OpenAPI-first routing — the route declares the contract, including errors | `.claude/rules/backend/hono.md` |
| Keyset pagination as the default list contract | `AGENTS.md` §H Rule 29, `backend/drizzle.md` |
| Redis cache-aside, in the service, always with a TTL | `.claude/rules/backend/performance.md` |
| Transaction boundaries in the repository, never spread across a service | `AGENTS.md` §H Rule 35 |

## Patterns deliberately NOT used

- **A generic repository/base-class layer.** Repositories are added per module, only when
  Rule 4's escalation criteria are met.
- **A DI container.** Default parameters cover every case this repo has.
- **A shared `test-utils` package.** Mock builders stay module-local until real duplication
  proves otherwise (`backend/testing.md`).
- **A second error envelope.** There is exactly one — `middlewares/error.middleware.ts` — and
  the migration to problem+json will replace it wholesale, not sit alongside it.
