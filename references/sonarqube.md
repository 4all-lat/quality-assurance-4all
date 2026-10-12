# SonarQube — Static Analysis Platform

SonarQube is **not a phase**. It is a static-analysis platform that aggregates what the pipeline
already measures and adds one family of metrics the pipeline does not have on its own: duplication,
cognitive complexity, code smells and the maintainability of the code being changed.

Read it that way and the integration is small: it consumes the coverage reports the pipeline already
produces, adds its own static findings, and enforces a gate. Read it as "the quality gate of the
project" and it quietly becomes a second source of truth for every threshold this skill defines —
which is the one thing this package cannot afford, because its readers act on those numbers.

> **Gate:** the analysis runs on every PR, and the SonarQube quality gate must reproduce the
> [canonical thresholds](quality-gates.md#canonical-thresholds) — not replace them. No new issue on
> the changed lines is left untriaged at release.

---

## What it adds, what it duplicates, what it does not replace

| Adds (nobody else measures it here) | Duplicates (already a phase) | Does **not** replace |
|-------------------------------------|------------------------------|----------------------|
| Duplicated lines, cognitive complexity, code smells, maintainability rating | Coverage → Phase 8 | The dynamic OWASP tests → Phase 6 |
| A quality gate scoped to **new code**, so a legacy codebase can adopt it | Reliability/Security ratings, security hotspots → the static half of Phase 6 | The mutation score → Phase 9 |
| Issue lifecycle: tracking, assignment, "won't fix" with a date | Lint/SAST findings → the SAST row of Phase 6 | Performance, concurrency, the threat model |
| Aggregation of every stack's report into one project view | — | Anything that needs a running system |

The value is in the first column and in the aggregation. Everything in the second column already has
a gate in this pipeline, and that gate stays authoritative.

---

## Editions and deployment — decide this first

This is the constraint that decides where the gate can live, and it is not a matter of taste:

| Option | Branch analysis | PR decoration | Notes |
|--------|-----------------|---------------|-------|
| SonarQube Server — Community Edition | No | No | Only the main branch is analyzed. Free, self-hosted. |
| SonarQube Server — Developer Edition and above | Yes | Yes | Paid. This is what makes it a PR gate on a self-hosted server. |
| SonarQube Cloud | Yes | Yes | Free for public repositories; paid for private ones. |
| Community Edition + `mc1arke/sonarqube-community-branch-plugin` | Yes | Yes (GitHub, GitLab, Bitbucket) | Not supported by SonarSource and there is no upgrade path to a commercial edition — migrating after using it risks losing the data. Treat it as a temporary measure with a date on it. |

**Consequence for the pipeline.** With the Community Edition the gate **cannot be a PR gate**: the
scanner will not accept branch or pull-request parameters. Run it on `main` inside the Full tier and
fail the run by reading the gate verdict from `api/qualitygates/project_status`. With Developer
Edition or Sonar Cloud, wire it to the Regression tier as described below.

Do not pretend otherwise in CI: a `sonar.pullrequest.*` property on a Community Edition server is
rejected, not ignored.

---

## Prerequisites

- **SonarScanner for .NET 7.0 or newer does not need a JRE on the machine.** It provisions one from
  the server, which requires SonarQube Server 10.6 or newer (or SonarQube Cloud). If you disable the
  auto-provisioning — an offline or egress-restricted runner — you must provide Java 21 locally.
- SonarQube Server 10.6 is therefore also the practical minimum for a .NET project on a self-hosted
  server. Below that, keep a JDK on the runner.
- A token in `SONAR_TOKEN`, and `SONAR_HOST_URL` when the server is self-hosted. Both are read from
  the environment by every scanner; neither has to appear on a command line, which keeps it out of
  the process list and out of the CI logs.

---

## The quality gate is the canonical table, applied

`assets/sonar-quality-gate.json` holds the gate conditions this package expects, and it is the file
the test suite compares against `references/quality-gates.md`. It is data, not a screenshot of
someone's UI: the same table that `docs.thresholds.test.sh` enforces across the documents also
applies to the gate.

Apply it with the web API rather than by hand, so the gate is reproducible on a fresh server:

```bash
# 1. create the gate
curl -s -u "$SONAR_TOKEN": -X POST "$SONAR_HOST_URL/api/qualitygates/create" \
  -d "name=QA 4All — canonical"

# 2. add every condition from assets/sonar-quality-gate.json, one call each
curl -s -u "$SONAR_TOKEN": -X POST "$SONAR_HOST_URL/api/qualitygates/create_condition" \
  -d "gateName=QA 4All — canonical" -d "metric=coverage" -d "op=LT" -d "error=80"

# 3. make it the default for new projects, or assign it per project
curl -s -u "$SONAR_TOKEN": -X POST "$SONAR_HOST_URL/api/qualitygates/set_as_default" \
  -d "name=QA 4All — canonical"
```

The numbers coincide with SonarQube's stock new-code gate on coverage and duplication — that is a
coincidence worth keeping, not a dependency. Every condition is stated explicitly in the asset so
the gate does not inherit a profile default that a server upgrade is free to change, and so a reader
who changes `quality-gates.md` is told to change the gate in the same commit.

**Waivers.** A finding that survives triage is waived with a date and an owner, in the tracker — the
same rule the static scans already follow (Phase 6). Marking it "won't fix" in the UI without an
owner is not a waiver; it is a quiet deletion that the next analysis inherits.

---

## The `sonar` stage of the runner

The runners expose it as the `sonar` stage, with the same exit-code contract as every other stage, so
it can sit in a pipeline exactly like the coverage stage. In `scripts/run-tests.sh` it is `-s Sonar`;
in `scripts/run-tests.ps1` it is `-Stage Sonar`.

```bash
export SONAR_TOKEN=...
export SONAR_PROJECT_KEY=my-org_my-project
./scripts/run-tests.sh -s Sonar
```

| Stack | What the stage runs |
|-------|---------------------|
| .NET | `dotnet sonarscanner begin` → `dotnet build` → `dotnet test --collect:"XPlat Code Coverage"` → `dotnet sonarscanner end`. The scanner has to wrap the build, which is why this stage builds and tests instead of only analyzing |
| Node.js/TS | `sonar-scanner` with `sonar.javascript.lcov.reportPaths` pointing at the lcov report Vitest writes |
| Python | `sonar-scanner` with `sonar.python.coverage.reportPaths` pointing at `coverage xml` |

Every stack passes `sonar.qualitygate.wait=true`, so the stage fails when the gate fails rather than
reporting success while the analysis is still queued. It is unbudgeted, like `Coverage` and
`Mutation`: the tiers budget *test* duration, and an analysis is not a tier.

The stage exits `1` when `SONAR_PROJECT_KEY` is unset — without it the scanner would analyze against
an empty key and report on a project that does not exist.

---

## Wiring it per stack

### .NET

```bash
dotnet tool install -g dotnet-sonarscanner
dotnet sonarscanner begin /k:"$SONAR_PROJECT_KEY" /d:sonar.qualitygate.wait=true
dotnet build
dotnet test --collect:"XPlat Code Coverage" --results-directory ./test-results
dotnet sonarscanner end
```

Coverlet's Cobertura report is what feeds the coverage condition: pass
`/d:sonar.cs.cobertura.reportsPaths=./test-results/**/coverage.cobertura.xml` on `begin`, or rely on
the scanner's auto-detection of the report written during the wrapped build. The report has to be
produced *inside* the `begin`/`end` window — a report from an earlier `-s Coverage` run is not picked
up.

### Node.js / TypeScript

```bash
npm install -D sonarqube-scanner   # or install the CLI scanner once on the runner
npx vitest run --coverage          # with an lcov reporter configured
sonar-scanner \
  -Dsonar.projectKey="$SONAR_PROJECT_KEY" \
  -Dsonar.javascript.lcov.reportPaths=coverage/lcov.info \
  -Dsonar.qualitygate.wait=true
```

Add `lcov` to the Vitest coverage reporters — `text`, `html` and `cobertura` do not give the
scanner what it needs.

### Python

```bash
coverage xml                        # writes coverage.xml
bandit -r src -f json -o bandit.json # optional: imported as external issues
sonar-scanner \
  -Dsonar.projectKey="$SONAR_PROJECT_KEY" \
  -Dsonar.python.coverage.reportPaths=coverage.xml \
  -Dsonar.qualitygate.wait=true
```

`bandit` is already the SAST gate of Phase 6; feeding its report to Sonar as well puts the findings
next to the code that caused them. It does not replace the gate — the report is advisory in Sonar,
the exit code is the gate.

---

## CI

In the workflow, the analysis belongs **after** the tests, in its own job, so a failing gate is
attributed to the gate and not to the test step:

```yaml
  sonar:
    needs: regression
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0        # the SCM blame and the issue tracking need the history
      - uses: actions/setup-dotnet@v4
        with:
          dotnet-version: '8.0'
      - run: dotnet tool install -g dotnet-sonarscanner
      # The gate waits for itself: the step fails when the gate fails.
      - run: |
          dotnet sonarscanner begin /k:"${{ vars.SONAR_PROJECT_KEY }}" /d:sonar.qualitygate.wait=true
          dotnet build
          dotnet test --collect:"XPlat Code Coverage"
          dotnet sonarscanner end
        env:
          SONAR_TOKEN: ${{ secrets.SONAR_TOKEN }}
          SONAR_HOST_URL: ${{ vars.SONAR_HOST_URL }}
```

- `fetch-depth: 0` is not optional: without the history, blame is wrong and issue tracking loses
  what it needs to tell a new issue from an old one.
- On SonarQube Cloud, PR decoration additionally needs the workflow to hold `pull-requests: write`.
- Keep the token in `secrets`, never in the workflow file, and never echo it — the scanner reads
  `SONAR_TOKEN` from the environment.

---

## What this platform must not become

- **Not a second source of thresholds.** If the gate says 80% and `quality-gates.md` says 80%, fine;
  the moment they differ, the document wins and the gate is wrong.
- **Not a PR gate on the Community Edition.** It cannot decorate a PR or analyze a branch; that is a
  licence boundary, not a configuration mistake.
- **Not a substitute for the dynamic half.** SonarQube reads source. BOLA, authentication lifecycle,
  injection against a running API and rate limiting are Phase 6 tests, and a green gate says nothing
  about them.
- **Not a dependency of this repository.** Like Gitleaks, ZAP and Trivy, it is an external platform
  the adopting project installs. This repository's own suite stays dependency-free.

---

## Checklist

- [ ] Deployment chosen deliberately, and the edition's limits acknowledged (no PR decoration on the
      Community Edition)
- [ ] Gate created from `assets/sonar-quality-gate.json` through the API, not by hand in the UI
- [ ] Gate conditions match the canonical table — `docs.thresholds.test.sh` fails when they drift
- [ ] Coverage report produced inside the analysis window (inside `begin`/`end` for .NET)
- [ ] `sonar.qualitygate.wait=true` set, so a queued analysis cannot pass as success
- [ ] `fetch-depth: 0` in CI, and `SONAR_TOKEN` in secrets
- [ ] New-code scope configured, so a legacy codebase can adopt the gate without a freeze
- [ ] Every surviving finding has an owner and a date; "won't fix" without one is not a waiver
- [ ] The gate is a required check on the default branch
- [ ] The dynamic OWASP suite still runs — a green gate did not replace it
