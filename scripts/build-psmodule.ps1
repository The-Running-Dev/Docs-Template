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
    Generator image used for the fallback. The module is copied out of it and
    imported locally; the image is never run.

    NOTE: pulling the generator out of an image is a workaround at the wrong
    layer. The build agent is the right place to provide SubZeroDev.PSGenerator,
    and is expected to do so later. Once it does, the installed-module branch
    above takes over and this fallback can be deleted outright.

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

function Import-GeneratorFromImage {
    <#
    .SYNOPSIS
    Copies SubZeroDev.PSGenerator out of the published image and imports it,
    returning the manifest path.

    Deliberately extracts the module rather than running the build inside the
    image. Bind-mounting this repository into a `docker run` is the obvious
    approach and it fails wherever the job is itself containerized: the path
    handed to -v is resolved by the Docker daemon on the *host*, while inside a
    container job the repository lives at something like
    /__w/<repo>/<repo>, which does not exist there. The mount silently
    resolves to an empty directory and the build fails with the specification
    "not found". That is exactly how release.yml broke -- its job runs in the
    build-agent image -- while test-and-coverage.yml, which runs directly on
    the runner, passed.

    NOTE: this is a workaround at the wrong layer. The build agent is the right
    place to provide the generator, and is expected to do so later; when it
    does, this whole fallback can go and the installed-module path takes over.

    docker create makes a container without starting it, so nothing executes:
    no entrypoint, no pwsh, and therefore none of the ownership or writable-HOME
    problems that running the image would bring. docker cp then writes the files
    as the invoking user.
    #>
    param(
        [Parameter(Mandatory)][string]$Image,
        [Parameter(Mandatory)][string]$Destination
    )

    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        throw (
            'SubZeroDev.PSGenerator was not found locally and docker is not on PATH, ' +
            'so the generator image cannot be used either. Pass -GeneratorPath, ' +
            'install the module, or make docker available.'
        )
    }

    Write-Host "[PSMODULE] Pulling $Image ..." -ForegroundColor Cyan
    & docker pull --quiet $Image | Out-Null
    if ($LASTEXITCODE -ne 0) {
        # A failed pull is only fatal with no local copy to fall back on.
        & docker image inspect $Image --format '{{.Id}}' 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "docker pull failed for '$Image' and no local copy exists."
        }
        Write-Warning "Could not pull '$Image'; using the local copy. It may be out of date."
    }

    $containerId = (& docker create $Image | Select-Object -First 1)
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($containerId)) {
        throw "docker create failed for '$Image'."
    }

    try {
        New-Item -ItemType Directory -Path $Destination -Force | Out-Null
        & docker cp "${containerId}:/usr/local/share/powershell/Modules/SubZeroDev.PSGenerator" $Destination
        if ($LASTEXITCODE -ne 0) {
            throw "docker cp failed; '$Image' does not carry the generator module where expected."
        }
    }
    finally {
        # Always remove the container, even when the copy failed, so a failed
        # build never leaves clutter behind.
        & docker rm --force $containerId 2>&1 | Out-Null
    }

    $manifest = Join-Path $Destination 'SubZeroDev.PSGenerator/SubZeroDev.PSGenerator.psd1'
    if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) {
        throw "The generator module was copied but no manifest was found at '$manifest'."
    }

    Import-Module $manifest -Force -ErrorAction Stop
    return $manifest
}

Write-Host "[PSMODULE] Specification: $specificationPath" -ForegroundColor Cyan

$generator = if ($UseContainer) { $null } else { Import-Generator -Path $GeneratorPath }
$generatorStaging = $null

try {
    if (-not $generator) {
        $generatorStaging = Join-Path ([IO.Path]::GetTempPath()) ('psgenerator-' + [Guid]::NewGuid().ToString('N').Substring(0, 12))
        $generator = Import-GeneratorFromImage -Image $GeneratorImage -Destination $generatorStaging
        Write-Host "[PSMODULE] Generator: $GeneratorImage (extracted from image)" -ForegroundColor Cyan
    }
    else {
        Write-Host "[PSMODULE] Generator: $generator" -ForegroundColor Cyan
    }

    # Remove a previous build so a command deleted from the specification cannot
    # survive in the output as a stale file.
    if (Test-Path -LiteralPath $outputPath) {
        Remove-Item -LiteralPath $outputPath -Recurse -Force
    }

    # One build path regardless of where the generator came from. Validate
    # first: Build-PSModule reports its own errors, but a specification fault is
    # worth failing on by itself, since it means the description is wrong rather
    # than that generation hit a problem.
    Test-PSModuleSpecification -Specification $specificationPath -ErrorAction Stop | Out-Null
    Write-Host '[PSMODULE] Specification is valid.' -ForegroundColor Green

    Build-PSModule -Specification $specificationPath -Output $outputPath -ErrorAction Stop | Out-Null
}
finally {
    if ($generatorStaging -and (Test-Path -LiteralPath $generatorStaging)) {
        # Unload before deleting: an imported module holds its files open on
        # Windows, and a cleanup failure must not fail a build that succeeded.
        Remove-Module 'SubZeroDev.PSGenerator' -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $generatorStaging -Recurse -Force -ErrorAction SilentlyContinue
    }
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
