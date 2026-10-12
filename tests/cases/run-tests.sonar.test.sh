#!/usr/bin/env bash
# Case: the Sonar stage runs the scanner the way each stack needs it to run.
#
# The shape of this stage is not cosmetic. For .NET the scanner has to wrap the
# build — begin, build, test, end — and the coverage the gate measures has to be
# produced inside that window; a report from an earlier `-s Coverage` run is not
# picked up, so a stage that only analyzed would report 0% coverage and fail the
# gate for the wrong reason. For the other two stacks the report has to exist
# before the scanner starts, and for Vitest it has to be lcov.
#
# `sonar.qualitygate.wait=true` on every stack is the difference between a gate
# and a report: without it the scanner returns as soon as the analysis is queued,
# and a red gate is reported as a pass.
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

export SONAR_PROJECT_KEY="qa-4all_under-test"

# ===========================================================================
# The project key is required, and its absence is an environment failure
# ===========================================================================

keyless="$(new_workdir)"
fixture_dotnet_csproj "$keyless"
shim_reset
qa_run "$keyless" env -u SONAR_PROJECT_KEY bash "$RUN" -s sonar
assert_exit 1 "$QA_STATUS" "sonar without SONAR_PROJECT_KEY fails rather than analyzing an empty key"
assert_contains "$QA_OUT" "SONAR_PROJECT_KEY" "the failure names the missing variable"
assert_shim_never dotnet

# ===========================================================================
# .NET — the scanner wraps the build
# ===========================================================================

net="$(new_workdir)"
fixture_dotnet_csproj "$net"
shim_reset
qa_run "$net" bash "$RUN" -s Sonar
assert_exit 0 "$QA_STATUS" "dotnet sonar exits 0"

assert_shim_called dotnet sonarscanner begin \
  "/k:qa-4all_under-test" \
  "/d:sonar.qualitygate.wait=true" \
  "/d:sonar.cs.cobertura.reportsPaths=./test-results/**/coverage.cobertura.xml"
assert_shim_called dotnet build
assert_shim_called dotnet test --results-directory ./test-results \
  --logger "console;verbosity=detailed" "--collect:XPlat Code Coverage"
assert_shim_called dotnet sonarscanner end

# The scanner is a global tool like Stryker and ReportGenerator, and the shim
# reports it as installed, so the stage must not try to install it again.
assert_shim_not_called dotnet tool install -g dotnet-sonarscanner

# ===========================================================================
# Node.js — lcov, because the scanner cannot read Vitest's other formats
# ===========================================================================

node="$(new_workdir)"
fixture_node "$node"
shim_reset
qa_run "$node" bash "$RUN" -s sonar
assert_exit 0 "$QA_STATUS" "node sonar exits 0"

assert_shim_called npx vitest run --coverage --coverage.reporter=lcov
assert_shim_called npx sonar-scanner \
  "-Dsonar.projectKey=qa-4all_under-test" \
  "-Dsonar.javascript.lcov.reportPaths=coverage/lcov.info" \
  "-Dsonar.qualitygate.wait=true"

# ===========================================================================
# Python — the scanner reads coverage.xml, written by pytest before it starts
# ===========================================================================

py="$(new_workdir)"
fixture_python_pytest_ini "$py"
shim_reset
qa_run "$py" bash "$RUN" -s sonar
assert_exit 0 "$QA_STATUS" "python sonar exits 0"

assert_shim_called python3 -m pytest --cov --cov-report=xml
assert_shim_called sonar-scanner \
  "-Dsonar.projectKey=qa-4all_under-test" \
  "-Dsonar.python.coverage.reportPaths=coverage.xml" \
  "-Dsonar.qualitygate.wait=true"

# ===========================================================================
# A red gate is a red stage
# ===========================================================================

# The scanner exits non-zero when the gate fails — that is the whole reason
# `qualitygate.wait` is passed. A runner that swallowed it would turn the gate
# back into a report. The Python stack is the one that invokes the scanner
# directly, so this is where a failing scanner can be injected.
fail="$(new_workdir)"
fixture_python_pytest_ini "$fail"
SHIM_FAIL_FOR=sonar-scanner
export SHIM_FAIL_FOR
shim_reset
qa_run "$fail" bash "$RUN" -s sonar
unset SHIM_FAIL_FOR
assert_exit 1 "$QA_STATUS" "a failing quality gate fails the stage"

# ===========================================================================
# The stage is untiered
# ===========================================================================

# Coverage, Mutation and Sonar are tools, not tiers: timing them against a tier
# budget would invent a fourth budget the canonical table does not have.
unbudgeted="$(new_workdir)"
fixture_dotnet_csproj "$unbudgeted"
shim_reset
qa_run "$unbudgeted" bash "$RUN" -s sonar --enforce-budget
assert_exit 0 "$QA_STATUS" "sonar is not subject to a tier budget"
assert_not_contains "$QA_OUT" "budget" "the sonar stage reports no tier budget"

qa_summary
