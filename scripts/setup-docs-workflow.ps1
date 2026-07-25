#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Copies the common docs workflow into a caller repository.

.DESCRIPTION
    This script copies the reusable docs workflow from this template repository
    into a caller repository under `.github/workflow/common`.

    It also prints wiring instructions for per-project workflow entrypoints,
    including a ready-to-copy sample workflow that triggers on docs changes
    and calls the reusable workflow.

    Source workflow template:
    - template/.github/workflow/docs.yml

    Source instructions markdown:
    - template/instructions.md

.PARAMETER CallerProjectDir
    Root directory of the caller repository. Defaults to current directory.

.PARAMETER TargetRelativeDir
    Relative destination directory in the caller repository.
    Default: .github/workflow/common

.PARAMETER TargetFileName
    Destination file name for the copied reusable workflow.
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
    [Parameter()][string]$TargetRelativeDir = '.github/workflow/common',
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

function Resolve-TemplateRoot {
    param(
        [Parameter(Mandatory)][string]$StartPath
    )

    $current = $StartPath
    for ($i = 0; $i -lt 8; $i++) {
        $workflowPath = Join-Path $current 'template/.github/workflow/docs.yml'
        $instructionsPath = Join-Path $current 'template/instructions.md'

        if ((Test-Path -LiteralPath $workflowPath) -and (Test-Path -LiteralPath $instructionsPath)) {
            return $current
        }

        $parent = Split-Path -Parent $current
        if ($parent -eq $current) {
            break
        }

        $current = $parent
    }

    throw "Unable to locate the template root. Expected template/.github/workflow/docs.yml and template/instructions.md in an ancestor directory of $StartPath."
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$templateRoot = Resolve-TemplateRoot -StartPath $scriptDir
$sourceWorkflow = Join-Path $templateRoot 'template/.github/workflow/docs.yml'
$sourceInstructions = Join-Path $templateRoot 'template/instructions.md'

if (-not (Test-Path -LiteralPath $sourceWorkflow)) {
    throw "Source Workflow not Found at $sourceWorkflow"
}
if (-not (Test-Path -LiteralPath $sourceInstructions)) {
    throw "Source Instructions not Found at $sourceInstructions"
}

$callerRoot = Resolve-OrCreateAbsolutePath -Path $CallerProjectDir
$targetDir = Resolve-OrCreateAbsolutePath -Path (Join-Path $callerRoot $TargetRelativeDir)
$targetPath = Join-Path $targetDir $TargetFileName

if ((Test-Path -LiteralPath $targetPath) -and (-not $Overwrite)) {
    throw "Destination File Already Exists: $targetPath. Re-run with -Overwrite to Replace It."
}

Copy-Item -LiteralPath $sourceWorkflow -Destination $targetPath -Force

Write-Host "[OK] Copied Reusable Workflow:" -ForegroundColor Green
Write-Host "     $targetPath" -ForegroundColor White
Write-Host ""

$instructions = Get-Content -LiteralPath $sourceInstructions -Raw
Write-Host "Instructions (template/instructions.md):" -ForegroundColor Cyan
Write-Host ""
Write-Host $instructions -ForegroundColor Gray
