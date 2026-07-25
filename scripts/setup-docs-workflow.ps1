#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Copies the Docs CI/Deploy workflow templates into a caller repository.

.DESCRIPTION
    Copies both split workflow templates from this repository into a caller
    repository under `.github/workflows`:

    - scripts/template/docs-ci.yml     (verify)
    - scripts/template/docs-deploy.yml  (deploy)

    Existing destination files are left untouched (skipped with a message) unless
    -Overwrite is passed. Each workflow declares workflow_call + workflow_dispatch
    so the caller's main workflow drives them (verify vs deploy) via `uses:`.

.PARAMETER CallerProjectDir
    Root directory of the caller repository. Defaults to current directory.

.PARAMETER TargetRelativeDir
    Relative destination directory in the caller repository.
    Default: .github/workflows

.PARAMETER Overwrite
    Overwrite destination files if they already exist.

.EXAMPLE
    ./scripts/setup-docs-workflow.ps1 -CallerProjectDir C:\src\my-docs-repo

.EXAMPLE
    ./scripts/setup-docs-workflow.ps1 -Overwrite
#>

[CmdletBinding()]
param(
    [Parameter()][string]$CallerProjectDir = '.',
    [Parameter()][string]$TargetRelativeDir = '.github/workflows',
    [Parameter()][switch]$Overwrite
)

$ErrorActionPreference = 'Stop'

$WorkflowTemplates = @('docs-ci.yml', 'docs-deploy.yml')

function Resolve-OrCreateAbsolutePath {
    param([Parameter(Mandatory)][string]$Path)

    if (Test-Path -LiteralPath $Path) {
        return (Resolve-Path -LiteralPath $Path).Path
    }

    $created = New-Item -ItemType Directory -Path $Path -Force
    return $created.FullName
}

function Resolve-TemplateFile {
    param(
        [Parameter(Mandatory)][string]$ScriptDirectory,
        [Parameter(Mandatory)][string]$FileName
    )

    $candidates = @(
        (Join-Path $ScriptDirectory "template/$FileName"),
        (Join-Path $ScriptDirectory "../template/$FileName"),
        (Join-Path $ScriptDirectory "../scripts/template/$FileName")
    )

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    throw "Unable to locate workflow template '$FileName'. Expected under scripts/template near '$ScriptDirectory'."
}

$scriptDir = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($scriptDir)) {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
}
if ([string]::IsNullOrWhiteSpace($scriptDir)) {
    $scriptDir = (Get-Location).Path
}

$callerRoot = Resolve-OrCreateAbsolutePath -Path $CallerProjectDir
$targetDir = Resolve-OrCreateAbsolutePath -Path (Join-Path $callerRoot $TargetRelativeDir)

foreach ($template in $WorkflowTemplates) {
    $sourcePath = Resolve-TemplateFile -ScriptDirectory $scriptDir -FileName $template
    $targetPath = Join-Path $targetDir $template

    if ((Test-Path -LiteralPath $targetPath) -and (-not $Overwrite)) {
        Write-Host "[SKIP] Exists, not overwriting: $targetPath" -ForegroundColor Yellow
        continue
    }

    Copy-Item -LiteralPath $sourcePath -Destination $targetPath -Force
    Write-Host "[OK] Copied workflow: $targetPath" -ForegroundColor Green
}

Write-Host ""
Write-Host "Both workflows declare workflow_call + workflow_dispatch." -ForegroundColor Cyan
Write-Host "Call them from your main workflow (uses:) to verify or deploy." -ForegroundColor Cyan
