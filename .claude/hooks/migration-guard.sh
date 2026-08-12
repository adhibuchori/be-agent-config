#!/usr/bin/env bash
# Blocks direct writes to drizzle-kit generated migration files.
# The only way migrations change is `bun run db:generate` (see AGENTS.md
# §D Rule 16) — hand-editing them lets the SQL drift from the schema without
# scripts/check-migrations.sh catching it until CI.

FILE="${CLAUDE_TOOL_INPUT_FILE_PATH:-}"

if [[ -z "$FILE" ]]; then
  exit 0
fi

if [[ "$FILE" =~ src/db/migrations/ ]]; then
  echo "[migration-guard] BLOCKED: $FILE is drizzle-kit generated. Edit src/db/schema.ts and run 'bun run db:generate' instead." >&2
  exit 1
fi

exit 0
