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
    repository -- and finally falls back to running the published generator
    image, which is what CI uses since it has neither of the first two.

.PARAMETER GeneratorImage
    Generator image used for the container fallback. It carries the module on
    its PowerShell module path and entrypoints to pwsh, so the build runs
    inside it with this repository mounted at /workspace.

.PARAMETER UseContainer
    Skip the local lookups and go straight to the generator image. Useful to
    reproduce exactly what CI does from a machine that also has a checkout.

.EXAMPLE
    ./scripts/build-psmodule.ps1

.EXAMPLE
    ./scripts/build-psmodule.ps1 -GeneratorPath ../SubZeroDev.PSGenerator/src/SubZeroDev.PSGenerator.psd1

.EXAMPLE
    ./scripts/build-psmodule.ps1 -UseContainer
#>

[CmdletBinding()]
param(
    [Parameter()][string]$Output = 'artifacts/PSModule',
    [Parameter()][string]$Specification = 'PSModule/PSModule.psd1',
    [Parameter()][string]$GeneratorPath,
    [Parameter()][string]$GeneratorImage = 'ghcr.io/the-running-dev/subzerodev.psgenerator:latest',
    [Parameter()][switch]$UseContainer
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

    # No local generator. The caller falls back to the published image, which
    # is the normal path in CI -- a runner has neither an installed module nor
    # a sibling checkout.
    return $null
}

function Invoke-GeneratorContainer {
    <#
    .SYNOPSIS
    Runs the build inside the published generator image.

    The image carries SubZeroDev.PSGenerator on its PowerShell module path and
    entrypoints to pwsh, so the whole build is one `docker run` with this
    repository mounted at the image's /workspace working directory.

    Runs as the invoking user so the generated files are not left root-owned on
    a Linux host, which would then need sudo to clean up or rebuild. id is not
    available on Windows, where Docker Desktop handles ownership itself, so the
    argument is only added when it can be resolved.
    #>
    param(
        [Parameter(Mandatory)][string]$Image,
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$SpecificationRelative,
        [Parameter(Mandatory)][string]$OutputRelative
    )

    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        throw (
            'SubZeroDev.PSGenerator was not found locally and docker is not on PATH, ' +
            'so the generator image cannot be used either. Pass -GeneratorPath, ' +
            'install the module, or make docker available.'
        )
    }

    # HOME=/tmp is not optional when --user is passed below. An arbitrary uid has
    # no /etc/passwd entry in the image, so $HOME resolves to '/', which is not
    # writable; pwsh then drops its startup cache
    # (StartupProfileData-NonInteractive) into the working directory instead --
    # and here that directory is the caller's repository root. Observed doing
    # exactly that before this was added.
    $arguments = @(
        'run', '--rm'
        '-v', "${RepositoryRoot}:/workspace"
        '-w', '/workspace'
        '-e', 'HOME=/tmp'
    )

    if ($IsLinux -or $IsMacOS) {
        $userId = (& id -u 2>$null)
        $groupId = (& id -g 2>$null)
        if ($LASTEXITCODE -eq 0 -and $userId -and $groupId) {
            $arguments += @('--user', "${userId}:${groupId}")
        }
    }

    # Forward-slash paths: the command runs inside a Linux container regardless
    # of the host, so a Windows-style relative path would not resolve.
    $specification = $SpecificationRelative.Replace('\', '/')
    $output = $OutputRelative.Replace('\', '/')

    $arguments += @(
        $Image
        '-NoProfile'
        '-Command'
        "Test-PSModuleSpecification -Specification './$specification' -ErrorAction Stop | Out-Null; " +
        "Build-PSModule -Specification './$specification' -Output './$output' -ErrorAction Stop | Out-Null"
    )

    & docker @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Generator container exited with code $LASTEXITCODE."
    }
}

$generator = if ($UseContainer) { $null } else { Import-Generator -Path $GeneratorPath }

Write-Host "[PSMODULE] Specification: $specificationPath" -ForegroundColor Cyan

# Remove a previous build so a command deleted from the specification cannot
# survive in the output as a stale file. Done before either path runs, so the
# container build starts from the same clean state the local one does.
if (Test-Path -LiteralPath $outputPath) {
    Remove-Item -LiteralPath $outputPath -Recurse -Force
}

if ($generator) {
    Write-Host "[PSMODULE] Generator: $generator" -ForegroundColor Cyan

    # Validate before building. Build-PSModule reports its own errors, but a
    # specification fault is worth failing on by itself: it means the description
    # is wrong, not that generation hit a problem.
    Test-PSModuleSpecification -Specification $specificationPath -ErrorAction Stop | Out-Null
    Write-Host '[PSMODULE] Specification is valid.' -ForegroundColor Green

    Build-PSModule -Specification $specificationPath -Output $outputPath -ErrorAction Stop | Out-Null
}
else {
    Write-Host "[PSMODULE] Generator: $GeneratorImage (container)" -ForegroundColor Cyan
    Invoke-GeneratorContainer `
        -Image $GeneratorImage `
        -RepositoryRoot $repositoryRoot `
        -SpecificationRelative $Specification `
        -OutputRelative $Output
}

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
