#!/usr/bin/env bash
# Sandbox helpers: throwaway project fixtures and PATH shims for the external
# toolchains (dotnet / npm / python / stryker / reportgenerator / sonar-scanner).
#
# The suite never invokes a real toolchain. Every external command the scripts
# under test call is intercepted by a recorder shim, so the tests assert on the
# exact argv the script produced. This is what makes the suite runnable on a
# machine with nothing installed.

QA_TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# make_sandbox — create the per-case sandbox root.
make_sandbox() {
  QA_SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/qa-4all-test.XXXXXX")"
  export QA_SANDBOX
  printf '%s\n' "$QA_SANDBOX"
}

cleanup_sandbox() {
  if [[ -n "${QA_SANDBOX:-}" && -d "$QA_SANDBOX" ]]; then
    rm -rf "$QA_SANDBOX"
  fi
}

# install_shims — shadow the external toolchains with the recorder.
install_shims() {
  local bindir="$QA_SANDBOX/bin"
  mkdir -p "$bindir"
  local shim
  for shim in dotnet npm npx python3 python pytest reportgenerator stryker sonar-scanner; do
    ln -sf "$QA_TESTS_DIR/shims/_recorder" "$bindir/$shim"
  done
  SHIM_LOG="$QA_SANDBOX/shims.log"
  : > "$SHIM_LOG"
  export SHIM_LOG
  PATH="$bindir:$PATH"
  export PATH
}

# new_workdir — a fresh directory to run a script under test inside.
new_workdir() {
  mktemp -d "$QA_SANDBOX/work.XXXXXX"
}

# --- Project fixtures -------------------------------------------------------

fixture_dotnet_sln() { : > "$1/Sample.sln"; }
fixture_dotnet_csproj() { : > "$1/Sample.csproj"; }
fixture_node() { printf '{"name":"sample"}\n' > "$1/package.json"; }
fixture_python_pytest_ini() { printf '[pytest]\n' > "$1/pytest.ini"; }
fixture_python_pyproject() { printf '[project]\nname="sample"\n' > "$1/pyproject.toml"; }
fixture_python_setup_py() { printf 'from setuptools import setup\n' > "$1/setup.py"; }
fixture_python_setup_cfg() { printf '[metadata]\n' > "$1/setup.cfg"; }
# Nothing at all: exercises the "could not detect the stack" path.

# --- Running the script under test -----------------------------------------

# qa_run <workdir> <command...> — run capturing stdout+stderr and the status.
# Sets QA_OUT and QA_STATUS. Always returns 0 so case files are never aborted.
# Set QA_VERBOSE=1 to echo what the script under test printed.
qa_run() {
  local workdir="$1"
  shift
  QA_OUT=""
  QA_STATUS=0
  QA_OUT="$(cd "$workdir" && "$@" 2>&1)" || QA_STATUS=$?
  if [[ -n "${QA_VERBOSE:-}" ]]; then
    printf '    [verbose] %s (exit %d)\n' "$*" "$QA_STATUS"
    printf '%s\n' "$QA_OUT" | sed 's/^/    | /'
  fi
  return 0
}

# shim_reset — forget every call recorded so far, so a later assertion only
# sees what the immediately preceding invocation did.
shim_reset() {
  : > "$SHIM_LOG"
}

# --- Shim log assertions ----------------------------------------------------

_shim_expected_line() {
  local name="$1"
  shift
  printf '%s' "$name"
  local arg
  for arg in "$@"; do
    printf '\t%s' "$arg"
  done
  printf '\n'
}

# assert_shim_called <shim> <arg>... — exact argv match, one invocation.
assert_shim_called() {
  local name="$1"
  shift
  local want got
  want="$(_shim_expected_line "$name" "$@")"
  if grep -Fxq "$want" "$SHIM_LOG" 2>/dev/null; then
    _qa_pass "invoked: $name $*"
  else
    got="$(awk -F'\t' '{printf "  %s %s\n", $1, substr($0, index($0,$2))}' "$SHIM_LOG" 2>/dev/null | head -20)"
    _qa_fail "invoked: $name $*" "not found among recorded calls:
$got"
  fi
}

# assert_shim_called_prefix <shim> <arg>... — first N argv entries must match,
# extra trailing arguments are ignored. Use when part of the command line is
# environment-dependent (absolute paths, temp directories).
assert_shim_called_prefix() {
  local name="$1"
  shift
  local want
  want="$(_shim_expected_line "$name" "$@")"
  want="${want%$'\n'}"
  if awk -F'\t' -v pat="$want" '
      BEGIN { n = split(pat, p, "\t") }
      {
        ok = 1
        for (i = 1; i <= n; i++) if ($i != p[i]) ok = 0
        if (ok) { found = 1; exit }
      }
      END { exit found ? 0 : 1 }' "$SHIM_LOG" 2>/dev/null; then
    _qa_pass "invoked: $name $* (prefix)"
  else
    _qa_fail "invoked: $name $* (prefix)" "no recorded call starts with it:
$(shim_calls | head -20)"
  fi
}

# assert_shim_not_called <shim> <arg>... — exact argv must be absent.
assert_shim_not_called() {
  local name="$1"
  shift
  local want
  want="$(_shim_expected_line "$name" "$@")"
  if grep -Fxq "$want" "$SHIM_LOG" 2>/dev/null; then
    _qa_fail "not invoked: $name $*" "but it was recorded"
  else
    _qa_pass "not invoked: $name $*"
  fi
}

# assert_shim_never <shim> — the shim was never called at all.
assert_shim_never() {
  if awk -F'\t' -v n="$1" '$1 == n { found = 1 } END { exit !found }' "$SHIM_LOG" 2>/dev/null; then
    _qa_fail "never invoked: $1" "but it was recorded"
  else
    _qa_pass "never invoked: $1"
  fi
}

# shim_calls — dump the recorded calls, for human-readable failure triage.
shim_calls() {
  awk -F'\t' '{printf "    %s %s\n", $1, substr($0, index($0,$2))}' "$SHIM_LOG" 2>/dev/null
}
