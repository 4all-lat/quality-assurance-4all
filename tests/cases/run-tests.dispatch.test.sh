#!/usr/bin/env bash
# Case: run-tests.sh dispatches the exact command line each stack and stage
# requires.
#
# Every filter string in this file is a contract: `Category=Smoke` is what
# separates the ~30s tier from the ~15min one, and `Category!=Security` is what
# keeps the security suite out of the PR tier. A silently reworded filter would
# not fail any test today. Here it fails this file.
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

run_stage() {
  local dir="$1" stage="$2"
  shift 2
  shim_reset
  qa_run "$dir" bash "$RUN" -s "$stage" "$@"
}

# ===========================================================================
# .NET
# ===========================================================================

net="$(new_workdir)"
fixture_dotnet_csproj "$net"

run_stage "$net" smoke
assert_exit 0 "$QA_STATUS" "dotnet smoke exits 0"
assert_shim_called dotnet test --results-directory ./test-results \
  --logger "console;verbosity=detailed" --filter "Category=Smoke"

run_stage "$net" regression
assert_exit 0 "$QA_STATUS" "dotnet regression exits 0"
assert_shim_called dotnet test --results-directory ./test-results \
  --logger "console;verbosity=detailed" --filter "Category!=Security&Category!=Performance"

run_stage "$net" coverage
assert_exit 0 "$QA_STATUS" "dotnet coverage exits 0"
assert_shim_called dotnet test --results-directory ./test-results \
  --logger "console;verbosity=detailed" "--collect:XPlat Code Coverage"
assert_shim_called reportgenerator \
  "-reports:./test-results/**/coverage.cobertura.xml" \
  "-targetdir:./test-results/coverage-report" \
  "-reporttypes:Html;Cobertura"

run_stage "$net" mutation
assert_exit 0 "$QA_STATUS" "dotnet mutation exits 0"
assert_shim_called dotnet stryker --output-path ./test-results/mutation-report --break-at 60

run_stage "$net" full
assert_exit 0 "$QA_STATUS" "dotnet full exits 0"
assert_shim_called dotnet test --results-directory ./test-results \
  --logger "console;verbosity=detailed"
assert_shim_called dotnet stryker --output-path ./test-results/mutation-report --break-at 60

run_stage "$net" mutation --project Sample.csproj
assert_exit 0 "$QA_STATUS" "dotnet mutation with --project exits 0"
assert_shim_called dotnet stryker -p Sample.csproj \
  --output-path ./test-results/mutation-report --break-at 60

run_stage "$net" mutation -m 80
assert_shim_called dotnet stryker --output-path ./test-results/mutation-report --break-at 80

# A tool that is already installed must not be installed again — even when the
# listing dies of SIGPIPE. `dotnet tool list -g | grep -q` under `pipefail` is a
# race: grep exits on the first match, the producer takes SIGPIPE and the
# pipeline fails exactly when the tool is present. SHIM_KILL_PIPE=1 reproduces
# that deterministically (the shim reports both tools as installed).
shim_reset
export SHIM_KILL_PIPE=1
qa_run "$net" bash "$RUN" -s mutation
unset SHIM_KILL_PIPE
assert_exit 0 "$QA_STATUS" "dotnet mutation survives a tool list that dies of SIGPIPE"
assert_shim_not_called dotnet tool install -g dotnet-stryker
assert_shim_not_called dotnet tool install -g dotnet-reportgenerator-globaltool

run_stage "$net" smoke --project Sample.csproj
assert_shim_called dotnet test Sample.csproj --results-directory ./test-results \
  --logger "console;verbosity=detailed" --filter "Category=Smoke"

# ===========================================================================
# Node.js / TypeScript
# ===========================================================================

node="$(new_workdir)"
fixture_node "$node"
printf '{}\n' >"$node/stryker.conf.json"

run_stage "$node" smoke
assert_exit 0 "$QA_STATUS" "node smoke exits 0"
assert_shim_called npx vitest run --testNamePattern Smoke

run_stage "$node" regression
assert_exit 0 "$QA_STATUS" "node regression exits 0"
# SecurityPR is deliberately *not* excluded: BOLA, authentication and injection
# must run on every PR, not wait for the nightly tier.
assert_shim_called npx vitest run --testNamePattern "^(?!.*(Security(?!PR)|Performance))"

run_stage "$node" coverage
assert_exit 0 "$QA_STATUS" "node coverage exits 0"
assert_shim_called npx vitest run --coverage

run_stage "$node" mutation
assert_exit 0 "$QA_STATUS" "node mutation exits 0 when a stryker config exists"
assert_shim_called npx stryker run

run_stage "$node" full
assert_exit 0 "$QA_STATUS" "node full exits 0"
assert_shim_called npx vitest run --coverage
assert_shim_called npx stryker run

# No stryker config: mutation must fail loudly rather than pretend to pass.
node_noconf="$(new_workdir)"
fixture_node "$node_noconf"
run_stage "$node_noconf" mutation
assert_exit 1 "$QA_STATUS" "node mutation without a stryker config exits 1"
assert_contains "$QA_OUT" "stryker" "node mutation without a config explains what is missing"

# ===========================================================================
# Python
# ===========================================================================

py="$(new_workdir)"
fixture_python_pytest_ini "$py"

run_stage "$py" smoke
assert_exit 0 "$QA_STATUS" "python smoke exits 0"
assert_shim_called python3 -m pytest -m smoke

run_stage "$py" regression
assert_exit 0 "$QA_STATUS" "python regression exits 0"
assert_shim_called python3 -m pytest -m "not security and not performance"

run_stage "$py" coverage
assert_exit 0 "$QA_STATUS" "python coverage exits 0"
assert_shim_called python3 -m pytest --cov --cov-report=html --cov-report=term

run_stage "$py" mutation
assert_exit 0 "$QA_STATUS" "python mutation exits 0"
assert_shim_called python3 -m mutmut run

run_stage "$py" full
assert_exit 0 "$QA_STATUS" "python full exits 0"
assert_shim_called python3 -m pytest --cov --cov-report=html --cov-report=term
assert_shim_called python3 -m mutmut run

# ===========================================================================
# Output directory
# ===========================================================================

out="$(new_workdir)"
fixture_dotnet_csproj "$out"
run_stage "$out" smoke --output-dir ./custom-out
assert_exit 0 "$QA_STATUS" "--output-dir run exits 0"
assert_dir "$out/custom-out" "--output-dir is created"
assert_shim_called dotnet test --results-directory ./custom-out \
  --logger "console;verbosity=detailed" --filter "Category=Smoke"

run_stage "$out" smoke -o ./nested/deep
assert_dir "$out/nested/deep" "--output-dir creates intermediate directories"

# ===========================================================================
# A failing toolchain must fail the runner
# ===========================================================================

net_fail="$(new_workdir)"
fixture_dotnet_csproj "$net_fail"
SHIM_FAIL_FOR=dotnet
SHIM_FAIL_EXIT=1
export SHIM_FAIL_FOR SHIM_FAIL_EXIT
run_stage "$net_fail" smoke
unset SHIM_FAIL_FOR SHIM_FAIL_EXIT
assert_exit 1 "$QA_STATUS" "a failing dotnet test fails the smoke stage"

py_fail="$(new_workdir)"
fixture_python_pytest_ini "$py_fail"
SHIM_FAIL_FOR=python3
export SHIM_FAIL_FOR
run_stage "$py_fail" smoke
unset SHIM_FAIL_FOR
assert_exit 1 "$QA_STATUS" "a failing pytest fails the smoke stage"

# A multi-step stage must report every step that broke, not just the first:
# the nightly tier exists to tell you everything that is wrong at once.
net_both="$(new_workdir)"
fixture_dotnet_csproj "$net_both"
SHIM_FAIL_FOR=dotnet
SHIM_FAIL_EXIT=1
export SHIM_FAIL_FOR SHIM_FAIL_EXIT
run_stage "$net_both" full
unset SHIM_FAIL_FOR SHIM_FAIL_EXIT
assert_exit 1 "$QA_STATUS" "full fails when one of its steps fails"
assert_shim_called dotnet stryker --output-path ./test-results/mutation-report --break-at 60

qa_summary
