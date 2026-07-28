<#
.SYNOPSIS
    Build and run the documentation site locally from docs/.

.DESCRIPTION
    Regenerates the README-derived page from the project README, then builds an
    image that overlays docs/ onto the published docs-template base image and
    runs it. No template checkout or Node install is needed locally.

    Where that page lives depends on the installed routeBasePath: at
    docs/docs/index.md when it is '/', or docs/src/pages/index.md -- the site
    root -- for any other value. Read live from docs/docusaurus.config.ts on
    every run, not cached, so it reflects a routeBasePath the project has
    changed since install.

    The page is regenerated on every run, so a README edit is picked up without
    being remembered. The documentation gate fails if the committed copy ever
    falls behind, which is the same comparison from the other direction.

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
    Skip regenerating the README-derived page. Use when it is authored by hand
    rather than generated from the README.

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
$homepageScript = Join-Path $root 'build' 'ConvertTo-DocumentationHomepage.ps1'
$rulesPath = Join-Path $root '.config' 'DocumentationRules.psd1'
$configPath = Join-Path $context 'docusaurus.config.ts'

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

    # Read live from docusaurus.config.ts rather than trusting the rules file
    # alone, so this still resolves correctly for a project installed with
    # -SkipGate (no rules file at all) and reflects a routeBasePath the
    # project has hand-edited since install.
    $routeBasePath = '/'
    if (Test-Path -LiteralPath $configPath -PathType Leaf) {
        $configMatch = [regex]::Match(
            (Get-Content -LiteralPath $configPath -Raw),
            "routeBasePath:\s*'([^']*)'")
        if ($configMatch.Success -and -not [string]::IsNullOrWhiteSpace($configMatch.Groups[1].Value)) {
            $routeBasePath = $configMatch.Groups[1].Value
        }
    }

    $relativeIndexPath = if ($routeBasePath.Trim('/') -eq '') {
        'docs/docs/index.md'
    }
    else {
        'docs/src/pages/index.md'
    }
    $index = Join-Path $root ($relativeIndexPath -replace '/', [IO.Path]::DirectorySeparatorChar)

    # Reuse the front matter and site origin recorded for the gate, so preview
    # and check agree by construction rather than by being edited together.
    # RouteBasePath is seeded from the live read above and then, if the rules
    # file has its own copy, overwritten with that -- the two are written from
    # the same value at install time, so this is a no-op except when the rules
    # file is absent (-SkipGate), where the live read is all there is.
    $homepageArguments = @{ ReadmePath = $readme; RouteBasePath = $routeBasePath }
    if (Test-Path -LiteralPath $rulesPath -PathType Leaf) {
        $rules = Import-PowerShellDataFile -LiteralPath $rulesPath
        if ($rules.Contains('GeneratedFiles') -and $rules.GeneratedFiles.Count -gt 0) {
            $entry = $rules.GeneratedFiles[0]
            if ($entry.ContainsKey('Arguments') -and $entry.Arguments) {
                foreach ($argument in $entry.Arguments.GetEnumerator()) {
                    $homepageArguments[$argument.Key] = $argument.Value
                }
            }
        }
    }

    $indexDir = Split-Path -Parent $index
    if (-not (Test-Path -LiteralPath $indexDir -PathType Container)) {
        New-Item -ItemType Directory -Path $indexDir -Force | Out-Null
    }

    $indexContent = & $homepageScript @homepageArguments
    [IO.File]::WriteAllText($index, $indexContent, [Text.UTF8Encoding]::new($false))
    Write-Host "Generated $relativeIndexPath from README.md." -ForegroundColor Cyan
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

    # Only when present: routeBasePath '/' has no site-root page under
    # src/pages at all, and mounting a host path that does not exist would
    # have Docker silently create an empty directory instead.
    $pagesDir = Join-Path $context 'src' 'pages'
    if (Test-Path -LiteralPath $pagesDir -PathType Container) {
        $runArgs += @('-v', "${mountContext}/src/pages:/template/src/pages")
    }
}
$runArgs += $Tag

Write-Host "Serving at http://localhost:$Port  (Ctrl+C to stop)" -ForegroundColor Green
docker @runArgs
