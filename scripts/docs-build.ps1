#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Build the documentation static site from inside the docs-template image.

.DESCRIPTION
    This script runs INSIDE the published base image (ghcr.io/the-running-dev/
    docs-template), where the full template already lives under /template with
    node_modules installed. It is the in-container build orchestrator used by the
    `docs-ci` / `docs-deploy` workflows (job-level `container:`), so it does NOT
    invoke the Docker CLI itself.

    Flow:
    1. Overlay the caller's local docs directory recursively over the template
       root, overriding docusaurus.config.ts, sidebar.ts, and docs/**.
    2. Run `pnpm run build` in the template root to produce the static site.
    3. Copy the built site out to -OutputPath (in the workspace) so a workflow
       step can upload it.

.PARAMETER SourceDocs
    The caller's docs overlay directory. Its contents are copied over the
    template root. Defaults to './docs' (relative to the current directory,
    i.e. the checked-out repository / GITHUB_WORKSPACE).

.PARAMETER TemplateDir
    The template root inside the image. Defaults to '/template'.

.PARAMETER OutputPath
    Where to copy the built static site. Defaults to 'artifacts/docs'.

.EXAMPLE
    # Inside the base image (e.g. a CI container job):
    /template/scripts/docs-build.ps1

.EXAMPLE
    ./scripts/docs-build.ps1 -SourceDocs ./docs -OutputPath artifacts/docs
#>

[CmdletBinding()]
param(
    [Parameter()][string]$SourceDocs = './docs',
    [Parameter()][string]$TemplateDir = '/template',
    [Parameter()][string]$OutputPath = 'artifacts/docs'
)

$ErrorActionPreference = 'Stop'

function Resolve-ExistingPath {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Label)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "$Label not found at '$Path'."
    }

    return (Resolve-Path -LiteralPath $Path).Path
}

$sourceRoot = Resolve-ExistingPath -Path $SourceDocs -Label 'Source docs directory'
$templateRoot = Resolve-ExistingPath -Path $TemplateDir -Label 'Template directory'

Write-Host "[DOCS-BUILD] Overlaying '$sourceRoot' over '$templateRoot' ..." -ForegroundColor Cyan

# Recursively overlay every file from the source docs over the template root,
# recreating the directory structure and overwriting existing files. A manual
# walk (rather than `Copy-Item -Recurse *`) keeps the merge behavior predictable
# when destination directories already exist.
$prefixLength = $sourceRoot.Length
Get-ChildItem -LiteralPath $sourceRoot -Recurse -File | ForEach-Object {
    $relative = $_.FullName.Substring($prefixLength).TrimStart([IO.Path]::DirectorySeparatorChar, '/')
    $destination = Join-Path $templateRoot $relative
    $destinationDir = Split-Path -Parent $destination

    if (-not (Test-Path -LiteralPath $destinationDir)) {
        New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
    }

    Copy-Item -LiteralPath $_.FullName -Destination $destination -Force
}

Write-Host "[DOCS-BUILD] Building static site in '$templateRoot' ..." -ForegroundColor Cyan

Push-Location $templateRoot
try {
    & pnpm run build
    if ($LASTEXITCODE -ne 0) {
        throw "Documentation build failed with exit code $LASTEXITCODE."
    }
}
finally {
    Pop-Location
}

$builtSite = Join-Path $templateRoot 'artifacts'
if (-not (Test-Path -LiteralPath $builtSite)) {
    throw "Expected built site at '$builtSite' but it does not exist."
}

Write-Host "[DOCS-BUILD] Copying static site to '$OutputPath' ..." -ForegroundColor Cyan

$workspaceRoot = (Resolve-Path -LiteralPath '.').Path.TrimEnd([IO.Path]::DirectorySeparatorChar, '/')

if (Test-Path -LiteralPath $OutputPath) {
    # Clear any prior contents so a rerun cannot publish stale files that the
    # current build no longer produces. Resolve and validate the target first so
    # a checked-in symlink or an unsafe path can't redirect the deletion.
    $item = Get-Item -LiteralPath $OutputPath -Force

    if ($item.LinkType) {
        # A symlink/reparse point could point anywhere (e.g. artifacts/docs -> /);
        # never follow it to clear another location.
        throw "Refusing to use symlinked output path '$OutputPath' (LinkType=$($item.LinkType))."
    }

    if (-not $item.PSIsContainer) {
        # A file where a directory is expected: replace it outright.
        Remove-Item -LiteralPath $OutputPath -Force
        New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    }
    else {
        $resolved = $item.FullName
        $normalized = $resolved.TrimEnd([IO.Path]::DirectorySeparatorChar, '/')
        if ([string]::IsNullOrWhiteSpace($normalized) -or
            $normalized -eq $workspaceRoot -or
            $normalized -eq $templateRoot -or
            ($normalized -match '^[A-Za-z]:$') -or
            ($normalized -match '^[\\/]+$')) {
            throw "Refusing to clear unsafe output path '$resolved'."
        }
        Get-ChildItem -LiteralPath $resolved -Force | Remove-Item -Recurse -Force
    }
}
else {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

Copy-Item -Path (Join-Path $builtSite '*') -Destination $OutputPath -Recurse -Force

$resolvedOutput = (Resolve-Path -LiteralPath $OutputPath).Path
Write-Host "[DOCS-BUILD] Done. Static site available at '$resolvedOutput'." -ForegroundColor Green
