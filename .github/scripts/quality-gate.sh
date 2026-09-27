#!/usr/bin/env bash
# Runs the checks quality-gate.yml runs, for promotions that cannot use CI. Usage: quality-gate.sh
# [base-ref, default origin/dev] [--strict]. Why each step: https://github.com/adhibuchori/be-agent-config#cicd
set -uo pipefail

cd "$(dirname "$0")/../.." || exit 2

BASE=origin/dev
STRICT=0
for arg in "$@"; do
  case "$arg" in
  --strict) STRICT=1 ;;
  -*) echo "::error::unknown option $arg" && exit 2 ;;
  *) BASE="$arg" ;;
  esac
done
# On a runner a skipped check is a hole in the gate, so it fails instead.
[ "${CI:-}" = "true" ] && STRICT=1

failed=0
skipped=""

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

# An optional module (the payload contract) runs here exactly when scripts/check/gates.list lists
# it, so deleting its lines there switches it off in both places.
optional() {
  local name="$1" script="$2"
  if grep -qE "^[^#].*run ${script}\$" scripts/check/gates.list 2>/dev/null; then
    run "$name" bun run "$script"
  else
    step "$name"
    echo "$script is not in scripts/check/gates.list - optional module not adopted"
  fi
}

git rev-parse --verify "$BASE" >/dev/null 2>&1 || {
  echo "::error::base ref '$BASE' not found; run: git fetch origin"
  exit 1
}

run "Install Dependencies" bun install --frozen-lockfile --ignore-scripts
run "Format & Lint" bun run fl:ci
run "Folder Shape Check" bun run check:folder-shape
run "Coverage Policy Check" bun run check:coverage-policy
run "Type Check" bun run type-check
run "Dead Code Check" bun run check:dead-code
run "Comment Style Check" bun run .github/scripts/check-comment-style.ts
run "Comment Block Length Check" bash .github/scripts/check-comment-blocks.sh

# Before the tests, because it decides whether their result means anything: one
# process-wide mock.module leak makes a passing suite a property of file order.
run "Module Mock Check" bun run check:mocks

# Unit tier only: src/test/preload.ts replaces every external client, so this
# needs the env vars set but no live server. See quality-gate.yml.
run "Unit Tests (coverage)" bun run test:coverage

# A role or queue name retyped instead of imported never fails loudly at runtime.
# The words are read out of each home, so a rename is picked up here automatically.
run "Constant Home Check" bun run check:constants

# The image builds what this gate validated: generated clients, a readable digest pin, and a Bun no
# older than the one this gate ran.
run "Dockerfile Check" bun run check:dockerfile
# The committed openapi.json describes every route the app mounts.
run "OpenAPI Document Check" bun run check:openapi
optional "Payload Endpoint Registry Check" check:endpoints
optional "Payload Crypto Interop Check" check:crypto-interop

# A stale copy under .claude/commands/ still reads as valid, and INDEX.md is what an agent
# consults to discover the commands at all. The script skips a branch without the sources.
run "Workflow Mirror Drift Check" bash scripts/sync/workflows.sh --check
run "Migration Drift Check" bash scripts/check/migrations.sh
run "Index Coverage Check" bash scripts/check/index-coverage.sh

# ── Runtime hardening — AGENTS.md §I Rules 38, 39, 41 ──
step "Runtime Hardening Check"
code() { sed -E 's://.*$::' "$1" | sed -E '/^[[:space:]]*[*]/d; /^[[:space:]]*\/\*/d'; }
# Read into a variable first: `code | grep -q` under pipefail turns an early grep exit into a miss.
app=$(code src/app.ts)
db_client=$(code src/db/client/index.ts)
rh_fail=0
if grep -qE 'cors\([[:space:]]*\)' <<<"$app"; then
  echo "::error file=src/app.ts::bare cors() sends Access-Control-Allow-Origin: * - pass an origin allowlist (Rule 39)"
  rh_fail=1
fi
for mw in requestId secureHeaders bodyLimit timeout; do
  if ! grep -qF "${mw}(" <<<"$app"; then
    echo "::error file=src/app.ts::missing ${mw} middleware (Rule 40, Rule 41)"
    rh_fail=1
  fi
done
if grep -qE 'max:[[:space:]]*[12][^0-9]' <<<"$db_client"; then
  echo "::error file=src/db/client/index.ts::a pool cap of 1-2 serializes every request (Rule 17)"
  rh_fail=1
fi
for setting in statement_timeout idle_in_transaction_session_timeout; do
  if ! grep -qF "$setting" <<<"$db_client"; then
    echo "::error file=src/db/client/index.ts::missing $setting (Rule 38)"
    rh_fail=1
  fi
done
if [ "$rh_fail" -ne 0 ]; then
  failed=$((failed + 1))
else
  echo "Clean"
fi

# Rule citations (a new rule renumbers AGENTS.md), the always-loaded budget, hook wiring, MCP pins.
run "AI Config Check" bash scripts/check/ai-config.sh
# Proves the MCP pin rule above both ways: movable specs fail it, exact releases pass it.
run "AI Config Probes" bash scripts/check/ai-config-probes.sh
# What each Claude Code hook must block and let through; skips on a branch without .claude/.
run "Hook Probes" bash scripts/check/hook-probes.sh
run "No Double Assertion" bash scripts/check/double-assertion.sh

# SkillSpector scans skills, commands, subagents and hooks; it installs and runs only when one changed.
step "Skill Security Scan"
SKILL_PATHS=(.agents/skills .claude/skills .claude/commands .claude/agents .claude/hooks _workflow-source .skillspector-baseline.yaml scripts/check/skills.sh)
if [ ! -d .claude ]; then
  echo ".claude/ not present on this branch - skipping"
elif git diff --quiet "$BASE"...HEAD -- "${SKILL_PATHS[@]}"; then
  echo "No skill, command, subagent or hook changed - skipping"
elif ! command -v uv >/dev/null 2>&1; then
  echo "::error::uv is required to install the pinned SkillSpector"
  failed=$((failed + 1))
else
  if ! command -v skillspector >/dev/null 2>&1; then
    # The same commit scripts/check/skills.sh pins; it refuses any other build.
    uv tool install --quiet --python 3.12 "git+https://github.com/NVIDIA/skillspector.git@69dcdfb74487d361ba4c811d088cfdea2ff3a9dc"
    PATH="$(uv tool dir --bin):$PATH"
  fi
  bash scripts/check/skills.sh --changed "$BASE" || failed=$((failed + 1))
fi

run "Security Audit" bun audit --audit-level high

# ── Security scans over the lines the branch adds against BASE ──
# $3 is a space-separated pathspec list, split on purpose. diff-scan.sh exits 2 when it cannot read.
scan() {
  step "$1"
  # shellcheck disable=SC2086 # one pathspec per word
  bash .github/scripts/diff-scan.sh "$BASE" "$2" $3
  case $? in
  0) echo "Clean" ;;
  1) echo "::error::$1 found a match" && failed=$((failed + 1)) ;;
  *) echo "::error::$1 could not read the diff" && failed=$((failed + 1)) ;;
  esac
}

step "Check .env Not Committed"
if ! changed=$(git diff --name-only "$BASE"...HEAD); then
  echo "::error::could not list the files changed since $BASE"
  failed=$((failed + 1))
elif env_files=$(grep -E '^\.env(\.|$)' <<<"$changed" | grep -vE '^\.env(\.[a-z]+)?\.example$'); then
  echo "$env_files"
  echo "::error::.env file committed"
  failed=$((failed + 1))
else
  echo "Clean"
fi

# The scans below trust diff-scan.sh; this proves it on a 40,000-line diff and a removed line first.
run "Diff Scan Probes" bash .github/scripts/diff-scan-probes.sh
scan "Dangerous JS APIs Check" '\beval\s*\(|new\s+Function\s*\(' "src scripts"
scan "Unsafe React Patterns Check" 'dangerouslySetInnerHTML|__html' "src scripts"
scan "URL Scheme Injection Check" '(javascript:|data:text/html|data:application/)' "src scripts"

step "Raw SQL / Interpolation Audit"
# The exemption is a path test. Testing it against the diff line, as this once did, never fires:
# a `+` line does not carry its own filename (https://github.com/adhibuchori/be-agent-config#gate-details).
raw_sql=$(git diff "$BASE"...HEAD --unified=0 -- src | awk '
  /^\+\+\+ b\// { path = substr($0, 7); next }
  /^\+/ && /sql`[^`]*\$\{/ {
    if (path ~ /\.repository\.ts$/) next
    if (path ~ /^src\/db\/schema\//) next
    printf "%s\n  %s\n", path, $0
  }
')
if [ -n "$raw_sql" ]; then
  echo "$raw_sql"
  echo "::error::Interpolated raw SQL found outside a *.repository.ts or src/db/schema/ file"
  failed=$((failed + 1))
else
  echo "Clean"
fi

step "Secret Scan (gitleaks)"
GITLEAKS_VERSION=8.30.1
GITLEAKS_SHA256=551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb
GL=""

# The pinned build and checksum, exactly as CI fetches them. Any other binary is
# a different scan, so elsewhere it falls back to whatever is installed.
if [ "$(uname -s)" = "Linux" ] && [ "$(uname -m)" = "x86_64" ]; then
  GL_URL="https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz"
  if curl -sSfL -o gitleaks.tar.gz "$GL_URL" && echo "${GITLEAKS_SHA256}  gitleaks.tar.gz" | sha256sum -c - && tar xzf gitleaks.tar.gz gitleaks; then
    GL=./gitleaks
  else
    echo "::error::could not fetch or verify the pinned gitleaks build"
    failed=$((failed + 1))
  fi
elif command -v gitleaks >/dev/null 2>&1; then
  GL=gitleaks
fi

# --config explicitly: the allowlist in .gitleaks.toml is only read when named.
if [ -n "$GL" ]; then
  if ! "$GL" git . --no-banner --redact --config .gitleaks.toml; then
    echo "::error::gitleaks found findings"
    failed=$((failed + 1))
  fi
elif [ "$failed" -eq 0 ]; then
  echo "gitleaks not installed — brew install gitleaks"
  skip "Secret Scan (gitleaks)" "no pinned build for $(uname -sm), none on PATH"
fi
rm -f gitleaks gitleaks.tar.gz

# The generated API client downstream reads openapi.json. A generator that fails leaves the old file
# in place, and an openapi.json never committed is invisible to `git diff`; both fail here.
step "OpenAPI Spec Drift Check"
if ! bun run spec:export; then
  echo "::error::bun run spec:export failed, so openapi.json was not regenerated"
  failed=$((failed + 1))
elif [ -n "$(git status --porcelain -- openapi.json)" ]; then
  git --no-pager diff -- openapi.json | head -40
  echo "::error::openapi.json is stale or uncommitted — run 'bun run spec:export' and commit it"
  failed=$((failed + 1))
else
  echo "Clean"
fi

run "Production Build" bun run build

# ── Security — source map leak check (dist/ only) ──
step "Check Source Maps Leak"
MAPS=$(find dist -name "*.map" 2>/dev/null | head -5)
if [ -n "$MAPS" ]; then
  echo "::error::Source maps leaked in the build output (dist/)"
  echo "$MAPS"
  failed=$((failed + 1))
else
  echo "Clean"
fi

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
