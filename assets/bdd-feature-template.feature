# BDD Scenario Template — Gherkin
#
# The @tags below are not decoration: they are how a runner selects a tier.
# A scenario without a tag cannot be selected, so it silently never runs in CI.
#
# Selecting scenarios by tag, per stack:
#   .NET / Reqnroll   dotnet test --filter "Category=Smoke"
#                     (Reqnroll maps a Gherkin @Tag to an xUnit trait; use
#                     whatever attribute your reqnroll.json maps Tag to)
#   Node / Cucumber.js  npx cucumber-js --tags "@Smoke"
#   Python / Behave     behave --tags=@smoke
#
# Tier map, matching the stratification in references/test-pyramid.md:
#   @Smoke        ~30s   every commit   — health, swagger, auth login
#   @Regression   ~5min  every PR       — contract, isolation, pagination, concurrency
#   @SecurityPR   ~5min  every PR       — the security subset that cannot wait for nightly
#   @Security     full   nightly        — the rest of the OWASP API Top 10 probes
#   @Property     full   nightly        — generative / property-based
#
# @SecurityPR is the BOLA / authentication / injection subset: cheap, deterministic
# and a release blocker if it regresses. The selection criterion is in
# references/test-pyramid.md; everything slower stays under @Security.

Feature: [Endpoint Name] for [Tenant/Context]
  As a [role]
  I want to [action]
  So that [business value]

  # --- Smoke tier — run on every commit (~30s) -----------------------------

  @Smoke
  Scenario: Happy Path — authenticated request returns expected fields
    Given the system is running
    And I am authenticated as "TENANT_NAME"
    When I request GET "/api/v1/resource?page=1&pageSize=10"
    Then the response status should be 200
    And the response should contain a JSON array
    And each item should have the following fields:
      | field      | type     |
      | id         | guid     |
      | name       | string   |
      | createdAt  | datetime |

  @Smoke
  Scenario: Health check returns OK
    Given the system is running
    When I request GET "/health"
    Then the response status should be 200

  @Smoke
  Scenario: Swagger is accessible
    Given the system is running
    When I request GET "/swagger/v1/swagger.json"
    Then the response status should be 200
    And the response should contain "openapi"

  # --- Regression tier — run on every PR (~5min) ---------------------------

  @Regression
  Scenario: Response Contract — required fields present, sensitive fields excluded
    Given I am authenticated as "TENANT_NAME"
    When I request GET "/api/v1/resource?page=1&pageSize=10"
    Then each item should match the fields defined in the API contract
    And the response should not expose internal fields

  # This is the BOLA probe (API1). It is a functional isolation test, so
  # @Regression already runs it on every PR — that is the SecurityPR criterion.
  @Regression
  Scenario: Tenant Isolation — tenant A cannot see tenant B's data
    Given I am authenticated as "TENANT_A"
    When I request GET "/api/v1/resource?page=1&pageSize=10"
    Then the response status should be 200
    And the response should not contain any item with tenantId "TENANT_B"

  @Regression
  Scenario: Non-authorized tenant is rejected
    Given I am authenticated as "TENANT_WITHOUT_FEATURE"
    When I request GET "/api/v1/resource?page=1&pageSize=10"
    Then the response status should be 403
    And the response should contain "Forbidden"

  @Regression
  Scenario: Error Handling — DB unavailable returns graceful error
    Given the database is unavailable
    And I am authenticated as "TENANT_NAME"
    When I request GET "/api/v1/resource?page=1&pageSize=10"
    Then the response status should be 500
    And the response should not contain "StackTrace"
    And the response should not contain "at System."

  @Regression
  Scenario: Pagination — page 1 returns most recent items
    Given I am authenticated as "TENANT_NAME"
    When I request GET "/api/v1/resource?page=1&pageSize=10"
    Then the response should contain 10 items
    And the items should be ordered by "createdAt" descending

  @Regression
  Scenario: Pagination — page size cap is enforced
    Given I am authenticated as "TENANT_NAME"
    When I request GET "/api/v1/resource?page=1&pageSize=100000"
    Then the response should contain at most 100 items

  @Regression
  Scenario: Rate limiting — exceeding limit returns 429
    Given I am authenticated as "TENANT_NAME"
    When I make 150 rapid requests to GET "/api/v1/resource?page=1&pageSize=10"
    Then at least one response should have status 429
    And the 429 response should contain a "Retry-After" header

  # --- Concurrency — run on every PR, with the Regression tier -------------
  # See references/concurrency-and-idempotency.md

  @Concurrency
  Scenario: Double submit — two identical requests create exactly one order
    Given I am authenticated as "TENANT_NAME"
    When I send 8 identical POST "/api/v1/orders" requests at the same instant
    Then exactly one response should have status 201
    And the other 7 responses should have status 409
    And the database should contain exactly 1 order with externalRef "ORDER-1"

  @Concurrency
  Scenario: Retry — the same idempotency key produces one effect
    Given I am authenticated as "TENANT_NAME"
    When I send POST "/api/v1/payments" twice with the idempotency key "key-1"
    Then both responses should have status 201
    And both responses should contain the same payment id
    And the database should contain exactly 1 payment with key "key-1"

  @Concurrency
  Scenario: Replayed webhook — a signed payload delivered twice is ignored
    Given the provider sends a signed webhook with eventId "evt_1"
    When the same signed payload is delivered again
    Then the second response should have status 409
    And the event "evt_1" should have been processed exactly once

  # --- SecurityPR — the security subset that runs on every PR --------------

  @SecurityPR
  Scenario: SQL Injection — malicious input does not execute
    Given I am authenticated as "TENANT_NAME"
    When I request GET "/api/v1/resource?filter=1; DROP TABLE--"
    Then the response status should be one of: 400, 200
    And the database table should still exist

  @SecurityPR
  Scenario: XSS — script tags are not rendered
    Given I am authenticated as "TENANT_NAME"
    When I send a request with "<script>alert('xss')</script>" in the name field
    Then the response content type should be "application/json"
    And the response should not contain "<script>"

  @SecurityPR
  Scenario: Path Traversal — directory traversal is blocked
    Given I am authenticated as "TENANT_NAME"
    When I request GET "/api/v1/files/../../../etc/passwd"
    Then the response status should be 404

  # --- Security tier — run in the Full tier (~15min) -----------------------

  @Security
  Scenario: HTTP Method Security — POST on GET-only endpoint returns 405
    Given I am authenticated as "TENANT_NAME"
    When I send POST "/api/v1/resource"
    Then the response status should be 405
    And the response should contain an "Allow" header

  # --- Property tier — run in the Full tier --------------------------------

  @Property
  Scenario Outline: Pagination offset is always valid
    Given I am authenticated as "TENANT_NAME"
    When I request GET "/api/v1/resource?page=<page>&pageSize=<pageSize>"
    Then the offset should be "(<page> - 1) * <pageSize>"
    And the offset should be >= 0

    Examples:
      | page | pageSize |
      | 1    | 10       |
      | 2    | 20       |
      | 0    | 10       |
      | -1   | 10       |
      | 1    | 0        |
      | 1    | -1       |
      | 999  | 100      |
