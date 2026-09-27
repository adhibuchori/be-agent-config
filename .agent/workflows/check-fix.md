---
description: Write the format, run every gate in scripts/check/gates.list and the build, and fix what fails until all pass.
---

<!-- Command: /check-fix -->
<!-- Source: _workflow-source/check-fix.md -->

# /check-fix — Quality Check & Fix

1. **Format + Lint**: `bun run fl`
   - Writes oxfmt's format, then runs `oxlint --type-aware`. The type-aware pass needs the
     `oxlint-tsgolint` devDependency and is what catches a Drizzle query with a missing `await`
     (AGENTS.md §H Rule 37). Fix each lint finding at its cause.

2. **Every gate**: `bash scripts/check/gates.sh`
   - The list `.husky/pre-commit` runs (`scripts/check/gates.list`): type check, dead code, one
     home per identifier, module mocks, double assertions, folder shape, the coverage policy, the
     unit tests at 100% per file with no source file left unloaded, the AI config and the command
     mirrors. It prints each gate's exit code and the tail of every failure. Fix, re-run, repeat
     until every gate passes.

3. **Build**: `bun run build`
   - Catches what `--noEmit` does not: bundler resolution failures.

Never silence a finding with `// oxlint-disable` — resolve the cause (AGENTS.md Rule 27). Note
also that this repo forbids `//` comments outside directives; use `/* */` or `/** */`.

If `src/db/schema/` was touched:

```bash
bun run db:generate                    # commit the generated migration in the same PR
bash scripts/check/index-coverage.sh   # every FK column needs an index (Rule 32)
```

If a route or its schema changed, `bun run spec:export` and commit the regenerated `openapi.json`
with it; the quality gate fails a stale one.

Output: PASS/FAIL per gate, with what was fixed and what remains.
