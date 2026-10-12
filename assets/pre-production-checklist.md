# Pre-Production Quality Checklist

> Complete every item before deploying to production.
> This checklist is the quality gate for Phase 11 of the QA pipeline.

## Spec & Review

- [ ] **Spec approved** by product owner and architect
- [ ] **Acceptance criteria** are all met and verified
- [ ] **Abuse cases recorded** — the spec names the realistic ways this change can be abused
- [ ] **Threat model walked** (STRIDE or equivalent) and its mitigations are implemented, or the residual risk is accepted in writing
- [ ] **Code review** approved by at least one peer
- [ ] **Open questions** from spec are all resolved

## Unit Tests

- [ ] **All unit tests pass**
- [ ] **Line coverage >= 80%** (enforced by CI)
- [ ] **Edge cases covered**: null inputs, empty collections, boundary values
- [ ] **No skipped/ignored tests** without a documented reason

## BDD Scenarios

- [ ] **All acceptance criteria have at least one BDD scenario**
- [ ] **All BDD scenarios pass**
- [ ] **Scenarios reviewed** by product owner

## Integration Tests

- [ ] **All endpoints x all tenants matrix tested**
- [ ] **Data isolation verified by content** (not just status codes)
- [ ] **Authentication tested** (valid/invalid credentials, JWT, API key)
- [ ] **Authorization tested** (tenant feature gating, 403 for disabled features)
- [ ] **Pagination tested** (page 1 vs page 2, page size cap, offset calculation)
- [ ] **Error handling tested** (DB unavailability -> graceful error, no stack trace)
- [ ] **Swagger visibility tested** (endpoint appears in OpenAPI spec)
- [ ] **Rate limiting tested** (429 when exceeded)

## Concurrency & Idempotency

Full guide: [`references/concurrency-and-idempotency.md`](../references/concurrency-and-idempotency.md).

- [ ] **Retry with an idempotency key** produces one effect and replays the first response
- [ ] **Same key, different body** is rejected (409) rather than silently applied a second time
- [ ] **Double submit** — simultaneous identical requests create exactly one record
- [ ] **Concurrent edits** — a stale write is rejected with a conflict, not silently overwritten
- [ ] **Check-then-act flows** (stock, balance, quota) hold their invariant under concurrent access
- [ ] **Signed webhooks** cannot be replayed — same body, or outside the timestamp window
- [ ] **Pagination during concurrent inserts** serves no row twice and skips none
- [ ] **Against the real database engine** — not an in-memory provider, which hides the race
- [ ] **Uniqueness constraints** back every rule the application also checks in code

## UI Quality

Only when the deliverable has a user interface. Practices and tooling:
[`references/quality-engineering-practices.md`](../references/quality-engineering-practices.md).

- [ ] **Automated accessibility audit passes** — axe / Lighthouse / Pa11y, with no new violations
- [ ] **Manual pass done** — keyboard-only navigation and one screen reader run over the changed flows
- [ ] **Every interactive element** is reachable by keyboard, has an accessible name, and shows visible focus
- [ ] **Semantic structure** — headings in order, landmarks present, form fields labelled with errors associated
- [ ] **Colour contrast** meets WCAG AA (4.5:1 for text)
- [ ] **Visual regression run** — every changed screen captured and compared
- [ ] **Visual differences reviewed and approved**, not mass-accepted
- [ ] **Responsive breakpoints verified** at phone, tablet and desktop widths
- [ ] **No console errors** in the browser during the critical flows

## Property-Based Tests

- [ ] **All normalization/calculation functions have property tests**
- [ ] **200+ random cases per property**
- [ ] **All property tests pass**

## Security Tests

- [ ] **API1: BOLA** — cross-tenant access returns 403
- [ ] **API2: Broken Auth** — invalid/malformed/expired JWT -> 401, invalid API key -> 401
- [ ] **API2: Session expiry** — a token that expires *during* a session is rejected on the next call
- [ ] **API2: Refresh rotation** — refresh tokens rotate, and replaying a rotated one is detected and revokes the family
- [ ] **API2: Revocation** — logout revokes the refresh token server-side; the old value stops working
- [ ] **API2: Password change** — every token issued before a password change is invalidated
- [ ] **API2: Algorithm confusion** — `alg=none` is rejected, and a token signed with the public key does not validate
- [ ] **API2: Signature and `kid`** — a tampered signature is rejected, and `kid` injection cannot select a key the caller supplies
- [ ] **API3: Property Level Auth** — mass assignment not possible
- [ ] **API4: Resource Consumption** — rate limiting returns 429
- [ ] **API5: Function Level Auth** — non-admin cannot access admin endpoints
- [ ] **API6: Sensitive Flows** — business flow cannot be bypassed
- [ ] **API7: SSRF** — server does not follow user-supplied URLs
- [ ] **API8: Security Misconfiguration** — no stack traces, no server version, CORS correct
- [ ] **API9: Inventory Management** — no undocumented endpoints accessible
- [ ] **API10: Unsafe Consumption** — third-party API responses are validated
- [ ] **SQL Injection** — `1; DROP TABLE--` does not execute
- [ ] **XSS** — `<script>` in params -> JSON response, not HTML
- [ ] **Path Traversal** — `../../../etc/passwd` -> 404
- [ ] **HTTP Method Security** — POST/DELETE on GET-only endpoint -> 405

## Security Scanning (Non-Intrusive)

These four scans read source, manifests and history — they need nothing deployed, so they run on
every PR rather than at release only. The checklist records their state at sign-off.

- [ ] **Dependency scan clean** — no `high` or `critical` advisory in direct or transitive dependencies
- [ ] **Dependency scan uses transitive resolution** (`--include-transitive` / `--audit-level=high` / `pip-audit`)
- [ ] **Secret scan clean on the diff** — no credential in this changeset
- [ ] **Secret scan clean on the full history** — no credential was ever committed
- [ ] **SAST clean at `high`/`critical`** — every surviving finding has a dated waiver and an owner
- [ ] **SBOM generated for this release** and attached to the release artifact
- [ ] **Container image scanned**, if the service ships in a container
- [ ] **`Medium` findings triaged** — each has an owner and a date, or a written acceptance

## Static Analysis & Quality Gate (SonarQube)

The static-analysis platform aggregates the reports above and adds the one family of metrics no
other section measures: duplication, cognitive complexity and the ratings of the changed code. The
quality gate must reproduce the canonical thresholds — it does not define them. Setup:
[`references/sonarqube.md`](../references/sonarqube.md).

- [ ] **Gate created from `assets/sonar-quality-gate.json`** through the API, so a fresh server gets the same gate instead of a hand-made one
- [ ] **Gate conditions match the canonical table** — `assets/sonar-quality-gate.json` and `references/quality-gates.md` agree
- [ ] **The analysis fails the build when the gate fails** — `sonar.qualitygate.wait=true`, so a queued analysis is never reported as a pass
- [ ] **Coverage report produced inside the analysis window** — inside `begin`/`end` for .NET; a report from an earlier run is not picked up and the gate measures 0%
- [ ] **New-code scope configured**, so the gate applies to the change and not to the whole legacy codebase
- [ ] **Duplication and complexity reviewed** on the changed files — the gate enforces the number, a human reads the reason
- [ ] **Security hotspots reviewed at 100%** on the new code; each closed with a reason, not a bulk dismissal
- [ ] **Every surviving finding has an owner and a date** — "won't fix" without either is not a waiver
- [ ] **Gate is a required check** on the default branch
- [ ] **Edition limits acknowledged** — on the Community Edition the gate runs on the main branch and cannot decorate a PR
- [ ] **The dynamic OWASP suite still ran** — a green gate is not a substitute for the security tests

## Performance Tests

- [ ] **P50 latency < 500ms**
- [ ] **P95 latency < 2000ms** (health), < 5000ms (DB queries)
- [ ] **P99 latency < 10000ms**
- [ ] **Throughput > 20 req/s**
- [ ] **Error rate < 0.1%**
- [ ] **No memory leaks** over 1000 requests
- [ ] **Tested with realistic load** (10-50 concurrent users)

## Code Coverage

- [ ] **Line coverage >= 80%**
- [ ] **Coverage report generated** (HTML / Cobertura)
- [ ] **CI build fails if coverage drops below threshold**
- [ ] **Migrations and test projects excluded** from coverage

## Mutation Testing

- [ ] **Mutation score >= 60%** (>= 80% for critical systems)
- [ ] **No surviving high-severity mutations** in critical paths
- [ ] **Mutation report reviewed**

## Test Suite Health

The suite is a gate only while it is fast and trustworthy. A tier that quietly grows past its
budget gets skipped by developers, and a suite that fails intermittently gets ignored — both turn
the pipeline back into decoration.

- [ ] **Tier budgets respected** — Smoke < 30s, Regression < 5min, Full < 15min
- [ ] **Budgets enforced in CI** — the runner is invoked with `--enforce-budget`, so an overrun fails the build rather than printing a number nobody reads
- [ ] **No flaky tests** — anything that failed intermittently in the last cycle is fixed or quarantined with an owner and a date
- [ ] **No skipped or ignored tests** without a documented reason
- [ ] **The suite is deterministic** — the same commit produces the same result on a rerun

## Security & Configuration

- [ ] **No secrets in code** (API keys, passwords, connection strings)
- [ ] **Secrets in vault/env vars** (Azure Key Vault, AWS Secrets Manager, etc.)
- [ ] **Error responses do not contain stack traces**
- [ ] **Swagger/OpenAPI documentation is complete and accurate**
- [ ] **Rate limiting is configured and tested**
- [ ] **Logging is configured** (no sensitive data logged)
- [ ] **CORS is configured correctly** (not `AllowAll` in production)
- [ ] **JWT expiration is set appropriately**
- [ ] **HTTPS is enforced**
- [ ] **Security headers present** (X-Content-Type-Options, X-Frame-Options, etc.)

## Database

- [ ] **Database migrations are reversible**
- [ ] **Migrations tested** in staging environment
- [ ] **Connection strings** use env vars or secret vault
- [ ] **No hardcoded SQL** outside of repository layer

## Deployment & Rollback

- [ ] **Rollback plan is documented**
- [ ] **Rollback plan is tested** in staging
- [ ] **Deployment script is versioned** in repository
- [ ] **Health check endpoint** returns healthy after deploy
- [ ] **Post-deployment smoke tests** ready to run

## Monitoring & Observability

- [ ] **Structured logging** configured (JSON with correlation IDs)
- [ ] **Health checks** endpoint with DB connectivity check
- [ ] **Alerts configured** for:
  - [ ] Availability < 99.5% for 5 min
  - [ ] P95 latency > 5000ms for 5 min
  - [ ] Error rate > 1% for 5 min
  - [ ] Rate limit hits > 10% for 10 min
- [ ] **Dashboard** created for key metrics

## Production Monitoring SLOs

SLO targets and alert thresholds are consolidated in [`references/quality-gates.md`](../references/quality-gates.md) (Phase 11).

## Post-Deployment Validation

- [ ] **Run smoke tests** against production endpoint immediately after deploy
- [ ] **Monitor error rate** for 15 minutes post-deploy
- [ ] **Monitor latency P95** for 15 minutes post-deploy
- [ ] **Check health endpoint** returns healthy
- [ ] **Verify Swagger** is accessible (if applicable)
- [ ] **Rollback plan ready** — if any metric degrades, rollback within 5 minutes

---

## Sign-off

The signatures below attest to the state of **this commit**, not of an earlier one: the quality gate
and the tier budgets are read from the run against the commit that is being released.

- [ ] **Quality gate green on the release commit** — SonarQube's gate passed on this revision
- [ ] **Tier budgets green on the release commit** — Smoke, Regression and Full ran within budget

| Role | Name | Date | Signature |
|------|------|------|-----------|
| Product Owner | | | |
| Tech Lead | | | |
| QA Lead | | | |
| DevOps | | | |
