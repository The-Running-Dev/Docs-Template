#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Build the docs-template base image and optionally push it to a registry.

.DESCRIPTION
    Builds the base image from the repository-root Dockerfile (the published
    ghcr.io/the-running-dev/docs-template image the docs workflows run inside),
    and can push it to a container registry, which creates/updates the registry
    package.

    This is the explicit, portable mechanism release.yml uses to version, build,
    and publish the image, and it can also be run locally or in any CI.

.PARAMETER Tag
    Primary image reference to build. Default the published base image at :latest.

.PARAMETER AdditionalTags
    Extra tags to apply to the same image. Each is also pushed when -Push is
    set. The release workflow passes an immutable GitVersion tag here, computed
    from GitVersion.yml, alongside the :latest that -Tag defaults to.

.PARAMETER Context
    Docker build context. Defaults to the repository root (the parent of this
    script's directory), matching the root Dockerfile's `COPY . .`.

.PARAMETER Dockerfile
    Dockerfile path. Defaults to <Context>/Dockerfile.

.PARAMETER Push
    Push every tag after a successful build. Without it, the script only builds.

.PARAMETER Registry
    Registry host used for login. Default ghcr.io.

.PARAMETER Username
    Registry username for login. Only used together with -Token.

.PARAMETER Token
    Registry token/password. When provided with -Push, the script logs in
    (via --password-stdin) before pushing; otherwise it assumes you are already
    authenticated (e.g. a prior `docker login` or docker/login-action).

.EXAMPLE
    # Build only
    ./scripts/docs-build-image.ps1

.EXAMPLE
    # Build and push :latest to GHCR (already logged in)
    ./scripts/docs-build-image.ps1 -Push

.EXAMPLE
    # Build, apply a second tag, log in, and push both
    ./scripts/docs-build-image.ps1 -AdditionalTags ghcr.io/the-running-dev/docs-template:preview `
        -Push -Username $env:GITHUB_ACTOR -Token $env:REGISTRY_TOKEN
#>

[CmdletBinding()]
param(
    [Parameter()][string]$Tag = 'ghcr.io/the-running-dev/docs-template:latest',
    [Parameter()][string[]]$AdditionalTags = @(),
    [Parameter()][string]$Context,
    [Parameter()][string]$Dockerfile,
    [Parameter()][switch]$Push,
    [Parameter()][string]$Registry = 'ghcr.io',
    [Parameter()][string]$Username,
    [Parameter()][string]$Token
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw 'docker not found on PATH. Install/launch Docker first.'
}

# Default the build context to the repository root (parent of scripts/).
$scriptDir = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($scriptDir)) {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
}
if ([string]::IsNullOrWhiteSpace($Context)) {
    $Context = Split-Path -Parent $scriptDir
}
$Context = (Resolve-Path -LiteralPath $Context).Path

if ([string]::IsNullOrWhiteSpace($Dockerfile)) {
    $Dockerfile = Join-Path $Context 'Dockerfile'
}
if (-not (Test-Path -LiteralPath $Dockerfile)) {
    throw "Dockerfile not found at '$Dockerfile'."
}

$allTags = @($Tag) + $AdditionalTags | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique

$buildArgs = @('build', '-f', $Dockerfile)
foreach ($t in $allTags) {
    $buildArgs += @('-t', $t)
}
$buildArgs += $Context

Write-Host "[IMAGE-BUILD] Building $($allTags -join ', ') from '$Context' ..." -ForegroundColor Cyan
& docker @buildArgs
if ($LASTEXITCODE -ne 0) {
    throw "docker build failed with exit code $LASTEXITCODE."
}

if (-not $Push) {
    Write-Host "[IMAGE-BUILD] Built (build-only; pass -Push to publish)." -ForegroundColor Green
    return
}

if ($Token) {
    if ([string]::IsNullOrWhiteSpace($Username)) {
        throw '-Username is required when -Token is provided.'
    }
    Write-Host "[IMAGE-BUILD] Logging in to $Registry as $Username ..." -ForegroundColor Cyan
    $Token | & docker login $Registry --username $Username --password-stdin
    if ($LASTEXITCODE -ne 0) {
        throw "docker login to '$Registry' failed with exit code $LASTEXITCODE."
    }
}

foreach ($t in $allTags) {
    Write-Host "[IMAGE-BUILD] Pushing $t ..." -ForegroundColor Cyan
    & docker push $t
    if ($LASTEXITCODE -ne 0) {
        throw "docker push '$t' failed with exit code $LASTEXITCODE."
    }
}

Write-Host "[IMAGE-BUILD] Published: $($allTags -join ', ')." -ForegroundColor Green
