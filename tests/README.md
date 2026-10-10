# Tests

Zero-dependency test suite for the scripts in `scripts/`. It exists because this
repository is the quality gate for every project that adopts it, and until now
none of its own ~900 lines of bash and PowerShell were tested.

Nothing needs to be installed: `bash` and `git` are enough. The external
toolchains the scripts call — `dotnet`, `npm`, `npx`, `python3`, `pytest`,
`reportgenerator`, `stryker` — are intercepted by PATH shims, so the suite runs
identically on a machine with nothing installed and on a CI runner.

## Running

```bash
tests/run.sh                 # everything
tests/run.sh parity          # only cases whose name contains "parity"
QA_VERBOSE=1 tests/run.sh run-tests.dispatch   # also dump what each script printed
```

Exit code is `0` when every case passed, `1` otherwise.

## Layout

```
tests/
  run.sh                    discover cases/*.test.sh, run each in its own subshell
  lib/assert.sh             assert_eq, assert_exit, assert_contains, assert_file, ...
  lib/sandbox.sh            sandbox, PATH shims, project fixtures, qa_run
  shims/_recorder           the one shim; symlinked as every external tool
  cases/*.test.sh           one file per behaviour under test
  parity-allowlist.txt      the bash<->PowerShell differences that are deliberate
```

There is no `fixtures/` directory: fixtures are four-line functions in
`lib/sandbox.sh` (`fixture_dotnet_sln`, `fixture_node`, …), which keeps them next
to the helpers that use them instead of in a parallel tree.

## How the shims work

`install_shims` symlinks `dotnet`, `npm`, `npx`, `python3`, `python`, `pytest`,
`reportgenerator` and `stryker` to a single script, `shims/_recorder`. Every call
the scripts make is appended to `$SHIM_LOG` as `name<TAB>arg<TAB>arg…`, and the
shim exits with `$SHIM_EXIT` (default `0`).

That turns each hard-coded filter into a testable contract:

```bash
assert_shim_called dotnet test --results-directory ./test-results \
  --logger "console;verbosity=detailed" --filter "Category=Smoke"
assert_shim_called_prefix dotnet new xunit -n Proj.Tests   # trailing args ignored
assert_shim_not_called dotnet tool install -g dotnet-stryker
assert_shim_never npx
shim_reset                                                 # forget calls so far
```

Control the toolchain from a case with:

```bash
SHIM_FAIL_FOR=dotnet SHIM_FAIL_EXIT=1 export SHIM_FAIL_FOR SHIM_FAIL_EXIT
SHIM_SLEEP=2 export SHIM_SLEEP     # make each shimmed call take 2s, to overrun a tier budget
SHIM_KILL_PIPE=1 export SHIM_KILL_PIPE  # make `dotnet tool list` die of SIGPIPE
```

`SHIM_SLEEP` exists for `run-tests.budget`: it slows the calls the runner makes
without slowing the runner's own bookkeeping, so a stage can be pushed past its
budget deterministically instead of with a real `sleep`.

`SHIM_KILL_PIPE` reproduces a race that is otherwise timing-dependent, and that
the suite found in the wild: `dotnet tool list -g | grep -q "$tool"` under
`pipefail` fails exactly when the tool *is* installed, because `grep` exits on
the first match and the producer then takes SIGPIPE. Both scripts now read the
listing into a variable instead, and `setup.scaffold` and `run-tests.dispatch`
assert it with this switch.

## The cases

| Case | What it pins down |
|------|-------------------|
| `run-tests.argparse` | the exit-code contract: `0` success, `1` gate failure, `2` usage error |
| `run-tests.detect` | stack detection, and that an unusable `--project` is a hard error |
| `run-tests.dispatch` | the exact command line for every stack × stage, output dirs, failure propagation and accumulation |
| `run-tests.budget` | the tier budgets (30/300/900s) appear in both runners, the warning is not a failure, and `--enforce-budget` turns an overrun into exit `1` |
| `setup.argparse` | the same exit-code contract for the scaffolder, plus the stack enum |
| `setup.scaffold` | the generated tree: folders, coverage thresholds, pytest markers, requirements |
| `parity` | stages, flags, stack enum, default threshold and Stryker project selection agree between bash and PowerShell |
| `scripts.syntax` | every shell script parses (`bash -n`) and declares a bash shebang |
| `docs.links` | every relative link and every in-repo path named in backticks resolves |
| `docs.thresholds` | every file quotes the canonical thresholds table verbatim |
| `docs.assets` | the Gherkin template is taggable, the XML asset is well-formed, the spec template covers OWASP API1–API10 |
| `docs.diagrams` | the draw.io diagram parses, keeps its 11 tabs, and does not contradict the canonical thresholds or keep retired claims |

## The bash ↔ PowerShell parity contract

`pwsh` is not installed on the development machine, so `cases/parity.test.sh`
compares the two implementations **statically**: it extracts the stage set, the
flag set, the stack enum, the default mutation threshold and the Stryker project
selection from each pair of files and requires them to match.

Differences that are deliberate live in `parity-allowlist.txt`, one per line as
`<suite> <item>`, each with a reason. Adding a line there is a decision to let
the two drift, so it should come with a justification, not a convenience.

If `pwsh` *is* available — on a Windows CI runner, for instance — the case also
performs a dynamic comparison and reports a `skip` line otherwise.

Documented, deliberate differences:

- `run-tests.ps1` is .NET-only; `run-tests.sh` also drives Node.js and Python.
- Neither PowerShell script declares a help switch; PowerShell provides `-?` and
  comment-based help automatically.

## Adding a case

Create `tests/cases/<name>.test.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail

QA_TESTS_DIR="${QA_TESTS_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
REPO_ROOT="${REPO_ROOT:-$(cd "$QA_TESTS_DIR/.." && pwd)}"
. "$QA_TESTS_DIR/lib/assert.sh"
. "$QA_TESTS_DIR/lib/sandbox.sh"

make_sandbox
trap cleanup_sandbox EXIT
install_shims

dir="$(new_workdir)"
fixture_node "$dir"
qa_run "$dir" bash "$REPO_ROOT/scripts/run-tests.sh" -s smoke
assert_exit 0 "$QA_STATUS" "smoke exits 0"

qa_summary
```

Do **not** use `set -e`: a failing assertion must not abort the case, or one
failure would hide every assertion after it. `qa_run` never returns non-zero for
this reason; it stores the status in `$QA_STATUS` and the output in `$QA_OUT`.

## Notes

- `cases/parity.test.sh` reads the scripts as text. It will not notice a change
  in behaviour that keeps the flags and stages the same — the other cases cover
  behaviour.
- `cases/docs.thresholds.test.sh` takes `references/quality-gates.md` as the
  source of truth. Change a number there and the other files must follow, or the
  build fails.
- `cases/parity.test.sh` canonicalises PowerShell parameter names to bash long
  flags, so a multi-word name like `EnforceBudget` needs its own
  `case` branch mapping it to `--enforce-budget`. Without that line a new flag
  reads as a divergence rather than a rename.
- The test categories the pipeline stratifies on — `Smoke`, `Regression`,
  `Concurrency`, `SecurityPR`, `Security`, `Performance`, `Property` — must appear
  in both runners, in the scaffolder's `pytest.ini` markers and in
  `assets/bdd-feature-template.feature`; `docs.assets` and `setup.scaffold` pin
  the last two.
- The Windows parity job in `.github/workflows/qa.yml` has not been executed on
  the development machine (no `pwsh`); it is exercised once a PR reaches CI.
