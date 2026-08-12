---
description: Run quality gates, inspect staged changes, and draft a conventional commit message.
---

<!-- Command: /commit -->
<!-- Source: _workflow-source/commit.md -->

# /commit — Quality Gate & Commit Message

1. **Quality Gate**: run `/check-fix` first. Do not proceed from a broken state.

2. **Inspect**: `git diff --staged` and `git status`.
   - **Never commit**: `.env*` (except the `.example` templates), `.claude/settings.json`,
     `openapi.json` when it was not regenerated from the source of truth.

3. **Stage explicitly** by name. Never `git add -A` or `git add .`.

4. **Draft the message**:

   ```
   type(scope): subject — max 50 characters

   [Optional body explaining the why, wrapped at 72 characters]
   ```

   - **Types**: `feat` · `fix` · `refactor` · `chore` · `docs` · `style` · `perf` · `test`
   - **Scopes**: `routes`, `db`, `auth`, `payments`, `middleware`, `config`
   - **Subject**: imperative, lowercase, no trailing period

Output the drafted message. Do not run the commit itself.
