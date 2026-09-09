# Scripts — Quality Assurance Pipeline

This directory contains working scripts for CI/CD integration and project setup. Two equivalents are
provided for each task:

- **`.sh` (bash)** — cross-platform (macOS, Linux, Docker, GitHub Actions `bash`).
- **`.ps1` (PowerShell)** — Windows and CI runners that use `pwsh` (PowerShell Core).

Both implement the same stages and parameters.

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
```

```powershell
# PowerShell (Windows / pwsh)
.\run-tests.ps1 -Stage Smoke
.\run-tests.ps1 -Stage Full -MutationThreshold 60
```

### Parameters

**run-tests.sh**

| Flag | Values | Default | Description |
|------|--------|---------|-------------|
| `-s`, `--stage` | `Smoke` \| `Regression` \| `Full` \| `Coverage` \| `Mutation` | — | Test stage to run (case-insensitive) |
| `-p`, `--project` | path | auto-detect | Path to test project (`.csproj`, `package.json`, or test dir) |
| `-o`, `--output-dir` | path | `./test-results` | Output directory for artifacts |
| `-m`, `--mutation-threshold` | int | `60` | Minimum mutation score for the run to pass |

**run-tests.ps1**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `Stage` | `Smoke\|Regression\|Full\|Coverage\|Mutation` | — | Test stage to run |
| `Project` | string | auto-detect | Path to test `.csproj` file |
| `OutputDir` | string | `./test-results` | Output directory for artifacts |
| `MutationThreshold` | int | `60` | Minimum mutation score for the run to pass |

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
[Trait("Category", "Security")]
public void CrossTenantAccess_Returns403() { ... }

[Fact]
[Trait("Category", "Performance")]
public void GetEndpoint_P95Under2Seconds() { ... }
```

### Stage Details

| Stage | .NET filter | Node.js / Python equivalent | Duration | Includes |
|-------|-------------|------------------------------|----------|----------|
| Smoke | `Category=Smoke` | `vitest --testNamePattern Smoke` / `pytest -m smoke` | ~30s | Health, swagger, auth login |
| Regression | `Category!=Security&Category!=Performance` | `vitest --testNamePattern "^(?!.*(Security\|Performance))"` / `pytest -m "not security and not performance"` | ~5min | Unit + BDD + Integration + Property-based |
| Full | all + mutation | all + mutation | ~15min | Everything + Stryker / mutmut |
| Coverage | `--collect:"XPlat Code Coverage"` + ReportGenerator | `vitest --coverage` / `pytest --cov` | varies | Coverage report |
| Mutation | `dotnet stryker --break-at N` | `stryker run` / `mutmut run` | ~10min | Mutation testing (fails below threshold) |

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
  pytest.ini          # Markers for stratification
  features/           # BDD .feature files
  integration/        # Integration tests
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
