#!/usr/bin/env bash
#
# run-tests.sh — Stratified test runner for the QA pipeline.
#
# Cross-platform (macOS / Linux / CI) equivalent of run-tests.ps1.
# Auto-detects the stack (.NET, Node.js/TS, Python) and runs the matching command
# for the requested stage.
#
# --- usage ---
# Usage: run-tests.sh --stage <stage> [options]
#
# Stages:
#   smoke      ~30s, every commit — health, swagger, auth login
#   regression ~5min, every PR — all functional tests
#   full       ~15min, nightly/pre-release — everything + mutation
#   coverage   generate coverage report
#   mutation   run mutation testing only (fails if score < threshold)
#
# Options:
#   -s, --stage <stage>               smoke|regression|full|coverage|mutation
#   -p, --project <path>              test project (default: auto-detect)
#   -o, --output-dir <dir>            artifact directory (default: ./test-results)
#   -m, --mutation-threshold <0-100>  minimum mutation score (default: 60)
#   -b, --enforce-budget              fail the stage if it overruns its tier budget
#   -h, --help                        show this message
#
# Tier budgets: the stage is timed and reported against its budget (Smoke 30s,
# Regression 5min, Full 15min). With --enforce-budget an overrun fails the run;
# QA_TIER_BUDGET=<seconds> overrides the budget for a slower CI runner.
#
# Exit codes:
#   0  the requested stage ran and succeeded
#   1  gate or environment failure (bad stage, no stack detected, test failure, budget overrun)
#   2  usage error (unknown flag, flag without a value, invalid flag value)
#
# Examples:
#   ./run-tests.sh --stage Smoke
#   ./run-tests.sh -s Full --project ./src/MyProject.Tests/MyProject.Tests.csproj
#   ./run-tests.sh -s Mutation --mutation-threshold 60
#   ./run-tests.sh -s Smoke --enforce-budget
# --- end usage ---
#
set -uo pipefail

STAGE=""
PROJECT=""
OUTPUT_DIR="./test-results"
MUTATION_THRESHOLD=60
ENFORCE_BUDGET=0

# Set to 1 by any step that fails. The runner keeps going after a failure so
# one broken step does not hide the rest, then reports the aggregate.
FAILED=0

usage() {
  sed -n '/^# --- usage ---$/,/^# --- end usage ---$/p' "$0" | sed -e '1d' -e '$d' -e 's/^# \{0,1\}//'
  exit 0
}

# require_value <canonical-flag> <argc> — a flag that is the last argument has
# no value. Exiting 2 keeps usage errors distinct from gate failures.
require_value() {
  if [[ "$2" -lt 2 ]]; then
    echo "ERROR: $1 requires a value." >&2
    echo "Run with --help for usage." >&2
    exit 2
  fi
}

# --- Argument parsing ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    -s|--stage) require_value "--stage" $#; STAGE="$2"; shift 2 ;;
    -p|--project) require_value "--project" $#; PROJECT="$2"; shift 2 ;;
    -o|--output-dir) require_value "--output-dir" $#; OUTPUT_DIR="$2"; shift 2 ;;
    -m|--mutation-threshold) require_value "--mutation-threshold" $#; MUTATION_THRESHOLD="$2"; shift 2 ;;
    -b|--enforce-budget) ENFORCE_BUDGET=1; shift ;;
    -h|--help) usage ;;
    *) echo "ERROR: Unknown argument: $1" >&2; echo "Run with --help for usage." >&2; exit 2 ;;
  esac
done

if ! [[ "$MUTATION_THRESHOLD" =~ ^[0-9]+$ ]] || (( MUTATION_THRESHOLD > 100 )); then
  echo "ERROR: --mutation-threshold must be an integer between 0 and 100 (got: $MUTATION_THRESHOLD)." >&2
  exit 2
fi

# Tier budgets in seconds. Kept in step with the canonical table in
# references/quality-gates.md. A budget of 0 means "this stage is not budgeted".
tier_budget() {
  if [[ -n "${QA_TIER_BUDGET:-}" ]]; then echo "$QA_TIER_BUDGET"; return; fi
  case "$1" in
    smoke) echo 30 ;;
    regression) echo 300 ;;
    full) echo 900 ;;
    *) echo 0 ;;
  esac
}

STAGE="$(printf '%s' "$STAGE" | tr '[:upper:]' '[:lower:]')"
if [[ -z "$STAGE" || ! "$STAGE" =~ ^(smoke|regression|full|coverage|mutation)$ ]]; then
  echo "ERROR: --stage is required. One of: Smoke, Regression, Full, Coverage, Mutation." >&2
  exit 1
fi

if [[ -n "$PROJECT" && ! -e "$PROJECT" ]]; then
  echo "ERROR: --project does not exist: $PROJECT" >&2
  exit 1
fi

# --- Stack detection ---
detect_stack() {
  if [[ -n "$PROJECT" ]]; then
    case "$PROJECT" in
      *.sln|*.csproj) echo "dotnet"; return ;;
      *package.json) echo "node"; return ;;
      *) echo "python"; return ;;
    esac
  fi
  if compgen -G '*.sln' >/dev/null || compgen -G '*.csproj' >/dev/null; then echo "dotnet"; return; fi
  if [[ -f package.json ]]; then echo "node"; return; fi
  if [[ -f pytest.ini || -f pyproject.toml || -f setup.py || -f setup.cfg ]]; then echo "python"; return; fi
  echo "ERROR: Could not detect the stack. Add --project <path> or create a test project first." >&2
  return 1
}

# detect_stack runs in a command substitution: an `exit` inside it would only
# terminate that subshell, leaving STACK empty and the runner exiting 0. The
# status has to be checked at the call site.
STACK="$(detect_stack)" || exit 1

# Prefer python3 (macOS/Linux); fall back to python for systems with only that name
if command -v python3 >/dev/null 2>&1; then PY=python3; else PY=python; fi

# --- Helpers ---
print_header() {
  echo ""
  echo "========================================"
  echo "  STAGE: $1"
  echo "  $2"
  echo "========================================"
  echo ""
}

ensure_dotnet_tool() {
  local tool="$1"
  local installed
  # Read the listing into a variable instead of piping it into `grep -q`. Under
  # `pipefail`, `dotnet tool list -g | grep -q` is a race: grep exits on the
  # first match and the producer then dies of SIGPIPE, so the pipeline reports
  # failure exactly when the tool *is* installed — and the script reinstalls it.
  installed="$(dotnet tool list -g 2>/dev/null || true)"
  case "$installed" in
    *"$tool"*) ;;
    *)
      echo "  Installing $tool globally..."
      dotnet tool install -g "$tool" || FAILED=1
      ;;
  esac
}

# --- Per-stack commands ---
# Every toolchain invocation is the gate for its stage: record the failure and
# keep going, so the run reports everything that is wrong at once.
run_dotnet() {
  local project_args=(--results-directory "$OUTPUT_DIR" --logger "console;verbosity=detailed")
  if [[ -n "$PROJECT" ]]; then project_args=("$PROJECT" "${project_args[@]}"); fi

  case "$STAGE" in
    smoke)
      print_header "Smoke" "Quick health check (~30s) — every commit"
      dotnet test "${project_args[@]}" --filter "Category=Smoke" || FAILED=1 ;;
    regression)
      print_header "Regression" "Full functional validation (~5min) — every PR"
      dotnet test "${project_args[@]}" --filter "Category!=Security&Category!=Performance" || FAILED=1 ;;
    coverage)
      print_header "Coverage" "Generate coverage report"
      dotnet test "${project_args[@]}" --collect:"XPlat Code Coverage" || FAILED=1
      ensure_dotnet_tool "dotnet-reportgenerator-globaltool"
      reportgenerator "-reports:$OUTPUT_DIR/**/coverage.cobertura.xml" "-targetdir:$OUTPUT_DIR/coverage-report" "-reporttypes:Html;Cobertura" || FAILED=1
      echo "  Coverage report: $OUTPUT_DIR/coverage-report/index.html" ;;
    mutation)
      print_header "Mutation" "Run mutation testing only (fails if score < $MUTATION_THRESHOLD%)"
      ensure_dotnet_tool "dotnet-stryker"
      dotnet stryker ${PROJECT:+-p "$PROJECT"} --output-path "$OUTPUT_DIR/mutation-report" --break-at "$MUTATION_THRESHOLD" || FAILED=1 ;;
    full)
      print_header "Full" "Complete QA suite (~15min) — nightly / pre-release"
      echo "  [1/2] Running all tests..."
      dotnet test "${project_args[@]}" || FAILED=1
      echo "  [2/2] Running mutation testing..."
      ensure_dotnet_tool "dotnet-stryker"
      dotnet stryker ${PROJECT:+-p "$PROJECT"} --output-path "$OUTPUT_DIR/mutation-report" --break-at "$MUTATION_THRESHOLD" || FAILED=1 ;;
  esac
}

run_node() {
  case "$STAGE" in
    smoke)
      print_header "Smoke" "Quick health check (~30s) — every commit"
      npx vitest run --testNamePattern "Smoke" || FAILED=1 ;;
    regression)
      print_header "Regression" "Full functional validation (~5min) — every PR"
      # Vitest --testNamePattern uses a RegExp: run every describe/test that is not
      # named Security or Performance. SecurityPR is the one exception — the BOLA,
      # authentication and injection subset that must run on every PR, not nightly.
      npx vitest run --testNamePattern "^(?!.*(Security(?!PR)|Performance))" || FAILED=1 ;;
    coverage)
      print_header "Coverage" "Generate coverage report"
      npx vitest run --coverage || FAILED=1 ;;
    mutation)
      print_header "Mutation" "Run mutation testing only"
      if [[ -f stryker.conf.json || -f stryker.conf.mjs ]]; then
        npx stryker run || FAILED=1
      else
        echo "  No stryker config found — run: npx stryker init" >&2
        FAILED=1
      fi ;;
    full)
      print_header "Full" "Complete QA suite (~15min) — nightly / pre-release"
      echo "  [1/2] Running all tests with coverage..."
      npx vitest run --coverage || FAILED=1
      echo "  [2/2] Running mutation testing..."
      npx stryker run || FAILED=1 ;;
  esac
}

run_python() {
  case "$STAGE" in
    smoke)
      print_header "Smoke" "Quick health check (~30s) — every commit"
      "$PY" -m pytest -m smoke || FAILED=1 ;;
    regression)
      print_header "Regression" "Full functional validation (~5min) — every PR"
      "$PY" -m pytest -m "not security and not performance" || FAILED=1 ;;
    coverage)
      print_header "Coverage" "Generate coverage report"
      "$PY" -m pytest --cov --cov-report=html --cov-report=term || FAILED=1 ;;
    mutation)
      print_header "Mutation" "Run mutation testing only"
      "$PY" -m mutmut run || FAILED=1 ;;
    full)
      print_header "Full" "Complete QA suite (~15min) — nightly / pre-release"
      echo "  [1/2] Running all tests with coverage..."
      "$PY" -m pytest --cov --cov-report=html --cov-report=term || FAILED=1
      echo "  [2/2] Running mutation testing..."
      "$PY" -m mutmut run || FAILED=1 ;;
  esac
}

# --- Main ---
if ! mkdir -p "$OUTPUT_DIR"; then
  echo "ERROR: cannot create the output directory: $OUTPUT_DIR" >&2
  exit 1
fi

echo ""
echo "QA Pipeline Test Runner"
echo "  Stage:       $STAGE"
echo "  Stack:       $STACK"
echo "  Project:     ${PROJECT:-auto-detect}"
echo "  Output:      $OUTPUT_DIR"
echo ""

STAGE_STARTED_AT="$(date +%s)"

case "$STACK" in
  dotnet) run_dotnet ;;
  node) run_node ;;
  python) run_python ;;
esac

# --- Tier budget ---
# The budget is a gate, not a table entry: a tier that quietly grows past it
# stops being the fast feedback loop it was designed to be.
BUDGET="$(tier_budget "$STAGE")"
ELAPSED=$(( $(date +%s) - STAGE_STARTED_AT ))
if (( BUDGET > 0 )); then
  echo "  Duration: ${ELAPSED}s / budget ${BUDGET}s for the $STAGE tier"
  if (( ELAPSED > BUDGET )); then
    if (( ENFORCE_BUDGET )); then
      echo "ERROR: the $STAGE tier overran its budget (${ELAPSED}s > ${BUDGET}s)." >&2
      FAILED=1
    else
      echo "  WARNING: the $STAGE tier overran its budget (${ELAPSED}s > ${BUDGET}s)." >&2
      echo "           Re-run with --enforce-budget to make this a failure." >&2
    fi
  fi
fi

exit "$FAILED"
