#!/usr/bin/env bash
# Runs oxlint on modified TypeScript files after every write. Advisory only
# (see run-tests.sh / CI for the blocking equivalent) — never exits non-zero.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

FILE="${CLAUDE_TOOL_INPUT_FILE_PATH:-}"

if [[ -z "$FILE" ]] || [[ ! -f "$FILE" ]]; then
  exit 0
fi

EXT="${FILE##*.}"

case "$EXT" in
  ts)
    if OXLINT="$(resolve_tool oxlint)"; then
      # .oxlintrc.json is discovered automatically from cwd — no -c needed.
      # shellcheck disable=SC2086 -- OXLINT may be "bunx oxlint", word splitting intended
      run_capped 10 $OXLINT "$FILE" 2>&1 || true
    fi
    ;;
  json)
    if command -v python3 &>/dev/null; then
      python3 -c "import json,sys; json.load(sys.stdin)" < "$FILE" 2>&1 && echo "[auto-lint] $FILE JSON valid" || echo "[auto-lint] WARNING: $FILE has JSON syntax errors" >&2
    fi
    ;;
esac

exit 0
