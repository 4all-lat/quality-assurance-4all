# [SPEC] - Title of the Change

> This template follows the WMSTek Feature Spec convention.
> Each section feeds different roles in the QA pipeline.
> Delete sections that are not applicable, but keep the numbering.

## 1. Metadata & Execution Routing

- **Recommended Preset:** `full_sdlc` | `express_fix` | `doc_architecture` | `modernization`
- **Affected WMS Module:** Name of the WMSTek module
- **Legacy Impact Level:** Low / Medium / High
- **Estimated Effort:** XS / S / M / L / XL
- **Stakeholders:** Product Owner, Tech Lead, QA Lead

## 2. Functional Requirement

### Business Context
Describe the business problem this change solves. Why is it needed? Who benefits?

### Expected Behavior
Describe what the system should do after this change. Be specific about inputs, outputs, and side effects.

### Key Acceptance Criteria
- [ ] Criterion 1 — measurable, testable
- [ ] Criterion 2 — measurable, testable
- [ ] Criterion 3 — measurable, testable

## 3. Pre-Analysis

### DB Tables Involved
- `table_name_1` — purpose, columns of interest
- `table_name_2` — purpose, columns of interest

### Stored Procedures & Functions
- `sp_name_1` — purpose, parameters
- `fn_name_1` — purpose, return value

### Services / Legacy APIs / C#
- `ServiceName.Method()` — purpose, current behavior
- `ControllerName.Endpoint()` — purpose, current behavior

### Business Rules / Guardrails
- Rule 1: description
- Rule 2: description

## 4. Technical Input / Output Contract

### Change 1: [Brief description]
**File:** `src/path/to/file.ext`
**Current state:** Describe what exists today.
**Expected state:** Describe what should exist after the change.

### Change 2: [Brief description]
**File:** `src/path/to/file.ext`
**Current state:** ...
**Expected state:** ...

### API Contract (if applicable)

```
GET /api/v1/resource
  Query params:
    - page (int, default 1)
    - pageSize (int, default 20, max 100)
  Response 200:
    [
      { "id": "guid", "name": "string", "createdAt": "datetime" }
    ]
  Response 401: { "error": "Unauthorized" }
  Response 403: { "error": "Forbidden" }
  Response 429: { "error": "Too Many Requests" }
```

### DTOs (if applicable)

```csharp
public class ResourceResponse
{
    public Guid Id { get; set; }
    public string Name { get; set; } = string.Empty;
    public DateTime CreatedAt { get; set; }
}
```

## 5. Edge Cases & Test Matrix

| Test Scenario | Input | Expected Result | Error Handling |
|---------------|-------|-----------------|----------------|
| Happy path | Valid input, authenticated | 200 with expected data | N/A |
| Empty result | Valid input, no data | 200 with empty array | N/A |
| Invalid auth | No/expired token | 401 Unauthorized | `{ "error": "Unauthorized" }` |
| Forbidden tenant | Tenant without feature | 403 Forbidden | `{ "error": "Forbidden" }` |
| Rate limited | > N requests in window | 429 Too Many Requests | `{ "error": "Too Many Requests" }` |
| Invalid input | Malformed query params | 400 Bad Request | `{ "error": "Invalid parameter: X" }` |
| DB unavailable | DB connection fails | 500 Internal Server Error | `{ "error": "Internal error" }` (no stack trace) |
| SQL injection | `1; DROP TABLE--` | 400 or safe empty result | No SQL executed |
| XSS payload | `<script>` in input | JSON response, no HTML | Script tags not rendered |
| Page overflow | `page=999999` | 200 with empty array | N/A |
| PageSize overflow | `pageSize=100000` | Capped to max (100) | N/A |

## 6. Open Questions & Blocking Points

- [ ] Open question 1 — who needs to decide?
- [ ] Open question 2 — who needs to decide?
- [ ] Risk 1 — description and mitigation
- [ ] Risk 2 — description and mitigation

## 7. QA Notes (optional)

### Properties to Test (Property-Based)
- `page <= 0` is always reset to 1
- `pageSize > max` is always capped
- `offset = (page - 1) * pageSize` never overflows
- Consecutive pages never overlap

### BDD Scenarios (Gherkin)
See `assets/bdd-feature-template.feature` for the BDD scenario template.

### Security Tests (OWASP)
- [ ] API1: Cross-tenant access returns 403
- [ ] API2: Invalid JWT/API key returns 401
- [ ] API4: Rate limiting returns 429
- [ ] API8: No stack traces in error responses
