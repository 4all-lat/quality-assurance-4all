<#
.SYNOPSIS
    Stratified test runner for the QA pipeline.

.DESCRIPTION
    Runs tests in tiers (Smoke, Regression, Full) with optional Coverage and Mutation stages.
    Designed for .NET projects using xUnit with [Trait("Category", "...")] categorization.

    - Smoke:      ~30s, every commit. Health, swagger, auth login.
    - Regression: ~5min, every PR. All functional tests (unit + BDD + integration).
    - Full:       ~15min, nightly/pre-release. + security + performance + mutation.
    - Coverage:   Generate coverage report only.
    - Mutation:   Run mutation testing only.

.PARAMETER Stage
    The test stage to run. One of: Smoke, Regression, Full, Coverage, Mutation.

.PARAMETER Project
    Path to the test .csproj file. If not specified, searches for *.Tests.csproj in current directory.

.PARAMETER OutputDir
    Directory for output artifacts (coverage reports, mutation reports). Defaults to ./test-results.

.PARAMETER MutationThreshold
    Minimum mutation score (percentage) that makes the run fail in Full/Mutation stages. Defaults to 60.

.EXAMPLE
    .\run-tests.ps1 -Stage Smoke
    Runs smoke tests only (~30s).

.EXAMPLE
    .\run-tests.ps1 -Stage Regression
    Runs all functional tests except security and performance (~5min).

.EXAMPLE
    .\run-tests.ps1 -Stage Full
    Runs all tests including security and performance (~15min).

.EXAMPLE
    .\run-tests.ps1 -Stage Coverage
    Runs all tests with coverage and generates an HTML report.

.EXAMPLE
    .\run-tests.ps1 -Stage Mutation
    Runs Stryker.NET mutation testing.

.EXAMPLE
    .\run-tests.ps1 -Stage Full -Project .\src\MyProject.Tests\MyProject.Tests.csproj
    Runs the full suite against a specific test project.
#>

param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("Smoke", "Regression", "Full", "Coverage", "Mutation")]
    [string]$Stage,

    [Parameter(Mandatory = $false)]
    [string]$Project = "",

    [Parameter(Mandatory = $false)]
    [string]$OutputDir = "./test-results",

    [Parameter(Mandatory = $false)]
    [int]$MutationThreshold = 60
)

$ErrorActionPreference = "Stop"

# --- Helper Functions ---

function Write-StageHeader($name, $description) {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  STAGE: $name" -ForegroundColor Cyan
    Write-Host "  $description" -ForegroundColor Gray
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
}

function Write-StageResult($name, $success, $duration) {
    Write-Host ""
    if ($success) {
        Write-Host "  [PASS] $name completed in $duration" -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] $name failed after $duration" -ForegroundColor Red
    }
    Write-Host ""
}

function Find-TestProject {
    if ($script:Project -and (Test-Path $script:Project)) {
        return $script:Project
    }
    $found = Get-ChildItem -Path . -Recurse -Filter "*.Tests.csproj" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) {
        return $found.FullName
    }
    # Fallback: any .csproj with test references
    $found = Get-ChildItem -Path . -Recurse -Filter "*.csproj" -ErrorAction SilentlyContinue | Where-Object {
        (Get-Content $_.FullName -Raw) -match "(xunit|NUnit|Microsoft\.NET\.Test\.Sdk)"
    } | Select-Object -First 1
    if ($found) {
        return $found.FullName
    }
    Write-Error "No test project found. Specify -Project <path-to-csproj>."
    exit 1
}

function Ensure-OutputDir {
    if (-not (Test-Path $OutputDir)) {
        New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
    }
}

function Ensure-Tool($toolName) {
    $installed = dotnet tool list -g 2>$null | Select-String $toolName
    if (-not $installed) {
        Write-Host "  Installing $toolName globally..." -ForegroundColor Yellow
        dotnet tool install -g $toolName
    }
}

# --- Main ---

$testProject = Find-TestProject
Ensure-OutputDir

Write-Host ""
Write-Host "QA Pipeline Test Runner" -ForegroundColor White
Write-Host "  Stage:   $Stage" -ForegroundColor Gray
Write-Host "  Project: $testProject" -ForegroundColor Gray
Write-Host "  Output:  $OutputDir" -ForegroundColor Gray

$overallStart = Get-Date
$overallSuccess = $true

switch ($Stage) {

    "Smoke" {
        Write-StageHeader "Smoke" "Quick health check (~30s) — every commit"
        $start = Get-Date
        dotnet test $testProject --filter "Category=Smoke" --logger "console;verbosity=detailed" --results-directory $OutputDir
        $success = $LASTEXITCODE -eq 0
        $duration = ((Get-Date) - $start).ToString("mm\:ss")
        Write-StageResult "Smoke" $success $duration
        if (-not $success) { $overallSuccess = $false }
    }

    "Regression" {
        Write-StageHeader "Regression" "Full functional validation (~5min) — every PR"
        $start = Get-Date
        dotnet test $testProject --filter "Category!=Security&Category!=Performance" --logger "console;verbosity=detailed" --results-directory $OutputDir
        $success = $LASTEXITCODE -eq 0
        $duration = ((Get-Date) - $start).ToString("mm\:ss")
        Write-StageResult "Regression" $success $duration
        if (-not $success) { $overallSuccess = $false }
    }

    "Full" {
        Write-StageHeader "Full" "Complete QA suite (~15min) — nightly / pre-release"

        # Step 1: All tests
        Write-Host "  [1/2] Running all tests..." -ForegroundColor Gray
        $start = Get-Date
        dotnet test $testProject --logger "console;verbosity=detailed" --results-directory $OutputDir
        $success = $LASTEXITCODE -eq 0
        $duration = ((Get-Date) - $start).ToString("mm\:ss")
        Write-StageResult "All Tests" $success $duration
        if (-not $success) { $overallSuccess = $false }

        # Step 2: Mutation testing (fails if score < MutationThreshold)
        Write-Host "  [2/2] Running mutation testing..." -ForegroundColor Gray
        Ensure-Tool "dotnet-stryker"
        $start = Get-Date
        dotnet stryker --output-path "$OutputDir/mutation-report" --break-at $MutationThreshold
        $mutationSuccess = $LASTEXITCODE -eq 0
        $duration = ((Get-Date) - $start).ToString("mm\:ss")
        Write-StageResult "Mutation Testing" $mutationSuccess $duration
        if (-not $mutationSuccess) { $overallSuccess = $false }
    }

    "Coverage" {
        Write-StageHeader "Coverage" "Generate coverage report"
        $start = Get-Date
        dotnet test $testProject --collect:"XPlat Code Coverage" --results-directory $OutputDir
        $success = $LASTEXITCODE -eq 0

        # Generate HTML report
        if ($success) {
            Ensure-Tool "dotnet-reportgenerator-globaltool"
            $coberturaFiles = Get-ChildItem -Path $OutputDir -Recurse -Filter "coverage.cobertura.xml" | Select-Object -ExpandProperty FullName
            if ($coberturaFiles) {
                $reports = $coberturaFiles -join ";"
                reportgenerator -reports:$reports -targetdir:"$OutputDir/coverage-report" -reporttypes:"Html;Cobertura"
                Write-Host "  Coverage report generated at: $OutputDir/coverage-report/index.html" -ForegroundColor Green
            }
        }

        $duration = ((Get-Date) - $start).ToString("mm\:ss")
        Write-StageResult "Coverage" $success $duration
        if (-not $success) { $overallSuccess = $false }
    }

    "Mutation" {
        Write-StageHeader "Mutation" "Run mutation testing only (fails if score < $MutationThreshold%)"
        Ensure-Tool "dotnet-stryker"
        $start = Get-Date
        dotnet stryker --output-path "$OutputDir/mutation-report" --break-at $MutationThreshold
        $success = $LASTEXITCODE -eq 0
        $duration = ((Get-Date) - $start).ToString("mm\:ss")
        Write-StageResult "Mutation" $success $duration
        if (-not $success) { $overallSuccess = $false }
    }
}

$overallDuration = ((Get-Date) - $overallStart).ToString("mm\:ss")

Write-Host ""
Write-Host "========================================" -ForegroundColor $(if ($overallSuccess) { "Green" } else { "Red" })
if ($overallSuccess) {
    Write-Host "  OVERALL: PASS ($overallDuration)" -ForegroundColor Green
} else {
    Write-Host "  OVERALL: FAIL ($overallDuration)" -ForegroundColor Red
}
Write-Host "========================================" -ForegroundColor $(if ($overallSuccess) { "Green" } else { "Red" })
Write-Host ""

if (-not $overallSuccess) { exit 1 }
