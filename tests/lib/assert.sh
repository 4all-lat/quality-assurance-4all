#!/usr/bin/env bash
# Assertion helpers, sourced by every case file.
#
# Each assertion prints one TAP-ish line and bumps a counter. Case files must
# NOT use `set -e`: a failing assertion must never abort the case, otherwise
# one failure would hide every later assertion.

_QA_TOTAL=0
_QA_FAILED=0
_QA_SKIPPED=0

_qa_pass() {
  _QA_TOTAL=$((_QA_TOTAL + 1))
  printf '    ok   %s\n' "$1"
}

# qa_skip <message> — an assertion that could not run (missing optional tool).
qa_skip() {
  _QA_SKIPPED=$((_QA_SKIPPED + 1))
  printf '    skip %s\n' "$1"
}

_qa_fail() {
  _QA_TOTAL=$((_QA_TOTAL + 1))
  _QA_FAILED=$((_QA_FAILED + 1))
  printf '    FAIL %s\n' "$1"
  if [[ -n "${2:-}" ]]; then
    printf '         %s\n' "$2"
  fi
}

# assert_eq <actual> <expected> <message>
assert_eq() {
  if [[ "$1" == "$2" ]]; then
    _qa_pass "$3"
  else
    _qa_fail "$3" "expected [$2], got [$1]"
  fi
}

# assert_ne <actual> <unexpected> <message>
assert_ne() {
  if [[ "$1" != "$2" ]]; then
    _qa_pass "$3"
  else
    _qa_fail "$3" "value should not be [$2]"
  fi
}

# assert_exit <expected_code> <actual_code> <message>
assert_exit() {
  if [[ "$1" -eq "$2" ]]; then
    _qa_pass "$3"
  else
    _qa_fail "$3" "expected exit $1, got $2"
  fi
}

# assert_contains <haystack> <needle> <message>
assert_contains() {
  if [[ "$1" == *"$2"* ]]; then
    _qa_pass "$3"
  else
    _qa_fail "$3" "expected to contain [$2]"
  fi
}

# assert_not_contains <haystack> <needle> <message>
assert_not_contains() {
  if [[ "$1" != *"$2"* ]]; then
    _qa_pass "$3"
  else
    _qa_fail "$3" "should not contain [$2]"
  fi
}

# assert_match <string> <extended-regex> <message>
assert_match() {
  if [[ "$1" =~ $2 ]]; then
    _qa_pass "$3"
  else
    _qa_fail "$3" "expected to match /$2/"
  fi
}

# assert_file <path> <message>
assert_file() {
  if [[ -f "$1" ]]; then
    _qa_pass "$2"
  else
    _qa_fail "$2" "missing file: $1"
  fi
}

# assert_dir <path> <message>
assert_dir() {
  if [[ -d "$1" ]]; then
    _qa_pass "$2"
  else
    _qa_fail "$2" "missing directory: $1"
  fi
}

# assert_not_exists <path> <message>
assert_not_exists() {
  if [[ ! -e "$1" ]]; then
    _qa_pass "$2"
  else
    _qa_fail "$2" "should not exist: $1"
  fi
}

# qa_summary — print the case totals and return non-zero when anything failed.
qa_summary() {
  local note=""
  if [[ "$_QA_SKIPPED" -gt 0 ]]; then
    note=", $_QA_SKIPPED skipped"
  fi
  if [[ "$_QA_FAILED" -eq 0 ]]; then
    printf '    --- %d assertions, all passed%s\n' "$_QA_TOTAL" "$note"
    return 0
  fi
  printf '    --- %d assertions, %d failed%s\n' "$_QA_TOTAL" "$_QA_FAILED" "$note"
  return 1
}
