#!/usr/bin/env bash
# Proves diff-scan.sh in a throwaway repo: a match inside a 40,000-line diff, a removed line, a bad base.
# A scan that stops reading early prints "Clean" over a match. Why: https://github.com/adhibuchori/be-agent-config#cicd
set -uo pipefail

SCAN="$(cd "$(dirname "$0")" && pwd)/diff-scan.sh"
EVAL='\beval\s*\(|new\s+Function\s*\('
PAD=40000
want_total=9

tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT
cd "$tmp" || exit 2

# The machine's identity, commit hooks and signing settings stay out of the throwaway commits.
g() { git -c user.name=probe -c user.email=probe@example.invalid -c commit.gpgsign=false -c core.hooksPath=/dev/null "$@"; }
commit() { g add -A && g commit -q --no-verify -m "$1"; }
case_branch() { g checkout -q -b "$1" "$base"; }
padding() { awk -v n="$PAD" 'BEGIN { for (i = 0; i < n; i++) printf "export const p%d = %d;\n", i, i }'; }

passed=0
failed=0
# expect <exit> <text the output must contain, or ""> <name> <diff-scan arguments>...
expect() {
  local want=$1 must=$2 name=$3 out got
  shift 3
  out=$(bash "$SCAN" "$@" 2>&1)
  got=$?
  if [ "$got" -eq "$want" ] && { [ -z "$must" ] || [[ "$out" == *"$must"* ]]; }; then
    passed=$((passed + 1))
  else
    failed=$((failed + 1))
    printf 'FAIL %s: exit %s (want %s)%s\n%s\n' "$name" "$got" "$want" "${must:+, output must contain \"$must\"}" "${out:0:600}"
  fi
}

g -c init.defaultBranch=main init -q . || exit 2
mkdir -p src docs
printf 'export const a = 1;\nconst x = eval("1");\n' >src/old.ts
commit base || exit 2
base=$(g rev-parse HEAD)

case_branch big-first
{ echo 'eval("1+1");' && padding; } >src/big.ts
commit big-first
expect 1 "src/big.ts:1: " "match on line 1 of a $PAD-line diff" "$base" "$EVAL" src scripts

case_branch big-last
{ padding && echo 'const f = new Function("return 1");'; } >src/big.ts
commit big-last
expect 1 "src/big.ts:$((PAD + 1)): " "match on the last line of a $PAD-line diff" "$base" "$EVAL" src scripts

case_branch removed
printf 'export const a = 1;\n' >src/old.ts
commit removed
expect 0 "" "a removed eval is not a new one" "$base" "$EVAL" src scripts

case_branch clean
padding >src/clean.ts
commit clean
expect 0 "" "a clean $PAD-line diff" "$base" "$EVAL" src scripts

case_branch path-only
mkdir -p src/__html && printf 'export const b = 2;\n' >src/__html/page.ts
commit path-only
expect 0 "" "a path is not the added text" "$base" 'dangerouslySetInnerHTML|__html' src scripts

case_branch outside
printf 'eval("1")\n' >docs/note.md
commit outside
expect 0 "" "a match outside the pathspecs" "$base" "$EVAL" src scripts

case_branch plus-line
printf '++ eval("1")\n' >src/plus.ts
commit plus-line
expect 1 "src/plus.ts:1: " "an added line that starts with ++" "$base" "$EVAL" src scripts

expect 2 "" "a base that does not exist" no-such-ref "$EVAL" src scripts
expect 2 "" "a pattern grep cannot compile" "$base" 'eval(' src scripts

total=$((passed + failed))
echo "diff-scan probes: $passed of $total passed, the largest diff $((PAD + 1)) lines"
[ "$failed" -eq 0 ] && [ "$total" -eq "$want_total" ]
