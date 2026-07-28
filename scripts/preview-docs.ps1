#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Run the docs-template image locally with live hot-reload from ./docs.

.DESCRIPTION
    This is a run-only helper for local development. It does NOT build anything —
    the static site build happens in CI via scripts/docs-build.ps1 inside the
    published base image.

    It runs the base image and bind-mounts the caller's local docs overlay over
    /template so edits hot-reload in the browser:

        ./docs/docs                  -> /template/docs
        ./docs/docusaurus.config.ts  -> /template/docusaurus.config.ts  (if present)
        ./docs/sidebar.ts            -> /template/sidebar.ts            (if present)

    The image's default command (pnpm run start:docker) serves the site on
    0.0.0.0:3000 with hot reload.

.PARAMETER Port
    Host port to publish (container serves on 3000). Default 3000.

.PARAMETER Tag
    Image to run. Defaults to the published base image. If the image is not
    present locally it is pulled.

.PARAMETER ProjectDir
    Project directory containing the docs overlay. Defaults to the current
    directory.

.PARAMETER DocsDirectory
    The overlay directory to bind-mount, relative to -ProjectDir. Defaults to
    'docs' -- pass the same value given to setup-docs.ps1's -DocsDirectory so
    this preview mounts the project's actual overlay rather than a stale
    default.

.EXAMPLE
    ./scripts/preview-docs.ps1          # serve http://localhost:3000/docs with hot reload
.EXAMPLE
    ./scripts/preview-docs.ps1 -Port 8080
#>

[CmdletBinding()]
param(
    [Parameter()][int]$Port = 3000,
    [Parameter()][string]$Tag = 'ghcr.io/the-running-dev/docs-template:latest',
    [Parameter()][string]$ProjectDir = '.',
    [Parameter()][ValidateNotNullOrEmpty()][string]$DocsDirectory = 'docs'
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw 'docker not found on PATH. Install/launch Docker Desktop first.'
}

if (-not (Test-Path -LiteralPath $ProjectDir)) {
    throw "Project directory not found at '$ProjectDir'."
}

$root = (Resolve-Path -LiteralPath $ProjectDir).Path
$docsDir = Join-Path $root $DocsDirectory

if (-not (Test-Path -LiteralPath $docsDir)) {
    throw "No '$DocsDirectory' directory at '$docsDir'. Run scripts/setup-docs.ps1 first to scaffold it."
}

# Ensure the image exists locally; pull it if not.
& docker image inspect $Tag *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Host "[DOCS] Image '$Tag' not found locally. Pulling ..." -ForegroundColor Yellow
    & docker pull $Tag
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to pull image '$Tag'. Log in to the registry or pass a local -Tag."
    }
}

# Docker wants forward-slash absolute paths for bind mounts.
$docsHost = ($docsDir -replace '\\', '/')

$runArgs = @('run', '--rm', '-it', '-p', "${Port}:3000")

# docs/ content is always overlaid for hot reload.
$docsContent = Join-Path $docsDir 'docs'
if (Test-Path -LiteralPath $docsContent) {
    $runArgs += @('-v', "${docsHost}/docs:/template/docs")
}
else {
    Write-Host "[DOCS] Note: '$docsContent' not found; serving without a docs/ overlay." -ForegroundColor Yellow
}

# Optional config + sidebar overrides.
$docusaurusConfig = Join-Path $docsDir 'docusaurus.config.ts'
if (Test-Path -LiteralPath $docusaurusConfig) {
    $runArgs += @('-v', "${docsHost}/docusaurus.config.ts:/template/docusaurus.config.ts")
}

$sidebarTs = Join-Path $docsDir 'sidebar.ts'
if (Test-Path -LiteralPath $sidebarTs) {
    $runArgs += @('-v', "${docsHost}/sidebar.ts:/template/sidebar.ts")
}

$runArgs += $Tag

Write-Host "[DOCS] Serving at http://localhost:$Port/docs  (Ctrl+C to stop)" -ForegroundColor Green
& docker @runArgs
