#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Scaffolds a docs overlay and installs the docs CI/deploy workflows.

.DESCRIPTION
    Orchestration only — this script does not run Docker. The documentation build
    happens in CI inside the published base image (see scripts/docs-build.ps1),
    and local preview is handled by scripts/docs.ps1.

    The caller's ./docs directory is a self-contained overlay copied over the
    image's /template root at build time, so it mirrors that layout:

        docs/
          docusaurus.config.ts   -> /template/docusaurus.config.ts
          sidebar.ts             -> /template/sidebar.ts
          docs/                  -> /template/docs
            index.md

    Setup behavior:
    - Creates docs/ and docs/docs/ when missing.
    - Creates docs/docs/index.md when missing (from a root README if one exists,
      otherwise a stub).
    - Seeds docs/docusaurus.config.ts and docs/sidebar.ts from the template when
      missing (optional overrides of the base image defaults).
    - Installs the docs-ci.yml / docs-deploy.yml workflows (unless -SkipWorkflow).

.PARAMETER ProjectDir
    The target project directory. Defaults to the current working directory.

.PARAMETER SkipWorkflow
    Skip installing the docs CI/deploy workflows.

.PARAMETER Overwrite
    Forwarded to the workflow install: overwrite existing workflow files.

.EXAMPLE
    ./scripts/setup-docs.ps1

.EXAMPLE
    ./scripts/setup-docs.ps1 -ProjectDir "C:\path\to\project" -SkipWorkflow
#>

[CmdletBinding()]
param(
    [Parameter()][string]$ProjectDir = '.',
    [Parameter()][switch]$SkipWorkflow,
    [Parameter()][switch]$Overwrite
)

$ErrorActionPreference = 'Stop'

$scriptDir = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($scriptDir)) {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
}

function Resolve-AbsolutePath {
    param([Parameter(Mandatory)][string]$Path)

    if (Test-Path -LiteralPath $Path) {
        return (Resolve-Path -LiteralPath $Path).Path
    }

    return (New-Item -ItemType Directory -Path $Path -Force).FullName
}

$projectPath = Resolve-AbsolutePath -Path $ProjectDir
$docsDir = Join-Path $projectPath 'docs'
$contentDir = Join-Path $docsDir 'docs'
$indexFile = Join-Path $contentDir 'index.md'
$templateDir = Join-Path $scriptDir 'template'

$readmeCandidates = @(
    (Join-Path $projectPath 'README.md'),
    (Join-Path $projectPath 'readme.md')
)
$readmePath = $readmeCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1

Write-Host "[SETUP] Project directory: $projectPath" -ForegroundColor Cyan

if (-not (Test-Path -LiteralPath $contentDir)) {
    Write-Host "[SETUP] Creating docs/docs Content Directory..." -ForegroundColor Yellow
    New-Item -ItemType Directory -Path $contentDir -Force | Out-Null
}

if (-not (Test-Path -LiteralPath $indexFile)) {
    if ($readmePath) {
        Write-Host "[SETUP] Creating docs/docs/index.md from $(Split-Path -Leaf $readmePath)..." -ForegroundColor Yellow
        Get-Content -LiteralPath $readmePath -Raw | Set-Content -Path $indexFile -Encoding UTF8 -NoNewline
    }
    else {
        Write-Host "[SETUP] Creating docs/docs/index.md Scaffold..." -ForegroundColor Yellow
        Set-Content -Path $indexFile -Encoding UTF8 -NoNewline -Value @"
---
title: Home
---

# Documentation
"@
    }
}

# Seed optional config + sidebar overrides from the template when missing.
$configPairs = @(
    @{ Source = (Join-Path $templateDir 'docusaurus.config.ts'); Target = (Join-Path $docsDir 'docusaurus.config.ts') },
    @{ Source = (Join-Path $templateDir 'sidebar.ts'); Target = (Join-Path $docsDir 'sidebar.ts') }
)
foreach ($pair in $configPairs) {
    if ((Test-Path -LiteralPath $pair.Source) -and (-not (Test-Path -LiteralPath $pair.Target))) {
        Write-Host "[SETUP] Seeding docs/$(Split-Path -Leaf $pair.Target) from template..." -ForegroundColor Yellow
        Copy-Item -LiteralPath $pair.Source -Destination $pair.Target -Force
    }
}

if (-not $SkipWorkflow) {
    $workflowScript = Join-Path $scriptDir 'setup-docs-workflow.ps1'
    if (-not (Test-Path -LiteralPath $workflowScript)) {
        throw "Workflow install script not found at '$workflowScript'."
    }

    Write-Host "[SETUP] Installing docs CI/deploy workflows..." -ForegroundColor Yellow
    & $workflowScript -CallerProjectDir $projectPath -Overwrite:$Overwrite
}

Write-Host "[SETUP] Complete." -ForegroundColor Green
Write-Host "[SETUP] Next Steps:" -ForegroundColor Cyan
Write-Host "  1. Install Dependencies: pnpm install" -ForegroundColor White
Write-Host "  2. Preview Locally:      ./scripts/docs.ps1" -ForegroundColor White
Write-Host "  3. Author docs under:    docs/docs/" -ForegroundColor White
