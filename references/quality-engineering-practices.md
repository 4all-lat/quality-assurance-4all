# Quality Engineering Practices

Practical practices that keep a test suite healthy over time: flaky test management, test data
management, accessibility testing, visual regression, code review checklist, and Definition of Done.

## 1. Flaky Test Management

A flaky test passes and fails intermittently without code changes. Flaky tests destroy trust in the
suite and hide real regressions.

### Causes and fixes

| Cause | Detection | Fix |
|-------|-----------|-----|
| Timing / race conditions | Test passes alone, fails in parallel | Use deterministic waits, `await` polling helpers; avoid `Task.Delay(500)` |
| Shared state between tests | Tests pass in isolation, fail in full run | Fresh state per test (fixtures/reset), no shared static/DB rows |
| Unordered DB data | Assertions on `First()` | Query with explicit `ORDER BY` and assert on a set |
| External service dependency | Fails when the service is slow/down | Contract-test it instead; stub in functional tests |
| Port/resource contention | Only fails under load | Isolate the test environment; unique ports/queues |

### Strategy

1. **Quarantine**: move suspected tests to a `Flaky` category instead of deleting or ignoring silently.
2. **Retry policy** (last resort): allow a bounded retry in CI, but flag the test for fixing.
3. **Track flakiness**: mark every test with the owning team/area so flaky reports reach the right owner.
4. **Ban silent skip/ignore**: a skipped test needs a documented reason and a tracking issue.

```python
# pytest: strict markers so typos fail loudly
[pytest]
markers =
    flaky: intermittently failing, investigate and fix
addopts = -W error::pytest.PytestUnhandledCoroutineWarning
```

## 2. Test Data Management

Tests need data that is **deterministic, isolated, and cheap to create**.

### Principles

- **Factories over fixtures dumps**: create objects in code with explicit defaults instead of relying
  on a shared SQL dump.
- **Transactional rollback**: wrap tests in a transaction and roll back, or truncate per test class.
- **Per-tenant isolation**: seed data scoped to the test tenant so parallel runs never collide.
- **No production-shaped PII**: use synthetic values (`john@example.com`), not copied customer data.

```csharp
public static class ItemFactory
{
    public static Item Create(int? id = null, string tenant = "TENANT_A")
        => new Item
        {
            Id = id ?? Guid.NewGuid(),
            TenantId = tenant,
            Name = $"Item-{Guid.NewGuid():N}",
            CreatedAt = DateTime.UtcNow
        };
}
```

### Test data anti-patterns

| Anti-pattern | Problem |
|--------------|---------|
| One giant shared seed DB | Tests depend on each other's data |
| Random real-looking data committed to repo | Coupling, drift, PII risk |
| Tests that create data via the live API | Slow, coupled to API behavior |
| Test data mixed with schema migrations | Migration + seed coupling surprises |

## 3. Accessibility (a11y) Testing

Web/UI quality is not complete until keyboard navigation, screen readers, and contrast work.

| Stack | Tool |
|-------|------|
| .NET (Playwright) | `axe-core` injected via Playwright |
| Node.js/TS (Playwright) | `@axe-core/playwright` |
| Python (Playwright/Selenium) | `axe-core` / `pa11y` (HTML) |

```typescript
// @axe-core/playwright — on every rendered route
import AxeBuilder from '@axe-core/playwright';

test('index page has no detectable a11y violations', async ({ page }) => {
  await page.goto('/');
  const results = await new AxeBuilder({ page }).analyze();
  expect(results.violations).toEqual([]);
});
```

Run as a `Security`-adjacent category in the Full tier; smoke only checks critical routes.

## 4. Visual Regression Testing

Verifies UI does not change beyond intent. Pairs with functional E2E: functional checks *behavior*,
visual checks *appearance*.

| Stack | Tool |
|-------|------|
| Node.js/TS | Playwright `toHaveScreenshot()`, Percy |
| .NET / Python | Playwright screenshots + image diff in CI |

**Tips**

- Take screenshots at fixed viewports (mobile 390px, desktop 1280px).
- Mask dynamic regions (dates, user avatars, random ids) before diffing.
- Approve intentional changes via baseline update, never by ignoring diffs.

## 5. Code Review Checklist

Use the checklist below alongside the automated gates to catch what tests can't.

- [ ] The change matches the approved spec and updates the spec when behavior changes
- [ ] Tests are behavior-oriented, not implementation-oriented (no assertions on private helpers/mocks overdone)
- [ ] New public methods have unit tests; new boundaries have contract/integration tests
- [ ] Error paths and edge cases (null, empty, boundary) are tested, not just the happy path
- [ ] No secrets, connection strings, or tokens in code or test data
- [ ] Logging added/updated does not capture sensitive data
- [ ] Public API/DTO changes are reflected in OpenAPI docs and consumers
- [ ] Migrations are reversible and tested against a copy of staging data
- [ ] Performance-sensitive paths have a baseline or a marked performance test

## 6. Definition of Done (DoD)

A single DoD makes "done" unambiguous across the team. Adapt thresholds to the project.

**Every user story / change is done when:**
- [ ] Spec section for the change is updated and reviewed
- [ ] Unit tests pass with coverage on the new code (≥ 80% line, project threshold)
- [ ] BDD scenarios added/updated for acceptance criteria and passing
- [ ] Integration/contract tests added for new boundaries (new endpoints × tenants)
- [ ] Security tests cover new endpoints (auth, authz, injection, no stack traces)
- [ ] Mutation score threshold met on the changed area
- [ ] Feature is smoke-tested against a real environment, not just in-memory
- [ ] No flaky-test quarantine added, and existing quarantined tests are green
- [ ] Documentation/OpenAPI updated
- [ ] Rollback plan confirmed for the release

## Quality gate

> **No test is left flaky or silently skipped. Every feature ships with deterministic, isolated test
> data. Primary UI routes pass a11y checks. Visual baselines are reviewed in every PR. The DoD
> checklist is the gate for closing a work item.**
