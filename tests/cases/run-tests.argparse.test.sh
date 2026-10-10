#!/usr/bin/env bash
# Case: run-tests.sh argument parsing and the exit-code contract.
#
#   exit 0 — the requested stage ran and succeeded
#   exit 1 — gate or environment failure (bad stage, no stack detected, test failure)
#   exit 2 — usage error (unknown flag, flag without a value, invalid flag value)
#
# The distinction matters in CI: today an unknown flag prints "ERROR: Unknown
# argument" and then exits 0, so a typo in a pipeline reads as a green build.
set -uo pipefail

QA_TESTS_DIR="${QA_TESTS_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$QA_TESTS_DIR/.." && pwd)}"
# shellcheck source=../lib/assert.sh
. "$QA_TESTS_DIR/lib/assert.sh"
# shellcheck source=../lib/sandbox.sh
. "$QA_TESTS_DIR/lib/sandbox.sh"

RUN="$REPO_ROOT/scripts/run-tests.sh"

make_sandbox
trap cleanup_sandbox EXIT
install_shims

# A workdir that auto-detects as .NET, so valid invocations get past detection.
dotnet_dir="$(new_workdir)"
fixture_dotnet_sln "$dotnet_dir"

# --- --help ----------------------------------------------------------------

qa_run "$dotnet_dir" bash "$RUN" --help
assert_exit 0 "$QA_STATUS" "--help exits 0"
assert_contains "$QA_OUT" "Usage:" "--help prints the usage block"
assert_contains "$QA_OUT" "smoke" "--help lists the stages"

qa_run "$dotnet_dir" bash "$RUN" -h
assert_exit 0 "$QA_STATUS" "-h exits 0"

# --- unknown flag ----------------------------------------------------------

qa_run "$dotnet_dir" bash "$RUN" -s smoke --bogus
assert_exit 2 "$QA_STATUS" "unknown flag exits 2 rather than reporting success"
assert_contains "$QA_OUT" "Unknown argument: --bogus" "unknown flag is named in the message"

# --- flag without a value --------------------------------------------------

qa_run "$dotnet_dir" bash "$RUN" -s
assert_exit 2 "$QA_STATUS" "--stage without a value exits 2"
assert_contains "$QA_OUT" "--stage" "--stage without a value names the flag"
assert_contains "$QA_OUT" "value" "--stage without a value says what is missing"

qa_run "$dotnet_dir" bash "$RUN" -s smoke -m
assert_exit 2 "$QA_STATUS" "--mutation-threshold without a value exits 2"
assert_contains "$QA_OUT" "--mutation-threshold" "--mutation-threshold without a value names the flag"

qa_run "$dotnet_dir" bash "$RUN" -s smoke -p
assert_exit 2 "$QA_STATUS" "--project without a value exits 2"

qa_run "$dotnet_dir" bash "$RUN" -s smoke -o
assert_exit 2 "$QA_STATUS" "--output-dir without a value exits 2"

# --- mutation threshold must be an integer in 0..100 ----------------------

qa_run "$dotnet_dir" bash "$RUN" -s smoke -m abc
assert_exit 2 "$QA_STATUS" "a non-numeric threshold exits 2"
assert_contains "$QA_OUT" "threshold" "a non-numeric threshold is reported as a threshold problem"

qa_run "$dotnet_dir" bash "$RUN" -s smoke -m 150
assert_exit 2 "$QA_STATUS" "a threshold above 100 exits 2"

qa_run "$dotnet_dir" bash "$RUN" -s smoke -m -5
assert_exit 2 "$QA_STATUS" "a negative threshold exits 2"

qa_run "$dotnet_dir" bash "$RUN" -s smoke -m 0
assert_exit 0 "$QA_STATUS" "threshold 0 is accepted"

qa_run "$dotnet_dir" bash "$RUN" -s smoke -m 100
assert_exit 0 "$QA_STATUS" "threshold 100 is accepted"

# --- stage normalisation and validation ------------------------------------

qa_run "$dotnet_dir" bash "$RUN" -s SMOKE
assert_exit 0 "$QA_STATUS" "-s SMOKE is normalised to lower case and accepted"

qa_run "$dotnet_dir" bash "$RUN" --stage Regression
assert_exit 0 "$QA_STATUS" "--stage Regression is accepted"

qa_run "$dotnet_dir" bash "$RUN" -s regresion
assert_exit 1 "$QA_STATUS" "a misspelled stage is a gate failure (1), not a usage error"

qa_run "$dotnet_dir" bash "$RUN" -s ""
assert_exit 1 "$QA_STATUS" "an empty stage value is a gate failure (1), not a usage error"

qa_run "$dotnet_dir" bash "$RUN" -s nosuchstage
assert_exit 1 "$QA_STATUS" "an unknown stage name exits 1"
assert_contains "$QA_OUT" "Smoke" "the stage error lists the valid stages"

# --- long and short forms are equivalent -----------------------------------

qa_run "$dotnet_dir" bash "$RUN" --stage smoke --project Sample.sln --output-dir ./out --mutation-threshold 80
assert_exit 0 "$QA_STATUS" "long-form flags are all accepted"

qa_run "$dotnet_dir" bash "$RUN" -s smoke -p Sample.sln -o ./out -m 80
assert_exit 0 "$QA_STATUS" "short-form flags are all accepted"

qa_summary
