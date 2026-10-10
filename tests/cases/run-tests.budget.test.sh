#!/usr/bin/env bash
# Case: the tier duration budget is reported, and enforced on request.
#
# A tier that quietly grows past its budget stops being the fast feedback loop
# it was designed to be — Smoke is supposed to be "every commit", and a Smoke
# that takes three minutes is not. The runner therefore times each stage against
# the budget in the canonical table, and can fail on an overrun.
set -uo pipefail

QA_TESTS_DIR="${QA_TESTS_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$QA_TESTS_DIR/.." && pwd)}"
# shellcheck source=../lib/assert.sh
. "$QA_TESTS_DIR/lib/assert.sh"
# shellcheck source=../lib/sandbox.sh
. "$QA_TESTS_DIR/lib/sandbox.sh"

RUN="$REPO_ROOT/scripts/run-tests.sh"
PS_RUN="$REPO_ROOT/scripts/run-tests.ps1"

make_sandbox
trap cleanup_sandbox EXIT
install_shims

# --- the budgets match the canonical table ---------------------------------

SH_SRC="$(cat "$RUN")"
PS_SRC="$(cat "$PS_RUN")"
assert_match "$SH_SRC" 'smoke[)] echo 30' "run-tests.sh budgets Smoke at the canonical 30 s"
assert_match "$SH_SRC" 'regression[)] echo 300' "run-tests.sh budgets Regression at the canonical 5 min"
assert_match "$SH_SRC" 'full[)] echo 900' "run-tests.sh budgets Full at the canonical 15 min"
assert_match "$PS_SRC" '"Smoke" *[{] return 30 [}]' "run-tests.ps1 budgets Smoke at the canonical 30 s"
assert_match "$PS_SRC" '"Regression" *[{] return 300 [}]' "run-tests.ps1 budgets Regression at the canonical 5 min"
assert_match "$PS_SRC" '"Full" *[{] return 900 [}]' "run-tests.ps1 budgets Full at the canonical 15 min"

# --- a normal run reports the elapsed time against the budget -------------

net="$(new_workdir)"
fixture_dotnet_csproj "$net"

qa_run "$net" bash "$RUN" -s smoke
assert_exit 0 "$QA_STATUS" "a run inside its budget exits 0"
assert_contains "$QA_OUT" "budget 30s" "the run reports the elapsed time against the tier budget"

# --- an overrun is a warning by default, a failure with the flag ----------
#
# SHIM_SLEEP makes the stubbed toolchain take two seconds and QA_TIER_BUDGET
# lowers the budget to one, so the overrun is real rather than simulated.

QA_TIER_BUDGET=1
SHIM_SLEEP=2
export QA_TIER_BUDGET SHIM_SLEEP

slow="$(new_workdir)"
fixture_dotnet_csproj "$slow"

qa_run "$slow" bash "$RUN" -s smoke
assert_exit 0 "$QA_STATUS" "an overrun without --enforce-budget is a warning, not a failure"
assert_contains "$QA_OUT" "WARNING" "the overrun is reported as a warning"
assert_contains "$QA_OUT" "--enforce-budget" "the warning says how to turn it into a failure"

qa_run "$slow" bash "$RUN" -s smoke --enforce-budget
assert_exit 1 "$QA_STATUS" "--enforce-budget turns the overrun into a failure"
assert_contains "$QA_OUT" "overran its budget" "the failure names the overrun"

unset QA_TIER_BUDGET SHIM_SLEEP

qa_summary
