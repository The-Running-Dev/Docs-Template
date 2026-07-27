<#
.SYNOPSIS
    Build and run the Docusaurus docs site from docs/ using docs/Dockerfile.

.DESCRIPTION
    The image extends the base docs-template (ghcr.io/the-running-dev/docs-template)
    and overlays the docs/ build context — our docusaurus.config.ts, sidebar.ts, and
    the markdown under docs/docs — over /template (Dockerfile `COPY . .`). That overlay
    is what overwrites the base image's default config and sidebar with the local ones.

.PARAMETER Live
    Bind-mount docs/ over the running container so editing markdown or config
    hot-reloads in the browser without rebuilding. Omit for a baked run (the image
    is self-contained; re-run this script to pick up edits).

.PARAMETER BuildOnly
    Build the image and stop; do not run a container.

.PARAMETER Port
    Host port to publish (container serves on 3000). Default 3000.

.PARAMETER Tag
    Image tag to build. Default 'gameoflife-docs'.

.PARAMETER BaseImage
    Base image passed as the Dockerfile BASE_IMAGE build-arg.

.EXAMPLE
    ./docs.ps1                 # build, run baked, serve http://localhost:3000/docs
.EXAMPLE
    ./docs.ps1 -Live           # build, run with hot-reload from docs/
.EXAMPLE
    ./docs.ps1 -BuildOnly      # just build the image
#>
[CmdletBinding()]
param(
    [switch]$Live,
    [switch]$BuildOnly,
    [int]$Port = 3000,
    [string]$Tag = 'gameoflife-docs',
    [string]$BaseImage = 'ghcr.io/the-running-dev/docs-template:latest'
)

$ErrorActionPreference = 'Stop'

# docs/ is both the Docker build context and the Docusaurus overlay.
$root    = Split-Path -Parent $MyInvocation.MyCommand.Definition
$context = Join-Path $root 'docs'
$dockerfile = Join-Path $context 'Dockerfile'

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw "docker not found on PATH. Install/launch Docker Desktop first."
}
if (-not (Test-Path $dockerfile)) {
    throw "Dockerfile not found at $dockerfile"
}

Write-Host "Building '$Tag' from $context (base: $BaseImage) ..." -ForegroundColor Cyan
docker build --build-arg "BASE_IMAGE=$BaseImage" -f $dockerfile -t $Tag $context
if ($LASTEXITCODE -ne 0) { throw "docker build failed (exit $LASTEXITCODE)" }

if ($BuildOnly) {
    Write-Host "Built '$Tag'. (build-only)" -ForegroundColor Green
    return
}

# Docker Desktop wants forward-slash absolute paths for bind mounts.
$ctx = ($context -replace '\\', '/')

$runArgs = @('run', '--rm', '-it', '-p', "${Port}:3000")

if ($Live) {
    Write-Host "Live mode: editing docs/ hot-reloads (bind-mounted over /template)." -ForegroundColor Yellow
    $runArgs += @(
        '-v', "${ctx}/docs:/template/docs",
        '-v', "${ctx}/docusaurus.config.ts:/template/docusaurus.config.ts",
        '-v', "${ctx}/sidebar.ts:/template/sidebar.ts"
    )
}

$runArgs += $Tag

Write-Host "Serving at http://localhost:$Port/docs  (Ctrl+C to stop)" -ForegroundColor Green
docker @runArgs
