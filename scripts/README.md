# Scripts — Quality Assurance Pipeline

This directory contains working scripts for CI/CD integration and project setup. Two equivalents are
provided for each task:

- **`.sh` (bash)** — cross-platform (macOS, Linux, Docker, GitHub Actions `bash`).
- **`.ps1` (PowerShell)** — Windows and CI runners that use `pwsh` (PowerShell Core).

Both implement the same stages and parameters, with two deliberate exceptions:

- **`run-tests.ps1` is .NET-only.** It has no stack detection and runs `dotnet test` for every stage;
  the Node.js and Python commands exist only in the bash runner. Extending it is out of scope — the
  bash runner covers those stacks on every platform that matters for them.
- **`run-tests.ps1` has no `-Help` switch.** PowerShell scripts get `-?` and comment-based help for
  free from the help block at the top of the file.

`tests/cases/parity.test.sh` enforces the rest: stages, flags, the stack enum and the default
mutation threshold are extracted from both implementations and compared, with
`tests/parity-allowlist.txt` holding the exceptions above.

### Exit codes

Both scripts use the same contract, so a CI step can tell a broken pipeline from a mistyped command:

| Code | Meaning | Examples |
|------|---------|----------|
| `0` | The requested work completed | smoke tests passed |
| `1` | Gate or environment failure | unknown stage, no stack detected, tests failed, target directory exists |
| `2` | Usage error (bash runners) | unknown flag, flag without a value, mutation threshold out of range |

The bash runners exit `2` for usage errors; the PowerShell scripts report those through PowerShell's
own parameter binding.

| Script | Purpose |
|--------|---------|
| `setup-qa-project.sh` / `setup-qa-project.ps1` | Scaffold a test project (folder structure + QA packages) for .NET, Node.js, or Python |
| `run-tests.sh` / `run-tests.ps1` | Stratified test runner (Smoke / Regression / Full / Coverage / Mutation) |

---

## run-tests.sh / run-tests.ps1

Stratified test runner. `run-tests.ps1` targets .NET projects with `[Trait("Category", "...")]`
categorization; `run-tests.sh` **auto-detects the stack** for .NET (`.sln`/`.csproj`), Node.js
(`package.json`), or Python (`pytest.ini`/`pyproject.toml`) and runs the matching command.

### Usage

```bash
# bash (macOS / Linux / CI)
./run-tests.sh --stage Smoke
./run-tests.sh -s Regression
./run-tests.sh -s Full --mutation-threshold 60
./run-tests.sh -s Coverage --project ./src/MyProject.Tests/MyProject.Tests.csproj
./run-tests.sh -s Regression --enforce-budget   # CI: overrunning 5min fails the build
```

```powershell
# PowerShell (Windows / pwsh)
.\run-tests.ps1 -Stage Smoke
.\run-tests.ps1 -Stage Full -MutationThreshold 60
.\run-tests.ps1 -Stage Regression -EnforceBudget
```

### Parameters

**run-tests.sh**

| Flag | Values | Default | Description |
|------|--------|---------|-------------|
| `-s`, `--stage` | `Smoke` \| `Regression` \| `Full` \| `Coverage` \| `Mutation` | — | Test stage to run (case-insensitive) |
| `-p`, `--project` | path | auto-detect | Path to test project (`.csproj`, `package.json`, or test dir) |
| `-o`, `--output-dir` | path | `./test-results` | Output directory for artifacts |
| `-m`, `--mutation-threshold` | int | `60` | Minimum mutation score for the run to pass |
| `-b`, `--enforce-budget` | flag | off | Fail the stage when it overruns its tier budget (see below) |

**run-tests.ps1**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `Stage` | `Smoke\|Regression\|Full\|Coverage\|Mutation` | — | Test stage to run |
| `Project` | string | auto-detect | Path to test `.csproj` file |
| `OutputDir` | string | `./test-results` | Output directory for artifacts |
| `MutationThreshold` | int | `60` | Minimum mutation score for the run to pass |
| `EnforceBudget` | switch | off | Fail the stage when it overruns its tier budget (see below) |

### Test Categorization

Tests must be categorized for the runner to filter them:

```csharp
[Fact]
[Trait("Category", "Smoke")]
public void HealthCheck_ReturnsOk() { ... }

[Fact]
[Trait("Category", "Regression")]
public void GetAllItems_ReturnsPaginatedResults() { ... }

[Fact]
[Trait("Category", "Concurrency")]
public async Task DoubleSubmit_CreatesExactlyOne() { ... }

// The PR subset of the security suite: BOLA, auth lifecycle, injection.
[Fact]
[Trait("Category", "SecurityPR")]
public async Task CrossTenantAccess_Returns403() { ... }

[Fact]
[Trait("Category", "Security")]
public async Task RateLimitExceeded_Returns429() { ... }

[Fact]
[Trait("Category", "Performance")]
public void GetEndpoint_P95WithinBudget() { ... }
```

### Stage Details

| Stage | .NET filter | Node.js / Python equivalent | Duration | Includes |
|-------|-------------|------------------------------|----------|----------|
| Smoke | `Category=Smoke` | `vitest --testNamePattern Smoke` / `pytest -m smoke` | ~30s | Health, swagger, auth login |
| Regression | `Category!=Security&Category!=Performance` | `vitest --testNamePattern "^(?!.*(Security(?!PR)\|Performance))"` / `pytest -m "not security and not performance"` | ~5min | Unit + BDD + Integration + Concurrency + the `SecurityPR` subset |
| Full | all + mutation | all + mutation | ~15min | Everything + the static scans + Stryker / mutmut |
| Coverage | `--collect:"XPlat Code Coverage"` + ReportGenerator | `vitest --coverage` / `pytest --cov` | varies | Coverage report |
| Mutation | `dotnet stryker --break-at N` | `stryker run` / `mutmut run` | ~10min | Mutation testing (fails below threshold) |

`Category=SecurityPR` is a distinct category from `Security`, so the .NET filter above
(`Category!=Security`) and pytest's `-m "not security ..."` already include it without changes. The
Node.js pattern needs the negative lookahead `Security(?!PR)` to keep `SecurityPR` in and drop
`Security`. See [`../references/test-pyramid.md`](../references/test-pyramid.md) for the criterion
that decides which security tests belong in the PR tier.

### Tier budgets

Each stage is timed and compared against its tier budget — Smoke `30s`, Regression `300s`, Full
`900s`; `Coverage` and `Mutation` are unbudgeted. By default an overrun is a warning, because a slow
laptop is not a regression:

```
  Duration: 412s / budget 300s for the Regression tier
  WARNING: the Regression tier overran its budget (412s > 300s).
           Re-run with --enforce-budget to make this a failure.
```

Pass `--enforce-budget` (bash) or `-EnforceBudget` (PowerShell) in CI to turn that warning into exit
code `1`. The budget can be overridden per run with the `QA_TIER_BUDGET` environment variable, which
is what `tests/cases/run-tests.budget.test.sh` uses to exercise the gate:
`QA_TIER_BUDGET=1 ./run-tests.sh -s Regression --enforce-budget`.

Move cases out of a tier that outgrows its budget rather than raising the number in the script; the
tier is sized for the feedback loop it exists to provide.

### Mutation threshold

`Full` and `Mutation` stages pass a `--break-at` (Stryker) value so the pipeline **fails** when the
mutation score drops below `MutationThreshold` (default `60`). Node and Python mutation runs use the
project's own configuration.

### Output

- Test results (TRX / terminal) in `$OutputDir` (`./test-results`)
- Coverage report (HTML/Cobertura) in `$OutputDir/coverage-report/`
- Mutation report in `$OutputDir/mutation-report/`

### CI Integration

#### GitHub Actions

```yaml
- name: Run Smoke Tests
  run: ./scripts/run-tests.sh -s Smoke
  shell: bash

- name: Run Regression Tests
  run: ./scripts/run-tests.sh -s Regression
  shell: bash

- name: Run Full Suite (nightly)
  run: ./scripts/run-tests.sh -s Full
  shell: bash
```

#### Azure DevOps (PowerShell runner)

```yaml
- task: PowerShell@2
  displayName: 'Run Smoke Tests'
  inputs:
    filePath: '$(Build.SourcesDirectory)\scripts\run-tests.ps1'
    arguments: '-Stage Smoke'
```

---

## setup-qa-project.sh / setup-qa-project.ps1

Quick-start scaffolder that creates a test project with the recommended folder structure and installs
all necessary QA packages.

### Prerequisites

- .NET 8.0 SDK (for `dotnet` stack)
- Node.js 20+ and npm (for `nodejs` stack)
- Python 3.8+ and pip (for `python` stack)

### Usage

```bash
./setup-qa-project.sh --name MyProject.Tests --stack dotnet
./setup-qa-project.sh -n my-project-tests -s nodejs
./setup-qa-project.sh -n my_project_tests -s python
```

```powershell
.\setup-qa-project.ps1 -ProjectName "MyProject.Tests" -Stack dotnet
.\setup-qa-project.ps1 -ProjectName "my-project-tests" -Stack nodejs
.\setup-qa-project.ps1 -ProjectName "my_project_tests" -Stack python
```

### What It Creates

#### .NET (xUnit — single test framework)

```
MyProject.Tests/
  MyProject.Tests.csproj
  Features/           # BDD .feature files (Reqnroll.xUnit)
  Integration/        # In-memory + live integration tests
  Concurrency/        # Races, retries, idempotency
  Security/           # OWASP security tests
  Performance/        # Load and latency tests
  PropertyBased/      # FsCheck property tests
  Controllers/        # Unit tests for controllers
  Services/           # Unit tests for services
  Repositories/       # Unit tests for repositories
```

Packages installed: xUnit, FluentAssertions, Moq, Coverlet, WebApplicationFactory, FsCheck,
**Reqnroll.xUnit**, Microsoft.Playwright. Global tools: Stryker.NET, ReportGenerator.

> The project uses **xUnit only** — Reqnroll is wired with `Reqnroll.xUnit` (never `Reqnroll.NUnit` in
> an xUnit project) and Playwright via the core library, so no second test framework is mixed in.

#### Node.js/TypeScript

```
my-project-tests/
  package.json
  vitest.config.ts    # With coverage thresholds (80%)
  features/           # BDD .feature files
  integration/        # Integration tests
  concurrency/        # Races, retries, idempotency
  security/           # Security tests
  performance/        # Performance tests
  property-based/     # fast-check tests
  unit/               # Unit tests
```

Packages installed: Vitest, @vitest/coverage-v8, Playwright, fast-check, Cucumber.js, Stryker.js.

#### Python

```
my_project_tests/
  requirements.txt    # pytest, hypothesis, behave, mutmut, locust
  .coveragerc         # Coverage config (80% threshold)
  pytest.ini          # Markers for stratification (smoke, regression, concurrency, security, securitypr, performance, property)
  features/           # BDD .feature files
  integration/        # Integration tests
  concurrency/        # Races, retries, idempotency
  security/           # Security tests
  performance/        # Performance tests
  property_based/     # Hypothesis tests
  unit/               # Unit tests
```

Packages installed: pytest, pytest-cov, Hypothesis, Behave, mutmut, locust.

### Post-Setup Steps

1. Add a reference to your source project (for .NET: `dotnet add reference ../src/MyProject.csproj`)
2. Copy the BDD template from `assets/bdd-feature-template.feature` to your `Features/` folder
3. Copy the AI Spec template from `assets/ai-spec-template.md` to your project root
4. Add coverage configuration (for .NET: see `assets/coverage-config.xml`)
5. Run your first smoke test:
   - .NET: `dotnet test --filter "Category=Smoke"`
   - Node.js: `npx vitest run --testNamePattern Smoke`
   - Python: `pytest -m smoke`
