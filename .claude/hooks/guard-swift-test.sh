#!/bin/sh
# PreToolUse hook for Bash: refuses a bare `swift test`. Without the flags the Makefile adds, the
# Command Line Tools can't find Swift Testing's macro plugin, and a cached build can hide that by
# passing on stale code. Only `swift test` where a command starts counts, so a commit message
# that mentions it gets through.
command=$(jq -r '.tool_input.command // empty')
if printf '%s\n' "$command" |
  grep -Eq "(^|[;&|(]|@ARGV'?)[[:space:]]*swift[[:space:]]+test([^[:alnum:]_-]|$)"; then
  echo "Use make test, make test-unit or make test-scenario (with FILTER=<regex> for a few" \
    "tests), not plain swift test: the Makefile adds the flags Swift Testing needs." >&2
  exit 2
fi
