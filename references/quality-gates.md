# Quality Gates Reference

Consolidated quality gates for each phase of the QA pipeline. Each gate must pass before moving to the next phase.

## Phase 1 — Specification (SDD)

> **Gate:** No code is written until the spec is reviewed and approved.

**Checklist:**
- [ ] Functional requirement documented (business context, expected behavior, acceptance criteria)
- [ ] Technical contract defined (API endpoints, DTOs, DB tables, data flow)
- [ ] Edge cases matrix completed (test scenarios, expected results, error handling)
- [ ] Open questions and blocking points listed
- [ ] Spec versioned in the repository alongside code
- [ ] Spec approved by product owner and architect

---

## Phase 2 — Unit Testing (TDD)

> **Gate:** Every public method has at least one unit test. Coverage >= 80% line.

**Checklist:**
- [ ] Tests written before implementation (Red-Green-Refactor cycle)
- [ ] Controller input validation and response shapes tested
- [ ] Service business logic and pass-through behavior tested
- [ ] Repository SQL contracts tested (static SQL string assertions)
- [ ] Middleware error handling tested
- [ ] Filter/attribute behavior tested
- [ ] Edge cases covered: null inputs, empty collections, boundary values
- [ ] Line coverage >= 80% (enforced by CI)

---

## Phase 3 — Behavior-Driven Development (BDD)

> **Gate:** Every acceptance criterion in the spec has at least one BDD scenario.

**Checklist:**
- [ ] `.feature` files written in Gherkin (Given-When-Then)
- [ ] Step definitions connected to code
- [ ] Scenarios run as part of the test suite
- [ ] All acceptance criteria from spec have at least one scenario
- [ ] Business-readable scenarios reviewed by product owner

---

## Phase 4 — Integration Testing

> **Gate:** All endpoints x all tenants matrix is tested. Data isolation is verified by content, not just status codes.

**Checklist:**
- [ ] In-memory tests (WebApplicationFactory / TestServer) for routing, auth, middleware
- [ ] Live tests (Playwright / HttpClient) for database queries, real auth flows
- [ ] Authentication tested (valid/invalid credentials, JWT, API key)
- [ ] Authorization tested (tenant feature gating, 403 for disabled features)
- [ ] Data isolation tested (tenant A cannot see tenant B's data — by content, not just status code)
- [ ] Pagination tested (page 1 vs page 2, page size cap, offset calculation)
- [ ] Error handling tested (DB unavailability -> graceful error, no stack trace)
- [ ] Swagger visibility tested (endpoint appears in OpenAPI spec)
- [ ] Rate limiting tested (429 when exceeded)
- [ ] Test pyramid ratio: 70% unit, 20% integration, 10% E2E

---

## Phase 5 — Property-Based Testing

> **Gate:** Every normalization/calculation function has at least one property test with 200+ random cases.

**Checklist:**
- [ ] Properties (invariants) defined for all normalization/calculation functions
- [ ] Framework generates random inputs (200+ cases per property)
- [ ] Shrinking works (framework finds minimal failing case)
- [ ] Common properties tested:
  - [ ] `page <= 0` is always reset to 1
  - [ ] `pageSize > max` is always capped
  - [ ] `offset = (page - 1) * pageSize` never overflows
  - [ ] Consecutive pages never overlap
  - [ ] SQL OFFSET and FETCH values are always valid (>= 0 and > 0)

---

## Phase 6 — Security Testing (OWASP API Top 10)

> **Gate:** All OWASP API Top 10 risks are tested. SQL injection does not execute. No stack traces in error responses.

**Checklist:**
- [ ] API1: Broken Object Level Authorization — cross-tenant access returns 403
- [ ] API2: Broken Authentication — invalid/expired JWT -> 401, invalid API key -> 401
- [ ] API3: Broken Object Property Level Authorization — mass assignment not possible
- [ ] API4: Unrestricted Resource Consumption — rate limiting returns 429
- [ ] API5: Broken Function Level Authorization — non-admin cannot access admin endpoints
- [ ] API6: Unrestricted Access to Sensitive Flows — business flow cannot be bypassed
- [ ] API7: SSRF — server does not follow user-supplied URLs
- [ ] API8: Security Misconfiguration — no stack traces, no server version, CORS correct
- [ ] API9: Improper Inventory Management — no undocumented endpoints accessible
- [ ] API10: Unsafe Consumption of APIs — third-party API responses are validated
- [ ] SQL Injection: `1; DROP TABLE--` in query params -> must not execute
- [ ] XSS: `<script>` in params -> response must be JSON, not HTML
- [ ] Path Traversal: `../../../etc/passwd` -> must return 404
- [ ] HTTP Method Security: POST/DELETE on GET-only endpoint -> 405

See `owasp-api-testing.md` for detailed test implementations.

---

## Phase 7 — Performance Testing

> **Gate:** P95 latency meets target under expected load. Error rate < 0.1%. No memory leaks.

**Checklist:**
- [ ] P50 latency < 500ms
- [ ] P95 latency < 2000ms (health), < 5000ms (DB queries)
- [ ] P99 latency < 10000ms
- [ ] Throughput > 20 req/s
- [ ] Error rate < 0.1%
- [ ] No memory leaks over 1000 requests
- [ ] Tested with realistic load (10-50 concurrent users)
- [ ] P50, P95, P99 percentiles measured

---

## Phase 8 — Code Coverage

> **Gate:** Line coverage >= 80%. Build fails if coverage drops below threshold.

**Checklist:**
- [ ] Coverage tool configured (Coverlet / c8 / coverage.py)
- [ ] Threshold set to 80% line coverage
- [ ] Migrations and test projects excluded from coverage
- [ ] Coverage report generated (HTML / Cobertura)
- [ ] CI build fails if coverage drops below threshold

---

## Phase 9 — Mutation Testing

> **Gate:** Mutation score >= 60% for production release. >= 80% for critical systems.

**Checklist:**
- [ ] Mutation testing tool installed (Stryker.NET / Stryker.js / mutmut)
- [ ] Files to mutate configured (controllers, services, repositories — not Program.cs or migrations)
- [ ] Mutation report reviewed
- [ ] Surviving mutations killed by adding tests
- [ ] Mutation score >= 60% (>= 80% for critical systems)
- [ ] No surviving high-severity mutations in critical paths

**Mutation Score Interpretation:**

| Score | Meaning |
|-------|---------|
| >= 80% | Strong tests |
| 60-79% | Adequate, room for improvement |
| < 60% | Tests are weak — improve before release |

---

## Phase 10 — Regression Suite Stratification

> **Gate:** Smoke passes on every commit. Regression passes on every PR. Full passes before every release.

**Three Tiers:**

| Tier | Category | Duration | When to run | What's included |
|------|----------|----------|-------------|-----------------|
| Smoke | `Smoke` | ~30s | Every commit | Health, swagger, auth login |
| Regression | `Regression` | ~5min | Every PR | All functional tests (unit + BDD + integration) |
| Full | `Full` | ~15min | Nightly / pre-release | + security + performance + mutation |

**Checklist:**
- [ ] Tests categorized with traits/tags (e.g., `[Trait("Category", "Smoke")]`)
- [ ] CI pipeline runs Smoke on every commit
- [ ] CI pipeline runs Regression on every PR
- [ ] Nightly/pre-release pipeline runs Full suite
- [ ] `run-tests.ps1` script configured with `-Stage` parameter

---

## Phase 11 — Production Quality Assurance

> **Gate:** All pre-production checklist items checked. Post-deployment validation passes.

**Pre-production checklist:**
- [ ] Spec approved by product owner and architect
- [ ] Unit tests pass with >= 80% coverage
- [ ] BDD scenarios pass for all acceptance criteria
- [ ] Integration tests pass for all endpoint x tenant combinations
- [ ] Property-based tests pass with 200+ random cases
- [ ] Security tests pass (OWASP API Top 10)
- [ ] Performance tests meet P95 latency targets
- [ ] Mutation score >= 60%
- [ ] No surviving high-severity mutations in critical paths
- [ ] Code review approved by at least one peer
- [ ] No secrets in code (API keys, passwords, connection strings)
- [ ] Error responses do not contain stack traces
- [ ] Swagger/OpenAPI documentation is complete and accurate
- [ ] Rate limiting is configured and tested
- [ ] Logging is configured (no sensitive data logged)
- [ ] CORS is configured correctly (not `AllowAll` in production)
- [ ] JWT expiration is set appropriately
- [ ] Database migrations are reversible
- [ ] Rollback plan is documented and tested

**Post-deployment validation:**
- [ ] Smoke tests run against production endpoint immediately after deploy
- [ ] Error rate monitored for 15 minutes post-deploy
- [ ] Latency P95 monitored for 15 minutes post-deploy
- [ ] Health endpoint returns healthy
- [ ] Swagger accessible (if applicable)
- [ ] Rollback plan ready — if any metric degrades, rollback within 5 minutes

**Production monitoring SLOs:**

| SLO | Target | Alert threshold |
|-----|--------|-----------------|
| Availability | 99.9% | < 99.5% for 5 min |
| P95 latency | < 2s | > 5s for 5 min |
| Error rate | < 0.1% | > 1% for 5 min |
| Rate limit hits | < 5% of requests | > 10% for 10 min |
