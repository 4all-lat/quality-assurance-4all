#!/usr/bin/env bash
#
# tests/run.sh — zero-dependency test runner for the QA pipeline scripts.
#
# Usage:
#   tests/run.sh              # run every case
#   tests/run.sh parity       # run cases whose name contains "parity"
#   QA_VERBOSE=1 tests/run.sh # also dump the output of the scripts under test
#
# Exit: 0 when every case passed, 1 otherwise.
#
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export QA_TESTS_DIR="$TESTS_DIR"
export REPO_ROOT="$(cd "$TESTS_DIR/.." && pwd)"

FILTER="${1:-}"
SELECTED=()

for candidate in "$TESTS_DIR"/cases/*.test.sh; do
  [[ -e "$candidate" ]] || continue
  case_name="$(basename "$candidate" .test.sh)"
  if [[ -n "$FILTER" && "$case_name" != *"$FILTER"* ]]; then
    continue
  fi
  SELECTED+=("$candidate")
done

if [[ "${#SELECTED[@]}" -eq 0 ]]; then
  printf 'run.sh: no cases match %s\n' "${FILTER:-<all>}" >&2
  exit 1
fi

printf '\nQA 4All — script test suite\n'
printf '  repo:  %s\n' "$REPO_ROOT"
printf '  cases: %d\n' "${#SELECTED[@]}"

PASSED=0
FAILED=0
FAILED_NAMES=()

for case_file in "${SELECTED[@]}"; do
  case_name="$(basename "$case_file" .test.sh)"
  printf '\n== %s\n' "$case_name"
  if bash "$case_file"; then
    PASSED=$((PASSED + 1))
    printf '  PASS %s\n' "$case_name"
  else
    FAILED=$((FAILED + 1))
    FAILED_NAMES+=("$case_name")
    printf '  FAIL %s\n' "$case_name"
  fi
done

printf '\n----------------------------------------\n'
printf '%d passed, %d failed\n' "$PASSED" "$FAILED"

if [[ "$FAILED" -gt 0 ]]; then
  printf 'failing cases:\n'
  printf '  - %s\n' "${FAILED_NAMES[@]}"
  exit 1
fi
exit 0
