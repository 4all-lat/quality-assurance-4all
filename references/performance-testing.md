# Performance Testing — Deep Dive with Code

Tests that validate the API performs within acceptable bounds under concurrent load, and that it does
not degrade over time (memory leaks, unbounded caches).

## Metrics framework

| Metric | Target (typical) | Meaning |
|--------|------------------|---------|
| P50 latency | < 500ms | Median request time — the "typical" experience |
| P95 latency | < 2000ms (health), < 5000ms (DB queries) | Long tail — affects most users |
| P99 latency | < 10000ms | Worst tolerable experience |
| Throughput | > 20 req/s | Requests the system serves per second |
| Error rate | < 0.1% | Share of failed requests under load |
| Memory | stable over 1000+ requests | No growth = no leak |

Always **baseline first**: measure against an empty/quiet system, then compare under load. Percentiles
matter more than averages — an average hides the long tail.

## Approach 1 — Concurrent HttpClient (.NET, in-process)

Fastest way to get realistic insight without external tools. Run it as an xUnit `[Fact]` marked
`Performance`.

```csharp
[Fact]
[Trait("Category", "Performance")]
public async Task Api_Meets_Performance_Budget()
{
    var client = _factory.CreateClient();
    var stopwatch = Stopwatch.StartNew();

    // Fire 500 concurrent requests
    var tasks = Enumerable.Range(0, 500)
        .Select(_ => client.GetAsync("/api/v1/dispatch-logs?page=1&pageSize=50"));
    var responses = await Task.WhenAll(tasks);

    // Aggregate
    var totalMs = stopwatch.Elapsed.TotalMilliseconds;
    var percentiles = responses
        .Zip(tasks, (r, _) => r)
        .Select(_ => stopwatch.Elapsed.TotalMilliseconds);

    // Budget assertions
    var errorRate = responses.Count(r => !r.IsSuccessStatusCode) / (double)responses.Length;
    errorRate.Should().BeLessThan(0.001);
    Throughput(targetRequestsPerSecond);
}
```

**Caveat:** `Task.WhenAll` on a single HttpClient works but does not model real client wait time or
TCP connection churn well. Use it for a fast smoke-level performance gate, and a dedicated load tool
for release validation.

## Approach 2 — NBomber (.NET)

```csharp
public class LoadScenario
{
    public static void Run()
    {
        var httpFactory = HttpClientFactory.Create();

        var scenario = Scenario.Create("api_v1_dispatch_logs", async context =>
        {
            var step = await Step.Run("get_dispatch_logs", context, async () =>
            {
                var request = Request.Create(HttpMethod.Get, "/api/v1/dispatch-logs?page=1&pageSize=50");
                var response = await httpFactory.GetClient().SendAsync(request);
                return response.IsSuccessStatusCode
                    ? Response.Ok(statusCode: (int)response.StatusCode, sizeBytes: (long)response.Content.Headers.ContentLength)
                    : Response.Fail(statusCode: (int)response.StatusCode);
            });
            return step;
        })
        .WithoutWarmUp()
        .WithLoadSimulations(
            Simulation.Inject(rate: 100, interval: TimeSpan.FromSeconds(1), during: TimeSpan.FromSeconds(30))
        );

        NBomberRunner.RegisterScenarios(scenario)
            .WithReportFolder("nbomber-reports")
            .Run();
    }
}
```

## Approach 3 — k6 (Node / any HTTP API) and locust (Python)

k6 (JS DSL, exports to Grafana):

```javascript
import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate } from 'k6/metrics';

const errorRate = new Rate('errors');

export const options = {
  stages: [
    { duration: '1m', target: 20 },  // ramp up to 20 VUs
    { duration: '3m', target: 50 },  // hold at 50 VUs
    { duration: '1m', target: 0 },   // ramp down
  ],
  thresholds: {
    http_req_duration: ['p(95)<2000', 'p(99)<10000'],
    errors: ['rate<0.001'],
    http_reqs: ['rate>20'],
  },
};

export default function () {
  const res = http.get('http://localhost:5000/api/v1/dispatch-logs?page=1&pageSize=50');
  errorRate.add(res.status !== 200);
  check(res, { 'status is 200': (r) => r.status === 200 });
  sleep(0.2);
}
```

locust (Python):

```python
from locust import HttpUser, between, task

class ApiUser(HttpUser):
    wait_time = between(0.1, 0.5)

    @task
    def dispatch_logs(self):
        self.client.get("/api/v1/dispatch-logs?page=1&pageSize=50")

# Run: locust --host http://localhost:5000 --users 50 --spawn-rate 10 -t 5m
```

## Memory leak check

Run a **long-lived soak**: 1000+ requests against the same endpoints, sample `GC.GetTotalMemory` (or
container RSS) after request 100, 500, 1000. If memory grows monotonically without settling, there is
a leak (caches, static collections, undisposed HttpClient).

```csharp
[Fact]
[Trait("Category", "Performance")]
public async Task No_Memory_Leak_Over_1000_Requests()
{
    var before = GC.GetTotalMemory(forceFullCollection: true);
    var client = _factory.CreateClient();

    for (int i = 0; i < 1000; i++)
        await client.GetAsync("/api/v1/dispatch-logs?page=1&pageSize=50");

    GC.Collect(); GC.WaitForPendingFinalizers();
    var after = GC.GetTotalMemory(forceFullCollection: true);

    (after - before).Should().BeLessThan(50 * 1024 * 1024); // < 50 MB growth
}
```

## Load profiles

| Profile | Concurrency | Duration | Purpose |
|---------|-------------|----------|---------|
| Smoke load | 10–20 users | 1m | Fast signal, run on every PR |
| Average | 50 users | 5m | Typical production traffic validation |
| Peak | 200 users | 5m | Release readiness |
| Soak | Steady 50 | 30m+ | Memory leaks and degradation over time |

## Quality gate

> **P95 latency meets its target under the expected load profile. Error rate < 0.1%. Memory stable
> across a soak run. Performance budget is enforced in CI on the release branch.**

## Performance anti-patterns

| Anti-pattern | Fix |
|--------------|-----|
| Asserting on a single request time | Use percentiles over a distribution |
| Running perf in the unit suite | Mark `Performance` category, run in Full tier only |
| Measuring against an empty DB | Seed a representative data volume |
| Shared HttpClient without pooling | One `HttpClient` per test run (or `IHttpClientFactory`) |
| No baseline | Always compare against a before-change run |
