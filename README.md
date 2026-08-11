# Quality Assurance 4All Skill

End-to-end QA pipeline guide from spec to production. Covers TDD, BDD, SDD, property-based testing, mutation testing, security testing, performance testing, code coverage, and regression suite stratification.

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
| 6. Security | OWASP API Top 10 | All 10 risks tested |
| 7. Performance | Load Testing | P95 < target, < 0.1% errors |
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

This skill is designed to be installed as an agent skill. Place the `quality-assurance-4all/` folder in your skills directory:

```
~/.agents/skills/quality-assurance-4all/
```

Or install from the source repository:

```bash
devin skill install https://github.com/4all-lat/quality-assurance-4all
```

## Usage

The skill is invoked automatically by the AI agent when the user's request matches any of the "When to Use" scenarios above. You can also explicitly trigger it:

```
Use the quality-assurance-4all skill to set up QA for this project.
```

### Quick Start

For a new .NET project, run the setup script to scaffold the test project structure:

```powershell
.\scripts\setup-qa-project.ps1 -ProjectName "MyProject.Tests" -Stack dotnet
```

For the stratified test runner:

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
  assets/               # Reusable templates and config snippets
    ai-spec-template.md     # AI Spec / Feature Spec template
    bdd-feature-template.feature  # Gherkin BDD scenario template
    pre-production-checklist.md   # Pre-production quality checklist
    coverage-config.xml     # Coverlet coverage configuration snippet
  scripts/              # Working scripts for CI and project setup
    run-tests.ps1           # Stratified test runner (Smoke/Regression/Full)
    setup-qa-project.ps1    # Quick-start QA project scaffolder
    README.md               # Scripts documentation
```

## Stacks Supported

| Stack | Unit | BDD | Property-Based | Coverage | Mutation |
|-------|------|-----|-----------------|----------|----------|
| .NET | xUnit / NUnit | Reqnroll | FsCheck | Coverlet | Stryker.NET |
| Node.js/TS | Vitest / Jest | Cucumber.js | fast-check | c8 / istanbul | Stryker.js |
| Python | pytest | Behave | Hypothesis | coverage.py | mutmut / cosmic-ray |

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
| Regression | `Regression` | ~5min | Every PR | All functional tests (unit + BDD + integration) |
| Full | `Full` | ~15min | Nightly / pre-release | + security + performance + mutation |

## License

MIT — See [LICENSE](LICENSE) file.

Copyright (c) 2026 4all.lat by Juan Francisco Asserella

Repository: https://github.com/4all-lat/quality-assurance-4all
