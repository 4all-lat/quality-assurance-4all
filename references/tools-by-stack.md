# Tools by Stack Reference

Frameworks and tools for each phase of the QA pipeline, organized by technology stack.

## .NET Stack

### Unit Testing

| Tool | Purpose | Install |
|------|---------|---------|
| xUnit | Test framework | `dotnet add package xunit` |
| NUnit | Test framework (alternative) | `dotnet add package NUnit` |
| Moq | Mocking library | `dotnet add package Moq` |
| NSubstitute | Mocking library (alternative) | `dotnet add package NSubstitute` |
| FluentAssertions | Readable assertions | `dotnet add package FluentAssertions` |

### BDD

| Tool | Purpose | Install |
|------|---------|---------|
| Reqnroll.xUnit | BDD framework for xUnit projects (default) | `dotnet add package Reqnroll.xUnit` |
| Reqnroll.NUnit | BDD framework for NUnit projects | `dotnet add package Reqnroll.NUnit` |
| NUnit3TestAdapter | Test adapter (NUnit projects only) | `dotnet add package NUnit3TestAdapter` |

> Use one test framework per project. Reqnroll has a separate package per framework —
> `Reqnroll.xUnit` for xUnit, `Reqnroll.NUnit` for NUnit. Do not mix them.

### Integration Testing

| Tool | Purpose | Install |
|------|---------|---------|
| WebApplicationFactory | In-memory test server | `dotnet add package Microsoft.AspNetCore.Mvc.Testing` |
| Playwright | Browser/live integration testing | `dotnet add package Microsoft.Playwright` |

### Concurrency & Idempotency

See [`concurrency-and-idempotency.md`](concurrency-and-idempotency.md) for the scenarios and the tests.

| Tool | Purpose | Install |
|------|---------|---------|
| `Barrier` / `CountdownEvent` | Release N requests at the same instant, so the race actually happens | Built-in (`System.Threading`) |
| Testcontainers for .NET | Run the race against the real database engine — in-memory providers hide it | `dotnet add package Testcontainers` |
| `[Trait("Category", "Concurrency")]` | Select the class in the Regression tier | Built-in xUnit |
| Polly | Assert retry and backoff behaviour on outbound calls | `dotnet add package Polly` |

### Property-Based Testing

| Tool | Purpose | Install |
|------|---------|---------|
| FsCheck | Property-based testing | `dotnet add package FsCheck` |
| FsCheck.Xunit | xUnit integration | `dotnet add package FsCheck.Xunit` |

### Code Coverage

| Tool | Purpose | Install |
|------|---------|---------|
| Coverlet | Coverage collector | `dotnet add package coverlet.collector` |
| ReportGenerator | HTML coverage reports | `dotnet tool install -g dotnet-reportgenerator-globaltool` |

### Mutation Testing

| Tool | Purpose | Install |
|------|---------|---------|
| Stryker.NET | Mutation testing | `dotnet tool install -g dotnet-stryker` |

### Performance Testing

| Tool | Purpose | Notes |
|------|---------|-------|
| HttpClient + Task.WhenAll | Simple concurrent load | Built-in, no install needed |
| NBomber | Advanced load testing | `dotnet add package NBomber` |

### Security Testing (dynamic)

These drive a running system, so they belong to the Full tier.

| Tool | Purpose | Notes |
|------|---------|-------|
| OWASP ZAP | DAST scanning | External tool, run separately |
| Playwright | Authenticated OWASP API probes | `dotnet add package Microsoft.Playwright` |
| jwt_tool | Forge `alg=none`, algorithm-confusion and `kid`-injection tokens for the API2 lifecycle tests | External tool (`pipx install jwt-tool`) |

### Security Scanning (static — every PR)

| Tool | Purpose | Install |
|------|---------|---------|
| `dotnet list package --vulnerable` | Dependency advisory scan, direct and transitive | Built into the SDK — no install |
| Gitleaks | Secret scanning over the diff and the git history | `brew install gitleaks` (external binary) |
| TruffleHog | Secret scanning with live-credential verification | `brew install trufflehog` (external binary) |
| Roslyn analyzers | SAST, built into the compiler | `<EnableNETAnalyzers>true</EnableNETAnalyzers>` and `<AnalysisMode>AllEnabledByDefault</AnalysisMode>` in the `.csproj` |
| CycloneDX for .NET | SBOM per release | `dotnet tool install -g CycloneDX` |
| Trivy | Container image scan (if the service ships in one) | External tool |

```xml
<!-- .csproj — fail the build on any analyzer warning instead of printing it -->
<PropertyGroup>
  <EnableNETAnalyzers>true</EnableNETAnalyzers>
  <AnalysisMode>AllEnabledByDefault</AnalysisMode>
  <TreatWarningsAsErrors>true</TreatWarningsAsErrors>
  <WarningsAsErrors>CA*,S*</WarningsAsErrors>
</PropertyGroup>
```

### Static Analysis Platform (SonarQube)

Not a phase and not a test runner: it consumes the coverage report from Phase 8, reads the source
like the scans above, and adds what none of them measure — duplicated lines, cognitive complexity,
code smells and the maintainability rating of the changed code. The edition choice, the quality gate
and the per-stack wiring are in [`sonarqube.md`](sonarqube.md).

| Tool | Purpose | Install |
|------|---------|---------|
| SonarScanner for .NET | Analysis wrapped around the build — it cannot analyze C# without the `begin`/`end` pair | `dotnet tool install -g dotnet-sonarscanner` |
| `sonar.qualitygate.wait=true` | Make the build fail when the gate fails, instead of reporting success while the analysis is still queued server-side | Passed on `begin` |

```bash
# What `run-tests.sh -s Sonar` runs. SONAR_TOKEN and SONAR_HOST_URL come from the
# environment; the scanner reads both, so neither appears on a command line.
dotnet sonarscanner begin /k:"$SONAR_PROJECT_KEY" \
  /d:sonar.qualitygate.wait=true \
  /d:sonar.cs.cobertura.reportsPaths="./test-results/**/coverage.cobertura.xml"
dotnet build
dotnet test --collect:"XPlat Code Coverage" --results-directory ./test-results
dotnet sonarscanner end
```

The coverage report has to be produced **inside** that window — Coverlet's output from an earlier
`-s Coverage` run is not picked up, and the gate then measures 0%.

### Test Categorization

```csharp
// Use xUnit Traits for stratification
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
// Not Category=Security, so `Category!=Security` lets it through to every PR.
[Fact]
[Trait("Category", "SecurityPR")]
public async Task CrossTenantAccess_Returns403() { ... }

[Fact]
[Trait("Category", "Security")]
public void RateLimitExceeded_Returns429() { ... }

[Fact]
[Trait("Category", "Performance")]
public void GetEndpoint_P95WithinBudget() { ... }
```

### UI Quality

Accessibility and visual regression are part of the same release gate as the API tests, so they run
in the Regression tier from the same test project. Practices and the full checklist live in
[`quality-engineering-practices.md`](quality-engineering-practices.md).

| Concern | Tool | Notes |
|---------|------|-------|
| Accessibility | `axe-core` injected through Playwright | Fails on any new violation, not on a raw count |
| Visual regression | Playwright `toHaveScreenshot()` | Snapshots committed; animations disabled, viewports fixed |
| Responsive | Playwright viewport projects | Phone / tablet / desktop as separate projects |

```csharp
[Fact]
[Trait("Category", "Regression")]
public async Task Home_HasNoAccessibilityViolations()
{
    await Page.GotoAsync("/");
    var results = await new AxeBuilder(Page).AnalyzeAsync();
    results.Violations.Should().BeEmpty();
}
```

### Coverage Configuration (.csproj)

```xml
<PropertyGroup>
  <CollectCoverage>true</CollectCoverage>
  <CoverletOutputFormat>cobertura,opencover</CoverletOutputFormat>
  <Threshold>80</Threshold>
  <ThresholdType>line</ThresholdType>
  <ThresholdStat>total</ThresholdStat>
  <Exclude>[TestProject]*,*Migrations*</Exclude>
</PropertyGroup>
```

---

## Node.js / TypeScript Stack

### Unit Testing

| Tool | Purpose | Install |
|------|---------|---------|
| Vitest | Test framework (modern, Vite-based) | `npm install -D vitest` |
| Jest | Test framework (popular alternative) | `npm install -D jest` |

Note: Vitest and Jest have built-in mocking and assertions — no separate libraries needed.

### BDD

| Tool | Purpose | Install |
|------|---------|---------|
| Cucumber.js | BDD framework | `npm install -D @cucumber/cucumber` |

### Integration Testing

| Tool | Purpose | Install |
|------|---------|---------|
| Supertest | HTTP assertion library | `npm install -D supertest` |
| Playwright | Browser integration testing | `npm install -D @playwright/test` |

### Concurrency & Idempotency

See [`concurrency-and-idempotency.md`](concurrency-and-idempotency.md) for the scenarios and the tests.

| Tool | Purpose | Install |
|------|---------|---------|
| `Promise.all` over a pre-armed barrier | Release N requests together — bare `Promise.all` usually serialises and hides the race | Built-in |
| testcontainers (Node) | Run the race against the real database engine | `npm install -D testcontainers` |
| `describe('Concurrency', …)` | Select the class in the Regression tier | Built-in Vitest |
| `AbortSignal.timeout` | Cap a hung race instead of blocking CI | Built-in |

### Property-Based Testing

| Tool | Purpose | Install |
|------|---------|---------|
| fast-check | Property-based testing | `npm install -D fast-check` |

### Code Coverage

| Tool | Purpose | Install |
|------|---------|---------|
| @vitest/coverage-v8 | V8-based coverage (Vitest provider `v8`) | `npm install -D @vitest/coverage-v8` |
| @vitest/coverage-istanbul | Istanbul-based coverage (alternative) | `npm install -D @vitest/coverage-istanbul` |

### Mutation Testing

| Tool | Purpose | Install |
|------|---------|---------|
| Stryker.js | Mutation testing | `npm install -D @stryker-mutator/core` |

### Performance Testing

| Tool | Purpose | Install |
|------|---------|---------|
| k6 | Load testing | External tool (https://k6.io) |
| autocannon | Node.js HTTP load testing | `npm install -D autocannon` |

### Security Testing (dynamic)

| Tool | Purpose | Install |
|------|---------|---------|
| Playwright | Authenticated OWASP API probes | `npm install -D @playwright/test` |
| OWASP ZAP | DAST scanning | External tool, run separately |
| jwt_tool / `jose` | Forge `alg=none`, algorithm-confusion and `kid`-injection tokens for the API2 lifecycle tests | `pipx install jwt-tool` / `npm install -D jose` |

### Security Scanning (static — every PR)

| Tool | Purpose | Install |
|------|---------|---------|
| `npm audit` | Dependency advisory scan | Built into npm — no install |
| eslint-plugin-security | SAST | `npm install -D eslint eslint-plugin-security` |
| Gitleaks / TruffleHog | Secret scanning over the diff and the history | `brew install gitleaks` (external binary) |
| `npm sbom` | SBOM per release | Built into npm 9+ |
| Trivy | Container image scan (if the service ships in one) | External tool |

```jsonc
// eslint.config.js — security rules as errors, not warnings, so CI fails
import security from 'eslint-plugin-security'
export default [ security.configs.recommended ]   // every rule is "error"
```

### Static Analysis Platform (SonarQube)

See [`sonarqube.md`](sonarqube.md) for the edition choice, the quality gate and the canonical
thresholds it has to reproduce.

| Tool | Purpose | Install |
|------|---------|---------|
| sonar-scanner | CLI analysis; reads `sonar-project.properties` for anything not passed as `-D` | `npm install -D sonarqube-scanner`, or the CLI scanner installed once on the runner |
| lcov reporter | The scanner cannot read Vitest's `text`, `html` or `cobertura` output — it wants `coverage/lcov.info` | `--coverage.reporter=lcov` |

```bash
# What `run-tests.sh -s Sonar` runs.
npx vitest run --coverage --coverage.reporter=lcov
sonar-scanner \
  -Dsonar.projectKey="$SONAR_PROJECT_KEY" \
  -Dsonar.javascript.lcov.reportPaths=coverage/lcov.info \
  -Dsonar.qualitygate.wait=true
```

### Test Categorization

```typescript
// Vitest: use test tags or separate files
describe('Smoke', () => {
  it('health check returns 200', async () => { ... })
})

describe('Regression', () => {
  it('returns paginated results', async () => { ... })
})

describe('Concurrency', () => {
  it('creates exactly one order on a double submit', async () => { ... })
})

// The PR subset of the security suite. The Regression filter is
// `--testNamePattern "^(?!.*(Security(?!PR)|Performance))"` — the negative
// lookahead keeps SecurityPR in and drops Security.
describe('SecurityPR', () => {
  it('cross-tenant access returns 403', async () => { ... })
})

describe('Security', () => {
  it('rate limiting returns 429 under load', async () => { ... })
})
```

### UI Quality

| Concern | Tool | Notes |
|---------|------|-------|
| Accessibility | `@axe-core/playwright` | Fails on any new violation |
| Visual regression | Playwright `toHaveScreenshot()`, or Percy for hosted review | Snapshots committed; `maxDiffPixelRatio` small and explicit |
| Responsive | Playwright viewport projects | Phone / tablet / desktop as separate projects |

```typescript
import AxeBuilder from '@axe-core/playwright'

describe('Regression', () => {
  it('home has no accessibility violations', async ({ page }) => {
    await page.goto('/')
    const results = await new AxeBuilder({ page }).analyze()
    expect(results.violations).toEqual([])
  })
})
```

### Coverage Configuration (vitest.config.ts)

```typescript
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
```

---

## Python Stack

### Unit Testing

| Tool | Purpose | Install |
|------|---------|---------|
| pytest | Test framework | `pip install pytest` |
| unittest.mock | Mocking (built-in) | Built-in with Python |

### BDD

| Tool | Purpose | Install |
|------|---------|---------|
| Behave | BDD framework (Gherkin) | `pip install behave` |

### Integration Testing

| Tool | Purpose | Install |
|------|---------|---------|
| pytest + httpx | HTTP integration testing | `pip install httpx pytest` |
| Playwright | Browser integration testing | `pip install playwright` |

### Concurrency & Idempotency

See [`concurrency-and-idempotency.md`](concurrency-and-idempotency.md) for the scenarios and the tests.

| Tool | Purpose | Install |
|------|---------|---------|
| `threading.Barrier` / `asyncio.gather` / `concurrent.futures` | Release N requests at the same instant, so the race actually happens | Built-in |
| testcontainers-python | Run the race against the real database engine — SQLite in-memory hides it | `pip install testcontainers` |
| pytest-timeout | Fail a hung race instead of blocking CI | `pip install pytest-timeout` |
| `@pytest.mark.concurrency` | Select the class in the Regression tier | Declared in `pytest.ini` |

### Property-Based Testing

| Tool | Purpose | Install |
|------|---------|---------|
| Hypothesis | Property-based testing | `pip install hypothesis` |

### Code Coverage

| Tool | Purpose | Install |
|------|---------|---------|
| coverage.py | Coverage measurement | `pip install coverage` |

### Mutation Testing

| Tool | Purpose | Install |
|------|---------|---------|
| mutmut | Mutation testing | `pip install mutmut` |
| cosmic-ray | Mutation testing (alternative) | `pip install cosmic-ray` |

### Performance Testing

| Tool | Purpose | Install |
|------|---------|---------|
| locust | Load testing | `pip install locust` |

### Security Testing (dynamic)

| Tool | Purpose | Install |
|------|---------|---------|
| Playwright | Authenticated OWASP API probes | `pip install playwright` |
| OWASP ZAP | DAST scanning | External tool, run separately |
| jwt_tool | Forge `alg=none`, algorithm-confusion and `kid`-injection tokens for the API2 lifecycle tests | `pipx install jwt-tool` |

### Security Scanning (static — every PR)

| Tool | Purpose | Install |
|------|---------|---------|
| pip-audit | Dependency advisory scan (`--strict` to fail on any advisory) | `pip install pip-audit` |
| bandit | SAST | `pip install bandit` |
| Gitleaks / TruffleHog | Secret scanning over the diff and the history | `brew install gitleaks` (external binary) |
| cyclonedx-bom | SBOM per release | `pip install cyclonedx-bom` |
| Trivy | Container image scan (if the service ships in one) | External tool |

```ini
# pyproject.toml — bandit as a build gate, not an advisory report
[tool.bandit]
exclude_dirs = ["tests", "migrations"]
# run: bandit -r src -c pyproject.toml   (exit 1 on any HIGH severity finding)
```

### Static Analysis Platform (SonarQube)

See [`sonarqube.md`](sonarqube.md) for the edition choice, the quality gate and the canonical
thresholds it has to reproduce.

| Tool | Purpose | Install |
|------|---------|---------|
| sonar-scanner | CLI analysis; reads `sonar-project.properties` for anything not passed as `-D` | CLI scanner on the runner, or `pip install sonarqube-scanner` |
| `bandit -f json` | The Phase 6 SAST report, imported as external issues so the findings sit next to the code that caused them | Already the SAST gate |

```bash
# What `run-tests.sh -s Sonar` runs.
coverage xml
bandit -r src -f json -o bandit.json   # optional: imported by the scanner's bandit report path
sonar-scanner \
  -Dsonar.projectKey="$SONAR_PROJECT_KEY" \
  -Dsonar.python.coverage.reportPaths=coverage.xml \
  -Dsonar.qualitygate.wait=true
```

The bandit report is advisory inside Sonar; the exit code of `bandit -r src` is the gate. Importing
it does not make the gate stronger — it makes the finding visible where it is fixed.

### Test Categorization

```python
# pytest: use markers for stratification
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

# The PR subset of the security suite. pytest -m "not security" includes it.
@pytest.mark.securitypr
def test_cross_tenant_access_returns_403():
    ...

@pytest.mark.security
def test_rate_limit_exceeded_returns_429():
    ...

# Run by marker:
# pytest -m smoke
# pytest -m regression
# pytest -m "not security and not performance"
```

### UI Quality

| Concern | Tool | Notes |
|---------|------|-------|
| Accessibility | `axe-core` through Playwright, or `pa11y` against a rendered URL | Fails on any new violation |
| Visual regression | Playwright `toHaveScreenshot()` | Snapshots committed; `max_diff_pixels` small and explicit |
| Responsive | Playwright viewport contexts | Phone / tablet / desktop as separate contexts |

```python
@pytest.mark.regression
def test_home_has_no_accessibility_violations(page):
    page.goto("/")
    results = Axe(page).analyze()
    assert results.violations == []
```

### Coverage Configuration (.coveragerc)

```ini
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
```

---

## Quick Reference: All Phases x All Stacks

| Phase | .NET | Node.js/TS | Python |
|-------|------|-----------|--------|
| Unit | xUnit + Moq + FluentAssertions | Vitest (built-in) | pytest + unittest.mock |
| BDD | Reqnroll | Cucumber.js | Behave |
| Integration | WebApplicationFactory + Playwright | Supertest + Playwright | httpx + Playwright |
| Concurrency | `Barrier` + Testcontainers | `Promise.all` + testcontainers | `threading.Barrier` + testcontainers |
| Property-Based | FsCheck | fast-check | Hypothesis |
| Coverage | Coverlet + ReportGenerator | @vitest/coverage-v8 | coverage.py |
| Mutation | Stryker.NET | Stryker.js | mutmut / cosmic-ray |
| Performance | HttpClient concurrent / NBomber | autocannon / k6 | locust |
| Security (dynamic) | Custom + Playwright + jwt_tool | Custom + Playwright + jwt_tool | Custom + Playwright + jwt_tool |
| Security scanning | `dotnet list --vulnerable` + Roslyn + gitleaks | `npm audit` + eslint-plugin-security + gitleaks | pip-audit + bandit + gitleaks |
| Static analysis | SonarScanner for .NET | sonar-scanner | sonar-scanner |
| UI quality | Playwright + `axe-core` + visual snapshots | `@axe-core/playwright` + Playwright snapshots | Playwright + `axe-core` / `pa11y` |

---

## CI/CD Integration

### GitHub Actions — .NET

```yaml
name: QA Pipeline
on: [push, pull_request]

jobs:
  smoke:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-dotnet@v4
        with:
          dotnet-version: '8.0'
      - run: dotnet test --filter "Category=Smoke"

  regression:
    needs: smoke
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0        # a shallow clone cannot scan the history for secrets
      - uses: actions/setup-dotnet@v4
        with:
          dotnet-version: '8.0'
      # Security scanning runs here, on every PR: none of it needs a deployed system.
      - name: Dependency scan
        run: |
          dotnet restore
          ! dotnet list package --vulnerable --include-transitive | grep -E '\b(High|Critical)\b'
      - name: Secret scan (diff and history)
        run: |
          gitleaks detect --redact
          trufflehog git file://. --only-verified --fail
      - name: SAST
        run: dotnet build -warnaserror
      # Category=SecurityPR is the BOLA/auth/injection subset that must not wait for nightly.
      - run: dotnet test --filter "Category!=Security&Category!=Performance"

  sonar:
    needs: regression
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0        # blame and issue tracking need the history
      - uses: actions/setup-dotnet@v4
        with:
          dotnet-version: '8.0'
      - run: dotnet tool install -g dotnet-sonarscanner
      # The gate waits for itself: this step fails when the gate fails, so a
      # queued analysis is never reported as a pass.
      - name: Static analysis and the quality gate
        run: |
          dotnet sonarscanner begin /k:"$SONAR_PROJECT_KEY" /d:sonar.qualitygate.wait=true
          dotnet build
          dotnet test --collect:"XPlat Code Coverage" --results-directory ./test-results
          dotnet sonarscanner end
        env:
          SONAR_PROJECT_KEY: ${{ vars.SONAR_PROJECT_KEY }}
          SONAR_HOST_URL: ${{ vars.SONAR_HOST_URL }}
          SONAR_TOKEN: ${{ secrets.SONAR_TOKEN }}

  full:
    needs: regression
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - uses: actions/setup-dotnet@v4
        with:
          dotnet-version: '8.0'
      - run: dotnet test  # all tests
      - run: dotnet stryker  # mutation testing
      - name: SBOM for the release artifact
        run: |
          dotnet tool install -g CycloneDX
          dotnet CycloneDX . --output-directory sbom
      - uses: actions/upload-artifact@v4
        with:
          name: sbom
          path: sbom/
```

### GitHub Actions — Node.js/TS

```yaml
name: QA Pipeline
on: [push, pull_request]

jobs:
  smoke:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
      - run: npm install
      - run: npm test -- --reporter=verbose --testNamePattern=Smoke

  regression:
    needs: smoke
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0        # a shallow clone cannot scan the history for secrets
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
      - run: npm ci
      # Security scanning runs here, on every PR: none of it needs a deployed system.
      - name: Dependency scan
        run: npm audit --audit-level=high
      - name: Secret scan (diff and history)
        run: |
          gitleaks detect --redact
          trufflehog git file://. --only-verified --fail
      - name: SAST
        run: npx eslint . --max-warnings=0
      - run: npx vitest run --coverage --testNamePattern "^(?!.*(Security(?!PR)|Performance))"

  sonar:
    needs: regression
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0        # blame and issue tracking need the history
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
      - run: npm ci
      - name: Static analysis and the quality gate
        run: |
          npx vitest run --coverage --coverage.reporter=lcov
          npx sonarqube-scanner \
            -Dsonar.projectKey="$SONAR_PROJECT_KEY" \
            -Dsonar.javascript.lcov.reportPaths=coverage/lcov.info \
            -Dsonar.qualitygate.wait=true
        env:
          SONAR_PROJECT_KEY: ${{ vars.SONAR_PROJECT_KEY }}
          SONAR_HOST_URL: ${{ vars.SONAR_HOST_URL }}
          SONAR_TOKEN: ${{ secrets.SONAR_TOKEN }}

  full:
    needs: regression
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
      - run: npm ci
      - run: npx vitest run          # all tests, security included
      - run: npx stryker run
      - name: SBOM for the release artifact
        run: npm sbom --sbom-format cyclonedx > sbom.json
      - uses: actions/upload-artifact@v4
        with:
          name: sbom
          path: sbom.json
```
