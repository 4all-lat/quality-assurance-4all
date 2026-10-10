#!/usr/bin/env bash
# Case: run-tests.sh stack detection, and what it does with an unusable
# --project path.
#
# An explicit --project that does not exist must be a hard error. Today it is
# silently ignored: the script falls through to auto-detection, so
# `--project typo.csproj` inside a Node repository happily runs the Node suite
# and exits 0.
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

# expect_stack <workdir> <stack> <label> [extra args...]
expect_stack() {
  local dir="$1" want="$2" label="$3"
  shift 3
  qa_run "$dir" bash "$RUN" -s smoke "$@"
  assert_exit 0 "$QA_STATUS" "$label: exits 0"
  assert_match "$QA_OUT" "Stack:[[:space:]]+$want" "$label: detected as $want"
}

# --- marker files ----------------------------------------------------------

for pair in "sln:dotnet:fixture_dotnet_sln" \
            "csproj:dotnet:fixture_dotnet_csproj" \
            "package.json:node:fixture_node" \
            "pytest.ini:python:fixture_python_pytest_ini" \
            "pyproject.toml:python:fixture_python_pyproject" \
            "setup.py:python:fixture_python_setup_py" \
            "setup.cfg:python:fixture_python_setup_cfg"; do
  marker="${pair%%:*}"
  rest="${pair#*:}"
  want="${rest%%:*}"
  builder="${rest#*:}"
  dir="$(new_workdir)"
  "$builder" "$dir"
  expect_stack "$dir" "$want" "a directory with $marker"
done

# --- --project overrides the directory scan --------------------------------

dir="$(new_workdir)"
fixture_node "$dir"
fixture_dotnet_sln "$dir"
qa_run "$dir" bash "$RUN" -s smoke --project Sample.sln
assert_match "$QA_OUT" "Stack:[[:space:]]+dotnet" "--project *.sln wins over a package.json in the same directory"

dir="$(new_workdir)"
mkdir -p "$dir/apps/web"
fixture_node "$dir/apps/web"
expect_stack "$dir" "node" "--project on a nested package.json" --project apps/web/package.json

dir="$(new_workdir)"
printf 'import pytest\n' >"$dir/conftest.py"
expect_stack "$dir" "python" "--project on a file matching no known marker" --project conftest.py

# --- a --project that does not exist ---------------------------------------

dir="$(new_workdir)"
qa_run "$dir" bash "$RUN" -s smoke --project missing.csproj
assert_exit 1 "$QA_STATUS" "--project pointing at a missing file exits 1"
assert_contains "$QA_OUT" "missing.csproj" "--project failure names the path that was not found"
assert_not_contains "$QA_OUT" "Could not detect the stack" "--project failure is not reported as a detection problem"

# The dangerous case: auto-detection would have succeeded, so the bad
# --project is swallowed and the run looks green.
dir="$(new_workdir)"
fixture_node "$dir"
shim_reset
qa_run "$dir" bash "$RUN" -s smoke --project missing.csproj
assert_exit 1 "$QA_STATUS" "a bad --project is not silently replaced by auto-detection"
assert_shim_never "npx" "no Node command is run when --project is unusable"

# --- nothing to detect -----------------------------------------------------

dir="$(new_workdir)"
qa_run "$dir" bash "$RUN" -s smoke
assert_exit 1 "$QA_STATUS" "an empty directory exits 1"
assert_contains "$QA_OUT" "Could not detect the stack" "an empty directory says detection failed"
assert_contains "$QA_OUT" "--project" "the detection error suggests --project"

# --- detection is skipped entirely when the stage is invalid ---------------

dir="$(new_workdir)"
qa_run "$dir" bash "$RUN" -s bogus
assert_exit 1 "$QA_STATUS" "an invalid stage fails before detection"

qa_summary
