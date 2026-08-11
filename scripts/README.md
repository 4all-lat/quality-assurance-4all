# Scripts — Quality Assurance Pipeline

This directory contains working scripts for CI/CD integration and project setup.

## run-tests.ps1

Stratified test runner for .NET projects using xUnit with `[Trait("Category", "...")]` categorization.

### Prerequisites

- .NET 8.0 SDK (or later)
- xUnit test project with categorized tests
- For Mutation stage: Stryker.NET (`dotnet tool install -g dotnet-stryker`)
- For Coverage stage: ReportGenerator (`dotnet tool install -g dotnet-reportgenerator-globaltool`)

### Usage

```powershell
# Smoke tier — ~30s, every commit
.\run-tests.ps1 -Stage Smoke

# Regression tier — ~5min, every PR
.\run-tests.ps1 -Stage Regression

# Full tier — ~15min, nightly / pre-release
.\run-tests.ps1 -Stage Full

# Coverage report only
.\run-tests.ps1 -Stage Coverage

# Mutation testing only
.\run-tests.ps1 -Stage Mutation
```

### Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `Stage` | `Smoke\|Regression\|Full\|Coverage\|Mutation` | Yes | — | Test stage to run |
| `Project` | string | No | Auto-detect | Path to test `.csproj` file |
| `OutputDir` | string | No | `./test-results` | Directory for output artifacts |

### Test Categorization

Tests must be categorized with xUnit Traits for the runner to filter them:

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

| Stage | Filter | Duration | Includes |
|-------|--------|----------|----------|
| Smoke | `Category=Smoke` | ~30s | Health, swagger, auth login |
| Regression | `Category!=Security&Category!=Performance` | ~5min | Unit + BDD + Integration + Property-based |
| Full | (all) + mutation | ~15min | Everything + Stryker.NET mutation testing |
| Coverage | (all) + coverage | varies | All tests with Cobertura + HTML report |
| Mutation | Stryker.NET | ~10min | Mutation testing only |

### Output

- Test results (TRX files) in `$OutputDir`
- Coverage report (HTML) in `$OutputDir/coverage-report/`
- Mutation report in `$OutputDir/mutation-report/`

### CI Integration

#### GitHub Actions

```yaml
- name: Run Smoke Tests
  run: .\scripts\run-tests.ps1 -Stage Smoke
  shell: pwsh

- name: Run Regression Tests
  run: .\scripts\run-tests.ps1 -Stage Regression
  shell: pwsh

- name: Run Full Suite (nightly)
  run: .\scripts\run-tests.ps1 -Stage Full
  shell: pwsh
```

#### Azure DevOps

```yaml
- task: PowerShell@2
  displayName: 'Run Smoke Tests'
  inputs:
    filePath: '$(Build.SourcesDirectory)\scripts\run-tests.ps1'
    arguments: '-Stage Smoke'
```

---

## setup-qa-project.ps1

Quick-start scaffolder that creates a test project with the recommended folder structure and installs all necessary QA packages.

### Prerequisites

- .NET 8.0 SDK (for `dotnet` stack)
- Node.js 20+ and npm (for `nodejs` stack)
- Python 3.8+ and pip (for `python` stack)

### Usage

```powershell
# .NET project
.\setup-qa-project.ps1 -ProjectName "MyProject.Tests" -Stack dotnet

# Node.js/TypeScript project
.\setup-qa-project.ps1 -ProjectName "my-project-tests" -Stack nodejs

# Python project
.\setup-qa-project.ps1 -ProjectName "my_project_tests" -Stack python
```

### Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `ProjectName` | string | Yes | — | Name of the test project |
| `Stack` | `dotnet\|nodejs\|python` | Yes | — | Technology stack |
| `OutputDir` | string | No | `.` | Directory where project is created |

### What It Creates

#### .NET

```
MyProject.Tests/
  MyProject.Tests.csproj
  Features/           # BDD .feature files
  Integration/        # In-memory + live integration tests
  Security/           # OWASP security tests
  Performance/        # Load and latency tests
  PropertyBased/      # FsCheck property tests
  Controllers/        # Unit tests for controllers
  Services/           # Unit tests for services
  Repositories/       # Unit tests for repositories
```

Packages installed: xUnit, FluentAssertions, Moq, Coverlet, WebApplicationFactory, FsCheck, Reqnroll, Playwright.
Global tools: Stryker.NET, ReportGenerator.

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

Packages installed: Vitest, Playwright, fast-check, Cucumber.js, c8, Stryker.js.

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
   - Node.js: `npx vitest --grep Smoke`
   - Python: `pytest -m smoke`
