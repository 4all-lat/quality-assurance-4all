#!/usr/bin/env bash
# Case: setup-qa-project.sh argument parsing and the exit-code contract.
#
# Same contract as run-tests.sh: 0 success · 1 gate/environment failure ·
# 2 usage error. Today a missing --name, an unknown flag and a flag without a
# value all end in either exit 0 or a silent exit 1, so a mistyped invocation
# reads as a successful scaffold.
set -uo pipefail

QA_TESTS_DIR="${QA_TESTS_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$QA_TESTS_DIR/.." && pwd)}"
# shellcheck source=../lib/assert.sh
. "$QA_TESTS_DIR/lib/assert.sh"
# shellcheck source=../lib/sandbox.sh
. "$QA_TESTS_DIR/lib/sandbox.sh"

SETUP="$REPO_ROOT/scripts/setup-qa-project.sh"

make_sandbox
trap cleanup_sandbox EXIT
install_shims

# --- --help ----------------------------------------------------------------

dir="$(new_workdir)"
qa_run "$dir" bash "$SETUP" --help
assert_exit 0 "$QA_STATUS" "--help exits 0"
assert_contains "$QA_OUT" "Usage:" "--help prints the usage block"
assert_contains "$QA_OUT" "setup-qa-project.sh" "--help names the script"

qa_run "$dir" bash "$SETUP" -h
assert_exit 0 "$QA_STATUS" "-h exits 0"

# --- required arguments ----------------------------------------------------

qa_run "$dir" bash "$SETUP"
assert_exit 1 "$QA_STATUS" "no arguments at all exits 1"
assert_contains "$QA_OUT" "--name" "the missing-argument error names --name"
assert_contains "$QA_OUT" "--stack" "the missing-argument error names --stack"

qa_run "$dir" bash "$SETUP" -n proj
assert_exit 1 "$QA_STATUS" "--stack missing exits 1"

qa_run "$dir" bash "$SETUP" -s python
assert_exit 1 "$QA_STATUS" "--name missing exits 1"
assert_contains "$QA_OUT" "--name" "the --name error names the flag"

# --- unknown flag ----------------------------------------------------------

qa_run "$dir" bash "$SETUP" -n proj -s python --bogus
assert_exit 2 "$QA_STATUS" "unknown flag exits 2 rather than reporting success"
assert_contains "$QA_OUT" "Unknown argument: --bogus" "unknown flag is named"

# --- flag without a value --------------------------------------------------

qa_run "$dir" bash "$SETUP" -n
assert_exit 2 "$QA_STATUS" "-n without a value exits 2"
assert_contains "$QA_OUT" "--name" "-n without a value names the flag"
assert_contains "$QA_OUT" "value" "-n without a value says what is missing"

qa_run "$dir" bash "$SETUP" -n proj -s
assert_exit 2 "$QA_STATUS" "-s without a value exits 2"

qa_run "$dir" bash "$SETUP" -n proj -s python -o
assert_exit 2 "$QA_STATUS" "-o without a value exits 2"

# --- stack enum ------------------------------------------------------------

qa_run "$dir" bash "$SETUP" -n proj -s bogus
assert_exit 1 "$QA_STATUS" "a stack outside the enum exits 1"
assert_contains "$QA_OUT" "dotnet, nodejs, python" "the stack error lists the accepted values"

qa_run "$dir" bash "$SETUP" -n proj -s DOTNET
assert_exit 1 "$QA_STATUS" "the stack enum is case sensitive (dotnet, not DOTNET)"

# --- refusing to clobber an existing directory -----------------------------

dir="$(new_workdir)"
mkdir -p "$dir/proj"
qa_run "$dir" bash "$SETUP" -n proj -s python
assert_exit 1 "$QA_STATUS" "an existing project directory exits 1"
assert_contains "$QA_OUT" "already exists" "the collision error says the directory exists"

dir="$(new_workdir)"
mkdir -p "$dir/sub/proj"
qa_run "$dir" bash "$SETUP" -n proj -s python -o ./sub
assert_exit 1 "$QA_STATUS" "an existing project directory under --output-dir exits 1"

# --- argument order does not matter ----------------------------------------

dir="$(new_workdir)"
qa_run "$dir" bash "$SETUP" -s python -n proj -o .
assert_exit 0 "$QA_STATUS" "flags may be given in any order"
assert_dir "$dir/proj" "the project directory is created"

qa_summary
