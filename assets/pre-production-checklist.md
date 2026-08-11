# Pre-Production Quality Checklist

> Complete every item before deploying to production.
> This checklist is the quality gate for Phase 11 of the QA pipeline.

## Spec & Review

- [ ] **Spec approved** by product owner and architect
- [ ] **Acceptance criteria** are all met and verified
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

## Property-Based Tests

- [ ] **All normalization/calculation functions have property tests**
- [ ] **200+ random cases per property**
- [ ] **All property tests pass**

## Security Tests

- [ ] **API1: BOLA** — cross-tenant access returns 403
- [ ] **API2: Broken Auth** — invalid/expired JWT -> 401, invalid API key -> 401
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
  - [ ] P95 latency > 5s for 5 min
  - [ ] Error rate > 1% for 5 min
  - [ ] Rate limit hits > 10% for 10 min
- [ ] **Dashboard** created for key metrics

## Production Monitoring SLOs

| SLO | Target | Alert threshold |
|-----|--------|-----------------|
| Availability | 99.9% | < 99.5% for 5 min |
| P95 latency | < 2s | > 5s for 5 min |
| Error rate | < 0.1% | > 1% for 5 min |
| Rate limit hits | < 5% of requests | > 10% for 10 min |

## Post-Deployment Validation

- [ ] **Run smoke tests** against production endpoint immediately after deploy
- [ ] **Monitor error rate** for 15 minutes post-deploy
- [ ] **Monitor latency P95** for 15 minutes post-deploy
- [ ] **Check health endpoint** returns healthy
- [ ] **Verify Swagger** is accessible (if applicable)
- [ ] **Rollback plan ready** — if any metric degrades, rollback within 5 minutes

---

## Sign-off

| Role | Name | Date | Signature |
|------|------|------|-----------|
| Product Owner | | | |
| Tech Lead | | | |
| QA Lead | | | |
| DevOps | | | |
