# Contract Testing — Deep Dive

Contract testing guarantees that two services (e.g., an API and its consumers, or two microservices)
can interoperate **without** running the full integration suite. Instead of testing against a live
system, each side validates against a shared, versioned contract.

Sits in the **Integration + Contract + E2E** layer of the quality pyramid: faster, more deterministic,
and cheaper than E2E, while still catching breaking changes between systems.

## Why contract testing

| Problem | How contract testing helps |
|---------|----------------------------|
| Integration suite needs a running server | Contracts test against mocks/stubs — no server required |
| Breaking API changes discovered in production | Broken contract fails the consumer's CI immediately |
| Teams move independently | Each side develops against the contract, not the other team's code |
| Flaky integration tests | Contract tests are deterministic and fast |

## Two approaches

### 1. Consumer-Driven Contracts (Pact)

The **consumer** (the team calling the API) writes the expectations: the exact requests it sends and
the responses it expects. These become a pact file. The **provider** (the API team) replays the pact
file against its real code to verify it can satisfy every expectation.

```
Consumer writes expectation (.pact file)
        │
        ▼
     Pact Broker  ──►  Provider replays pact against real code ("pact verify")
        ▼
  CI fails if provider breaks a consumer expectation
```

### 2. Schema-Based Contract (OpenAPI / JSON Schema)

The API publishes its OpenAPI/JSON Schema definition as the contract. The provider validates the
spec (with `spectral` or `.NET`'s `Microsoft.OpenApi`), and consumers validate that their requests
and the responses they parse match the schema. No shared Broker needed — the spec file is the contract.

## Tooling by stack

| Stack | Consumer-Driven (Pact) | Schema Validation |
|-------|------------------------|-------------------|
| .NET | PactNet | `Microsoft.OpenApi` / Spectral |
| Node.js/TS | `@pact-foundation/pact` | Ajv / Spectral |
| Python | `pact-python` | `openapi-spec-validator` / Spectral |

## What to test at the contract level

- Request/response shapes match the published contract (fields, types, arrays vs objects)
- Required vs optional fields are honored
- Pagination shape: `data`, `items`, or raw array — consumers and provider agree
- Error contracts: 400/401/403/404/429 bodies (keys and messages)
- Header contracts: `Content-Type`, `Retry-After`, rate-limit headers
- Enumerations and enum values
- Nullability: which fields may be `null`

## Example — PactNet (.NET)

```csharp
// Consumer side: define the expected interaction
PactBuilder
    .Create("Web-Consumer", "CatalogApi")
    .Given("an item exists")
    .UponReceiving("A request for an item by id")
    .WithRequest(HttpMethod.Get, "/api/v1/items/42")
    .WillRespondWith(StatusCodes.Status200OK, header =>
    {
        header["Content-Type"] = "application/json";
    })
    .WithJsonBody(new
    {
        id = 42,
        name = Match.Type("Widget"),
        price = Match.Decimal(9.99m)
    });

// Provider side: replay the pact against the real endpoint
// (PactNet v4: IPactVerifier)
var verifier = new PactVerifier();
verifier
    .ServiceProvider("CatalogApi", new Uri("http://localhost:5001"))
    .WithFileSource(new FileInfo("pacts/Web-Consumer-CatalogApi.json"))
    .Verify();
```

## Example — OpenAPI schema validation (Spectral, Node)

```bash
npx @stoplight/spectral-cli lint openapi.yaml
```

```yaml
# .spectral.yml — enforce that every response has a schema
rules:
  response-schema:
    given: $.paths[*][*].responses[*]
    severity: error
    then:
      field: content
      function: defined
```

## Quality gate

> **Every API boundary between teams has a contract. The provider's CI fails when a consumer
> expectation is broken. Schema validation runs on every PR for the published OpenAPI spec.**

## CI/CD integration

| Step | Consumer side | Provider side |
|------|---------------|---------------|
| On PR | Run unit tests + publish pact | Replay latest pacts (`pact verify`) |
| On merge | Publish pact to broker | Publish new OpenAPI spec |

See `tools-by-stack.md` for the shared CI/CD patterns.
