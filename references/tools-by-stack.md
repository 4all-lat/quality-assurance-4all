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

### Security Testing

| Tool | Purpose | Notes |
|------|---------|-------|
| OWASP ZAP | DAST scanning | External tool, run separately |
| SonarQube | SAST static analysis | External server/tool |

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
[Trait("Category", "Security")]
public void CrossTenantAccess_Returns403() { ... }

[Fact]
[Trait("Category", "Performance")]
public void GetEndpoint_P95Under2Seconds() { ... }
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

### Test Categorization

```typescript
// Vitest: use test tags or separate files
describe('Smoke', () => {
  it('health check returns 200', async () => { ... })
})

describe('Regression', () => {
  it('returns paginated results', async () => { ... })
})

describe('Security', () => {
  it('cross-tenant access returns 403', async () => { ... })
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

@pytest.mark.security
def test_cross_tenant_access():
    ...

# Run by marker:
# pytest -m smoke
# pytest -m regression
# pytest -m "not slow"
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
| Property-Based | FsCheck | fast-check | Hypothesis |
| Coverage | Coverlet + ReportGenerator | @vitest/coverage-v8 | coverage.py |
| Mutation | Stryker.NET | Stryker.js | mutmut / cosmic-ray |
| Performance | HttpClient concurrent / NBomber | autocannon / k6 | locust |
| Security | Custom + Playwright | Custom + Playwright | Custom + Playwright |

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
      - uses: actions/setup-dotnet@v4
        with:
          dotnet-version: '8.0'
      - run: dotnet test --filter "Category=Regression"

  full:
    needs: regression
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-dotnet@v4
        with:
          dotnet-version: '8.0'
      - run: dotnet test  # all tests
      - run: dotnet stryker  # mutation testing
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
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
      - run: npm install
      - run: npm test --coverage
```
