#!/bin/sh
# PostToolUse hook for Edit, Write and MultiEdit: formats an edited Swift file, then lints it as the
# pre-commit hook will, so a violation (a file or type grown past SwiftLint's length limits, a
# short name) shows at the edit instead of blocking the commit later. Violations go back to
# Claude (exit 2); the edit itself stands. Lints with the .swiftlint.yml of the file's own
# checkout, so it works in a worktree too.
file=$(jq -r '.tool_input.file_path // .tool_response.filePath // empty')
case "$file" in
  *.swift) ;;
  *) exit 0 ;;
esac
[ -f "$file" ] || exit 0
swift format format -i "$file" 2>/dev/null || true
command -v swiftlint >/dev/null || exit 0
root=$(git -C "$(dirname "$file")" rev-parse --show-toplevel 2>/dev/null) || exit 0
violations=$(cd "$root" &&
  TOOLCHAIN_DIR="${TOOLCHAIN_DIR:-/Library/Developer/CommandLineTools}" \
    swiftlint lint --strict --quiet --force-exclude --config .swiftlint.yml "$file" 2>&1)
if [ -n "$violations" ]; then
  printf 'SwiftLint, as the pre-commit hook will run it:\n%s\n' "$violations" >&2
  exit 2
fi
