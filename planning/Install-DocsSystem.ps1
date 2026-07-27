#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Installs the containerized Docusaurus documentation system into a project.

.DESCRIPTION
    Drop this single file into any repository and run it. It installs everything
    needed to author, preview, check, and publish documentation:

      docs/                       Docusaurus overlay copied over /template
        docusaurus.config.ts      Site configuration
        sidebar.ts                Sidebar configuration
        Dockerfile                Extends the base image, overlays this folder
        .dockerignore             Keeps the build context to the overlay
        docs/index.md             Homepage, generated from the README
      docs.ps1                    Local preview entry point
      build/                      Homepage generator and documentation gate
      .config/                    Gate rules
      .github/workflows/docs-ci.yml   Gate, build, and deploy

    Nothing is cloned. The payload is pulled from the published documentation
    image and copied out of it, which is the same image the preview and CI
    builds overlay. One artifact, one version, one place to update.

    The site itself is never installed: docs/Dockerfile does FROM <base image>
    and COPY . ., so `docker build` pulls the base and overlays docs/ on top.
    That is why a consumer needs no Node install and no template checkout.

    Idempotent. Without -Overwrite an existing file is left alone and reported
    as skipped, so the command can be re-run against a newer image to pick up
    upstream fixes without discarding local edits.

.PARAMETER ProjectDir
    Project to install into. Defaults to the current directory. Created if it
    does not exist.

.PARAMETER Title
    Site and homepage title. Defaults to the project directory name.

.PARAMETER Description
    Site tagline and homepage front matter description.

.PARAMETER SiteUrl
    Published site origin, with a trailing slash. Absolute links to it in the
    README are rewritten to '/' in the generated homepage, so one README works
    both on the code host and as the site homepage.

.PARAMETER BaseImage
    Documentation image to take the payload from, and the base image the
    installed Dockerfile and preview script build on.

.PARAMETER PayloadDir
    Use an already-extracted payload instead of pulling the image. Point it at
    a directory holding the same files found under /template/scripts/template.
    Useful offline, in CI that has them already, or when testing changes to the
    payload before publishing an image.

.PARAMETER ScriptDir
    Where PowerShell tooling is installed, relative to the project. Default 'build'.

.PARAMETER ConfigDir
    Where the gate rules are installed, relative to the project. Default '.config'.

.PARAMETER NoHomepage
    Do not generate the homepage from the README, and do not drift-check it.
    Use when the homepage is authored by hand.

.PARAMETER SkipWorkflow
    Install no GitHub Actions workflow.

.PARAMETER SkipGate
    Install no documentation gate: no checker, no rules file, no gate job.

.PARAMETER Overwrite
    Replace files that already exist. Without it, existing files are skipped,
    which is what makes re-running safe.

.EXAMPLE
    ./Install-DocsSystem.ps1

    Install into the current directory, taking the payload from the published
    image.

.EXAMPLE
    ./Install-DocsSystem.ps1 -Title 'My Project' -SiteUrl 'https://docs.example.com/'

.EXAMPLE
    ./Install-DocsSystem.ps1 -WhatIf

    Report every file that would be written, without writing any. The payload is
    still acquired, since that is what makes the report accurate.

.EXAMPLE
    ./Install-DocsSystem.ps1 -PayloadDir ../Docusaurus-Template/scripts/template

    Install from a local payload without pulling anything.

.EXAMPLE
    ./Install-DocsSystem.ps1 -Overwrite

    Re-run after the image has been republished, replacing the installed files.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()][string]$ProjectDir = '.',
    [Parameter()][string]$Title,
    [Parameter()][string]$Description = '',
    [Parameter()][string]$SiteUrl = '',
    [Parameter()][string]$BaseImage = 'ghcr.io/the-running-dev/docs-template:latest',
    [Parameter()][string]$PayloadDir,
    [Parameter()][string]$ScriptDir = 'build',
    [Parameter()][string]$ConfigDir = '.config',
    [Parameter()][switch]$NoHomepage,
    [Parameter()][switch]$SkipWorkflow,
    [Parameter()][switch]$SkipGate,
    [Parameter()][switch]$Overwrite
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$created = [System.Collections.Generic.List[string]]::new()
$skipped = [System.Collections.Generic.List[string]]::new()
$replaced = [System.Collections.Generic.List[string]]::new()

function Write-Step {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host "[INSTALL-DOCS] $Message" -ForegroundColor Cyan
}

function Remove-TemporaryTree {
    <#
    .SYNOPSIS
    Deletes a staging tree.

    A failure to clean up a temporary directory must never fail an install that
    already succeeded, so this warns rather than throws.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Deletes only a temporary directory this script created, and must run from finally even under -WhatIf; honoring ShouldProcess here would leak staging directories on every dry run.'
    )]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { return }

    try {
        Get-ChildItem -LiteralPath $Path -Recurse -Force -File -ErrorAction SilentlyContinue |
            ForEach-Object { $_.Attributes = 'Normal' }
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
    }
    catch {
        Write-Warning "Could not remove temporary directory '$Path': $($_.Exception.Message)"
    }
}

function Get-PayloadFromImage {
    <#
    .SYNOPSIS
    Pulls the documentation image and copies the installable payload out of it,
    returning the staging directory.

    Uses `docker create` rather than `docker run`: the payload only has to be
    read out of the image's filesystem, so nothing needs to execute.
    #>
    param(
        [Parameter(Mandatory)][string]$Image,
        [Parameter(Mandatory)][string]$Destination
    )

    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        throw 'docker was not found on PATH. Install or start Docker, or pass -PayloadDir with an extracted payload.'
    }

    Write-Step "Pulling $Image ..."
    & docker pull $Image 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        # A failed pull is only fatal when there is nothing to fall back on.
        # GHCR packages are private by default, and the image may well already
        # be present from a previous run or a local build.
        $local = & docker image inspect $Image --format '{{.Id}}' 2>$null
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($local)) {
            throw "docker pull failed for '$Image' and no local copy exists. Check the tag, or authenticate to the registry with 'docker login ghcr.io'."
        }
        Write-Warning "Could not pull '$Image'; using the local copy. It may be out of date."
    }

    $containerId = (& docker create $Image | Select-Object -First 1)
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($containerId)) {
        throw "docker create failed for '$Image'."
    }

    try {
        New-Item -ItemType Directory -Path $Destination -Force | Out-Null
        Write-Step 'Copying the documentation payload out of the image ...'
        & docker cp "${containerId}:/template/scripts/template/." $Destination 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "docker cp failed. '$Image' does not carry /template/scripts/template; it may predate the payload being added."
        }
    }
    finally {
        # Always remove the container, even when the copy failed, so a failed
        # install never leaves clutter behind.
        & docker rm --force $containerId 2>&1 | Out-Null
    }

    return $Destination
}

function Set-ProjectFile {
    <#
    .SYNOPSIS
    Writes one installed file, honoring -Overwrite and -WhatIf.

    Declares SupportsShouldProcess in its own right rather than borrowing the
    script's $PSCmdlet. -WhatIf on the script sets $WhatIfPreference for the
    whole script scope, which this function inherits, so the reporting is the
    same either way.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Destination,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Content,
        [Parameter(Mandatory)][string]$Relative
    )

    $exists = Test-Path -LiteralPath $Destination -PathType Leaf
    if ($exists -and -not $Overwrite) {
        $skipped.Add($Relative)
        return
    }

    if (-not $PSCmdlet.ShouldProcess($Destination, $(if ($exists) { 'Replace' } else { 'Create' }))) {
        return
    }

    $parent = Split-Path -Parent $Destination
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    # LF and no BOM: these files are read by Linux containers, and the gate's
    # drift check compares generated content byte for byte.
    [IO.File]::WriteAllText($Destination, ($Content -replace "`r`n", "`n"), [Text.UTF8Encoding]::new($false))

    if ($exists) { $replaced.Add($Relative) } else { $created.Add($Relative) }
}

function Copy-PayloadFile {
    <#
    .SYNOPSIS
    Installs one file from the staged payload, applying literal substitutions.
    #>
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Destination,
        [Parameter(Mandatory)][string]$Relative,
        [Parameter()][hashtable]$Replace = @{}
    )

    $source = Join-Path $script:payloadRoot $Name
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw "Payload file '$Name' not found at '$source'. The image or -PayloadDir may predate it."
    }

    $content = Get-Content -LiteralPath $source -Raw
    foreach ($token in $Replace.GetEnumerator()) {
        $content = $content.Replace($token.Key, $token.Value)
    }

    Set-ProjectFile -Destination $Destination -Content $content -Relative $Relative
}

function ConvertTo-PowerShellSingleQuoted {
    <#
    .SYNOPSIS
    Escapes a value for embedding inside a PowerShell single-quoted string.
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Value)
    return $Value.Replace("'", "''")
}

# --- Resolve the project ------------------------------------------------------

if (Test-Path -LiteralPath $ProjectDir) {
    $projectPath = (Resolve-Path -LiteralPath $ProjectDir).Path
}
else {
    $projectPath = (New-Item -ItemType Directory -Path $ProjectDir -Force).FullName
}

if (-not $PSBoundParameters.ContainsKey('Title') -or [string]::IsNullOrWhiteSpace($Title)) {
    $Title = Split-Path -Leaf $projectPath
}

# The gate resolves the project root by walking up for '.git'. Without one it
# fails at run time rather than here, which is a worse place to find out.
if (-not (Test-Path -LiteralPath (Join-Path $projectPath '.git'))) {
    Write-Warning "'$projectPath' is not a git repository. The documentation gate locates the project root by walking up for a .git marker and will fail until this is one."
}

$docsDir = Join-Path $projectPath 'docs'
$contentDir = Join-Path $docsDir 'docs'
$scriptTarget = Join-Path $projectPath $ScriptDir
$configTarget = Join-Path $projectPath $ConfigDir
$workflowDir = Join-Path $projectPath '.github/workflows'

$imageTag = ($Title -replace '[^A-Za-z0-9]+', '-').ToLowerInvariant().Trim('-')
if ([string]::IsNullOrWhiteSpace($imageTag)) { $imageTag = 'project' }

# --- Acquire the payload ------------------------------------------------------

$stagingRoot = $null

try {
    if ($PSBoundParameters.ContainsKey('PayloadDir') -and -not [string]::IsNullOrWhiteSpace($PayloadDir)) {
        if (-not (Test-Path -LiteralPath $PayloadDir -PathType Container)) {
            throw "PayloadDir '$PayloadDir' does not exist or is not a directory."
        }
        $script:payloadRoot = (Resolve-Path -LiteralPath $PayloadDir).Path
        Write-Step "Using local payload: $script:payloadRoot"
    }
    else {
        $stagingRoot = Join-Path ([IO.Path]::GetTempPath()) ('docs-payload-' + [Guid]::NewGuid().ToString('N').Substring(0, 12))
        $script:payloadRoot = Get-PayloadFromImage -Image $BaseImage -Destination $stagingRoot
    }

    Write-Host ''
    Write-Step "Project:  $projectPath"
    Write-Step "Scripts:  $ScriptDir"
    Write-Step "Config:   $ConfigDir"
    Write-Host ''

    # --- Docusaurus overlay ---------------------------------------------------

    # routeBasePath and onBrokenLinks are forced rather than left at the
    # payload's defaults: the homepage generator rewrites the site origin to
    # '/', which only resolves when documentation is served from the root, and
    # a build that warns about broken links cannot gate anything.
    Copy-PayloadFile -Name 'docusaurus.config.ts' `
        -Destination (Join-Path $docsDir 'docusaurus.config.ts') `
        -Relative 'docs/docusaurus.config.ts' `
        -Replace @{
            "title: ''"                = "title: '$(ConvertTo-PowerShellSingleQuoted $Title)'"
            "tagline: ''"              = "tagline: '$(ConvertTo-PowerShellSingleQuoted $Description)'"
            "url: 'https://example.com'" = "url: '$(ConvertTo-PowerShellSingleQuoted ($SiteUrl.TrimEnd('/')))'"
            "onBrokenLinks: 'warn'"    = "onBrokenLinks: 'throw'"
            "routeBasePath: 'docs'"    = "routeBasePath: '/'"
        }

    Copy-PayloadFile -Name 'sidebar.ts' `
        -Destination (Join-Path $docsDir 'sidebar.ts') `
        -Relative 'docs/sidebar.ts'

    Copy-PayloadFile -Name 'Dockerfile' `
        -Destination (Join-Path $docsDir 'Dockerfile') `
        -Relative 'docs/Dockerfile' `
        -Replace @{
            'ARG BASE_IMAGE=ghcr.io/the-running-dev/docs-template:latest' = "ARG BASE_IMAGE=$BaseImage"
        }

    # Named without the leading dot in the payload so it is not treated as a
    # dockerignore for the template's own build context.
    Copy-PayloadFile -Name 'dockerignore' `
        -Destination (Join-Path $docsDir '.dockerignore') `
        -Relative 'docs/.dockerignore'

    # --- Local preview --------------------------------------------------------

    Copy-PayloadFile -Name 'docs.ps1' `
        -Destination (Join-Path $projectPath 'docs.ps1') `
        -Relative 'docs.ps1' `
        -Replace @{
            "Join-Path `$root 'build' 'ConvertTo-DocumentationHomepage.ps1'"  = "Join-Path `$root '$ScriptDir' 'ConvertTo-DocumentationHomepage.ps1'"
            "Join-Path `$root '.config' 'DocumentationRules.psd1'"            = "Join-Path `$root '$ConfigDir' 'DocumentationRules.psd1'"
            "[string]`$Tag = 'project-docs'"                                  = "[string]`$Tag = '$imageTag-docs'"
            "[string]`$BaseImage = 'ghcr.io/the-running-dev/docs-template:latest'" = "[string]`$BaseImage = '$BaseImage'"
        }

    # --- Homepage -------------------------------------------------------------

    $readmePath = Join-Path $projectPath 'README.md'
    $indexPath = Join-Path $contentDir 'index.md'
    $generateHomepage = -not $NoHomepage -and (Test-Path -LiteralPath $readmePath -PathType Leaf)

    if (-not $NoHomepage -and -not (Test-Path -LiteralPath $readmePath -PathType Leaf)) {
        Write-Warning 'No README.md found; skipping homepage generation. Pass -NoHomepage to silence this.'
    }

    # Only install the generator when something actually runs it. With no
    # homepage the gate has no drift check and docs.ps1 skips regeneration, so
    # shipping it would leave a script nothing calls.
    if ($generateHomepage) {
        Copy-PayloadFile -Name 'ConvertTo-DocumentationHomepage.ps1' `
            -Destination (Join-Path $scriptTarget 'ConvertTo-DocumentationHomepage.ps1') `
            -Relative "$ScriptDir/ConvertTo-DocumentationHomepage.ps1"

        $homepageScript = Join-Path $script:payloadRoot 'ConvertTo-DocumentationHomepage.ps1'
        $content = & $homepageScript `
            -ReadmePath $readmePath `
            -Title $Title `
            -Description $Description `
            -SiteUrl $SiteUrl
        Set-ProjectFile -Destination $indexPath -Content $content -Relative 'docs/docs/index.md'
    }
    elseif (-not (Test-Path -LiteralPath $indexPath -PathType Leaf)) {
        # A Docusaurus site serving from the root still needs a page there.
        Set-ProjectFile `
            -Destination $indexPath `
            -Content "---`ntitle: $Title`nsidebar_position: 1`n---`n`n# $Title`n" `
            -Relative 'docs/docs/index.md'
    }

    # --- Documentation gate ---------------------------------------------------

    if (-not $SkipGate) {
        Copy-PayloadFile -Name 'Test-Documentation.ps1' `
            -Destination (Join-Path $scriptTarget 'Test-Documentation.ps1') `
            -Relative "$ScriptDir/Test-Documentation.ps1" `
            -Replace @{
                "Join-Path `$repositoryRoot '.config' 'DocumentationRules.psd1'" = "Join-Path `$repositoryRoot '$ConfigDir' 'DocumentationRules.psd1'"
            }

        # The rules file carries this project's front matter and site origin, so
        # the gate regenerates the homepage exactly as the preview script does.
        $rules = Get-Content -LiteralPath (Join-Path $script:payloadRoot 'DocumentationRules.psd1') -Raw
        $rules = $rules.Replace("Generator = 'build/ConvertTo-DocumentationHomepage.ps1'", "Generator = '$ScriptDir/ConvertTo-DocumentationHomepage.ps1'")
        $rules = $rules.Replace("Title = 'Home'", "Title = '$(ConvertTo-PowerShellSingleQuoted $Title)'")
        $rules = $rules.Replace("Description = ''", "Description = '$(ConvertTo-PowerShellSingleQuoted $Description)'")
        $rules = $rules.Replace("SiteUrl = ''", "SiteUrl = '$(ConvertTo-PowerShellSingleQuoted $SiteUrl)'")

        if (-not $generateHomepage) {
            # Drop the GeneratedFiles block rather than leave a drift check for a
            # file this project does not generate. This also covers a project
            # with no README, where the generator was never installed and the
            # check would fail on a missing script rather than on real drift.
            # The markers exist in the payload for exactly this excision.
            $rules = [regex]::Replace(
                $rules,
                '(?s)[ \t]*#\s*---\s*GeneratedFiles:start\s*---.*?#\s*---\s*GeneratedFiles:end\s*---[ \t]*\r?\n',
                ''
            )
        }

        Set-ProjectFile `
            -Destination (Join-Path $configTarget 'DocumentationRules.psd1') `
            -Content $rules `
            -Relative "$ConfigDir/DocumentationRules.psd1"
    }

    # --- Workflow -------------------------------------------------------------

    if (-not $SkipWorkflow) {
        # One workflow, three jobs. The gate and the site build check disjoint
        # things: the build catches what Docusaurus itself rejects, while the
        # gate covers what the build never sees -- root Markdown such as
        # README.md, relative link targets, heading anchors, terminology, and
        # drift between the README and the generated homepage.
        $gateJob = @'
    documentation:
        name: Documentation links and terminology
        runs-on: ubuntu-latest

        steps:
            - name: Check out repository
              uses: actions/checkout@v6

            - name: Validate Markdown links, terminology, and generated files
              shell: pwsh
              run: ./__SCRIPT_DIR__/Test-Documentation.ps1 -TreatWarningsAsErrors

'@

        $workflow = @'
name: Docs CI

# Everything the documentation needs, in one workflow: check the authored
# Markdown, build the site, and deploy it.
#
# The gate and the build are not the same check. Docusaurus fails on unresolved
# routes inside the site; the gate covers what the site build never sees --
# README.md, which is not part of the site at all, plus relative link targets,
# heading anchors, product-name casing, and drift between a generated file and
# its source.

"on":
    pull_request:
    push:
        branches:
            - main
    workflow_dispatch:

# A job can never hold more permissions than the workflow, so these cover the
# superset the deploy job requires.
permissions:
    contents: read
    packages: read
    pages: write
    id-token: write

jobs:
__GATE_JOB__    verify:
        name: Verify Documentation Build
        if: github.event_name != 'push'
        runs-on: ubuntu-latest
        # Run inside the published base image, which already carries the
        # template under /template with node_modules and PowerShell installed.
        container:
            image: __BASE_IMAGE__
            credentials:
                username: ${{ github.repository_owner }}
                password: ${{ secrets.REGISTRY_TOKEN || github.token }}

        steps:
            - name: Check out repository
              uses: actions/checkout@v6

            - name: Build documentation
              shell: pwsh
              run: /template/scripts/docs-build.ps1 -SourceDocs ./docs -OutputPath artifacts/docs

            # Run the same archiving step the deploy job uses, so the deploy
            # path is covered before merge rather than after it. This action
            # tars the site with `tar --hard-dereference`, which fails outright
            # on an image without GNU tar. Uploading an artifact publishes
            # nothing; deploy-pages does that, and it is not in this job.
            - name: Archive Pages artifact (verify deploy path)
              uses: actions/upload-pages-artifact@v4
              with:
                  path: artifacts/docs

    deploy:
        name: Build and Deploy Documentation
        if: github.event_name == 'push'
        runs-on: ubuntu-latest
        # Scoped to this job so verify runs never contend for the Pages lock.
        concurrency:
            group: github-pages
            cancel-in-progress: false
        environment:
            name: github-pages
            url: ${{ steps.deployment.outputs.page_url }}
        container:
            image: __BASE_IMAGE__
            credentials:
                username: ${{ github.repository_owner }}
                password: ${{ secrets.REGISTRY_TOKEN || github.token }}

        steps:
            - name: Check out repository
              uses: actions/checkout@v6

            - name: Configure GitHub Pages
              uses: actions/configure-pages@v5

            - name: Build documentation
              shell: pwsh
              run: /template/scripts/docs-build.ps1 -SourceDocs ./docs -OutputPath artifacts/docs

            - name: Upload Pages artifact
              uses: actions/upload-pages-artifact@v4
              with:
                  path: artifacts/docs

            - name: Deploy to GitHub Pages
              id: deployment
              uses: actions/deploy-pages@v4
'@

        $workflow = $workflow.Replace('__GATE_JOB__', $(if ($SkipGate) { '' } else { $gateJob.Replace('__SCRIPT_DIR__', $ScriptDir) }))
        $workflow = $workflow.Replace('__BASE_IMAGE__', $BaseImage)

        Set-ProjectFile `
            -Destination (Join-Path $workflowDir 'docs-ci.yml') `
            -Content $workflow `
            -Relative '.github/workflows/docs-ci.yml'
    }
}
finally {
    if ($stagingRoot) { Remove-TemporaryTree -Path $stagingRoot }
}

# --- Summary ------------------------------------------------------------------

Write-Host ''
foreach ($group in @(
        @{ Label = 'Created';  Items = $created;  Color = 'Green' }
        @{ Label = 'Replaced'; Items = $replaced; Color = 'Yellow' }
        @{ Label = 'Skipped';  Items = $skipped;  Color = 'DarkGray' }
    )) {
    if ($group.Items.Count -eq 0) { continue }
    Write-Host "[INSTALL-DOCS] $($group.Label) ($($group.Items.Count)):" -ForegroundColor $group.Color
    foreach ($item in $group.Items) { Write-Host "               $item" -ForegroundColor $group.Color }
}

if ($skipped.Count -gt 0 -and -not $Overwrite) {
    Write-Host ''
    Write-Host '[INSTALL-DOCS] Existing files were left alone. Re-run with -Overwrite to replace them.' -ForegroundColor DarkGray
}

Write-Host ''
if ($WhatIfPreference) {
    Write-Step 'Dry run complete. Nothing was written; re-run without -WhatIf to install.'
}
else {
    Write-Step 'Next steps:'
    # Built as a list so the numbering stays contiguous whichever steps the
    # -Skip switches remove.
    $steps = [System.Collections.Generic.List[string]]::new()
    $steps.Add('Author documentation under docs/docs/')
    $steps.Add('Preview locally:  ./docs.ps1')
    if (-not $SkipGate) {
        $steps.Add("Check it:         ./$ScriptDir/Test-Documentation.ps1")
    }
    if (-not $SkipWorkflow) {
        $steps.Add('Enable GitHub Pages for this repository, source: GitHub Actions')
        $steps.Add('Make the docs checks required, or a red run will not block a merge')
    }
    for ($i = 0; $i -lt $steps.Count; $i++) {
        Write-Host "               $($i + 1). $($steps[$i])" -ForegroundColor White
    }
    Write-Host ''
    Write-Host '[INSTALL-DOCS] Note: packages published to GHCR are private by default. If CI' -ForegroundColor DarkGray
    Write-Host '               cannot pull the base image, set the REGISTRY_TOKEN secret or make' -ForegroundColor DarkGray
    Write-Host '               the package visible to this repository.' -ForegroundColor DarkGray
}
