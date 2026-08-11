<#
.SYNOPSIS
    Quick-start QA project scaffolder.

.DESCRIPTION
    Creates a test project with the recommended folder structure and installs
    all necessary QA packages for the specified stack.

.PARAMETER ProjectName
    Name of the test project to create (e.g., "MyProject.Tests").

.PARAMETER Stack
    Technology stack: dotnet, nodejs, or python.

.PARAMETER OutputDir
    Directory where the test project will be created. Defaults to current directory.

.EXAMPLE
    .\setup-qa-project.ps1 -ProjectName "MyProject.Tests" -Stack dotnet
    Creates a .NET xUnit test project with all QA packages and folder structure.

.EXAMPLE
    .\setup-qa-project.ps1 -ProjectName "my-project-tests" -Stack nodejs
    Creates a Node.js/TypeScript Vitest project with all QA packages and folder structure.

.EXAMPLE
    .\setup-qa-project.ps1 -ProjectName "my_project_tests" -Stack python
    Creates a Python pytest project with all QA packages and folder structure.
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectName,

    [Parameter(Mandatory = $true)]
    [ValidateSet("dotnet", "nodejs", "python")]
    [string]$Stack,

    [Parameter(Mandatory = $false)]
    [string]$OutputDir = "."
)

$ErrorActionPreference = "Stop"

$projectPath = Join-Path $OutputDir $ProjectName

Write-Host ""
Write-Host "QA Project Setup" -ForegroundColor Cyan
Write-Host "  Project: $ProjectName" -ForegroundColor Gray
Write-Host "  Stack:   $Stack" -ForegroundColor Gray
Write-Host "  Path:    $projectPath" -ForegroundColor Gray
Write-Host ""

if (Test-Path $projectPath) {
    Write-Error "Directory already exists: $projectPath"
    exit 1
}

switch ($Stack) {

    "dotnet" {
        Write-Host "[1/4] Creating xUnit test project..." -ForegroundColor Yellow
        dotnet new xunit -n $ProjectName -o $projectPath
        Push-Location $projectPath

        Write-Host "[2/4] Installing QA packages..." -ForegroundColor Yellow
        $packages = @(
            "FluentAssertions",
            "Moq",
            "coverlet.collector",
            "Microsoft.AspNetCore.Mvc.Testing",
            "FsCheck",
            "FsCheck.Xunit",
            "Reqnroll.NUnit",
            "NUnit3TestAdapter",
            "Microsoft.Playwright.NUnit"
        )
        foreach ($pkg in $packages) {
            Write-Host "  - $pkg" -ForegroundColor Gray
            dotnet add package $pkg 2>$null
        }

        Write-Host "[3/4] Installing global tools..." -ForegroundColor Yellow
        $tools = @(
            "dotnet-stryker",
            "dotnet-reportgenerator-globaltool"
        )
        foreach ($tool in $tools) {
            $installed = dotnet tool list -g 2>$null | Select-String $tool
            if (-not $installed) {
                Write-Host "  - $tool" -ForegroundColor Gray
                dotnet tool install -g $tool
            } else {
                Write-Host "  - $tool (already installed)" -ForegroundColor DarkGray
            }
        }

        Write-Host "[4/4] Creating folder structure..." -ForegroundColor Yellow
        $folders = @("Features", "Integration", "Security", "Performance", "PropertyBased", "Controllers", "Services", "Repositories")
        foreach ($folder in $folders) {
            $folderPath = Join-Path $projectPath $folder
            New-Item -ItemType Directory -Path $folderPath -Force | Out-Null
            Write-Host "  - $folder/" -ForegroundColor Gray
        }

        Pop-Location
        Write-Host ""
        Write-Host "Done! .NET QA project created at: $projectPath" -ForegroundColor Green
        Write-Host ""
        Write-Host "Next steps:" -ForegroundColor Cyan
        Write-Host "  1. Add coverage config to .csproj (see assets/coverage-config.xml)" -ForegroundColor Gray
        Write-Host "  2. Add project reference: dotnet add reference ../src/MyProject/MyProject.csproj" -ForegroundColor Gray
        Write-Host "  3. Copy BDD template: copy assets\bdd-feature-template.feature Features\resource.feature" -ForegroundColor Gray
        Write-Host "  4. Run smoke tests: dotnet test --filter Category=Smoke" -ForegroundColor Gray
    }

    "nodejs" {
        Write-Host "[1/4] Creating Node.js project..." -ForegroundColor Yellow
        New-Item -ItemType Directory -Path $projectPath -Force | Out-Null
        Push-Location $projectPath

        # Initialize project
        npm init -y 2>$null

        Write-Host "[2/4] Installing QA packages..." -ForegroundColor Yellow
        $devDeps = @(
            "vitest",
            "@playwright/test",
            "fast-check",
            "@cucumber/cucumber",
            "c8",
            "@stryker-mutator/core"
        )
        Write-Host "  npm install -D $($devDeps -join ' ')" -ForegroundColor Gray
        npm install -D $devDeps 2>$null

        Write-Host "[3/4] Creating vitest.config.ts..." -ForegroundColor Yellow
        $vitestConfig = @"
import { defineConfig } from 'vitest/config'

export default defineConfig({
  test: {
    coverage: {
      provider: 'c8',
      reporter: ['text', 'html', 'cobertura'],
      thresholds: {
        lines: 80,
        functions: 80,
        branches: 80,
        statements: 80,
      },
      exclude: ['node_modules/', 'dist/', '**/*.config.*'],
    },
  },
})
"@
        Set-Content -Path "vitest.config.ts" -Value $vitestConfig

        Write-Host "[4/4] Creating folder structure..." -ForegroundColor Yellow
        $folders = @("features", "integration", "security", "performance", "property-based", "unit")
        foreach ($folder in $folders) {
            $folderPath = Join-Path $projectPath $folder
            New-Item -ItemType Directory -Path $folderPath -Force | Out-Null
            Write-Host "  - $folder/" -ForegroundColor Gray
        }

        Pop-Location
        Write-Host ""
        Write-Host "Done! Node.js/TS QA project created at: $projectPath" -ForegroundColor Green
        Write-Host ""
        Write-Host "Next steps:" -ForegroundColor Cyan
        Write-Host "  1. Add test scripts to package.json" -ForegroundColor Gray
        Write-Host "  2. Copy BDD template to features/" -ForegroundColor Gray
        Write-Host "  3. Run: npx vitest --grep Smoke" -ForegroundColor Gray
    }

    "python" {
        Write-Host "[1/4] Creating Python project..." -ForegroundColor Yellow
        New-Item -ItemType Directory -Path $projectPath -Force | Out-Null
        Push-Location $projectPath

        # Create requirements file
        $requirements = @"
# QA Pipeline — Python dependencies
pytest>=8.0
pytest-cov>=4.0
hypothesis>=6.0
behave>=1.2
mutmut>=2.0
locust>=2.0
"@
        Set-Content -Path "requirements.txt" -Value $requirements

        Write-Host "[2/4] Installing QA packages..." -ForegroundColor Yellow
        pip install -r requirements.txt 2>$null

        Write-Host "[3/4] Creating .coveragerc..." -ForegroundColor Yellow
        $coveragerc = @"
[run]
source = ./src
omit =
    */migrations/*
    */tests/*
    */config/*

[report]
fail_under = 80
show_missing = True

[html]
directory = coverage_html_report
"@
        Set-Content -Path ".coveragerc" -Value $coveragerc

        Write-Host "[4/4] Creating folder structure..." -ForegroundColor Yellow
        $folders = @("features", "integration", "security", "performance", "property_based", "unit")
        foreach ($folder in $folders) {
            $folderPath = Join-Path $projectPath $folder
            New-Item -ItemType Directory -Path $folderPath -Force | Out-Null
            Write-Host "  - $folder/" -ForegroundColor Gray
            # Create __init__.py for Python packages
            Set-Content -Path (Join-Path $folderPath "__init__.py") -Value ""
        }

        # Create pytest.ini with markers
        $pytestIni = @"
[pytest]
markers =
    smoke: quick health check tests (run on every commit)
    regression: functional tests (run on every PR)
    security: security tests (OWASP API Top 10)
    performance: performance/load tests
    property: property-based tests
"@
        Set-Content -Path "pytest.ini" -Value $pytestIni

        Pop-Location
        Write-Host ""
        Write-Host "Done! Python QA project created at: $projectPath" -ForegroundColor Green
        Write-Host ""
        Write-Host "Next steps:" -ForegroundColor Cyan
        Write-Host "  1. Copy BDD template to features/" -ForegroundColor Gray
        Write-Host "  2. Run smoke: pytest -m smoke" -ForegroundColor Gray
        Write-Host "  3. Run with coverage: pytest --cov" -ForegroundColor Gray
    }
}

Write-Host ""
Write-Host "Recommended folder structure:" -ForegroundColor Cyan
Write-Host @"
  $ProjectName/
    Features/          # BDD .feature files (Gherkin)
    Integration/       # In-memory + live integration tests
    Security/          # OWASP security tests
    Performance/       # Load and latency tests
    PropertyBased/     # Property-based / generative tests
    Controllers/       # Unit tests for controllers (or Unit/ for Node.js/Python)
    Services/          # Unit tests for services
    Repositories/      # Unit tests for repositories
"@ -ForegroundColor Gray
Write-Host ""
