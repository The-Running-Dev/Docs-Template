#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Copies the common docs workflow into a caller repository.

.DESCRIPTION
    This script copies the reusable docs workflow from this template repository
    into a caller repository under `.github/common`.

    It also prints wiring instructions for per-project workflow entrypoints,
    including a ready-to-copy sample workflow that triggers on docs changes
    and calls the reusable workflow.

.PARAMETER CallerProjectDir
    Root directory of the caller repository. Defaults to current directory.

.PARAMETER TargetRelativeDir
    Relative destination directory in the caller repository.
    Default: .github/common

.PARAMETER TargetFileName
    Destination file name for the copied reusable workflow.
    Default: docs-build-common.yml

.PARAMETER Overwrite
    Overwrite destination file if it already exists.

.EXAMPLE
    ./scripts/setup-common-workflow.ps1 -CallerProjectDir C:\src\my-docs-repo

.EXAMPLE
    ./scripts/setup-common-workflow.ps1 -Overwrite
#>

[CmdletBinding()]
param(
    [Parameter()][string]$CallerProjectDir = '.',
    [Parameter()][string]$TargetRelativeDir = '.github/common',
    [Parameter()][string]$TargetFileName = 'docs-build-common.yml',
    [Parameter()][switch]$Overwrite
)

$ErrorActionPreference = 'Stop'

function Resolve-OrCreateAbsolutePath {
    param(
        [Parameter(Mandatory)][string]$Path
    )

    if (Test-Path -LiteralPath $Path) {
        return (Resolve-Path -LiteralPath $Path).Path
    }

    $created = New-Item -ItemType Directory -Path $Path -Force
    return $created.FullName
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$templateRoot = Split-Path -Parent $scriptDir
$sourceWorkflow = Join-Path $templateRoot '.github/workflows/docs-build-common.yml'

if (-not (Test-Path -LiteralPath $sourceWorkflow)) {
    throw "Source workflow not found at $sourceWorkflow"
}

$callerRoot = Resolve-OrCreateAbsolutePath -Path $CallerProjectDir
$targetDir = Resolve-OrCreateAbsolutePath -Path (Join-Path $callerRoot $TargetRelativeDir)
$targetPath = Join-Path $targetDir $TargetFileName

if ((Test-Path -LiteralPath $targetPath) -and (-not $Overwrite)) {
    throw "Destination file already exists: $targetPath. Re-run with -Overwrite to replace it."
}

Copy-Item -LiteralPath $sourceWorkflow -Destination $targetPath -Force

Write-Host "[OK] Copied reusable workflow:" -ForegroundColor Green
Write-Host "     $targetPath" -ForegroundColor White
Write-Host ""

$entryWorkflowPath = '.github/workflows/docs-build.yml'

$entryWorkflowContent = @"
name: Docs

on:
  pull_request:
    paths:
      - '.github/workflows/docs-build.yml'
      - '.github/workflows/docs-build-common.yml'
      - 'docs/**'
      - 'scripts/docs.ps1'
      - 'scripts/setup-docs.ps1'
      - 'README.md'
  push:
    branches:
      - main
    paths:
      - '.github/workflows/docs-build.yml'
      - '.github/workflows/docs-build-common.yml'
      - 'docs/**'
      - 'scripts/docs.ps1'
      - 'scripts/setup-docs.ps1'
      - 'README.md'
  workflow_dispatch:

permissions:
  contents: read
  packages: read
  pages: write
  id-token: write

jobs:
  docs:
    uses: ./.github/workflows/docs-build-common.yml
    with:
      docs-script: ./scripts/docs.ps1
      image-tag-prefix: docs-site
      output-path: artifacts/docs
    secrets: inherit
"@

Write-Host "Wiring Instructions:" -ForegroundColor Cyan
Write-Host "  1. Copy the shared workflow into workflows directory (required by GitHub reusable workflows):" -ForegroundColor White
Write-Host "     - Source: .github/common/$TargetFileName" -ForegroundColor White
Write-Host "     - Target: .github/workflows/docs-build-common.yml" -ForegroundColor White
Write-Host ""
Write-Host "  2. Create a project entry workflow at ${entryWorkflowPath}:" -ForegroundColor White
Write-Host ""
Write-Host $entryWorkflowContent -ForegroundColor Gray
Write-Host ""
Write-Host "  3. Adjust path filters and inputs (docs-script/image-tag-prefix/output-path) for each project." -ForegroundColor White
