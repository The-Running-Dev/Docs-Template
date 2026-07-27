#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Generates the DocsTemplate PowerShell module from PSModule/PSModule.psd1.

.DESCRIPTION
    Runs SubZeroDev.PSGenerator over the specification in PSModule/PSModule.psd1
    and writes the generated module to -Output. The module is self-contained:
    the generator copies the referenced scripts into <module>/Scripts, so the
    commands resolve without anything else being staged beside them.

    The generated module is what gets embedded at /PSModule in the published
    image. Consumers then run Install-PSModule against the image to install it
    locally, rather than being handed a `docker run` line to remember.

    Nothing here is hand-written. The specification is the input; if a command
    or parameter looks wrong, fix PSModule/PSModule.psd1 and re-run, do not
    edit the output.

.PARAMETER Output
    Where the generated module is written. Defaults to artifacts/PSModule,
    which the root Dockerfile copies to /PSModule.

.PARAMETER Specification
    The specification to build from. Defaults to PSModule/PSModule.psd1.

.PARAMETER GeneratorPath
    Path to the SubZeroDev.PSGenerator module manifest. When omitted the script
    looks for an already-installed module first, then a sibling source checkout
    -- the layout on a development machine, where PSGenerator sits next to this
    repository.

.EXAMPLE
    ./scripts/build-psmodule.ps1

.EXAMPLE
    ./scripts/build-psmodule.ps1 -GeneratorPath ../SubZeroDev.PSGenerator/src/SubZeroDev.PSGenerator.psd1
#>

[CmdletBinding()]
param(
    [Parameter()][string]$Output = 'artifacts/PSModule',
    [Parameter()][string]$Specification = 'PSModule/PSModule.psd1',
    [Parameter()][string]$GeneratorPath
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$specificationPath = Join-Path $repositoryRoot $Specification
$outputPath = Join-Path $repositoryRoot $Output

if (-not (Test-Path -LiteralPath $specificationPath -PathType Leaf)) {
    throw "Specification not found at '$specificationPath'."
}

function Import-Generator {
    <#
    .SYNOPSIS
    Loads SubZeroDev.PSGenerator from an explicit path, an installed module, or
    a sibling checkout, in that order.

    The sibling checkout is last because it is the least reproducible: it is
    what a development machine has, not what CI has. When none of the three
    work the error names all three, since "module not found" alone does not
    tell anyone which of them to fix.
    #>
    param([string]$Path)

    if ($Path) {
        Import-Module $Path -Force -ErrorAction Stop
        return $Path
    }

    $installed = Get-Module -ListAvailable -Name 'SubZeroDev.PSGenerator' |
        Sort-Object Version -Descending |
        Select-Object -First 1
    if ($installed) {
        Import-Module $installed.Path -Force -ErrorAction Stop
        return $installed.Path
    }

    $sibling = Join-Path (Split-Path -Parent $repositoryRoot) 'SubZeroDev.PSGenerator/src/SubZeroDev.PSGenerator.psd1'
    if (Test-Path -LiteralPath $sibling -PathType Leaf) {
        Import-Module $sibling -Force -ErrorAction Stop
        return $sibling
    }

    throw (
        'SubZeroDev.PSGenerator was not found. Pass -GeneratorPath, install the ' +
        'module so Get-Module -ListAvailable finds it, or place a checkout at ' +
        "'$sibling'."
    )
}

$generator = Import-Generator -Path $GeneratorPath
Write-Host "[PSMODULE] Generator: $generator" -ForegroundColor Cyan
Write-Host "[PSMODULE] Specification: $specificationPath" -ForegroundColor Cyan

# Validate before building. Build-PSModule reports its own errors, but a
# specification fault is worth failing on by itself: it means the description
# is wrong, not that generation hit a problem.
Test-PSModuleSpecification -Specification $specificationPath -ErrorAction Stop | Out-Null
Write-Host '[PSMODULE] Specification is valid.' -ForegroundColor Green

# Remove a previous build so a command deleted from the specification cannot
# survive in the output as a stale file.
if (Test-Path -LiteralPath $outputPath) {
    Remove-Item -LiteralPath $outputPath -Recurse -Force
}

Build-PSModule -Specification $specificationPath -Output $outputPath -ErrorAction Stop | Out-Null

$manifest = Join-Path $outputPath 'DocsTemplate.psd1'
if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) {
    throw "Generation reported success but no manifest was produced at '$manifest'."
}

# Importing is the real check: a manifest that exists but does not load would
# otherwise be found by whoever installs it, not by this build.
Import-Module $manifest -Force -ErrorAction Stop
$commands = (Get-Command -Module 'DocsTemplate').Name
Remove-Module 'DocsTemplate' -Force -ErrorAction SilentlyContinue

Write-Host "[PSMODULE] Generated $($commands.Count) command(s) at '$outputPath':" -ForegroundColor Green
foreach ($command in $commands) {
    Write-Host "           $command" -ForegroundColor Green
}
