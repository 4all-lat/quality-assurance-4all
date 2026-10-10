# Concurrency and Idempotency

Most test suites ask "does it work?" one request at a time. Production asks "does it work when the
same request arrives three times at once, when the client retries after a timeout it did not see,
and when the message broker delivers the same event twice?" Those are the failures that cost money
— a duplicated payment, a lost update, an order shipped twice.

This is the reference for that class of test. It is *not* about load: `performance-testing.md` covers
throughput and latency. Here the load is irrelevant; what matters is that two things happen at the
same moment, or that one thing happens twice.

## The six scenarios

| # | Scenario | The failure it catches |
|---|----------|------------------------|
| 1 | Retry with an idempotency key | A network timeout the client could not distinguish from a rejection → the client retries → the operation runs twice |
| 2 | Double submit | A user double-clicks, or two tabs post at once → two records, two charges |
| 3 | Two updates to the same row | Last-write-wins silently discards one edit; nobody gets a conflict |
| 4 | TOCTOU (check-then-act) | Stock is checked, then reserved — and between the two, someone else reserved it |
| 5 | Signed-webhook replay | A captured, validly signed payload is delivered again |
| 6 | Offset pagination with concurrent inserts | Paging skips or duplicates rows because `OFFSET` counts a moving target |

Mark every test in this class with the `concurrency` category, so the tier logic can select it
(see [Stratification](#stratification)).

---

## 1. Retry with an idempotency key

The client sends a request, the connection drops, and it cannot tell whether the server processed
it. It retries. The API must produce **one** effect and return the same response both times.

```csharp
[Fact]
[Trait("Category", "Concurrency")]
public async Task SameIdempotencyKey_ProducesOneEffect()
{
    var key = Guid.NewGuid().ToString();
    var payload = new { amount = 100, currency = "USD" };

    var first = await _client.PostWithKeyAsync("/api/v1/payments", payload, key);
    var retry = await _client.PostWithKeyAsync("/api/v1/payments", payload, key);

    first.StatusCode.Should().Be(HttpStatusCode.Created);
    retry.StatusCode.Should().Be(HttpStatusCode.Created, "the retry replays the first response");
    (await first.Content.ReadFromJsonAsync<Payment>()).Id
        .Should().Be((await retry.Content.ReadFromJsonAsync<Payment>()).Id);

    _db.Payments.Count(p => p.IdempotencyKey == key).Should().Be(1);
}
```

What to verify:
- Same key + same body → same result, one side effect, and the **stored response is replayed**
- Same key + **different** body → `409 Conflict`, not a silent second effect
- The key is scoped per tenant/account, so one tenant cannot collide with another's key
- A key that is never completed (crash mid-flight) can be retried rather than blocking forever
- Keys expire; the store does not grow without bound

## 2. Double submit

No idempotency key, no coordination — just two identical requests landing together. Exactly one must
win. Fire them from a barrier so they actually overlap rather than running one after the other.

```csharp
[Fact]
[Trait("Category", "Concurrency")]
public async Task SimultaneousDoubleSubmit_CreatesExactlyOne()
{
    const int attempts = 8;
    using var barrier = new Barrier(attempts);          // all 8 POST at the same instant

    var responses = await Task.WhenAll(Enumerable.Range(0, attempts).Select(async _ =>
    {
        barrier.SignalAndWait();
        return await _client.PostAsJsonAsync("/api/v1/orders", OrderPayload());
    }));

    responses.Count(r => r.StatusCode is HttpStatusCode.Created or HttpStatusCode.OK).Should().Be(1);
    responses.Count(r => r.StatusCode == HttpStatusCode.Conflict).Should().Be(attempts - 1);
    _db.Orders.Count(o => o.ExternalRef == "ORDER-1").Should().Be(1);
}
```

The barrier is the point. `Task.WhenAll` alone usually serialises on a fast machine and the test
passes against code that is in fact broken. A unique constraint (or `INSERT ... ON CONFLICT`) is the
only defence that cannot be raced.

## 3. Two updates to the same row

Two users open the same record and both save. Without optimistic concurrency, the second silently
overwrites the first and nobody is told.

```csharp
[Fact]
[Trait("Category", "Concurrency")]
public async Task ConcurrentEdits_ProduceAConflictNotALostUpdate()
{
    var doc = await CreateDocument();

    var a = await _client.PatchAsync($"/api/v1/docs/{doc.Id}",
        JsonContent(new { title = "A", version = doc.Version }));
    var b = await _client.PatchAsync($"/api/v1/docs/{doc.Id}",
        JsonContent(new { title = "B", version = doc.Version }));   // same version as `a` read

    a.StatusCode.Should().Be(HttpStatusCode.OK);
    b.StatusCode.Should().Be(HttpStatusCode.Conflict, "because the version it wrote against is stale");
}
```

What to verify:
- The response carries the version/ETag, and a write against a stale one is rejected
- A `PATCH` with no version at all is either rejected or explicitly documented as last-write-wins
- Field-level updates do not clobber unrelated fields written concurrently

## 4. TOCTOU — check then act

The bug is the gap between the read and the write. The test is to shrink the gap to nothing by
running many actors at once and asserting an **invariant**, not a status code.

```csharp
[Fact]
[Trait("Category", "Concurrency")]
public async Task ConcurrentDebits_NeverOverdrawTheBalance()
{
    var account = await CreateAccount(balance: 100);
    using var barrier = new Barrier(10);

    var results = await Task.WhenAll(Enumerable.Range(0, 10).Select(async _ =>
    {
        barrier.SignalAndWait();                          // 10 debits of 20 against a balance of 100
        return await _client.PostAsJsonAsync($"/api/v1/accounts/{account.Id}/debit",
            new { amount = 20 });
    }));

    (await GetBalance(account.Id)).Should().BeGreaterThanOrEqualTo(0);
    results.Count(r => r.IsSuccessStatusCode).Should().Be(5, "only 5 debits fit in 100");
    _ledger.Entries.Count(e => e.AccountId == account.Id).Should().Be(5);
}
```

The invariant — *the balance never goes negative and the ledger matches the balance* — is what the
test asserts. A test that only checks the status codes passes on a system that lost money.

## 5. Signed-webhook replay

A signature proves *who* sent the payload, not *when* it is being used. Without a nonce or a
timestamp window, any captured delivery can be replayed.

```csharp
[Theory]
[Trait("Category", "Concurrency")]
[InlineData("identical body delivered twice")]
[InlineData("identical delivery 10 minutes later")]
public async Task ReplayedWebhook_IsRejected(string description)
{
    var delivery = SignedWebhook(eventId: "evt_1", timestamp: _clock.UtcNow);

    (await _client.PostAsync("/api/v1/webhooks/provider", delivery.Body, delivery.Signature))
        .StatusCode.Should().Be(HttpStatusCode.OK);

    _clock.Advance(TimeSpan.FromMinutes(10));
    var replay = await _client.PostAsync("/api/v1/webhooks/provider", delivery.Body, delivery.Signature);

    replay.StatusCode.Should().Be(HttpStatusCode.Conflict, $"because {description} must be ignored");
    _db.ProcessedEvents.Count(e => e.EventId == "evt_1").Should().Be(1);
}
```

What to verify:
- The signature covers the raw body, a timestamp and the event id — not just the body
- A delivery outside the tolerance window is rejected even with a valid signature
- The same `event_id` processed twice is a no-op, and the *second* response is the replayed one
- Verification uses a constant-time comparison

## 6. Offset pagination with concurrent inserts

`OFFSET 20` means "skip 20 rows of whatever the table looks like now". Insert a row on page 1 and
page 2 shifts: one row is served twice and another is never served.

```csharp
[Fact]
[Trait("Category", "Concurrency")]
public async Task PagingWhileRowsAreInserted_LosesNoRow()
{
    var seen = new List<Guid>();

    for (var page = 1; page <= 5; page++)
    {
        var batch = await GetPage(page, pageSize: 20);
        seen.AddRange(batch.Select(x => x.Id));
        await InsertMoreRows(3);                    // someone else is writing while we page
    }

    seen.Should().OnlyHaveUniqueItems("because a stable cursor must not serve a row twice");
    seen.Should().BeEquivalentTo(await AllIdsAtStart());
}
```

The fix is a keyset (seek) cursor — `WHERE (created_at, id) < (@lastCreatedAt, @lastId)` — not a
larger `OFFSET`. The test is the same either way.

---

## Stratification

Tests in this class are functional tests with a race in them, so they belong to the **`Regression`**
tier — every PR. They are cheap to run and expensive to discover late. The `Smoke` tier stays free of
them because a smoke test must be deterministic.

| Stack | How to mark | How it is selected |
|-------|-------------|--------------------|
| .NET | `[Trait("Category", "Concurrency")]` | included by the Regression filter `Category!=Security&Category!=Performance` |
| Node.js/TS | `describe('Concurrency', …)` | included by the Regression pattern `^(?!.*(Security(?!PR)\|Performance))` |
| Python | `@pytest.mark.concurrency` | included by `pytest -m "not security and not performance"` |

---

## Rules that make these tests trustworthy

**Run against the real engine.** EF Core InMemory, SQLite in-memory and mock repositories do not
enforce unique constraints, row locks or transaction isolation — the three things these tests exist
to check. Use [Testcontainers](https://testcontainers.com/) (`.NET`, Node, Python) or the same engine
version as production.

**Synchronise the start.** `Barrier` / `CountdownEvent` in .NET, `Promise.all` on a pre-arranged set
of promises in Node, a `threading.Barrier` in Python. Un-synchronised "concurrent" tests usually run
sequentially and always pass.

**Assert invariants, not statuses.** "The balance is never negative", "exactly one order exists",
"no row was served twice". A status-code assertion is satisfied by a system that corrupts data.

**Make it repeatable.** Run the case in a loop (`for i in {1..20}`) locally before trusting it; a race
that reproduces one time in five is a real bug you have not caught yet.

**Do not retry the test to make it pass.** If a concurrency test is flaky, the system has a race, not
the test.

---

## Quality gate

> **Every state-changing endpoint is exercised by at least one test that fires it twice or fires it
> concurrently. The system produces exactly one effect, and the invariant holds — no double charge,
> no lost update, no replay, no skipped row.**
