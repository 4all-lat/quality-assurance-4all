---
name: quality-assurance-4all
description: End-to-end QA pipeline guide from spec to production. Covers TDD, BDD, SDD, property-based testing, mutation testing, security testing, performance testing, code coverage, and regression suite stratification. Use when starting a new project, establishing QA standards, or preparing a solution for production delivery.
---

# Quality Assurance Pipeline — From Spec to Production

A comprehensive, reusable QA methodology that ensures quality at every stage of the software delivery lifecycle. Designed for .NET / API projects but applicable to any stack.

## When to Use This Skill

- Starting a new software project from scratch
- Establishing QA standards for a team or organization
- Preparing a solution for production delivery
- Auditing existing QA practices
- Defining a CI/CD quality pipeline
- Responding to "how do we ensure quality?" questions
- Planning a release with confidence in test coverage

---

## 1. The Quality Pyramid

Quality is not a single activity at the end — it is built in layers throughout the lifecycle:

```
    ┌─────────────────────────────────────────┐
    │         PRODUCTION MONITORING            │  ← Observability, alerts, SLOs
    ├─────────────────────────────────────────┤
    │     PERFORMANCE + SECURITY TESTING       │  ← Non-functional requirements
    ├─────────────────────────────────────────┤
    │  INTEGRATION + CONTRACT + E2E TESTING    │  ← Between systems
    ├─────────────────────────────────────────┤
    │    BDD + PROPERTY-BASED TESTING          │  ← Behavior and edge cases
    ├─────────────────────────────────────────┤
    │       UNIT TESTING (TDD) + COVERAGE      │  ← Individual components
    ├─────────────────────────────────────────┤
    │  SPEC-DRIVEN DEVELOPMENT (SDD) + AI Spec │  ← Source of truth
    └─────────────────────────────────────────┘
```

Each layer depends on the one below. You cannot have reliable integration tests without reliable unit tests. You cannot have reliable security tests without reliable functional tests.

---

## 2. Phase 1 — Specification (SDD: Spec-Driven Development)

### What it is

The spec is the single source of truth. Everything — code, tests, documentation, tickets — derives from it. Any change starts by updating or reviewing the spec.

### How to apply

1. **Write the AI Spec or Feature Spec before coding.** The spec should include:
   - Functional requirement (business context, expected behavior, acceptance criteria)
   - Technical contract (API endpoints, DTOs, DB tables, data flow)
   - Edge cases matrix (test scenarios, expected results, error handling)
   - Open questions and blocking points

2. **Version the spec** in the repository alongside the code.

3. **Derive everything from the spec:**
   - User stories / work items → from acceptance criteria
   - BDD scenarios → from edge cases matrix
   - Unit tests → from technical contract
   - Integration tests → from functional requirement
   - Documentation → from all sections

4. **When requirements change, update the spec first**, then propagate to code and tests.

### Template (AI Spec)

```markdown
# [SPEC] - Title

## 1. Metadata & Execution Routing
- Preset, module, impact level

## 2. Functional Requirement
- Business context
- Expected behavior
- Acceptance criteria

## 3. Pre-Analysis
- DB tables, SPs, legacy services affected

## 4. Technical Contract
- API endpoints, DTOs, files to modify

## 5. Edge Cases & Test Matrix
| Scenario | Input | Expected | Error Handling |

## 6. Open Questions & Blockers
- Pending decisions, risks
```

### Quality gate

> **No code is written until the spec is reviewed and approved.**

---

## 3. Phase 2 — Unit Testing (TDD: Test-Driven Development)

### What it is

Write the test before the implementation. The cycle is:

```
Red (test fails) → Green (minimum code to pass) → Refactor (improve without breaking)
```

### How to apply

1. **Write a failing test** that describes the behavior you want.
2. **Write the minimum code** to make the test pass.
3. **Refactor** the code while keeping the test green.
4. **Repeat** for each new behavior.

### Frameworks by stack

| Stack | Framework | Mocking | Assertions |
|-------|-----------|--------|------------|
| .NET | xUnit / NUnit | Moq / NSubstitute | FluentAssertions |
| Node.js/TS | Vitest / Jest | built-in | built-in |
| Python | pytest | unittest.mock | pytest assertions |

### What to test at the unit level

- Controller input validation and response shapes
- Service business logic and pass-through behavior
- Repository SQL contracts (static SQL string assertions)
- Middleware error handling
- Filter/attribute behavior
- Edge cases: null inputs, empty collections, boundary values

### Quality gate

> **Every public method has at least one unit test. Coverage ≥ 80% line.**

---

## 4. Phase 3 — Behavior-Driven Development (BDD)

### What it is

Define behavior in business-readable scenarios using Given-When-Then (Gherkin). These scenarios are executable tests that validate the system from the user's perspective.

### How to apply

1. **Write `.feature` files** in Gherkin that describe the expected behavior.
2. **Write step definitions** that connect each Gherkin line to code.
3. **Run scenarios** as part of the test suite.

### Frameworks by stack

| Stack | BDD Framework |
|-------|---------------|
| .NET | Reqnroll (formerly SpecFlow) |
| Node.js/TS | Cucumber.js |
| Python | Behave |

### Gherkin template

```gherkin
Feature: Endpoint Name for Tenant

  Scenario: Happy Path — authenticated request returns expected fields
    Given the system calls the endpoint authenticated as "TENANT"
    When the API reads from "TABLE_NAME"
    Then it returns the N specified fields
    And edge case condition is handled

  Scenario: Non-authorized tenant is rejected
    Given a non-authorized tenant "OTHER" calls the endpoint
    When the filter evaluates
    Then the API returns 403
```

### Quality gate

> **Every acceptance criterion in the spec has at least one BDD scenario.**

---

## 5. Phase 4 — Integration Testing

### What it is

Tests that validate the system works correctly when all components are wired together — API, database, auth, middleware, routing.

### Two tiers

| Tier | Tool | Speed | Dependency |
|------|------|-------|------------|
| In-memory | WebApplicationFactory (TestServer) | ~2s | None |
| Live | Playwright / HttpClient against deployed API | ~55s | Running server |

### How to apply

1. **Start with in-memory tests** for routing, auth, middleware, HTTP method security.
2. **Add live integration tests** for database queries, real auth flows, tenant isolation, pagination.
3. **Use the test pyramid**: 70% unit, 20% integration, 10% E2E.

### What to test at the integration level

- Authentication (valid/invalid credentials, JWT, API key)
- Authorization (tenant feature gating, 403 for disabled features)
- Data isolation (tenant A cannot see tenant B's data)
- Pagination (page 1 vs page 2, page size cap, offset calculation)
- Error handling (DB unavailability → graceful error, no stack trace)
- Swagger visibility (endpoint appears in OpenAPI spec)
- Rate limiting (429 when exceeded)

### Quality gate

> **All endpoints × all tenants matrix is tested. Data isolation is verified by content, not just status codes.**

---

## 6. Phase 5 — Property-Based Testing

### What it is

Instead of testing with fixed values, generate hundreds of random combinations automatically to find edge cases that a human wouldn't think of.

### How to apply

1. **Define properties** (invariants) that should always hold.
2. **Let the framework generate random inputs** and verify the property.
3. **When a test fails**, the framework shrinks the input to the minimal failing case.

### Frameworks by stack

| Stack | Framework |
|-------|-----------|
| .NET | FsCheck |
| Node.js/TS | fast-check |
| Python | Hypothesis |

### Example properties

- `page <= 0` is always reset to 1
- `pageSize > max` is always capped
- `offset = (page - 1) * pageSize` never overflows
- Consecutive pages never overlap
- SQL OFFSET and FETCH values are always valid (≥ 0 and > 0)

### Quality gate

> **Every normalization/calculation function has at least one property test with 200+ random cases.**

---

## 7. Phase 6 — Security Testing (OWASP API Top 10)

### What it is

Tests that validate the API is secure against the OWASP API Security Top 10 risks.

### The 10 risks and what to test

| # | Risk | Test |
|---|------|------|
| API1 | Broken Object Level Authorization | Cross-tenant access returns 403 |
| API2 | Broken Authentication | Invalid/expired JWT → 401, invalid API key → 401 |
| API3 | Broken Object Property Level Authorization | Mass assignment not possible |
| API4 | Unrestricted Resource Consumption | Rate limiting returns 429 |
| API5 | Broken Function Level Authorization | Non-admin cannot access admin endpoints |
| API6 | Unrestricted Access to Sensitive Flows | Business flow cannot be bypassed |
| API7 | SSRF | Server does not follow user-supplied URLs |
| API8 | Security Misconfiguration | No stack traces, no server version, CORS correct |
| API9 | Improper Inventory Management | No undocumented endpoints accessible |
| API10 | Unsafe Consumption of APIs | Third-party API responses are validated |

### Additional security tests

- **SQL Injection**: send `1; DROP TABLE--` in query params → must not execute
- **XSS**: send `<script>` in params → response must be JSON, not HTML
- **Path Traversal**: send `../../../etc/passwd` → must return 404
- **HTTP Method Security**: POST/DELETE on GET-only endpoint → 405

### Quality gate

> **All OWASP API Top 10 risks are tested. SQL injection does not execute. No stack traces in error responses.**

---

## 8. Phase 7 — Performance Testing

### What it is

Tests that validate the API performs within acceptable bounds under concurrent load.

### Metrics to measure

| Metric | Target |
|--------|--------|
| P50 latency | < 500ms |
| P95 latency | < 2000ms (health), < 5000ms (DB queries) |
| P99 latency | < 10000ms |
| Throughput | > 20 req/s |
| Error rate | < 0.1% |
| Memory | No leaks over 1000 requests |

### How to apply

1. **Use concurrent HttpClient** with `Task.WhenAll` for simplicity, or NBomber/k6 for advanced scenarios.
2. **Measure P50, P95, P99** latency percentiles.
3. **Test with realistic load**: 10-50 concurrent users for typical APIs.
4. **Verify no memory leaks** by running 1000+ requests and checking memory growth.

### Quality gate

> **P95 latency meets target under expected load. Error rate < 0.1%. No memory leaks.**

---

## 9. Phase 8 — Code Coverage

### What it is

Measure which lines of production code are executed by tests. Set a minimum threshold.

### Configuration

```xml
<!-- .csproj -->
<CollectCoverage>true</CollectCoverage>
<CoverletOutputFormat>cobertura,opencover</CoverletOutputFormat>
<Threshold>80</Threshold>
<ThresholdType>line</ThresholdType>
<ThresholdStat>total</ThresholdStat>
<Exclude>[TestProject]*,*Migrations*</Exclude>
```

### Tools by stack

| Stack | Coverage Tool | Report Generator |
|-------|---------------|------------------|
| .NET | Coverlet | ReportGenerator |
| Node.js/TS | c8 / istanbul | built-in HTML |
| Python | coverage.py | built-in HTML |

### Quality gate

> **Line coverage ≥ 80%. Build fails if coverage drops below threshold.**

---

## 10. Phase 9 — Mutation Testing

### What it is

Mutate the production code (change `>` to `>=`, remove conditions, alter constants) and verify whether the tests detect the mutations. If a mutation survives, your tests are not effective.

### How to apply

1. **Install the mutation testing tool.**
2. **Configure which files to mutate** (controllers, services, repositories — not Program.cs or migrations).
3. **Run the tool** — it will generate mutations and run tests for each.
4. **Review the report** — kill surviving mutations by adding tests.

### Tools by stack

| Stack | Tool |
|-------|------|
| .NET | Stryker.NET |
| Node.js/TS | Stryker.js |
| Python | mutmut / cosmic-ray |

### Mutation score

| Score | Meaning |
|-------|---------|
| ≥ 80% | Strong tests |
| 60-79% | Adequate, room for improvement |
| < 60% | Tests are weak — improve before release |

### Quality gate

> **Mutation score ≥ 60% for production release. ≥ 80% for critical systems.**

---

## 11. Phase 10 — Regression Suite Stratification

### What it is

Organize tests into tiers that run at different speeds and frequencies.

### Three tiers

| Tier | Category | Duration | When to run | What's included |
|------|----------|----------|-------------|-----------------|
| Smoke | `Smoke` | ~30s | Every commit | Health, swagger, auth login |
| Regression | `Regression` | ~5min | Every PR | All functional tests (unit + BDD + integration) |
| Full | `Full` | ~15min | Nightly / pre-release | + security + performance + mutation |

### CI Pipeline script

```powershell
# .\run-tests.ps1 -Stage Smoke       # Quick health check
# .\run-tests.ps1 -Stage Regression  # Full functional validation
# .\run-tests.ps1 -Stage Full        # Everything including perf + security
# .\run-tests.ps1 -Stage Coverage    # Generate coverage report
# .\run-tests.ps1 -Stage Mutation    # Run mutation testing
```

### Quality gate

> **Smoke passes on every commit. Regression passes on every PR. Full passes before every release.**

---

## 12. Phase 11 — Production Quality Assurance

### Pre-production checklist

- [ ] **Spec approved** by product owner and architect
- [ ] **Unit tests** pass with ≥ 80% coverage
- [ ] **BDD scenarios** pass for all acceptance criteria
- [ ] **Integration tests** pass for all endpoint × tenant combinations
- [ ] **Property-based tests** pass with 200+ random cases
- [ ] **Security tests** pass (OWASP API Top 10)
- [ ] **Performance tests** meet P95 latency targets
- [ ] **Mutation score** ≥ 60%
- [ ] **No surviving high-severity mutations** in critical paths
- [ ] **Code review** approved by at least one peer
- [ ] **No secrets in code** (API keys, passwords, connection strings)
- [ ] **Error responses** do not contain stack traces
- [ ] **Swagger/OpenAPI** documentation is complete and accurate
- [ ] **Rate limiting** is configured and tested
- [ ] **Logging** is configured (no sensitive data logged)
- [ ] **CORS** is configured correctly (not `AllowAll` in production)
- [ ] **JWT expiration** is set appropriately
- [ ] **Database migrations** are reversible
- [ ] **Rollback plan** is documented and tested

### Recommended production quality options

| Option | Tool/Practice | Priority |
|--------|---------------|----------|
| **Observability** | OpenTelemetry, Serilog, Application Insights | High |
| **Health checks** | `/health` endpoint with DB connectivity check | High |
| **Structured logging** | JSON logs with correlation IDs | High |
| **Secrets management** | Azure Key Vault, AWS Secrets Manager, Kubernetes Secrets | High |
| **API Gateway** | Rate limiting, request validation, IP allowlisting | Medium |
| **WAF** | Web Application Firewall (Azure Front Door, Cloudflare) | Medium |
| **DAST scanning** | OWASP ZAP, Burp Suite (dynamic security testing) | Medium |
| **Dependency scanning** | Dependabot, Snyk, Trivy (supply chain security) | Medium |
| **Container scanning** | Trivy, Grype (if using Docker) | Medium |
| **SAST scanning** | SonarQube, Roslyn analyzers (static analysis) | Medium |
| **Contract testing** | Pact (consumer-driven contract testing) | Low |
| **Chaos engineering** | Chaos Mesh, Gremlin (resilience testing) | Low |
| **Canary deployments** | Flagger, Argo Rollouts (progressive delivery) | Low |

### Production monitoring SLOs

| SLO | Target | Alert threshold |
|-----|--------|-----------------|
| Availability | 99.9% | < 99.5% for 5 min |
| P95 latency | < 2s | > 5s for 5 min |
| Error rate | < 0.1% | > 1% for 5 min |
| Rate limit hits | < 5% of requests | > 10% for 10 min |

### Post-deployment validation

1. **Run smoke tests** against the production endpoint immediately after deploy.
2. **Monitor error rate** for 15 minutes post-deploy.
3. **Monitor latency P95** for 15 minutes post-deploy.
4. **Check health endpoint** returns healthy.
5. **Verify Swagger** is accessible (if applicable).
6. **Have a rollback plan** ready — if any metric degrades, rollback within 5 minutes.

---

## 13. Summary — Quality Checklist by Phase

| Phase | Methodology | Quality Gate | Tool Example |
|-------|-------------|--------------|--------------|
| 1. Specification | SDD | Spec approved before coding | AI Spec document |
| 2. Unit | TDD | ≥ 80% coverage | xUnit + Moq + Coverlet |
| 3. Behavior | BDD | All acceptance criteria covered | Reqnroll + Gherkin |
| 4. Integration | Test Pyramid | All endpoints × tenants tested | Playwright + WebApplicationFactory |
| 5. Edge cases | Property-Based | 200+ random cases per property | FsCheck |
| 6. Security | OWASP API Top 10 | All 10 risks tested | Custom + Playwright |
| 7. Performance | Load Testing | P95 < target, 0% errors | HttpClient concurrent / NBomber |
| 8. Coverage | Code Coverage | ≥ 80% line coverage | Coverlet + ReportGenerator |
| 9. Mutation | Mutation Testing | ≥ 60% mutation score | Stryker.NET |
| 10. Regression | Stratified Suite | Smoke/Regression/Full pass | NUnit Categories + CI script |
| 11. Production | Pre-prod checklist | All items checked | Manual + automated |

---

## 14. Quick Start — New Project Setup

```bash
# 1. Create the test project
dotnet new xunit -n MyProject.Tests
cd MyProject.Tests

# 2. Install QA packages
dotnet add package FluentAssertions
dotnet add package Moq
dotnet add package coverlet.collector
dotnet add package Microsoft.AspNetCore.Mvc.Testing
dotnet add package FsCheck
dotnet add package FsCheck.Xunit
dotnet add package Reqnroll.NUnit
dotnet add package NUnit3TestAdapter
dotnet add package Microsoft.Playwright.NUnit

# 3. Configure coverage in .csproj
# <CollectCoverage>true</CollectCoverage>
# <Threshold>80</Threshold>

# 4. Create folder structure
mkdir Features       # BDD .feature files
mkdir Integration    # In-memory + live integration tests
mkdir Security       # OWASP security tests
mkdir Performance    # Load tests
mkdir PropertyBased  # FsCheck property tests
mkdir Controllers    # Unit tests for controllers
mkdir Services       # Unit tests for services
mkdir Repositories   # Unit tests for repositories

# 5. Install Stryker globally for mutation testing
dotnet tool install -g dotnet-stryker

# 6. Install ReportGenerator for coverage reports
dotnet tool install -g dotnet-reportgenerator-globaltool
```

---

## 15. Anti-Patterns to Avoid

| Anti-pattern | Why it's bad | What to do instead |
|--------------|-------------|-------------------|
| Testing only happy path | Bugs hide in edge cases | Test null, empty, negative, overflow, boundary |
| 100% coverage, 0% mutation | Coverage doesn't mean tests are effective | Run mutation testing to verify test quality |
| All tests in one suite | Slow feedback loop | Stratify: Smoke → Regression → Full |
| Integration tests only | Slow, fragile, hide unit bugs | Follow the test pyramid (70/20/10) |
| No security tests | Production will be attacked | Test OWASP API Top 10 before every release |
| No performance tests | Will fail under load | Test P95 latency under concurrent load |
| Secrets in test code | Leaks credentials | Use user secrets or environment variables |
| Testing implementation details | Brittle tests | Test behavior, not implementation |
| No rollback plan | Cannot recover from bad deploy | Document and test rollback procedure |
| Skipping spec | No source of truth | Write the spec first, derive everything from it |

---

## 16. Supporting Files

This skill includes reference documentation, reusable templates, and working scripts beyond this `SKILL.md`.

### references/

Detailed deep-dive documentation for each topic:

| File | Content |
|------|---------|
| `references/quality-gates.md` | Consolidated quality gates and checklists for all 11 phases |
| `references/owasp-api-testing.md` | Detailed test implementations for OWASP API Top 10 (with .NET examples) |
| `references/tools-by-stack.md` | Frameworks and tools by stack (.NET, Node.js/TS, Python) with CI/CD examples |
| `references/test-pyramid.md` | Test pyramid, regression stratification, and CI pipeline integration deep dive |

### assets/

Reusable templates and configuration snippets:

| File | Content |
|------|---------|
| `assets/ai-spec-template.md` | AI Spec / Feature Spec template (6-section WMSTek convention) |
| `assets/bdd-feature-template.feature` | Gherkin BDD scenario template (Smoke, Regression, Security, Property-Based) |
| `assets/pre-production-checklist.md` | Pre-production quality checklist with sign-off table |
| `assets/coverage-config.xml` | Coverlet coverage configuration snippet for .csproj |

### scripts/

Working scripts for CI/CD and project setup:

| File | Content |
|------|---------|
| `scripts/run-tests.ps1` | Stratified test runner (Smoke / Regression / Full / Coverage / Mutation) |
| `scripts/setup-qa-project.ps1` | Quick-start QA project scaffolder (.NET, Node.js, Python) |
| `scripts/README.md` | Detailed documentation for both scripts |

See `README.md` in the skill root for a human-readable overview of the entire skill.
