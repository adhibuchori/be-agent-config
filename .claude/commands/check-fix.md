---
description: Run format, lint, and type checks, applying fixes where possible.
---

<!-- Command: /check-fix -->
<!-- Source: _workflow-source/check-fix.md -->

# /check-fix — Quality Check & Fix

1. **Format + Lint**: `bun run fl`
   - Runs oxfmt then `oxlint --type-aware`. The type-aware pass needs the `oxlint-tsgolint`
     devDependency and is what catches a Drizzle query with a missing `await` (AGENTS.md §H
     Rule 37).
   - **Action**: re-run once — oxlint applies auto-fixes on the second pass.

2. **Type Check**: `bun run type-check`
   - `tsc --noEmit`, must exit 0.

3. **Build**: `bun run build`
   - Catches what `--noEmit` does not: bundler resolution failures.

> There is no test gate in this repo — it has no test suite (AGENTS.md §E). Do not add a
> `bun test` step to any checklist until one exists.

Never silence a finding with `// oxlint-disable` — resolve the cause (AGENTS.md Rule 28). Note
also that this repo forbids `//` comments outside directives; use `/* */` or `/** */`.

If `src/db/schema/` was touched:

```bash
bun run db:generate                    # commit the generated migration in the same PR
bash scripts/check-index-coverage.sh   # every FK column needs an index (Rule 32)
```

Output: PASS/FAIL with what was fixed and what remains.
