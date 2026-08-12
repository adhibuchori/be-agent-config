#!/usr/bin/env bash
# Runs the checks quality-gate.yaml runs, for promotions that cannot use CI.
# Usage: quality-gate.sh [base-ref]   default origin/dev. See README § CI/CD.
set -uo pipefail

cd "$(dirname "$0")/../.."

BASE="${1:-origin/dev}"
failed=0
skipped=""

# On a runner a skipped check is a hole in the gate, so it fails instead.
STRICT=0
[ "${CI:-}" = "true" ] && STRICT=1
case " $* " in *" --strict "*) STRICT=1 ;; esac

step() {
  printf '\n\033[1m── %s\033[0m\n' "$1"
}

run() {
  step "$1"
  shift
  if ! "$@"; then
    echo "::error::$* failed"
    failed=$((failed + 1))
  fi
}

# A check that cannot run here is recorded, never silently passed — the summary
# at the end is what tells you the gate was partial.
skip() {
  skipped="${skipped}"$'\n'"  $1 — $2"
}

git rev-parse --verify "$BASE" >/dev/null 2>&1 || {
  echo "::error::base ref '$BASE' not found; run: git fetch origin"
  exit 1
}

run "Install Dependencies" bun install --frozen-lockfile --ignore-scripts
run "Format & Lint" bun run fl:ci
run "Type Check" bun run type-check
run "Comment Style Check" bun run .github/scripts/check-comment-style.ts
run "Comment Block Length Check" bash .github/scripts/check-comment-blocks.sh

# A stale copy under .claude/commands/ still reads as valid, and INDEX.md is what an agent
# consults to discover the commands at all. Skipped on prod, where the strip removed the source.
step "Workflow Mirror Drift Check"
if [ ! -d _workflow-source ] || [ ! -f scripts/sync-workflows.sh ]; then
  echo "_workflow-source/ not present on this branch - skipping"
elif ! bash scripts/sync-workflows.sh --check; then
  echo "::error::workflow mirror or INDEX.md has drifted"
  failed=$((failed + 1))
fi
run "Migration Drift Check" bash scripts/check-migrations.sh
run "Index Coverage Check" bash scripts/check-index-coverage.sh

# ── Runtime hardening — AGENTS.md §I Rules 38, 39, 41 ──
step "Runtime Hardening Check"
code() { sed -E 's://.*$::' "$1" | sed -E '/^[[:space:]]*[*]/d; /^[[:space:]]*\/\*/d'; }
rh_fail=0
if code src/app.ts | grep -qE 'cors\([[:space:]]*\)'; then
  echo "::error file=src/app.ts::bare cors() sends Access-Control-Allow-Origin: * - pass an origin allowlist (Rule 39)"
  rh_fail=1
fi
for mw in requestId secureHeaders bodyLimit timeout; do
  if ! code src/app.ts | grep -q "${mw}("; then
    echo "::error file=src/app.ts::missing ${mw} middleware (Rule 40, Rule 41)"
    rh_fail=1
  fi
done
if code src/db/index.ts | grep -qE 'max:[[:space:]]*[12][^0-9]'; then
  echo "::error file=src/db/index.ts::a pool cap of 1-2 serializes every request (Rule 17)"
  rh_fail=1
fi
for setting in statement_timeout idle_in_transaction_session_timeout; do
  if ! code src/db/index.ts | grep -q "$setting"; then
    echo "::error file=src/db/index.ts::missing $setting (Rule 38)"
    rh_fail=1
  fi
done
if [ "$rh_fail" -ne 0 ]; then
  failed=$((failed + 1))
else
  echo "Clean"
fi

# Inserting a rule renumbers AGENTS.md and breaks every citation.
step "AI Config Rule Drift Check"
if [ ! -f AGENTS.md ] || [ ! -d .claude ]; then
  echo "AGENTS.md or .claude/ not present on this branch - skipping"
else
  ai_stale=0
  for f in .claude/agents/*.md .claude/hooks/*.sh; do
    [ -f "$f" ] || continue
    for n in $(grep -oE "Rule [0-9]+" "$f" | grep -oE "[0-9]+" | sort -u); do
      if ! grep -qE "Rule $n[^0-9]" AGENTS.md; then
        echo "::error file=$f::cites Rule $n, which does not exist in AGENTS.md"
        ai_stale=1
      fi
    done
  done
  if [ "$ai_stale" -ne 0 ]; then
    failed=$((failed + 1))
  else
    echo "All cited rule numbers exist in AGENTS.md"
  fi
fi

run "Security Audit" bun audit --audit-level high

# ── Security scans over the diff against BASE ──
scan() {
  step "$1"
  if git diff "$BASE"...HEAD -- $3 | grep -Eq "$2"; then
    echo "::error::$1 found a match"
    git diff "$BASE"...HEAD -- $3 | grep -En "$2" | head -20
    failed=$((failed + 1))
  else
    echo "Clean"
  fi
}

step "Check .env Not Committed"
if git diff "$BASE"...HEAD --name-only | grep -E "^\.env(\.|$)" | grep -qvE "^\.env(\.[a-z]+)?\.example$"; then
  echo "::error::.env file committed"
  failed=$((failed + 1))
else
  echo "Clean"
fi

scan "Dangerous JS APIs Check" '\beval\s*\(|new\s+Function\s*\(' "src scripts"
scan "Unsafe React Patterns Check" 'dangerouslySetInnerHTML|__html' "src scripts"
scan "URL Scheme Injection Check" '(javascript:|data:text/html|data:application/)' "src scripts"

step "Secret Scan"
if git diff "$BASE"...HEAD | grep -iEq "(api[_-]?key|secret|password|token|bearer|private[_-]?key)["']?[[:space:]]*[:=][[:space:]]*["'][^"']{6,}"; then
  echo "::error::Potential secrets detected"
  failed=$((failed + 1))
else
  echo "Clean"
fi
# <frontend-repo>'s orval client reads openapi.json.
step "OpenAPI Spec Drift Check"
bun run spec:export
if ! git diff --exit-code openapi.json; then
  echo "::error::openapi.json is stale — run 'bun run spec:export' and commit"
  failed=$((failed + 1))
fi

run "Production Build" bun run build

# ── Summary ──
printf '\n\033[1m── Summary\033[0m\n'
if [ -n "$skipped" ]; then
  printf 'Checks that did NOT run:%s\n\n' "$skipped"
fi

if [ "$failed" -gt 0 ]; then
  printf '::error::%d check(s) failed.\n' "$failed"
  exit 1
fi

if [ -n "$skipped" ]; then
  if [ "$STRICT" -eq 1 ]; then
    echo "::error::gate was partial and strict mode is on."
    exit 1
  fi
  echo "All checks that ran passed, but the gate was PARTIAL — see the list above."
  exit 0
fi

echo "Full gate passed."
