#!/usr/bin/env bash
# Case: every shell script parses.
#
# `bash -n` is the one check that can run everywhere with nothing installed, and
# it catches the failure mode that matters most in a gate script: a syntax error
# that turns a failing pipeline into a passing one. It is not a substitute for
# shellcheck in CI, which finds real bugs this cannot.
set -uo pipefail

QA_TESTS_DIR="${QA_TESTS_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$QA_TESTS_DIR/.." && pwd)}"
# shellcheck source=../lib/assert.sh
. "$QA_TESTS_DIR/lib/assert.sh"

SHELL_FILES=()
while IFS= read -r f; do
  SHELL_FILES+=("$REPO_ROOT/${f#./}")
done < <(
  cd "$REPO_ROOT" &&
    find scripts tests -type f \( -name '*.sh' -o -name '_recorder' \) \
      -not -path '*/.git/*' | sort
)

assert_ne "${#SHELL_FILES[@]}" "0" "there are shell scripts to check"

for file in "${SHELL_FILES[@]}"; do
  rel="${file#"$REPO_ROOT"/}"
  if output="$(bash -n "$file" 2>&1)"; then
    _qa_pass "parses: $rel"
  else
    _qa_fail "parses: $rel" "$output"
  fi
done

# A shebang that points at a shell that cannot run the file is worth catching
# too: every script here uses bash-only syntax.
for file in "${SHELL_FILES[@]}"; do
  rel="${file#"$REPO_ROOT"/}"
  assert_match "$(head -1 "$file")" '^#!/usr/bin/env bash$' "$rel declares a bash shebang"
done

qa_summary
