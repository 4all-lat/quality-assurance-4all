Feature: [Endpoint Name] for [Tenant/Context]
  As a [role]
  I want to [action]
  So that [business value]

  # Smoke Scenarios — run on every commit (~30s)

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

  Scenario: Health check returns OK
    Given the system is running
    When I request GET "/health"
    Then the response status should be 200

  Scenario: Swagger is accessible
    Given the system is running
    When I request GET "/swagger/v1/swagger.json"
    Then the response status should be 200
    And the response should contain "openapi"

  # Regression Scenarios — run on every PR (~5min)

  Scenario: Column Exclusion — sensitive columns are not returned
    Given I am authenticated as "TENANT_NAME"
    When I request GET "/api/v1/resource?page=1&pageSize=10"
    Then the response should not contain "ExpirationDate"
    And the response should not contain "FabricationDate"
    And the response should not contain "SealNumber"

  Scenario: Tenant Isolation — tenant A cannot see tenant B's data
    Given I am authenticated as "TENANT_A"
    When I request GET "/api/v1/resource?page=1&pageSize=10"
    Then the response status should be 200
    And the response should not contain any item with tenantId "TENANT_B"

  Scenario: Non-authorized tenant is rejected
    Given I am authenticated as "TENANT_WITHOUT_FEATURE"
    When I request GET "/api/v1/resource?page=1&pageSize=10"
    Then the response status should be 403
    And the response should contain "Forbidden"

  Scenario: Error Handling — DB unavailable returns graceful error
    Given the database is unavailable
    And I am authenticated as "TENANT_NAME"
    When I request GET "/api/v1/resource?page=1&pageSize=10"
    Then the response status should be 500
    And the response should not contain "StackTrace"
    And the response should not contain "at System."

  Scenario: Read-Only Guarantee — no DML operations
    Given I am authenticated as "TENANT_NAME"
    When I request GET "/api/v1/resource?page=1&pageSize=10"
    Then no INSERT, UPDATE, or DELETE should have been executed on the database

  Scenario: Pagination — page 1 returns most recent items
    Given I am authenticated as "TENANT_NAME"
    When I request GET "/api/v1/resource?page=1&pageSize=10"
    Then the response should contain 10 items
    And the items should be ordered by "createdAt" descending

  Scenario: Pagination — page size cap is enforced
    Given I am authenticated as "TENANT_NAME"
    When I request GET "/api/v1/resource?page=1&pageSize=100000"
    Then the response should contain at most 100 items

  Scenario: Rate limiting — exceeding limit returns 429
    Given I am authenticated as "TENANT_NAME"
    When I make 150 rapid requests to GET "/api/v1/resource?page=1&pageSize=10"
    Then at least one response should have status 429
    And the 429 response should contain a "Retry-After" header

  # Security Scenarios — run in Full tier (~15min)

  Scenario: SQL Injection — malicious input does not execute
    Given I am authenticated as "TENANT_NAME"
    When I request GET "/api/v1/resource?filter=1; DROP TABLE--"
    Then the response status should be one of: 400, 200
    And the database table should still exist

  Scenario: XSS — script tags are not rendered
    Given I am authenticated as "TENANT_NAME"
    When I send a request with "<script>alert('xss')</script>" in the name field
    Then the response content type should be "application/json"
    And the response should not contain "<script>"

  Scenario: Path Traversal — directory traversal is blocked
    Given I am authenticated as "TENANT_NAME"
    When I request GET "/api/v1/files/../../../etc/passwd"
    Then the response status should be 404

  Scenario: HTTP Method Security — POST on GET-only endpoint returns 405
    Given I am authenticated as "TENANT_NAME"
    When I send POST "/api/v1/resource"
    Then the response status should be 405
    And the response should contain an "Allow" header

  # Property-Based Scenarios — run in Full tier

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
