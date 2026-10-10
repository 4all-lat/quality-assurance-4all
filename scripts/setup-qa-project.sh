#!/usr/bin/env bash
#
# setup-qa-project.sh — Quick-start QA project scaffolder.
#
# Cross-platform (macOS / Linux / CI) equivalent of setup-qa-project.ps1.
# Creates a test project with the recommended folder structure and installs
# the QA packages for the requested stack.
#
# --- usage ---
# Usage: setup-qa-project.sh --name <name> --stack <stack> [options]
#
# Options:
#   -n, --name <name>        project name (required)
#   -s, --stack <stack>      dotnet | nodejs | python (required)
#   -o, --output-dir <dir>   parent directory (default: .)
#   -h, --help               show this message
#
# Exit codes:
#   0  the project was scaffolded
#   1  gate or environment failure (bad stack, target directory already exists)
#   2  usage error (unknown flag, flag without a value, missing required flag)
#
# Examples:
#   ./setup-qa-project.sh --name MyProject.Tests --stack dotnet
#   ./setup-qa-project.sh -n my-project-tests -s nodejs
#   ./setup-qa-project.sh -n my_project_tests -s python
# --- end usage ---
#
set -euo pipefail

NAME=""
STACK=""
OUTPUT_DIR="."

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

while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--name) require_value "--name" $#; NAME="$2"; shift 2 ;;
    -s|--stack) require_value "--stack" $#; STACK="$2"; shift 2 ;;
    -o|--output-dir) require_value "--output-dir" $#; OUTPUT_DIR="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "ERROR: Unknown argument: $1" >&2; echo "Run with --help for usage." >&2; exit 2 ;;
  esac
done

if [[ -z "$NAME" || -z "$STACK" ]]; then
  echo "ERROR: --name and --stack are required." >&2
  echo "Run with --help for usage." >&2
  exit 1
fi
case "$STACK" in
  dotnet|nodejs|python) ;;
  *) echo "ERROR: --stack must be one of: dotnet, nodejs, python." >&2; exit 1 ;;
esac

PROJECT_PATH="$OUTPUT_DIR/$NAME"
if [[ -e "$PROJECT_PATH" ]]; then
  echo "ERROR: Directory already exists: $PROJECT_PATH" >&2
  exit 1
fi

mkdir -p "$PROJECT_PATH"
# Resolve to an absolute path before entering it: every step below writes
# relative to the project, and a relative --output-dir would otherwise be
# re-interpreted from inside the project and nest one level deeper.
PROJECT_PATH="$(cd "$PROJECT_PATH" && pwd)"
cd "$PROJECT_PATH"

echo ""
echo "QA Project Setup"
echo "  Project: $NAME"
echo "  Stack:   $STACK"
echo ""

if [[ "$STACK" == "dotnet" ]]; then
  echo "[1/4] Creating xUnit test project..."
  dotnet new xunit -n "$NAME" -o "$PROJECT_PATH"

  echo "[2/4] Installing QA packages..."
  for pkg in \
    FluentAssertions \
    Moq \
    coverlet.collector \
    Microsoft.AspNetCore.Mvc.Testing \
    FsCheck \
    FsCheck.Xunit \
    Reqnroll.xUnit \
    Microsoft.Playwright; do
    echo "  - $pkg"
    dotnet add package "$pkg"
  done

  echo "[3/4] Installing global tools..."
  # Read the listing into a variable instead of piping it into `grep -q`. Under
  # `pipefail`, `dotnet tool list -g | grep -q` is a race: grep exits on the
  # first match and the producer then dies of SIGPIPE, so the pipeline reports
  # failure exactly when the tool *is* installed — and the script reinstalls it.
  installed_tools="$(dotnet tool list -g 2>/dev/null || true)"
  for tool in dotnet-stryker dotnet-reportgenerator-globaltool; do
    case "$installed_tools" in
      *"$tool"*)
        echo "  - $tool (already installed)"
        ;;
      *)
        echo "  - $tool"
        dotnet tool install -g "$tool"
        ;;
    esac
  done

  echo "[4/4] Creating folder structure..."
  for folder in Features Integration Concurrency Security Performance PropertyBased Controllers Services Repositories; do
    mkdir -p "$folder"
    echo "  - $folder/"
  done

  echo ""
  echo "Done! .NET QA project created at: $PROJECT_PATH"
  echo "Next steps:"
  echo "  1. Add coverage config to .csproj (see assets/coverage-config.xml)"
  echo "  2. Add project reference: dotnet add reference ../src/$NAME.csproj"
  echo "  3. Run smoke tests: dotnet test --filter Category=Smoke"

elif [[ "$STACK" == "nodejs" ]]; then
  echo "[1/4] Creating Node.js project..."
  npm init -y
  npm pkg set type=module

  echo "[2/4] Installing QA packages..."
  npm install -D vitest @vitest/coverage-v8 @playwright/test fast-check @cucumber/cucumber @stryker-mutator/core

  echo "[3/4] Creating vitest.config.ts..."
  cat > vitest.config.ts <<'EOF'
import { defineConfig } from 'vitest/config'

export default defineConfig({
  test: {
    coverage: {
      provider: 'v8',
      reporter: ['text', 'html', 'cobertura'],
      thresholds: {
        lines: 80,
        functions: 80,
        branches: 80,
        statements: 80,
      },
      exclude: ['node_modules/', 'dist/', '**/*.config.*'],
    },
  },
})
EOF

  echo "[4/4] Creating folder structure..."
  for folder in features integration concurrency security performance property-based unit; do
    mkdir -p "$folder"
    echo "  - $folder/"
  done

  echo ""
  echo "Done! Node.js/TS QA project created at: $PROJECT_PATH"
  echo "Next steps:"
  echo "  1. Add test scripts to package.json"
  echo "  2. Run smoke: npx vitest run --testNamePattern Smoke"

else # python
  echo "[1/4] Creating Python project..."
  cat > requirements.txt <<'EOF'
# QA Pipeline — Python dependencies
pytest>=8.0
pytest-cov>=4.0
hypothesis>=6.0
behave>=1.2
mutmut>=2.0
locust>=2.0
EOF

  echo "[2/4] Installing QA packages..."
  # Prefer python3 (macOS/Linux); fall back to python
  if command -v python3 >/dev/null 2>&1; then PY=python3; else PY=python; fi
  "$PY" -m pip install -r requirements.txt

  echo "[3/4] Creating .coveragerc..."
  cat > .coveragerc <<'EOF'
[run]
source = ./src
omit =
    */migrations/*
    */tests/*
    */config/*

[report]
fail_under = 80
show_missing = True

[html]
directory = coverage_html_report
EOF

  cat > pytest.ini <<'EOF'
[pytest]
markers =
    smoke: quick health check tests (run on every commit)
    regression: functional tests (run on every PR)
    concurrency: races, retries and double-submit tests (run on every PR)
    security: security tests (OWASP API Top 10)
    securitypr: BOLA/auth/injection subset that runs on every PR
    performance: performance/load tests
    property: property-based tests
EOF

  echo "[4/4] Creating folder structure..."
  for folder in features integration concurrency security performance property_based unit; do
    mkdir -p "$folder"
    touch "$folder/__init__.py"
    echo "  - $folder/"
  done

  echo ""
  echo "Done! Python QA project created at: $PROJECT_PATH"
  echo "Next steps:"
  echo "  1. Run smoke: pytest -m smoke"
  echo "  2. Run with coverage: pytest --cov"
fi

echo ""
echo "Recommended folder structure:"
echo "  $NAME/"
echo "    Features/          # BDD .feature files (Gherkin)"
echo "    Integration/       # In-memory + live integration tests"
echo "    Concurrency/       # Races, retries, idempotency (Regression tier)"
echo "    Security/          # OWASP security tests"
echo "    Performance/       # Load and latency tests"
echo "    PropertyBased/     # Property-based / generative tests"
echo "    Controllers/       # Unit tests for controllers (or Unit/ for Node.js/Python)"
echo "    Services/          # Unit tests for services"
echo "    Repositories/      # Unit tests for repositories"
echo ""
