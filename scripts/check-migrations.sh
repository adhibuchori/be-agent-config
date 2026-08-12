#!/usr/bin/env bash
# Migration drift gate,
# adapted for this repo's drizzle.config.ts (schema: src/db/schema.ts, out:
# src/db/migrations). Regenerates migrations from the current schema and
# fails if the migrations directory doesn't match what's committed — i.e.
# the schema changed but `bun run db:generate` was never run / committed.
set -euo pipefail

MIGRATIONS_DIR="src/db/migrations"

echo "Generating migrations..."
if ! bun run db:generate; then
  echo "Error: Failed to generate migrations (schema syntax error?)"
  exit 1
fi

if ! git rev-parse --git-dir > /dev/null 2>&1; then
  echo "Error: Not in a git repository"
  exit 1
fi

STATUS=$(git status --porcelain "$MIGRATIONS_DIR/" 2>&1) || {
  echo "Error: git status failed"
  exit 1
}

if [ -n "$STATUS" ]; then
  echo "Error: Migrations are out of date!"
  echo ""
  echo "The following migration files need to be committed:"
  echo "$STATUS"
  echo ""

  echo "=== Migration file contents ==="
  echo "$STATUS" | while read -r line; do
    file=$(echo "$line" | awk '{print $2}')
    if [ -f "$file" ] && [[ "$file" == *.sql ]]; then
      echo ""
      echo "--- $file ---"
      cat "$file"
    fi
  done
  echo ""
  echo "==============================="
  echo ""
  echo "Run 'bun run db:generate' locally and commit the generated migrations."
  exit 1
fi

echo "✓ Migrations are up to date"
