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
| Regression | `Regression` | ~5min | Every PR | All functional tests (unit + BDD + integration + concurrency) + the `SecurityPR` subset |
| Full | `Full` | ~15min | Nightly / pre-release | + the full security suite, the static scans, performance and mutation |

The durations are a **gate, not a description**. The runner times each stage against the budget in
the canonical table and `--enforce-budget` turns an overrun into a build failure. A tier that grows
past its budget stops being the fast feedback loop it was sized for, and developers start skipping
it.

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
- **All concurrency and idempotency tests** (`Concurrency`) — cheap to run, expensive to discover late
- **The `SecurityPR` subset** (see below)

**Speed target:** < 5 minutes total (enforced by `--enforce-budget`)

**Example (.NET):**
```csharp
// Everything except the security and performance suites. Note that this filter
// already includes Category=SecurityPR: `SecurityPR != Security`.
// Run with: dotnet test --filter "Category!=Security&Category!=Performance"
```

#### The `SecurityPR` subset

Running the whole OWASP suite on every PR is what makes a PR tier slow, so the usual advice is to
push all of security to the nightly run. That is how a BOLA regression ships on a Thursday and is
found on Friday night.

The split is by **cost**, not by topic. A test belongs in `SecurityPR` — and therefore runs on every
PR — when all three hold:

1. **It is fast and deterministic** — no load, no sleep, no third-party dependency.
2. **Its failure is a release blocker** — the exploit is directly reachable and has real impact.
3. **It needs no special environment** — no scanner, no external target, no production data.

The three that qualify today:

| Included in `SecurityPR` | Why |
|---|---|
| **API1 — BOLA**: cross-tenant access returns 403 | The single highest-impact API flaw; a regression is a data breach |
| **API2 — authentication lifecycle**: invalid/expired tokens, refresh rotation, revocation | Identity is the front door; a regression locks out or lets in everyone |
| **Injection**: SQL injection, XSS, path traversal do not execute | One string-concatenated query undoes the whole PR |

Everything else — rate limiting under load, SSRF against a metadata endpoint, misconfiguration
sweeps, inventory checks, the DAST run — stays in `Full`, where it belongs.

Keep the subset small enough that it never dominates the PR tier. If `SecurityPR` starts pushing
Regression past its budget, that is the signal to move a case back to the nightly run, not to raise
the budget.

### Full Tier

**Purpose:** Comprehensive quality validation before release.

**What to include:**
- Everything from Regression tier
- The **full** security suite (OWASP API Top 10, including the probes too slow for `SecurityPR`)
- The static security scans: dependencies, secrets, SAST, and the SBOM for the release
- Performance tests (load, latency percentiles)
- Mutation testing

**Speed target:** < 15 minutes total (enforced by `--enforce-budget`)

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
      # Includes Category=SecurityPR (the BOLA/auth/injection subset); excludes the
      # full security and performance suites.
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
[Trait("Category", "Concurrency")]
public async Task DoubleSubmit_CreatesExactlyOne() { ... }

// The PR subset of the security suite — not Category=Security, so the
// Regression filter (Category!=Security) lets it through.
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

**Filtering:**
```bash
dotnet test --filter "Category=Smoke"
dotnet test --filter "Category!=Security&Category!=Performance"   # PR tier; includes SecurityPR
dotnet test                                                       # Full tier
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

describe('Concurrency', () => {
  it('creates exactly one order on a double submit', async () => { ... })
})

// SecurityPR is the PR subset; the rest of the security suite is 'Security'.
describe('SecurityPR', () => {
  it('cross-tenant access returns 403', async () => { ... })
})

// Smoke:      vitest run --testNamePattern "Smoke"
// Regression: vitest run --testNamePattern "^(?!.*(Security(?!PR)|Performance))"
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

@pytest.mark.concurrency
def test_double_submit_creates_exactly_one():
    ...

@pytest.mark.securitypr
def test_cross_tenant_access_returns_403():
    ...

# Smoke:      pytest -m smoke
# Regression: pytest -m "not security and not performance"   (securitypr is included)
# Full:       pytest
```

---

## Common Pitfalls

| Pitfall | Why it's bad | What to do instead |
|---------|-------------|-------------------|
| All tests in one suite | Slow feedback loop | Stratify: Smoke -> Regression -> Full |
| Smoke tests too slow | Developers skip running them | Keep smoke < 30s, only critical paths |
| No categorization | Can't run subsets efficiently | Use traits/markers/tags from day one |
| E2E tests in Smoke | E2E is slow and flaky | Smoke = unit-level health checks only |
| All security tests in Regression | Slows down PR feedback | Keep only the `SecurityPR` subset in Regression; the rest go to Full |
| No security at all in Regression | A BOLA regression ships on Thursday and is caught on Friday night | Move API1, API2 and injection into the PR tier |
| A tier that outgrows its budget | Developers start skipping it, so it stops being a gate | Enforce the budget with `--enforce-budget`, then move cases out rather than raise it |
| No nightly Full run | Quality drift between releases | Schedule Full suite nightly on main branch |
