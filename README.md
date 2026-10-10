# Quality Assurance 4All Skill

End-to-end QA pipeline guide from spec to production. Covers TDD, BDD, SDD, threat modeling and abuse cases, property-based testing, mutation testing, security testing (dynamic and static scanning), concurrency and idempotency testing, accessibility and visual regression, performance testing, code coverage, and regression suite stratification with enforced tier budgets.

## What This Skill Provides

A comprehensive, reusable QA methodology that ensures quality at every stage of the software delivery lifecycle. Designed for .NET / API projects but applicable to any stack.

The skill defines **11 phases** organized as a quality pyramid:

| Phase | Methodology | Quality Gate |
|-------|-------------|--------------|
| 1. Specification | SDD (Spec-Driven Development) | Spec approved before coding |
| 2. Unit Testing | TDD (Test-Driven Development) | >= 80% line coverage |
| 3. Behavior | BDD (Behavior-Driven Development) | All acceptance criteria covered |
| 4. Integration | Test Pyramid (70/20/10) | All endpoints x tenants tested |
| 5. Edge Cases | Property-Based Testing | 200+ random cases per property |
| 6. Security | OWASP API Top 10 + static scans | All 10 risks tested; scans clean |
| 7. Performance | Load Testing | P95 < 2000ms, error rate < 0.1% |
| 8. Coverage | Code Coverage | >= 80% line coverage |
| 9. Mutation | Mutation Testing | >= 60% mutation score |
| 10. Regression | Stratified Suite (Smoke/Regression/Full) | Tiered pass gates |
| 11. Production | Pre-production checklist | All items checked |

## When to Use

- Starting a new software project from scratch
- Establishing QA standards for a team or organization
- Preparing a solution for production delivery
- Auditing existing QA practices
- Defining a CI/CD quality pipeline
- Responding to "how do we ensure quality?" questions
- Planning a release with confidence in test coverage

## Installation

This skill is designed to be installed as an agent skill. Copy the `quality-assurance-4all/` folder
into your agent's skills directory:

| Agent | Directory |
|-------|-----------|
| Claude Code | `~/.claude/skills/quality-assurance-4all/` (user-wide) or `.claude/skills/` (project-scoped) |
| Devin | `~/.agents/skills/quality-assurance-4all/` |

Or install from the source repository:

```bash
devin skill install https://github.com/4all-lat/quality-assurance-4all
```

Once present under `~/.claude/skills/`, Claude Code discovers the skill automatically and exposes it
as `/quality-assurance-4all`.

## Usage

The skill is invoked automatically by the AI agent when the user's request matches any of the "When to Use" scenarios above. You can also explicitly trigger it:

```
Use the quality-assurance-4all skill to set up QA for this project.
```

### Quick Start

For a new .NET project, run the setup script to scaffold the test project structure:

```bash
./scripts/setup-qa-project.sh --name MyProject.Tests --stack dotnet
```

```powershell
.\scripts\setup-qa-project.ps1 -ProjectName "MyProject.Tests" -Stack dotnet
```

For the stratified test runner (cross-platform bash, or PowerShell on Windows):

```bash
./scripts/run-tests.sh -s Smoke       # Quick health check (~30s)
./scripts/run-tests.sh -s Regression  # Full functional validation (~5min)
./scripts/run-tests.sh -s Full        # Everything including perf + security (~15min)
./scripts/run-tests.sh -s Coverage    # Generate coverage report
./scripts/run-tests.sh -s Mutation    # Run mutation testing
```

```powershell
.\scripts\run-tests.ps1 -Stage Smoke       # Quick health check (~30s)
.\scripts\run-tests.ps1 -Stage Regression  # Full functional validation (~5min)
.\scripts\run-tests.ps1 -Stage Full        # Everything including perf + security (~15min)
.\scripts\run-tests.ps1 -Stage Coverage    # Generate coverage report
.\scripts\run-tests.ps1 -Stage Mutation    # Run mutation testing
```

## Directory Structure

```
quality-assurance-4all/
  SKILL.md              # Main skill definition (agent-invocable)
  README.md             # This file — human-readable overview
  references/           # Detailed reference documentation
    quality-gates.md        # Consolidated quality gates per phase
    owasp-api-testing.md    # Detailed OWASP API Top 10 testing guide
    tools-by-stack.md       # Frameworks and tools by stack (.NET, Node.js, Python)
    test-pyramid.md         # Test pyramid and stratification deep dive
    contract-testing.md     # Contract testing (Pact + OpenAPI schema)
    performance-testing.md  # Performance testing with code examples
    concurrency-and-idempotency.md # Races, retries, double submit, replay, keyset paging
    quality-engineering-practices.md # Flaky, test data, a11y, visual regression, DoD
  assets/               # Reusable templates and config snippets
    ai-spec-template.md     # AI Spec / Feature Spec template
    bdd-feature-template.feature  # Gherkin BDD scenario template
    pre-production-checklist.md   # Pre-production quality checklist
    coverage-config.xml     # Coverlet coverage configuration snippet
  scripts/              # Working scripts for CI and project setup
    run-tests.sh            # Stratified test runner (bash, cross-platform)
    run-tests.ps1           # Stratified test runner (PowerShell, .NET-only)
    setup-qa-project.sh     # Quick-start QA scaffolder (bash, cross-platform)
    setup-qa-project.ps1    # Quick-start QA project scaffolder (PowerShell)
    README.md               # Scripts documentation
  tests/                # This repository's own test suite (zero dependencies)
    run.sh                  # Discovers cases/*.test.sh and runs them
    cases/                  # One file per behaviour under test
    README.md               # How the suite works
  .github/workflows/qa.yml  # CI: smoke, regression and Windows parity jobs
```

## Testing This Repository

The scripts in `scripts/` are what every adopting project runs as its gate, so
they are covered by their own suite. It needs nothing installed — the external
toolchains are replaced by PATH shims — and it runs the same way locally and in
CI:

```bash
tests/run.sh                 # every case
tests/run.sh parity          # only the bash <-> PowerShell parity contract
```

It pins down the runner's exit-code contract (`0` success · `1` gate failure ·
`2` usage error), the exact command line each stack and stage produces, the
scaffolder's generated tree, the documented thresholds (a single canonical table
in `references/quality-gates.md`), and the bash/PowerShell parity of stages,
flags and thresholds. See [`tests/README.md`](tests/README.md).

## Stacks Supported

| Stack | Unit | BDD | Property-Based | Coverage | Mutation |
|-------|------|-----|-----------------|----------|----------|
| .NET | xUnit / NUnit | Reqnroll | FsCheck | Coverlet | Stryker.NET |
| Node.js/TS | Vitest / Jest | Cucumber.js | fast-check | @vitest/coverage-v8 / istanbul | Stryker.js |
| Python | pytest | Behave | Hypothesis | coverage.py | mutmut / cosmic-ray |

Concurrency, security scanning and UI quality (accessibility, visual regression) are documented per
stack in [`references/tools-by-stack.md`](references/tools-by-stack.md).

## Quality Pyramid

```
    +-----------------------------------------+
    |         PRODUCTION MONITORING            |  <- Observability, alerts, SLOs
    +-----------------------------------------+
    |     PERFORMANCE + SECURITY TESTING       |  <- Non-functional requirements
    +-----------------------------------------+
    |  INTEGRATION + CONTRACT + E2E TESTING    |  <- Between systems
    +-----------------------------------------+
    |    BDD + PROPERTY-BASED TESTING          |  <- Behavior and edge cases
    +-----------------------------------------+
    |       UNIT TESTING (TDD) + COVERAGE      |  <- Individual components
    +-----------------------------------------+
    |  SPEC-DRIVEN DEVELOPMENT (SDD) + AI Spec |  <- Source of truth
    +-----------------------------------------+
```

Each layer depends on the one below. You cannot have reliable integration tests without reliable unit tests. You cannot have reliable security tests without reliable functional tests.

## Regression Suite Stratification

| Tier | Category | Duration | When to run | What's included |
|------|----------|----------|-------------|-----------------|
| Smoke | `Smoke` | ~30s | Every commit | Health, swagger, auth login |
| Regression | `Regression` | ~5min | Every PR | All functional tests (unit + BDD + integration + concurrency) + the `SecurityPR` subset |
| Full | `Full` | ~15min | Nightly / pre-release | + the full security suite, the static scans, performance and mutation |

The durations are enforced by the runners (`--enforce-budget` / `-EnforceBudget`), not merely
documented. `SecurityPR` is the BOLA / authentication / injection subset that cannot wait for the
nightly run; the selection criterion is in [`references/test-pyramid.md`](references/test-pyramid.md).

## License

MIT — See [LICENSE](LICENSE) file.

Copyright (c) 2026 4all.lat by Juan Francisco Asserella

Repository: https://github.com/4all-lat/quality-assurance-4all
