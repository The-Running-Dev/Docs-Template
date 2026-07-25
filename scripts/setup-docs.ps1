#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Initializes docs scaffold and optionally builds/runs docs via Docker.

.DESCRIPTION
    This script is intentionally generic so it can be reused outside this repository.

    Setup behavior:
    - Creates docs/ when missing
    - Creates docs/index.md when missing
    - If a root README.md/readme.md exists, uses that content for docs/index.md
    - Creates docs/Dockerfile when missing

    Optional Docker behavior (from docs.ps1 workflow):
    - Builds docs image from docs/Dockerfile
    - Optionally runs container with live bind mounts for docs and config files

.PARAMETER ProjectDir
    The target project directory. Defaults to the current working directory.

.PARAMETER DockerDocs
    Build/run docs Docker workflow after setup.

.PARAMETER Live
    Builds and runs the Docker docs workflow with docs/config files bind-mounted
    for hot reload. Implies -DockerDocs.

.PARAMETER BuildOnly
    Builds the Docker docs image without running it. Implies -DockerDocs.

.PARAMETER Port
    Host port for Docker docs server (container uses 3000).

.PARAMETER Tag
    Docker image tag for docs image build.

.PARAMETER BaseImage
    Base image passed as docs/Dockerfile BASE_IMAGE build arg.

.EXAMPLE
    ./scripts/setup-docs.ps1

.EXAMPLE
    ./scripts/setup-docs.ps1 -ProjectDir "C:\path\to\project"

.EXAMPLE
    ./scripts/setup-docs.ps1 -DockerDocs -Live
#>

[CmdletBinding()]
param(
    [Parameter()][string]$ProjectDir = '.',
    [Parameter()][switch]$DockerDocs,
    [Parameter()][switch]$Live,
    [Parameter()][switch]$BuildOnly,
    [Parameter()][int]$Port = 3000,
    [Parameter()][string]$Tag = 'docusaurus-docs',
    [Parameter()][string]$BaseImage = 'ghcr.io/the-running-dev/docs-template:latest'
)

$ErrorActionPreference = 'Stop'

function Resolve-AbsolutePath {
    param(
        [Parameter(Mandatory)][string]$Path
    )

    if (Test-Path -LiteralPath $Path) {
        return (Resolve-Path -LiteralPath $Path).Path
    }

    $item = New-Item -ItemType Directory -Path $Path -Force

    return $item.FullName
}

$projectPath = Resolve-AbsolutePath -Path $ProjectDir
$docsDir = Join-Path $projectPath 'docs'
$indexFile = Join-Path $docsDir 'index.md'
$dockerfile = Join-Path $docsDir 'Dockerfile'
$readmeCandidates = @(
    (Join-Path $projectPath 'README.md'),
    (Join-Path $projectPath 'readme.md')
)
$readmePath = $readmeCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1

Write-Host "[SETUP] Project directory: $projectPath" -ForegroundColor Cyan

if (-not (Test-Path -LiteralPath $docsDir)) {
    Write-Host "[SETUP] Creating Docs Directory..." -ForegroundColor Yellow
    New-Item -ItemType Directory -Path $docsDir -Force | Out-Null
}

if (-not (Test-Path -LiteralPath $indexFile)) {
    if ($readmePath) {
        Write-Host "[SETUP] Creating docs/index.md from $(Split-Path -Leaf $readmePath)..." -ForegroundColor Yellow
        Get-Content -LiteralPath $readmePath -Raw | Set-Content -Path $indexFile -Encoding UTF8 -NoNewline
    }
    else {
        Write-Host "[SETUP] Creating docs/index.md Scaffold..." -ForegroundColor Yellow
        Set-Content -Path $indexFile -Encoding UTF8 -NoNewline -Value @"
---
title: Home
---

# Documentation
"@
    }
}

if (-not (Test-Path -LiteralPath $dockerfile)) {
    Write-Host "[SETUP] Creating docs/Dockerfile..." -ForegroundColor Yellow
    Set-Content -LiteralPath $dockerfile -Encoding UTF8 -NoNewline -Value @'
ARG BASE_IMAGE=ghcr.io/the-running-dev/docs-template:latest
FROM ${BASE_IMAGE}

WORKDIR /template
COPY . ./docs

CMD ["sh", "-c", "pnpm run start:docker"]
'@
}

Write-Host "[SETUP] Complete." -ForegroundColor Green
Write-Host "[SETUP] Next Steps:" -ForegroundColor Cyan
Write-Host "  1. Install Dependencies: pnpm install" -ForegroundColor White
Write-Host "  2. Start Dev Server:    pnpm run dev" -ForegroundColor White

if ($Live -or $BuildOnly) {
    $DockerDocs = $true
}

if ($DockerDocs) {
    $context = Join-Path $projectPath 'docs'

    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        throw "Docker not Found on PATH. Install/launch Docker Desktop First."
    }
    if (-not (Test-Path -LiteralPath $dockerfile)) {
        throw "Dockerfile not Found at $dockerfile"
    }

    Write-Host "[DOCKER] Building '$Tag' from $context (base: $BaseImage) ..." -ForegroundColor Cyan
    & docker build --build-arg "BASE_IMAGE=$BaseImage" -f $dockerfile -t $Tag $context

    if ($LASTEXITCODE -ne 0) {
        throw "Docker Build Failed (exit $LASTEXITCODE)"
    }

    if ($BuildOnly) {
        Write-Host "[DOCKER] Built '$Tag'. (build-only)" -ForegroundColor Green
        return
    }

    $ctx = ($context -replace '\\', '/')
    $runArgs = @('run', '--rm', '-it', '-p', "${Port}:3000")

    if ($Live) {
        Write-Host "[DOCKER] Live Mode Enabled (bind mounts)." -ForegroundColor Yellow
        $runArgs += @('-v', "${ctx}/docs:/template/docs")

        $docusaurusConfig = Join-Path $context 'docusaurus.config.ts'
        if (Test-Path -LiteralPath $docusaurusConfig) {
            $runArgs += @('-v', "${ctx}/docusaurus.config.ts:/template/docusaurus.config.ts")
        }

        $sidebarTs = Join-Path $context 'sidebar.ts'
        $sidebarsTs = Join-Path $projectPath 'sidebars.ts'
        if (Test-Path -LiteralPath $sidebarTs) {
            $runArgs += @('-v', "${ctx}/sidebar.ts:/template/sidebar.ts")
        }
        elseif (Test-Path -LiteralPath $sidebarsTs) {
            $sidebarsHost = ((Resolve-Path -LiteralPath $sidebarsTs).Path -replace '\\', '/')
            $runArgs += @('-v', "${sidebarsHost}:/template/sidebars.ts")
        }
    }

    $runArgs += $Tag
    Write-Host "[DOCKER] Serving at http://localhost:$Port/docs (Ctrl+C to stop)" -ForegroundColor Green
    
    & docker @runArgs
}
