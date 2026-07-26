<#
.SYNOPSIS
    Build and run the documentation site locally from docs/.

.DESCRIPTION
    Regenerates docs/docs/index.md from the project README, then builds an image
    that overlays docs/ onto the published docs-template base image and runs it.
    No template checkout or Node install is needed locally.

    The homepage is regenerated on every run, so a README edit is picked up
    without being remembered. The documentation gate fails if the committed copy
    ever falls behind, which is the same comparison from the other direction.

.PARAMETER Live
    Bind-mount docs/ over the running container so edits hot-reload. Omit for a
    baked run; re-run this script to pick up changes.

.PARAMETER BuildOnly
    Build the image and stop.

.PARAMETER Port
    Host port to publish. The container serves on 3000.

.PARAMETER Tag
    Image tag to build.

.PARAMETER BaseImage
    Base image passed as the Dockerfile BASE_IMAGE build argument.

.PARAMETER NoHomepage
    Skip regenerating docs/docs/index.md. Use when the homepage is authored by
    hand rather than generated from the README.

.EXAMPLE
    ./docs.ps1                 # build, run, serve http://localhost:3000
.EXAMPLE
    ./docs.ps1 -Live           # hot-reload from docs/
.EXAMPLE
    ./docs.ps1 -BuildOnly      # build only
#>
[CmdletBinding()]
param(
    [switch]$Live,
    [switch]$BuildOnly,
    [int]$Port = 3000,
    [string]$Tag = 'project-docs',
    [string]$BaseImage = 'ghcr.io/the-running-dev/docs-template:latest',
    [switch]$NoHomepage
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $MyInvocation.MyCommand.Definition
$context = Join-Path $root 'docs'
$dockerfile = Join-Path $context 'Dockerfile'
$readme = Join-Path $root 'README.md'
$index = Join-Path $context 'docs' 'index.md'
$homepageScript = Join-Path $root 'build' 'ConvertTo-DocumentationHomepage.ps1'
$rulesPath = Join-Path $root '.config' 'DocumentationRules.psd1'

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw 'docker was not found on PATH. Install or start Docker first.'
}
if (-not (Test-Path -LiteralPath $dockerfile -PathType Leaf)) {
    throw "Dockerfile not found at '$dockerfile'."
}

if (-not $NoHomepage -and (Test-Path -LiteralPath $homepageScript -PathType Leaf)) {
    if (-not (Test-Path -LiteralPath $readme -PathType Leaf)) {
        throw "README not found at '$readme'. Pass -NoHomepage to skip homepage generation."
    }

    # Reuse the front matter and site origin recorded for the gate, so preview
    # and check agree by construction rather than by being edited together.
    $homepageArguments = @{ ReadmePath = $readme }
    if (Test-Path -LiteralPath $rulesPath -PathType Leaf) {
        $rules = Import-PowerShellDataFile -LiteralPath $rulesPath
        if ($rules.Contains('GeneratedFiles')) {
            $entry = $rules.GeneratedFiles |
                Where-Object { $_.Path -replace '\\', '/' -eq 'docs/docs/index.md' } |
                Select-Object -First 1
            if ($entry -and $entry.ContainsKey('Arguments') -and $entry.Arguments) {
                foreach ($argument in $entry.Arguments.GetEnumerator()) {
                    $homepageArguments[$argument.Key] = $argument.Value
                }
            }
        }
    }

    $indexContent = & $homepageScript @homepageArguments
    [IO.File]::WriteAllText($index, $indexContent, [Text.UTF8Encoding]::new($false))
    Write-Host 'Generated docs/docs/index.md from README.md.' -ForegroundColor Cyan
}

Write-Host "Building '$Tag' from $context (base: $BaseImage) ..." -ForegroundColor Cyan
docker build --build-arg "BASE_IMAGE=$BaseImage" -f $dockerfile -t $Tag $context
if ($LASTEXITCODE -ne 0) { throw "docker build failed with exit code $LASTEXITCODE." }

if ($BuildOnly) {
    Write-Host "Built '$Tag'. (build-only)" -ForegroundColor Green
    return
}

# Docker wants forward-slash absolute paths for bind mounts.
$mountContext = ($context -replace '\\', '/')

$runArgs = @('run', '--rm', '-it', '-p', "${Port}:3000")
if ($Live) {
    Write-Host 'Live mode: edits to docs/ hot-reload.' -ForegroundColor Yellow
    $runArgs += @(
        '-v', "${mountContext}/docs:/template/docs",
        '-v', "${mountContext}/docusaurus.config.ts:/template/docusaurus.config.ts",
        '-v', "${mountContext}/sidebar.ts:/template/sidebar.ts"
    )
}
$runArgs += $Tag

Write-Host "Serving at http://localhost:$Port  (Ctrl+C to stop)" -ForegroundColor Green
docker @runArgs
