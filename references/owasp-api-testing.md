# OWASP API Top 10 — Detailed Testing Guide

Practical test implementations for each of the OWASP API Security Top 10 risks. Tests are written in a stack-agnostic way with .NET examples where helpful.

## API1 — Broken Object Level Authorization (BOLA)

**Risk:** An attacker can access objects they should not be able to access by manipulating object IDs in requests.

### Test: Cross-tenant access returns 403

```csharp
[Fact]
[Trait("Category", "Security")]
public async Task CrossTenantAccess_Returns403()
{
    // Arrange — authenticate as tenant A
    var clientA = _factory.CreateClientWithTenant("TENANT_A");
    var responseA = await clientA.GetAsync("/api/v1/dispatch-logs?page=1&pageSize=10");

    // Act — try to access tenant B's data with tenant A's token
    var clientB = _factory.CreateClientWithTenant("TENANT_B");
    var responseB = await clientB.GetAsync("/api/v1/dispatch-logs?page=1&pageSize=10");

    // Assert — tenant A should NOT see tenant B's data
    responseA.StatusCode.Should().Be(HttpStatusCode.OK);
    var contentA = await responseA.Content.ReadFromJsonAsync<List<Dictionary<string, object>>>();
    var contentB = await responseB.Content.ReadFromJsonAsync<List<Dictionary<string, object>>>();

    // Data isolation verified by CONTENT, not just status codes
    contentA.Should().NotBeEquivalentTo(contentB);
    contentA.Should().NotContain(x => x["tenantId"]?.ToString() == "TENANT_B");
}
```

### What to verify
- Tenant A cannot read tenant B's data
- Tenant A cannot modify tenant B's objects
- Object ID enumeration does not bypass tenant isolation
- Indirect object references are enforced server-side

---

## API2 — Broken Authentication

**Risk:** Authentication mechanisms are flawed, allowing attackers to assume identities.

### Test: Invalid/expired JWT returns 401

```csharp
[Theory]
[Trait("Category", "Security")]
[InlineData("", "empty token")]
[InlineData("invalid.jwt.token", "malformed token")]
[InlineData("Bearer expired", "expired token")]
public async Task InvalidJwt_Returns401(string token, string description)
{
    var client = _factory.CreateClient();
    if (!string.IsNullOrEmpty(token))
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);

    var response = await client.GetAsync("/api/v1/dispatch-logs");

    response.StatusCode.Should().Be(HttpStatusCode.Unauthorized,
        $"because {description} should be rejected");
}
```

### Test: Invalid API key returns 401

```csharp
[Fact]
[Trait("Category", "Security")]
public async Task InvalidApiKey_Returns401()
{
    var client = _factory.CreateClient();
    client.DefaultRequestHeaders.Add("X-API-Key", "sk_invalid_key_12345");

    var response = await client.GetAsync("/api/v1/dispatch-logs");

    response.StatusCode.Should().Be(HttpStatusCode.Unauthorized);
}
```

### What to verify
- Empty/malformed/expired JWT -> 401
- Invalid API key -> 401
- Missing auth header -> 401
- JWT with tampered payload -> 401
- API key with wrong prefix -> 401

---

## API3 — Broken Object Property Level Authorization

**Risk:** API exposes more properties than it should, or allows mass assignment.

### Test: Mass assignment not possible

```csharp
[Fact]
[Trait("Category", "Security")]
public async Task MassAssignment_IsBlocked()
{
    var payload = new
    {
        name = "Updated Name",
        role = "Admin",           // should NOT be assignable by user
        isAdmin = true,           // should NOT be assignable by user
        tenantId = "TENANT_OTHER" // should NOT be reassignable
    };

    var response = await _client.PatchAsJsonAsync("/api/v1/users/123", payload);

    // Either the extra fields are ignored, or the request is rejected
    var updated = await response.Content.ReadFromJsonAsync<UserResponse>();
    updated.Role.Should().NotBe("Admin");
    updated.IsAdmin.Should().BeFalse();
}
```

### What to verify
- Extra properties in request body are ignored or rejected
- Sensitive fields (role, isAdmin, tenantId) cannot be modified by regular users
- Response does not expose internal/sensitive fields

---

## API4 — Unrestricted Resource Consumption

**Risk:** API does not limit resource consumption, enabling DoS attacks.

### Test: Rate limiting returns 429

```csharp
[Fact]
[Trait("Category", "Security")]
public async Task RateLimitExceeded_Returns429()
{
    var tasks = Enumerable.Range(0, 150)
        .Select(_ => _client.GetAsync("/api/v1/dispatch-logs?page=1&pageSize=10"));

    var responses = await Task.WhenAll(tasks);

    var tooManyRequests = responses.Count(r => r.StatusCode == HttpStatusCode.TooManyRequests);
    tooManyRequests.Should().BeGreaterThan(0, "because rate limiting should trigger after exceeding the limit");
}
```

### What to verify
- Rate limiting triggers (429) after exceeding configured limit
- `Retry-After` header is present in 429 response
- `X-RateLimit-Remaining` header is present
- Large `pageSize` values are capped (e.g., max 1000)
- Pagination prevents unbounded data retrieval

---

## API5 — Broken Function Level Authorization

**Risk:** Users can access functions they should not have access to.

### Test: Non-admin cannot access admin endpoints

```csharp
[Fact]
[Trait("Category", "Security")]
public async Task NonAdmin_CannotAccessAdminEndpoints()
{
    var regularUserClient = _factory.CreateClientWithRole("User");

    var response = await regularUserClient.DeleteAsync("/api/v1/users/123");

    response.StatusCode.Should().Be(HttpStatusCode.Forbidden);
}
```

### What to verify
- Regular user cannot access admin-only endpoints (DELETE, admin panels)
- Role-based access control is enforced server-side, not just in UI
- HTTP method security: POST/DELETE on GET-only endpoints -> 405

---

## API6 — Unrestricted Access to Sensitive Flows

**Risk:** Business flows can be bypassed or abused.

### Test: Business flow cannot be bypassed

```csharp
[Fact]
[Trait("Category", "Security")]
public async Task BusinessFlow_CannotBeBypassed()
{
    // Attempt to skip a required step in a multi-step flow
    // e.g., try to confirm an order without completing payment
    var response = await _client.PostAsJsonAsync("/api/v1/orders/123/confirm", new { });

    response.StatusCode.Should().Be(HttpStatusCode.BadRequest,
        "because confirming without payment should be rejected");
}
```

### What to verify
- Multi-step business flows cannot be skipped
- State machine transitions are enforced (e.g., cannot go from "draft" to "shipped" without "paid")
- Critical operations require all prerequisite steps

---

## API7 — Server-Side Request Forgery (SSRF)

**Risk:** Server follows user-supplied URLs, potentially accessing internal resources.

### Test: Server does not follow user-supplied URLs

```csharp
[Fact]
[Trait("Category", "Security")]
public async Task SSRF_InternalUrlsAreBlocked()
{
    var payload = new { webhookUrl = "http://169.254.169.254/latest/meta-data/" };

    var response = await _client.PostAsJsonAsync("/api/v1/webhooks", payload);

    // The server should NOT make the request to the internal URL
    response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
    // Verify no metadata was returned in the response
    var content = await response.Content.ReadAsStringAsync();
    content.Should().NotContain("ami-id");
    content.Should().NotContain("instance-id");
}
```

### What to verify
- Internal IP ranges (169.254.x.x, 10.x.x.x, 192.168.x.x) are blocked
- User-supplied URLs are validated against an allowlist
- Server does not return internal resource content

---

## API8 — Security Misconfiguration

**Risk:** Poor security configuration exposes the system.

### Test: No stack traces in error responses

```csharp
[Fact]
[Trait("Category", "Security")]
public async Task Errors_DoNotExposeStackTraces()
{
    // Trigger an error
    var response = await _client.GetAsync("/api/v1/dispatch-logs?page=invalid");

    var content = await response.Content.ReadAsStringAsync();

    content.Should().NotContain("at System.");
    content.Should().NotContain("StackTrace");
    content.Should().NotContain("   at ");
    content.Should().NotContain("System.NullReferenceException");
}
```

### Test: CORS is not AllowAll in production

```csharp
[Fact]
[Trait("Category", "Security")]
public async Task ProductionCors_NotAllowAll()
{
    var client = _factory.CreateClient(environment: "Production");
    client.DefaultRequestHeaders.Add("Origin", "https://evil.com");

    var response = await client.GetAsync("/api/v1/dispatch-logs");

    // Production should NOT have Access-Control-Allow-Origin: *
    response.Headers.Should().NotContain(h =>
        h.Key == "Access-Control-Allow-Origin" &&
        h.Value.Contains("*"));
}
```

### What to verify
- No stack traces in any error response (400, 404, 500)
- No server version header exposed
- CORS is not `AllowAll` in production
- HTTPS is enforced
- Security headers present (X-Content-Type-Options, X-Frame-Options, etc.)

---

## API9 — Improper Inventory Management

**Risk:** Old or undocumented API versions are still accessible.

### Test: No undocumented endpoints accessible

```csharp
[Fact]
[Trait("Category", "Security")]
public async Task UndocumentedEndpoints_NotAccessible()
{
    // Try accessing a deprecated endpoint
    var response = await _client.GetAsync("/api/v0/legacy-endpoint");

    response.StatusCode.Should().Be(HttpStatusCode.NotFound);
}
```

### What to verify
- Deprecated API versions return 404 or 410 (Gone)
- No undocumented endpoints are accessible
- Swagger only shows current API version
- Old admin/debug endpoints are removed or protected

---

## API10 — Unsafe Consumption of APIs

**Risk:** Third-party API responses are not validated, potentially injecting malicious data.

### Test: Third-party API responses are validated

```csharp
[Fact]
[Trait("Category", "Security")]
public async Task ThirdPartyApiResponses_AreValidated()
{
    // Mock a third-party API returning malicious content
    _mockThirdPartyApi.Setup(x => x.GetData())
        .ReturnsAsync(new { name = "<script>alert('xss')</script>", id = "1; DROP TABLE--" });

    var response = await _client.GetAsync("/api/v1/enriched-data");

    var content = await response.Content.ReadAsStringAsync();

    // The API should sanitize/validate third-party data before returning it
    content.Should().NotContain("<script>");
    content.Should().NotContain("DROP TABLE");
}
```

### What to verify
- Third-party API responses are validated/sanitized before use
- Malicious payloads from third-party APIs do not propagate to clients
- Third-party API timeouts are handled gracefully
- Third-party API failures do not crash the system

---

## Additional Security Tests

### SQL Injection

```csharp
[Theory]
[Trait("Category", "Security")]
[InlineData("1; DROP TABLE DispatchLogs--")]
[InlineData("1' OR '1'='1")]
[InlineData("1; SELECT * FROM Users--")]
[InlineData("1 UNION SELECT * FROM Users--")]
public async Task SqlInjection_DoesNotExecute(string maliciousInput)
{
    var response = await _client.GetAsync($"/api/v1/dispatch-logs?page=1&pageSize=10&filter={maliciousInput}");

    // Should return 400 Bad Request or safe empty result, NOT 500
    response.StatusCode.Should().BeOneOf(HttpStatusCode.BadRequest, HttpStatusCode.OK);

    // Verify the table still exists (injection did not execute)
    var healthCheck = await _client.GetAsync("/health");
    healthCheck.StatusCode.Should().Be(HttpStatusCode.OK);
}
```

### XSS

```csharp
[Fact]
[Trait("Category", "Security")]
public async Task XssPayload_ReturnsJsonNotHtml()
{
    var payload = new { name = "<script>alert('xss')</script>" };
    var response = await _client.PostAsJsonAsync("/api/v1/items", payload);

    var contentType = response.Content.Headers.ContentType?.MediaType;
    contentType.Should().Be("application/json", "because API should return JSON, not HTML");

    var content = await response.Content.ReadAsStringAsync();
    content.Should().NotContain("<script>");
}
```

### Path Traversal

```csharp
[Theory]
[Trait("Category", "Security")]
[InlineData("../../../etc/passwd")]
[InlineData("..\\..\\..\\windows\\system32\\config\\sam")]
[InlineData("%2e%2e%2f%2e%2e%2f%2e%2e%2fetc%2fpasswd")]
public async Task PathTraversal_Returns404(string traversal)
{
    var response = await _client.GetAsync($"/api/v1/files/{traversal}");

    response.StatusCode.Should().Be(HttpStatusCode.NotFound);
}
```

### HTTP Method Security

```csharp
[Fact]
[Trait("Category", "Security")]
public async Task PostOnGetOnlyEndpoint_Returns405()
{
    var response = await _client.PostAsJsonAsync("/api/v1/dispatch-logs", new { });

    response.StatusCode.Should().Be(HttpStatusCode.MethodNotAllowed);
    response.Headers.Should().Contain(h => h.Key == "Allow");
}
```
