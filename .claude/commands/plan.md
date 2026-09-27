---
description: Produce an implementation plan before writing backend code.
---

<!-- Command: /plan -->
<!-- Source: _workflow-source/plan.md -->

# /plan — Implementation Plan

## Step 1: Research Before Designing

Check whether the problem is already solved: existing modules in `src/`, the Hono and Drizzle
docs via Context7, then the wider ecosystem. Prefer extending a proven pattern in this repo over
inventing a parallel one.

## Step 2: Read The Relevant Sections

`SSOT.md` for architecture and env facts, `AGENTS.md` §B for layer ownership, §C for the error
contract.

## Step 3: Output

```markdown
# Plan: {title}

## SCOPE
- Routes/handlers affected:
- Schema changes (and therefore migrations):
- Env vars added or changed:

## UNKNOWNS
- What the code did not answer, each with how to find out ("No unknowns" when there are none)

## TASKS
- [ ] [layer] [verb] [file] — what and why — ~N min

## DATA
- New tables/columns, with the indexes each FK needs
- Migration strategy, and whether it is reversible

## RISKS
- [HIGH/MED/LOW] risk → mitigation; only risks that could actually block or break something

## CONFIRMATION
- One to three questions that need an answer before starting, or "No blockers — ready to execute"
```

Tasks are 5 to 30 minutes each (split a larger one), ordered by what depends on what, each naming
its test at the mirrored path. More than 50 tasks means phases: show phase 1 and ask before planning
the rest.

Branch scopes in this repo (`internal/{scope}`, CLAUDE.md § Branching): `routes`, `db`, `auth`,
`queues`, `middleware`, `config`.

Do not start implementing until the plan is confirmed.
