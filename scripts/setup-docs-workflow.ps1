#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Installs just the documentation workflows into a caller repository.

.DESCRIPTION
    Installs `docs-ci.yml` (documentation gate + build verification) and
    `docs-deploy.yml` (build + deploy to GitHub Pages) into a caller repository
    under `.github/workflows`, leaving everything else that project has alone.

    Use it to refresh the workflows of a repository that already has the rest of
    the documentation system, without re-running the full installer.

    Existing files are skipped unless -Overwrite is passed, and workflow files an
    earlier version installed and this one no longer uses are removed, since
    leaving them behind breaks the two that remain.

    This is a thin wrapper over `setup-docs.ps1 -WorkflowsOnly`. The two
    workflow files are not plain copies -- the gate job is excised from
    docs-ci.yml under -SkipGate, and -BaseImage is substituted into the
    container image of both -- so the templating lives in one place rather than
    being duplicated here.

.PARAMETER CallerProjectDir
    Root directory of the caller repository. Defaults to the current directory.

.PARAMETER TargetRelativeDir
    Relative destination directory in the caller repository.
    Default: .github/workflows

.PARAMETER BaseImage
    Documentation image the installed workflows run their container jobs in.
    Defaults to the published image at :latest.

.PARAMETER SkipGate
    Install the workflows without the documentation gate job.

.PARAMETER Overwrite
    Overwrite destination files if they already exist.

.EXAMPLE
    ./scripts/setup-docs-workflow.ps1 -CallerProjectDir /src/my-docs-repo

.EXAMPLE
    ./scripts/setup-docs-workflow.ps1 -Overwrite

.EXAMPLE
    ./scripts/setup-docs-workflow.ps1 -BaseImage ghcr.io/the-running-dev/docs-template:latest -Overwrite
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()][string]$CallerProjectDir = '.',
    [Parameter()][string]$TargetRelativeDir = '.github/workflows',
    [Parameter()][string]$BaseImage = 'ghcr.io/the-running-dev/docs-template:latest',
    [Parameter()][switch]$SkipGate,
    [Parameter()][switch]$Overwrite
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$scriptRoot = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($scriptRoot)) {
    $scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
}

$installer = Join-Path $scriptRoot 'setup-docs.ps1'
if (-not (Test-Path -LiteralPath $installer -PathType Leaf)) {
    throw "Installer not found at '$installer'."
}

# -WhatIf and -Verbose reach setup-docs.ps1 through the preference variables
# this scope already inherits, so they do not need forwarding by hand.
& $installer `
    -ProjectDir $CallerProjectDir `
    -WorkflowDir $TargetRelativeDir `
    -BaseImage $BaseImage `
    -WorkflowsOnly `
    -SkipGate:$SkipGate `
    -Overwrite:$Overwrite
