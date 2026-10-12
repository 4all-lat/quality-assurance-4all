# Quality Gates Reference

Consolidated quality gates for each phase of the QA pipeline. Each gate must pass before moving to the next phase.

## Canonical Thresholds

**This table is the single source for every numeric threshold in the pipeline.** When a gate below,
`SKILL.md`, `pre-production-checklist.md`, `performance-testing.md`, `tools-by-stack.md`, the
scaffolder or `README.md` quotes a number, it must match this table — including the unit and the
spelling of the metric. `tests/cases/docs.thresholds.test.sh` fails the build when a file states one
of these metrics with a different value.

| Metric | Canonical value | Gate |
|--------|-----------------|------|
| Line coverage | `>= 80%` | Phase 2, Phase 8 |
| New-code coverage | `>= 80%` | Phase 8, SonarQube gate |
| Mutation score | `>= 60%` (`>= 80%` for critical paths) | Phase 9 |
| Property-based cases | `>= 200` per property | Phase 5 |
| Test pyramid mix | `70% unit / 20% integration / 10% e2e` | Phase 10 |
| Tier budget — Smoke | `< 30s` | every commit |
| Tier budget — Regression | `< 5min` | every PR |
| Tier budget — Full | `< 15min` | nightly / pre-release |
| P50 latency | `< 500ms` | Phase 7 |
| P95 latency | `< 2000ms` (health), `< 5000ms` (DB queries) | Phase 7, SLO |
| P99 latency | `< 10000ms` | Phase 7 |
| Throughput | `> 20 req/s` | Phase 7 |
| Error rate | `< 0.1%` | Phase 7, SLO |
| Memory | no leak over `1000` requests | Phase 7 |
| Availability (SLO) | `99.9%` | Phase 11 |
| Rate limit hits (SLO) | `< 5%` of requests | Phase 11 |
| Duplicated lines on new code | `<= 3%` | SonarQube gate |
| Security hotspots reviewed | `100%` | Phase 6, SonarQube gate |
| Ratings on new code (maintainability, reliability, security) | `A` | SonarQube gate |

Spelling to use: `>=` for minimums, `<` for maximums, `ms` for milliseconds, `%` for percentages —
never `2s` for `2000ms`, never `0%` for `< 0.1%`.

The static-analysis platform (SonarQube) is held to the same table. Its quality gate is stored as an
artifact — [`assets/sonar-quality-gate.json`](../assets/sonar-quality-gate.json) — and
`tests/cases/docs.thresholds.test.sh` fails when that file and this table disagree. The gate
reproduces these numbers; it never becomes their source.

---

## Phase 1 — Specification (SDD)

> **Gate:** No code is written until the spec is reviewed and approved, and its abuse cases are
> walked.

**Checklist:**
- [ ] Functional requirement documented (business context, expected behavior, acceptance criteria)
- [ ] Technical contract defined (API endpoints, DTOs, DB tables, data flow)
- [ ] Edge cases matrix completed (test scenarios, expected results, error handling)
- [ ] Abuse cases recorded — one row per trust boundary the change adds or crosses
- [ ] Threat model walked with STRIDE (spoofing, tampering, repudiation, information disclosure, denial of service, elevation of privilege)
- [ ] Untrusted inputs identified, including those coming from other internal services
- [ ] Concurrent paths identified (simultaneous identical requests, client retries, duplicate delivery)
- [ ] Accepted risks written down with their reason — an undocumented acceptance is an unnoticed one
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

> **Gate:** All endpoints x all tenants matrix is tested. Data isolation is verified by content, not
> just status codes. Every state-changing endpoint is exercised twice and concurrently, with exactly
> one effect.

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

**Concurrency and idempotency** — every state-changing endpoint, marked `Concurrency` so the
Regression tier runs it. Full guide: [`concurrency-and-idempotency.md`](concurrency-and-idempotency.md).

- [ ] Retrying with the same idempotency key produces one effect and replays the first response
- [ ] The same key with a different body returns 409, and keys are scoped per tenant
- [ ] Simultaneous identical submits (barrier-synchronised) create exactly one record
- [ ] A stale update is rejected with a conflict rather than silently overwriting
- [ ] Check-then-act flows (stock, balance, quota) hold their invariant under concurrent access
- [ ] A replayed signed webhook — same body, or outside the timestamp window — is rejected
- [ ] Paging while rows are inserted serves no row twice and skips none (keyset cursor, not `OFFSET`)
- [ ] These tests run against the real database engine, not an in-memory provider

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

> **Gate:** All OWASP API Top 10 risks are tested. SQL injection does not execute. No stack traces in
> error responses. No `high` or `critical` finding survives any of the four scans below.

The phase has two halves. The dynamic half (below) drives a running system and only the Full tier
can afford it. The static half — **Security Scanning** — reads source, manifests and history, needs
nothing deployed, and therefore runs on every PR.

**Dynamic tests — checklist:**
- [ ] API1: Broken Object Level Authorization — cross-tenant access returns 403
- [ ] API2: Broken Authentication — invalid/expired JWT -> 401, invalid API key -> 401
- [ ] API2 (lifecycle): a token that expires *during* a session is rejected on the next call
- [ ] API2 (lifecycle): refresh tokens rotate, and replaying a rotated one is detected and revokes the family
- [ ] API2 (lifecycle): logout revokes the refresh token server-side — the old value stops working
- [ ] API2 (lifecycle): a password change invalidates every token issued before it
- [ ] API2 (crypto): `alg=none` and algorithm confusion are rejected; a token signed with the public key fails
- [ ] API2 (crypto): a tampered signature is rejected, and `kid` injection cannot select a key the caller supplies
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
- [ ] `SecurityPR` subset (BOLA, authentication lifecycle, injection) tagged so the PR tier runs it — see the selection criterion in `test-pyramid.md`

See `owasp-api-testing.md` for detailed test implementations.

### Security Scanning (static — every PR, not release-only)

These four scans need no deployed system, which is exactly why they cannot be postponed to the
nightly tier: a vulnerable dependency or a leaked key is committed once and stays in the history.

| Scan | Scope | Fails the build on | Command |
|------|-------|--------------------|---------|
| Dependencies (SCA) | Direct **and** transitive, every PR | any `high` or `critical` advisory | `dotnet list package --vulnerable --include-transitive` · `npm audit --audit-level=high` · `pip-audit` |
| Secrets | The diff and the **full history** | any hit | `gitleaks detect --redact` · `trufflehog git file://. --only-verified` |
| SAST | Source, every PR | any `high` or `critical` finding | Roslyn analyzers · `eslint-plugin-security` · `bandit -r src` |
| SBOM | Every release artifact | missing or unattached SBOM | `dotnet CycloneDX` · `npm sbom` · `cyclonedx-py` |

**Checklist:**
- [ ] Dependency scan wired into the PR pipeline with transitive resolution
- [ ] Dependency scan clean — no `high`/`critical` advisory
- [ ] Secret scan clean on the diff
- [ ] Secret scan clean on the full history (a secret that was ever committed is compromised)
- [ ] SAST clean at `high`/`critical`; every surviving finding has a dated waiver and an owner
- [ ] SBOM generated per release and attached to the artifact
- [ ] Container image scanned, if the service ships in a container
- [ ] Static-analysis platform (SonarQube) gate green on the changed lines — duplication, complexity
      and the ratings of the new code, which no other scan measures — see [`sonarqube.md`](sonarqube.md)
- [ ] Every `Medium` finding triaged into the tracker with an owner and a date

See `tools-by-stack.md` (Security section per stack) for the exact command lines.

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
- [ ] Coverage tool configured (Coverlet / @vitest/coverage-v8 / coverage.py)
- [ ] Threshold set to 80% line coverage
- [ ] Migrations and test projects excluded from coverage
- [ ] Coverage report generated (HTML / Cobertura)
- [ ] CI build fails if coverage drops below threshold
- [ ] The same report feeds the static-analysis platform, so the new-code coverage condition is
      measured on real data instead of reporting 0% — see [`sonarqube.md`](sonarqube.md)

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
| Regression | `Regression` | ~5min | Every PR | All functional tests (unit + BDD + integration + concurrency) + the `SecurityPR` subset |
| Full | `Full` | ~15min | Nightly / pre-release | + the full security suite, the static scans, performance and mutation |

**Checklist:**
- [ ] Tests categorized with traits/tags (e.g., `[Trait("Category", "Smoke")]`)
- [ ] CI pipeline runs Smoke on every commit
- [ ] CI pipeline runs Regression on every PR
- [ ] Nightly/pre-release pipeline runs Full suite
- [ ] `run-tests.sh` / `run-tests.ps1` script configured with the stage parameter
- [ ] Duration budget **enforced**, not merely documented: the runner is invoked with `--enforce-budget`, so Smoke over 30s / Regression over 5min / Full over 15min fails the build
- [ ] The untiered stages (`-s Sonar`) run after the tiers in the same pipeline: an analysis is not a
      test tier, and it must not be counted against a tier budget
- [ ] No flaky test survives a cycle — each is fixed or quarantined with an owner and a date
- [ ] No test is skipped or ignored without a documented reason

---

## Phase 11 — Production Quality Assurance

> **Gate:** All pre-production checklist items checked. Post-deployment validation passes.

**Pre-production checklist & post-deployment validation:**
See [`assets/pre-production-checklist.md`](../assets/pre-production-checklist.md) — the sign-off-ready
checklist covering tests, security, configuration, database, deployment & rollback, monitoring, and
post-deployment validation. Use it as the single operational source at release time.

**Production monitoring SLOs (single source):**

| SLO | Target | Alert threshold |
|-----|--------|-----------------|
| Availability | 99.9% | < 99.5% for 5 min |
| P95 latency | < 2000ms | > 5000ms for 5 min |
| Error rate | < 0.1% | > 1% for 5 min |
| Rate limit hits | < 5% of requests | > 10% for 10 min |

---

## Static Analysis Platform (SonarQube)

A cross-cutting gate rather than a phase: it reads the coverage report Phase 8 produces, adds the
static findings Phase 6 already scans for, and contributes the one family of metrics no other phase
measures — duplication, cognitive complexity, code smells and the ratings of the changed lines. The
full setup, per stack, is in [`sonarqube.md`](sonarqube.md).

> **Gate:** The analysis runs on every PR, the quality gate reproduces the canonical table above —
> it does not define its own numbers — and no new issue on the changed lines reaches release
> untriaged.

**Checklist:**
- [ ] Gate created from [`assets/sonar-quality-gate.json`](../assets/sonar-quality-gate.json) through the API, so a fresh server gets the same gate
- [ ] Gate conditions match the canonical table; the analysis fails the build when the gate fails (`sonar.qualitygate.wait=true`)
- [ ] Coverage report produced inside the analysis window — inside the `begin`/`end` block for .NET, never reused from an earlier run
- [ ] Scope set to new code, so a legacy codebase can adopt the gate without a freeze or a mass waiver
- [ ] Every surviving finding has an owner and a date; "won't fix" with neither is not a waiver
- [ ] The gate is a required check on the default branch
- [ ] On the Community Edition, the gate runs on the main branch — it cannot decorate a PR, so it is not wired as one
- [ ] The dynamic OWASP suite still runs: a green gate is not a substitute for Phase 6

---

## UI Quality (front-end deliverables)

A cross-cutting gate, because it applies to whatever phase produced the screen. Practices and
tooling live in [`quality-engineering-practices.md`](quality-engineering-practices.md); this is the
gate that has to pass.

> **Gate:** An automated accessibility audit reports no new violations, the changed screens have
> been through visual regression with every difference reviewed, and the critical flows work by
> keyboard alone.**

**Checklist:**
- [ ] Accessibility scan wired into CI (axe / Lighthouse CI / Pa11y) and failing on new violations
- [ ] Keyboard-only pass over every changed flow — nothing reachable only by pointer
- [ ] Screen-reader pass over the primary flow of the change
- [ ] Every interactive element has an accessible name and a visible focus indicator
- [ ] Heading order and landmarks are correct; form fields are labelled and errors associated
- [ ] Colour contrast meets WCAG AA (4.5:1 for body text)
- [ ] Visual regression captures every changed screen, at fixed viewports and with animations disabled
- [ ] Every visual difference is reviewed and approved — never mass-accepted
- [ ] Responsive breakpoints verified (phone, tablet, desktop)
- [ ] No console errors during the critical flows
