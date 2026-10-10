#!/usr/bin/env bash
# Case: the bash and PowerShell scripts must stay in step.
#
# `pwsh` is not installed here, so parity is checked statically: the stages,
# the flags, the default mutation threshold, the stack enum and whether the
# project is handed to Stryker are each extracted from both implementations and
# compared. A new stage or flag added to one side only fails this file.
#
# Genuine, intentional differences belong in tests/parity-allowlist.txt with a
# reason. If pwsh is available, an extra dynamic check runs the real thing.
set -uo pipefail

QA_TESTS_DIR="${QA_TESTS_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$QA_TESTS_DIR/.." && pwd)}"
# shellcheck source=../lib/assert.sh
. "$QA_TESTS_DIR/lib/assert.sh"
# shellcheck source=../lib/sandbox.sh
. "$QA_TESTS_DIR/lib/sandbox.sh"

SH_RUN="$REPO_ROOT/scripts/run-tests.sh"
PS_RUN="$REPO_ROOT/scripts/run-tests.ps1"
SH_SETUP="$REPO_ROOT/scripts/setup-qa-project.sh"
PS_SETUP="$REPO_ROOT/scripts/setup-qa-project.ps1"
ALLOWLIST="$QA_TESTS_DIR/parity-allowlist.txt"

# allowlisted <suite> <item>
allowlisted() {
  [[ -f "$ALLOWLIST" ]] || return 1
  awk -v suite="$1" -v item="$2" '
    { sub(/#.*/, "") }
    NF >= 2 && $1 == suite && $2 == item { found = 1 }
    END { exit found ? 0 : 1 }' "$ALLOWLIST"
}

# compare_sets <suite> <what> <bash-block> <ps-block>
compare_sets() {
  local suite="$1" what="$2" bash_block="$3" ps_block="$4" item
  local missing_ps="" missing_sh=""

  while IFS= read -r item; do
    [[ -n "$item" ]] || continue
    if ! grep -Fxq -- "$item" <<<"$ps_block"; then
      if ! allowlisted "$suite" "$item"; then
        missing_ps="$missing_ps $item"
      fi
    fi
  done <<<"$bash_block"

  while IFS= read -r item; do
    [[ -n "$item" ]] || continue
    if ! grep -Fxq -- "$item" <<<"$bash_block"; then
      if ! allowlisted "$suite" "$item"; then
        missing_sh="$missing_sh $item"
      fi
    fi
  done <<<"$ps_block"

  if [[ -z "$missing_ps" && -z "$missing_sh" ]]; then
    _qa_pass "$suite: $what match"
  else
    _qa_fail "$suite: $what match" \
      "only in bash:${missing_ps:- none} | only in PowerShell:${missing_sh:- none}"
  fi
}

# --- extraction helpers -----------------------------------------------------

# Stages from `case "$STAGE" in ... esac`.
sh_stages() {
  sed -n '/case "\$STAGE" in/,/^  esac$/p' "$1" | sed -n 's/^ *\([a-z][a-z]*\))$/\1/p' | sort -u
}

# Stages from `switch ($Stage) { ... }` with "Smoke" { labels.
ps_stages() {
  sed -n '/switch (\$Stage)/,/^}/p' "$1" |
    sed -n 's/^ *"\([A-Za-z][A-Za-z]*\)" *{.*/\1/p' |
    tr 'A-Z' 'a-z' | sort -u
}

# Flags from the bash argument loop, e.g. `-p|--project) ...`
sh_flags() {
  sed -n '/while \[\[ \$# -gt 0 \]\]/,/^done$/p' "$1" |
    sed -n 's/^ *-[a-zA-Z]|\(--[a-z-]*\)).*/\1/p' | sort -u
}

# Parameters from the PowerShell param() block, canonicalised to the bash
# long flag they correspond to.
ps_run_flags() {
  sed -n '/^param(/,/^)/p' "$1" |
    sed -n 's/^ *\[[A-Za-z]*\]\$\([A-Za-z][A-Za-z]*\).*/\1/p' |
    while IFS= read -r name; do
      case "$name" in
        Stage) echo "--stage" ;;
        Project) echo "--project" ;;
        OutputDir) echo "--output-dir" ;;
        MutationThreshold) echo "--mutation-threshold" ;;
        EnforceBudget) echo "--enforce-budget" ;;
        *) echo "--$(echo "$name" | tr 'A-Z' 'a-z')" ;;
      esac
    done | sort -u
}

ps_setup_flags() {
  sed -n '/^param(/,/^)/p' "$1" |
    sed -n 's/^ *\[[A-Za-z]*\]\$\([A-Za-z][A-Za-z]*\).*/\1/p' |
    while IFS= read -r name; do
      case "$name" in
        ProjectName) echo "--name" ;;
        Stack) echo "--stack" ;;
        OutputDir) echo "--output-dir" ;;
        *) echo "--$(echo "$name" | tr 'A-Z' 'a-z')" ;;
      esac
    done | sort -u
}

# --- the files exist --------------------------------------------------------

for script in "$SH_RUN" "$PS_RUN" "$SH_SETUP" "$PS_SETUP"; do
  assert_file "$script" "$(basename "$script") exists"
done

# --- stages -----------------------------------------------------------------

SH_STAGES="$(sh_stages "$SH_RUN")"
PS_STAGES="$(ps_stages "$PS_RUN")"
compare_sets "run-tests" "stages" "$SH_STAGES" "$PS_STAGES"
assert_eq "$(printf '%s\n' "$SH_STAGES" | wc -l | tr -d ' ')" "5" "the runner defines five stages"

# --- flags ------------------------------------------------------------------

compare_sets "run-tests" "flags" "$(sh_flags "$SH_RUN")" "$(ps_run_flags "$PS_RUN")"
compare_sets "setup" "flags" "$(sh_flags "$SH_SETUP")" "$(ps_setup_flags "$PS_SETUP")"

# --- default mutation threshold --------------------------------------------

sh_threshold="$(sed -n 's/^MUTATION_THRESHOLD=\([0-9]*\)$/\1/p' "$SH_RUN")"
ps_threshold="$(sed -n 's/^ *\[int\]\$MutationThreshold *= *\([0-9]*\).*/\1/p' "$PS_RUN")"
assert_eq "$sh_threshold" "$ps_threshold" "the default mutation threshold is the same in both runners"
assert_eq "$sh_threshold" "60" "the default mutation threshold is 60"

# --- stack enum -------------------------------------------------------------

sh_stacks="$(sed -n '/^case "\$STACK" in$/,/^esac$/p' "$SH_SETUP" | sed -n 's/^ *\([a-z|]*\)).*/\1/p' | tr '|' '\n' | sort -u)"
ps_stacks="$(sed -n 's/.*ValidateSet(\(.*\)).*/\1/p' "$PS_SETUP" | tr -d '",' | tr ' ' '\n' | sed '/^$/d' | sort -u)"
compare_sets "setup" "stack enum" "$sh_stacks" "$ps_stacks"
assert_eq "$(printf '%s\n' "$sh_stacks" | wc -l | tr -d ' ')" "3" "three stacks are supported"

# --- Stryker must be told which project to mutate ---------------------------

assert_eq "$(grep 'dotnet stryker' "$SH_RUN" | grep -c 'PROJECT:+-p')" \
  "$(grep -c 'dotnet stryker' "$SH_RUN")" \
  "run-tests.sh passes the test project to every Stryker invocation"
assert_eq "$(grep 'dotnet stryker' "$PS_RUN" | grep -c -- '-p \$testProject')" \
  "$(grep -c 'dotnet stryker' "$PS_RUN")" \
  "run-tests.ps1 passes the test project to every Stryker invocation"

# --- the documented limitations stay accurate -------------------------------

README="$REPO_ROOT/scripts/README.md"
if [[ -f "$README" ]]; then
  assert_contains "$(cat "$README")" ".NET-only" \
    "scripts/README.md records that run-tests.ps1 is .NET-only"
else
  _qa_fail "scripts/README.md exists" "missing file: $README"
fi

# --- optional: run the real PowerShell against the real bash ----------------

if command -v pwsh >/dev/null 2>&1; then
  sh_dynamic="$(grep -oE '^\s+(smoke|regression|full|coverage|mutation)\)' "$SH_RUN" | tr -d ' )' | sort -u)"
  ps_dynamic="$(pwsh -NoProfile -Command "
    (Get-Command '$PS_RUN').Parameters['Stage'].Attributes |
    Where-Object { \$_ -is [System.Management.Automation.ValidateSetAttribute] } |
    ForEach-Object { \$_.ValidValues }" 2>/dev/null | tr 'A-Z' 'a-z' | sort -u)"
  compare_sets "run-tests" "stages (dynamic)" "$sh_dynamic" "$ps_dynamic"
else
  qa_skip "dynamic parity check: pwsh is not installed"
fi

qa_summary
