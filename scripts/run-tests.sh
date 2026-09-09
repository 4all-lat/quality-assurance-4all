#!/usr/bin/env bash
#
# run-tests.sh — Stratified test runner for the QA pipeline.
#
# Cross-platform (macOS / Linux / CI) equivalent of run-tests.ps1.
# Auto-detects the stack (.NET, Node.js/TS, Python) and runs the matching command
# for the requested stage.
#
# Stages:
#   smoke      ~30s, every commit — health, swagger, auth login
#   regression ~5min, every PR — all functional tests
#   full       ~15min, nightly/pre-release — everything + mutation
#   coverage   generate coverage report
#   mutation   run mutation testing only (fails if score < threshold)
#
# Usage:
#   ./run-tests.sh --stage Smoke
#   ./run-tests.sh -s Full --project ./src/MyProject.Tests/MyProject.Tests.csproj
#   ./run-tests.sh -s Mutation --mutation-threshold 60
#
set -euo pipefail

STAGE=""
PROJECT=""
OUTPUT_DIR="./test-results"
MUTATION_THRESHOLD=60

usage() {
  sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
}

# --- Argument parsing ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    -s|--stage) STAGE="${2:-}"; shift 2 ;;
    -p|--project) PROJECT="${2:-}"; shift 2 ;;
    -o|--output-dir) OUTPUT_DIR="${2:-}"; shift 2 ;;
    -m|--mutation-threshold) MUTATION_THRESHOLD="${2:-}"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "ERROR: Unknown argument: $1" >&2; usage ;;
  esac
done

STAGE="$(printf '%s' "$STAGE" | tr '[:upper:]' '[:lower:]')"
if [[ -z "$STAGE" || ! "$STAGE" =~ ^(smoke|regression|full|coverage|mutation)$ ]]; then
  echo "ERROR: --stage is required. One of: Smoke, Regression, Full, Coverage, Mutation." >&2
  exit 1
fi

# --- Stack detection ---
detect_stack() {
  if [[ -n "$PROJECT" && -f "$PROJECT" ]]; then
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
  exit 1
}

STACK="$(detect_stack)"

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

print_result() {
  local name="$1" success="$2"
  echo ""
  if [[ "$success" -eq 0 ]]; then
    echo "  [PASS] $name"
  else
    echo "  [FAIL] $name"
  fi
  echo ""
}

ensure_dotnet_tool() {
  local tool="$1"
  if ! dotnet tool list -g 2>/dev/null | grep -q "$tool"; then
    echo "  Installing $tool globally..."
    dotnet tool install -g "$tool"
  fi
}

ensure_npx() {
  # Install a missing tool locally without prompting
  npx --yes --no-install "$@" 2>/dev/null || { echo "  Installing $1..."; npx --yes "$@"; }
}

# --- Per-stack commands ---
run_dotnet() {
  local project_args=(--results-directory "$OUTPUT_DIR" --logger "console;verbosity=detailed")
  if [[ -n "$PROJECT" ]]; then project_args=("$PROJECT" "${project_args[@]}"); fi

  case "$STAGE" in
    smoke)
      print_header "Smoke" "Quick health check (~30s) — every commit"
      dotnet test "${project_args[@]}" --filter "Category=Smoke" ;;
    regression)
      print_header "Regression" "Full functional validation (~5min) — every PR"
      dotnet test "${project_args[@]}" --filter "Category!=Security&Category!=Performance" ;;
    coverage)
      print_header "Coverage" "Generate coverage report"
      dotnet test "${project_args[@]}" --collect:"XPlat Code Coverage"
      ensure_dotnet_tool "dotnet-reportgenerator-globaltool"
      reportgenerator "-reports:$OUTPUT_DIR/**/coverage.cobertura.xml" "-targetdir:$OUTPUT_DIR/coverage-report" "-reporttypes:Html;Cobertura"
      echo "  Coverage report: $OUTPUT_DIR/coverage-report/index.html" ;;
    mutation)
      print_header "Mutation" "Run mutation testing only (fails if score < $MUTATION_THRESHOLD%)"
      ensure_dotnet_tool "dotnet-stryker"
      dotnet stryker ${PROJECT:+-p "$PROJECT"} --output-path "$OUTPUT_DIR/mutation-report" --break-at "$MUTATION_THRESHOLD" ;;
    full)
      print_header "Full" "Complete QA suite (~15min) — nightly / pre-release"
      echo "  [1/2] Running all tests..."
      dotnet test "${project_args[@]}"
      echo "  [2/2] Running mutation testing..."
      ensure_dotnet_tool "dotnet-stryker"
      dotnet stryker ${PROJECT:+-p "$PROJECT"} --output-path "$OUTPUT_DIR/mutation-report" --break-at "$MUTATION_THRESHOLD" ;;
  esac
}

run_node() {
  case "$STAGE" in
    smoke)
      print_header "Smoke" "Quick health check (~30s) — every commit"
      npx vitest run --testNamePattern "Smoke" ;;
    regression)
      print_header "Regression" "Full functional validation (~5min) — every PR"
      # Vitest --testNamePattern uses a RegExp: run every describe/test not named Security or Performance
      npx vitest run --testNamePattern "^(?!.*(Security|Performance))" ;;
    coverage)
      print_header "Coverage" "Generate coverage report"
      npx vitest run --coverage ;;
    mutation)
      print_header "Mutation" "Run mutation testing only"
      if [[ -f stryker.conf.json || -f stryker.conf.mjs ]]; then
        npx stryker run
      else
        echo "  No stryker config found — run: npx stryker init" >&2; exit 1
      fi ;;
    full)
      print_header "Full" "Complete QA suite (~15min) — nightly / pre-release"
      echo "  [1/2] Running all tests with coverage..."
      npx vitest run --coverage
      echo "  [2/2] Running mutation testing..."
      npx stryker run ;;
  esac
}

run_python() {
  case "$STAGE" in
    smoke)
      print_header "Smoke" "Quick health check (~30s) — every commit"
      "$PY" -m pytest -m smoke ;;
    regression)
      print_header "Regression" "Full functional validation (~5min) — every PR"
      "$PY" -m pytest -m "not security and not performance" ;;
    coverage)
      print_header "Coverage" "Generate coverage report"
      "$PY" -m pytest --cov --cov-report=html --cov-report=term ;;
    mutation)
      print_header "Mutation" "Run mutation testing only"
      "$PY" -m mutmut run ;;
    full)
      print_header "Full" "Complete QA suite (~15min) — nightly / pre-release"
      echo "  [1/2] Running all tests with coverage..."
      "$PY" -m pytest --cov --cov-report=html --cov-report=term
      echo "  [2/2] Running mutation testing..."
      "$PY" -m mutmut run ;;
  esac
}

# --- Main ---
mkdir -p "$OUTPUT_DIR"

echo ""
echo "QA Pipeline Test Runner"
echo "  Stage:       $STAGE"
echo "  Stack:       $STACK"
echo "  Project:     ${PROJECT:-auto-detect}"
echo "  Output:      $OUTPUT_DIR"
echo ""

case "$STACK" in
  dotnet) run_dotnet ;;
  node) run_node ;;
  python) run_python ;;
esac
