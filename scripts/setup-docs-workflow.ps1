#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Copies the Docs workflow into a caller repository.

.DESCRIPTION
    This script copies the Docs workflow template from this repository
    into a caller repository under `.github/workflows`.

    Source workflow template:
    - template/.github/workflows/docs.yml

.PARAMETER CallerProjectDir
    Root directory of the caller repository. Defaults to current directory.

.PARAMETER TargetRelativeDir
    Relative destination directory in the caller repository.
    Default: .github/workflows

.PARAMETER TargetFileName
    Destination file name for the copied workflow.
    Default: docs.yml

.PARAMETER Overwrite
    Overwrite destination file if it already exists.

.EXAMPLE
    ./scripts/setup-docs-workflow.ps1 -CallerProjectDir C:\src\my-docs-repo

.EXAMPLE
    ./scripts/setup-docs-workflow.ps1 -Overwrite
#>

[CmdletBinding()]
param(
    [Parameter()][string]$CallerProjectDir = '.',
    [Parameter()][string]$TargetRelativeDir = '.github/workflows',
    [Parameter()][string]$TargetFileName = 'docs.yml',
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

function Resolve-TemplateWorkflowPath {
    param(
        [Parameter(Mandatory)][string]$ScriptDirectory
    )

    $candidates = @(
        (Join-Path $ScriptDirectory '../template/.github/workflows/docs.yml'),
        (Join-Path $ScriptDirectory '../../template/.github/workflows/docs.yml'),
        (Join-Path $ScriptDirectory '../../../template/.github/workflows/docs.yml')
    )

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    throw "Unable to locate Docs workflow template. Expected template/.github/workflows/docs.yml near script path '$ScriptDirectory'."
}

$scriptDir = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($scriptDir)) {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
}
if ([string]::IsNullOrWhiteSpace($scriptDir)) {
    $scriptDir = (Get-Location).Path
}

$sourceWorkflow = Resolve-TemplateWorkflowPath -ScriptDirectory $scriptDir

if (-not (Test-Path -LiteralPath $sourceWorkflow)) {
    throw "Source workflow not found at '$sourceWorkflow'."
}

$callerRoot = Resolve-OrCreateAbsolutePath -Path $CallerProjectDir
$targetDir = Resolve-OrCreateAbsolutePath -Path (Join-Path $callerRoot $TargetRelativeDir)
$targetPath = Join-Path $targetDir $TargetFileName

if ((Test-Path -LiteralPath $targetPath) -and (-not $Overwrite)) {
    throw "Destination file already exists: '$targetPath'. Re-run with -Overwrite to replace it."
}

Copy-Item -LiteralPath $sourceWorkflow -Destination $targetPath -Force

Write-Host "[OK] Copied Docs Workflow:" -ForegroundColor Green
Write-Host "     $targetPath" -ForegroundColor White
Write-Host ""
Write-Host "Triggers: pull_request, push (main), workflow_dispatch" -ForegroundColor Cyan
