Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

# Resolved once at import time. This module ships at
# <repo>/PowerShell/DocusaurusTemplate/DocusaurusTemplate.psm1 and the scripts
# it wraps live at <repo>/scripts, so ../../scripts from here is stable
# whether <repo> is /template inside the published image or a host checkout.
$script:ScriptsRoot = Join-Path $PSScriptRoot '../../scripts'

function Assert-NotTemplateDirectory {
    <#
    .SYNOPSIS
    Refuses a -ProjectDir that resolves inside the image's own /template tree.

    The published image sets WORKDIR /template and Invoke-SetupDocs defaults
    -ProjectDir to '.', so `docker run <image> Invoke-SetupDocs` with no mount
    and no explicit -ProjectDir would install the docs system into the
    template image's own checkout rather than a caller's project. This is a
    container-specific hazard -- scripts/setup-docs.ps1 itself is unaware of
    /template and stays correct for host use, so the guard lives here rather
    than in the shared script.
    #>
    param([Parameter(Mandatory)][string]$ProjectDir)

    $candidate = if ([IO.Path]::IsPathRooted($ProjectDir)) {
        $ProjectDir
    }
    else {
        [IO.Path]::GetFullPath((Join-Path (Get-Location).Path $ProjectDir))
    }
    $candidate = $candidate.TrimEnd('/')

    if ($candidate -eq '/template' -or $candidate.StartsWith('/template/')) {
        throw (
            "-ProjectDir resolves to '$candidate', inside the template image " +
            'itself. Mount your project and point -ProjectDir at the mount, e.g.: ' +
            "docker run --rm -v `"`$PWD`:/work`" -w /work <image> Invoke-SetupDocs -ProjectDir /work"
        )
    }
}

function Invoke-SetupDocs {
    <#
    .SYNOPSIS
    Installs the documentation system into a project. Container-side wrapper
    around scripts/setup-docs.ps1 -- see that script for full parameter help.

    .EXAMPLE
    docker run --rm -v "$PWD:/work" -w /work <image> Invoke-SetupDocs -ProjectDir /work -Title 'My Project' -SiteUrl 'https://docs.example.com/'
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter()][string]$ProjectDir = '.',
        [Parameter()][string]$Title,
        [Parameter()][string]$Description = '',
        [Parameter()][string]$SiteUrl = '',
        [Parameter()][string]$ScriptDir = 'build',
        [Parameter()][string]$ConfigDir = '.config',
        [Parameter()][switch]$NoHomepage,
        [Parameter()][switch]$SkipWorkflow,
        [Parameter()][switch]$SkipGate,
        [Parameter()][switch]$Overwrite
    )

    Assert-NotTemplateDirectory -ProjectDir $ProjectDir

    & (Join-Path $script:ScriptsRoot 'setup-docs.ps1') @PSBoundParameters
}

function Invoke-DocsBuild {
    <#
    .SYNOPSIS
    Builds a Docusaurus site. Container-side wrapper around
    scripts/docs-build.ps1 -- see that script for full parameter help.

    .EXAMPLE
    docker run --rm -v "$PWD:/work" -w /work <image> Invoke-DocsBuild -SourceDocs /work/docs -OutputPath /work/artifacts/docs
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$SourceDocs = './docs',
        [Parameter()][string]$TemplateDir = '/template',
        [Parameter()][string]$OutputPath = 'artifacts/docs'
    )

    & (Join-Path $script:ScriptsRoot 'docs-build.ps1') @PSBoundParameters
}

Export-ModuleMember -Function 'Invoke-SetupDocs', 'Invoke-DocsBuild'
