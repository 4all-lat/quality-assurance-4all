#!/usr/bin/env bash
# Case: setup-qa-project.sh actually produces the documented scaffold.
#
# The generated tree is the contract the rest of the pipeline assumes: the
# coverage thresholds the scaffolder writes are the ones quality-gates.md
# quotes back (80), the pytest markers are the ones run-tests.sh filters on
# (smoke/regression/security/performance/property), and the folder names are
# what the BDD and security templates point at.
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

# ===========================================================================
# .NET
# ===========================================================================

net="$(new_workdir)"
qa_run "$net" bash "$SETUP" -n Proj.Tests -s dotnet
assert_exit 0 "$QA_STATUS" "dotnet scaffold with the default --output-dir exits 0"
assert_dir "$net/Proj.Tests" "the project directory is created"
assert_not_exists "$net/Proj.Tests/Proj.Tests" \
  "the project is not nested inside a directory of its own name"

assert_shim_called_prefix dotnet new xunit -n Proj.Tests

for pkg in FluentAssertions Moq coverlet.collector Microsoft.AspNetCore.Mvc.Testing \
           FsCheck FsCheck.Xunit Reqnroll.xUnit Microsoft.Playwright; do
  assert_shim_called dotnet add package "$pkg"
done

for folder in Features Integration Concurrency Security Performance PropertyBased Controllers Services Repositories; do
  assert_dir "$net/Proj.Tests/$folder" "dotnet scaffold creates $folder/"
done

# The global tools are reported as already installed by the shim, so the
# scaffolder must not try to install them again.
assert_shim_not_called dotnet tool install -g dotnet-stryker
assert_shim_not_called dotnet tool install -g dotnet-reportgenerator-globaltool

# ...and it must still reach that conclusion when the listing arrives over a
# pipe that closes early. `dotnet tool list -g | grep -q` under `pipefail` is a
# race: grep exits on the first match and the producer dies of SIGPIPE, so the
# pipeline fails exactly when the tool is installed. The shim reproduces that
# deterministically with SHIM_KILL_PIPE=1.
shim_reset
net_pipe="$(new_workdir)"
export SHIM_KILL_PIPE=1
qa_run "$net_pipe" bash "$SETUP" -n Proj.Tests -s dotnet
unset SHIM_KILL_PIPE
assert_exit 0 "$QA_STATUS" "dotnet scaffold survives a tool list that dies of SIGPIPE"
assert_shim_not_called dotnet tool install -g dotnet-stryker
assert_shim_not_called dotnet tool install -g dotnet-reportgenerator-globaltool

# ===========================================================================
# Node.js / TypeScript
# ===========================================================================

node="$(new_workdir)"
qa_run "$node" bash "$SETUP" -n proj -s nodejs
assert_exit 0 "$QA_STATUS" "nodejs scaffold exits 0"
assert_dir "$node/proj" "the project directory is created"

for folder in features integration concurrency performance property-based security unit; do
  assert_dir "$node/proj/$folder" "nodejs scaffold creates $folder/"
done

assert_shim_called npm init -y
assert_shim_called npm pkg set type=module
assert_shim_called npm install -D vitest @vitest/coverage-v8 @playwright/test \
  fast-check @cucumber/cucumber @stryker-mutator/core

assert_file "$node/proj/vitest.config.ts" "vitest.config.ts is generated"
vitest_cfg="$(cat "$node/proj/vitest.config.ts")"
for metric in lines functions branches statements; do
  assert_contains "$vitest_cfg" "$metric: 80" "vitest.config.ts pins $metric coverage at 80"
done

# ===========================================================================
# Python
# ===========================================================================

py="$(new_workdir)"
qa_run "$py" bash "$SETUP" -n proj -s python
assert_exit 0 "$QA_STATUS" "python scaffold exits 0"
assert_dir "$py/proj" "the project directory is created"

for folder in features integration concurrency performance property_based security unit; do
  assert_dir "$py/proj/$folder" "python scaffold creates $folder/"
  assert_file "$py/proj/$folder/__init__.py" "python scaffold makes $folder a package"
done

assert_shim_called python3 -m pip install -r requirements.txt

assert_file "$py/proj/requirements.txt" "requirements.txt is generated"
requirements="$(cat "$py/proj/requirements.txt")"
for dep in "pytest>=8.0" "pytest-cov>=4.0" "hypothesis>=6.0" \
           "behave>=1.2" "mutmut>=2.0" "locust>=2.0"; do
  assert_contains "$requirements" "$dep" "requirements.txt pins $dep"
done

assert_file "$py/proj/.coveragerc" ".coveragerc is generated"
coveragerc="$(cat "$py/proj/.coveragerc")"
assert_contains "$coveragerc" "fail_under = 80" ".coveragerc fails the build below 80% coverage"

assert_file "$py/proj/pytest.ini" "pytest.ini is generated"
pytest_ini="$(cat "$py/proj/pytest.ini")"
# Every marker the runner's filters name must be declared, or pytest warns and
# the `-m` selection silently matches nothing.
for marker in smoke regression concurrency security securitypr performance property; do
  assert_contains "$pytest_ini" "$(printf '\n    %s:' "$marker")" \
    "pytest.ini declares the $marker marker"
done

# ===========================================================================
# --output-dir
# ===========================================================================

out="$(new_workdir)"
qa_run "$out" bash "$SETUP" -n proj -s python -o ./sub
assert_exit 0 "$QA_STATUS" "python scaffold into a nested --output-dir exits 0"
assert_dir "$out/sub/proj" "the project lands under --output-dir"
assert_not_exists "$out/proj" "nothing is written to the working directory instead"

out="$(new_workdir)"
qa_run "$out" bash "$SETUP" -n proj -s nodejs -o "$out/abs"
assert_exit 0 "$QA_STATUS" "nodejs scaffold into an absolute --output-dir exits 0"
assert_dir "$out/abs/proj" "the project lands under the absolute --output-dir"

qa_summary
