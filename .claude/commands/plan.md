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

## TASKS
- [ ] [layer] [verb] [file] — what and why

## DATA
- New tables/columns, with the indexes each FK needs
- Migration strategy, and whether it is reversible

## RISKS
- Only risks that could actually block or break something

## CONFIRMATION
- Questions that need an answer before starting
```

Scopes in this repo: `routes`, `db`, `auth`, `payments`, `middleware`, `config`.

Do not start implementing until the plan is confirmed.
