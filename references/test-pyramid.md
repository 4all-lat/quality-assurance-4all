# Test Pyramid and Stratification Deep Dive

## The Test Pyramid

The test pyramid is a foundational concept in test strategy. It describes the ratio of test types you should aim for to balance speed, reliability, and coverage.

```
        /\
       /  \        E2E (10%)
      /----\
     /      \      Integration (20%)
    /--------\
   /          \    Unit (70%)
  /____________\
```

### Why the Pyramid Shape?

- **Unit tests (70%)** are fast, reliable, and pinpoint failures. They should form the base.
- **Integration tests (20%)** verify components work together but are slower and more fragile.
- **E2E tests (10%)** verify the entire system end-to-end but are the slowest and most brittle.

### The Inverted Pyramid Anti-Pattern

```
  /____________\
   \          /    Too many E2E tests
    \--------/
     \      /      Few integration tests
      \----/
       \  /        Almost no unit tests
        \/
```

This is the most common anti-pattern. Teams rely on manual testing or E2E automated tests, resulting in:
- Slow test suites (hours to run)
- Flaky tests (false positives/negatives)
- Poor fault isolation (when a test fails, you don't know which component broke)
- High maintenance cost

### The Hourglass Anti-Pattern

```
        /\
       /  \
      /----\
     /      \
    /        \      Lots of E2E
   /----------\
  /            \
 /______________\  Lots of unit tests
```

Lots of unit tests and lots of E2E tests, but few integration tests. This misses the "middle layer" that verifies components work together without the full overhead of E2E.

---

## Regression Suite Stratification

Beyond the test pyramid (which describes test *types*), stratification describes *when* and *how often* tests run.

### Three Tiers

| Tier | Category | Duration | When to run | What's included |
|------|----------|----------|-------------|-----------------|
| Smoke | `Smoke` | ~30s | Every commit | Health, swagger, auth login |
| Regression | `Regression` | ~5min | Every PR | All functional tests (unit + BDD + integration) |
| Full | `Full` | ~15min | Nightly / pre-release | + security + performance + mutation |

### Smoke Tier

**Purpose:** Verify the system is alive and the most critical paths work.

**What to include:**
- Health endpoint returns 200
- Swagger / OpenAPI spec is accessible
- Authentication login works (valid credentials -> token)
- One happy-path API call per critical endpoint

**Speed target:** < 30 seconds total

**Example (.NET):**
```csharp
[Fact]
[Trait("Category", "Smoke")]
public async Task Health_ReturnsOk() { ... }

[Fact]
[Trait("Category", "Smoke")]
public async Task Swagger_IsAccessible() { ... }

[Fact]
[Trait("Category", "Smoke")]
public async Task Login_ValidCredentials_ReturnsToken() { ... }
```

### Regression Tier

**Purpose:** Verify all functional behavior works as expected before merging.

**What to include:**
- All unit tests
- All BDD scenarios
- All integration tests (in-memory + live)
- All property-based tests

**Speed target:** < 5 minutes total

**Example (.NET):**
```csharp
// All tests with Category=Unit, Category=BDD, Category=Integration, Category=PropertyBased
// Run with: dotnet test --filter "Category!=Security&Category!=Performance"
```

### Full Tier

**Purpose:** Comprehensive quality validation before release.

**What to include:**
- Everything from Regression tier
- Security tests (OWASP API Top 10)
- Performance tests (load, latency percentiles)
- Mutation testing

**Speed target:** < 15 minutes total

**Example (.NET):**
```csharp
// All tests + mutation testing
// Run with: dotnet test && dotnet stryker
```

---

## CI Pipeline Integration

### GitHub Actions Example

```yaml
name: QA Pipeline

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

jobs:
  smoke:
    name: Smoke Tests
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Setup .NET
        uses: actions/setup-dotnet@v4
        with:
          dotnet-version: '8.0'
      - name: Run Smoke Tests
        run: dotnet test --filter "Category=Smoke" --logger "console;verbosity=detailed"

  regression:
    name: Regression Tests
    needs: smoke
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Setup .NET
        uses: actions/setup-dotnet@v4
        with:
          dotnet-version: '8.0'
      - name: Run Regression Tests
        run: dotnet test --filter "Category!=Security&Category!=Performance" --collect:"XPlat Code Coverage"
      - name: Coverage Report
        run: |
          dotnet tool install -g dotnet-reportgenerator-globaltool
          reportgenerator -reports:**/coverage.cobertura.xml -targetdir:coverage-report -reporttypes:Html
      - name: Upload Coverage
        uses: actions/upload-artifact@v4
        with:
          name: coverage-report
          path: coverage-report/

  full:
    name: Full QA Suite
    needs: regression
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Setup .NET
        uses: actions/setup-dotnet@v4
        with:
          dotnet-version: '8.0'
      - name: Run All Tests
        run: dotnet test
      - name: Run Mutation Testing
        run: |
          dotnet tool install -g dotnet-stryker
          dotnet stryker
      - name: Upload Mutation Report
        uses: actions/upload-artifact@v4
        with:
          name: mutation-report
          path: StrykerOutput/
```

### Azure DevOps Example

```yaml
trigger:
  branches:
    include:
      - main
      - develop

pr:
  branches:
    include:
      - main

stages:
  - stage: Smoke
    jobs:
      - job: SmokeTests
        steps:
          - task: DotNetCoreCLI@2
            displayName: 'Run Smoke Tests'
            inputs:
              command: 'test'
              arguments: '--filter "Category=Smoke"'

  - stage: Regression
    dependsOn: Smoke
    condition: succeeded()
    jobs:
      - job: RegressionTests
        steps:
          - task: DotNetCoreCLI@2
            displayName: 'Run Regression Tests'
            inputs:
              command: 'test'
              arguments: '--filter "Category!=Security&Category!=Performance" --collect:"XPlat Code Coverage"'

  - stage: Full
    dependsOn: Regression
    condition: and(succeeded(), eq(variables['Build.SourceBranch'], 'refs/heads/main'))
    jobs:
      - job: FullSuite
        steps:
          - task: DotNetCoreCLI@2
            displayName: 'Run All Tests'
            inputs:
              command: 'test'
          - script: 'dotnet stryker'
            displayName: 'Run Mutation Testing'
```

---

## Test Categorization by Stack

### .NET (xUnit Traits)

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

**Filtering:**
```bash
dotnet test --filter "Category=Smoke"
dotnet test --filter "Category!=Security&Category!=Performance"
dotnet test  # all tests
```

### Node.js / TypeScript (Vitest)

```typescript
// Use describe blocks for categorization
describe('Smoke', () => {
  it('health check returns 200', async () => { ... })
})

describe('Regression', () => {
  it('returns paginated results', async () => { ... })
})

// Run with: vitest --grep Smoke
```

### Python (pytest markers)

```python
import pytest

@pytest.mark.smoke
def test_health_check():
    ...

@pytest.mark.regression
def test_get_all_items():
    ...

# Run with: pytest -m smoke
# Run with: pytest -m "not security and not performance"
```

---

## Common Pitfalls

| Pitfall | Why it's bad | What to do instead |
|---------|-------------|-------------------|
| All tests in one suite | Slow feedback loop | Stratify: Smoke -> Regression -> Full |
| Smoke tests too slow | Developers skip running them | Keep smoke < 30s, only critical paths |
| No categorization | Can't run subsets efficiently | Use traits/markers/tags from day one |
| E2E tests in Smoke | E2E is slow and flaky | Smoke = unit-level health checks only |
| Security tests in Regression | Slows down PR feedback | Security tests go in Full tier only |
| No nightly Full run | Quality drift between releases | Schedule Full suite nightly on main branch |
