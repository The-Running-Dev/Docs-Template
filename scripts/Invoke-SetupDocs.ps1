<#
.SYNOPSIS
    Sets a project up with the full documentation system in one command.

.DESCRIPTION
    Installs everything a project needs to author, preview, check, and publish
    documentation from this template:

      docs/                          Docusaurus overlay copied over /template
        docusaurus.config.ts         Site configuration
        sidebar.ts                   Sidebar configuration
        Dockerfile, .dockerignore    Local preview only
        docs/index.md                Homepage, generated from the README
      docs.ps1                       Local preview entry point
      build/                         Homepage generator and documentation gate
      .config/                       Gate rules
      .github/workflows/             docs.yml, docs-ci.yml, docs-deploy.yml,
                                     docs-quality.yml

    Idempotent. Without -Overwrite an existing file is left alone and reported
    as skipped, which matters because the workflows are kept byte-identical to
    this template so the command can be re-run to pick up upstream fixes.

    Only files this script owns are written. It never edits a workflow or script
    the project author wrote, which is why the gate ships as its own
    docs-quality.yml rather than a job appended to an existing test workflow.

.PARAMETER ProjectDir
    Target project directory. Defaults to the current directory.

.PARAMETER Title
    Homepage front matter title. Defaults to the project directory name.

.PARAMETER Description
    Homepage front matter description.

.PARAMETER SiteUrl
    Published site origin, with a trailing slash, rewritten to '/' in the
    generated homepage. Give this when the README links to the published site
    using absolute URLs, which is what makes one README work both on the code
    host and as the site homepage.

.PARAMETER ScriptDir
    Where PowerShell tooling is installed, relative to the project. Defaults to
    'build'. Not every project has one, so it is a parameter rather than a
    convention.

.PARAMETER ConfigDir
    Where the gate rules are installed, relative to the project. Defaults to
    '.config'.

.PARAMETER NoHomepage
    Do not generate the homepage from the README, and do not register it for
    drift checking. Use when the homepage is authored by hand.

.PARAMETER SkipWorkflow
    Install no GitHub Actions workflows.

.PARAMETER SkipGate
    Install no documentation gate: no checker, no rules, no docs-quality.yml.

.PARAMETER Overwrite
    Replace files that already exist.

.EXAMPLE
    ./scripts/Invoke-SetupDocs.ps1 -ProjectDir C:\src\my-project

.EXAMPLE
    ./scripts/Invoke-SetupDocs.ps1 -ProjectDir . -Title 'My Project' -SiteUrl 'https://docs.example.com/'

.EXAMPLE
    ./scripts/Invoke-SetupDocs.ps1 -Overwrite -WhatIf
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

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$scriptRoot = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($scriptRoot)) {
    $scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
}
$templateDir = Join-Path $scriptRoot 'template'

$created = [System.Collections.Generic.List[string]]::new()
$skipped = [System.Collections.Generic.List[string]]::new()
$replaced = [System.Collections.Generic.List[string]]::new()

function Resolve-ProjectPath {
    param([Parameter(Mandatory)][string]$Path)

    if (Test-Path -LiteralPath $Path) {
        return (Resolve-Path -LiteralPath $Path).Path
    }
    return (New-Item -ItemType Directory -Path $Path -Force).FullName
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

    # LF and no BOM: these files are read by Linux containers and compared
    # byte-for-byte by the drift check.
    [IO.File]::WriteAllText($Destination, ($Content -replace "`r`n", "`n"), [Text.UTF8Encoding]::new($false))

    if ($exists) { $replaced.Add($Relative) } else { $created.Add($Relative) }
}

function Copy-TemplateFile {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Destination,
        [Parameter(Mandatory)][string]$Relative,
        [Parameter()][hashtable]$Replace = @{}
    )

    $source = Join-Path $templateDir $Name
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw "Template asset '$Name' not found at '$source'."
    }

    $content = Get-Content -LiteralPath $source -Raw
    foreach ($token in $Replace.GetEnumerator()) {
        $content = $content.Replace($token.Key, $token.Value)
    }

    Set-ProjectFile -Destination $Destination -Content $content -Relative $Relative
}

function ConvertTo-DockerTagSegment {
    <#
    .SYNOPSIS
    Turns a title into a lowercase, hyphenated segment safe for a Docker tag.

    Decomposes accented characters first (U-with-diaeresis becomes U plus a
    combining mark) and drops the combining marks, so an accented title keeps
    its readable base letters instead of losing them outright. Falls back to
    a fixed segment when nothing alphanumeric survives, since a tag cannot be
    empty or start with '-' (e.g. a title of '!!!' or only whitespace).
    #>
    param (
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Value
    )

    $decomposed = $Value.Normalize([Text.NormalizationForm]::FormD)
    $withoutMarks = -join ($decomposed.ToCharArray() | Where-Object {
            [Globalization.CharUnicodeInfo]::GetUnicodeCategory($_) -ne
            [Globalization.UnicodeCategory]::NonSpacingMark
        })

    $slug = ($withoutMarks -replace '[^A-Za-z0-9]+', '-').ToLowerInvariant().Trim('-')

    if ([string]::IsNullOrEmpty($slug)) {
        return 'project'
    }
    return $slug
}

$projectPath = Resolve-ProjectPath -Path $ProjectDir
$docsDir = Join-Path $projectPath 'docs'
$contentDir = Join-Path $docsDir 'docs'
$scriptTarget = Join-Path $projectPath $ScriptDir
$configTarget = Join-Path $projectPath $ConfigDir
$workflowDir = Join-Path $projectPath '.github/workflows'

if ([string]::IsNullOrWhiteSpace($Title)) {
    $Title = Split-Path -Leaf $projectPath
}

Write-Host "[SETUP] Project:  $projectPath" -ForegroundColor Cyan
Write-Host "[SETUP] Scripts:  $ScriptDir" -ForegroundColor Cyan
Write-Host "[SETUP] Config:   $ConfigDir" -ForegroundColor Cyan

# --- Docusaurus overlay -----------------------------------------------------

foreach ($directory in @($docsDir, $contentDir)) {
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        if ($PSCmdlet.ShouldProcess($directory, 'Create directory')) {
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
        }
    }
}

Copy-TemplateFile -Name 'docusaurus.config.ts' `
    -Destination (Join-Path $docsDir 'docusaurus.config.ts') `
    -Relative 'docs/docusaurus.config.ts'

Copy-TemplateFile -Name 'sidebar.ts' `
    -Destination (Join-Path $docsDir 'sidebar.ts') `
    -Relative 'docs/sidebar.ts'

Copy-TemplateFile -Name 'Dockerfile' `
    -Destination (Join-Path $docsDir 'Dockerfile') `
    -Relative 'docs/Dockerfile'

# Stored without the leading dot so it is not hidden, and not applied to this
# template's own build context.
Copy-TemplateFile -Name 'dockerignore' `
    -Destination (Join-Path $docsDir '.dockerignore') `
    -Relative 'docs/.dockerignore'

Copy-TemplateFile -Name 'docs.ps1' `
    -Destination (Join-Path $projectPath 'docs.ps1') `
    -Relative 'docs.ps1' `
    -Replace @{
        "Join-Path `$root 'build' 'ConvertTo-DocumentationHomepage.ps1'" = "Join-Path `$root '$ScriptDir' 'ConvertTo-DocumentationHomepage.ps1'"
        "Join-Path `$root '.config' 'DocumentationRules.psd1'" = "Join-Path `$root '$ConfigDir' 'DocumentationRules.psd1'"
        "[string]`$Tag = 'project-docs'" = "[string]`$Tag = '$(ConvertTo-DockerTagSegment -Value $Title)-docs'"
    }

# --- Homepage ---------------------------------------------------------------

$readmePath = Join-Path $projectPath 'README.md'
$indexPath = Join-Path $contentDir 'index.md'
$generateHomepage = -not $NoHomepage -and (Test-Path -LiteralPath $readmePath -PathType Leaf)

if (-not $NoHomepage -and -not (Test-Path -LiteralPath $readmePath -PathType Leaf)) {
    Write-Warning 'No README.md found; skipping homepage generation. Pass -NoHomepage to silence this.'
}

# Only install the generator when something actually runs it. With -NoHomepage
# the gate has no drift check and docs.ps1 skips regeneration, so shipping it
# would leave a script nothing calls.
if ($generateHomepage) {
    Copy-TemplateFile -Name 'ConvertTo-DocumentationHomepage.ps1' `
        -Destination (Join-Path $scriptTarget 'ConvertTo-DocumentationHomepage.ps1') `
        -Relative "$ScriptDir/ConvertTo-DocumentationHomepage.ps1"
}

if ($generateHomepage) {
    $homepageScript = Join-Path $templateDir 'ConvertTo-DocumentationHomepage.ps1'
    $content = & $homepageScript `
        -ReadmePath $readmePath `
        -Title $Title `
        -Description $Description `
        -SiteUrl $SiteUrl
    Set-ProjectFile -Destination $indexPath -Content $content -Relative 'docs/docs/index.md'
}
elseif (-not (Test-Path -LiteralPath $indexPath -PathType Leaf)) {
    Set-ProjectFile `
        -Destination $indexPath `
        -Content "---`ntitle: $Title`nsidebar_position: 1`n---`n`n# $Title`n" `
        -Relative 'docs/docs/index.md'
}

# --- Documentation gate -----------------------------------------------------

if (-not $SkipGate) {
    Copy-TemplateFile -Name 'Test-Documentation.ps1' `
        -Destination (Join-Path $scriptTarget 'Test-Documentation.ps1') `
        -Relative "$ScriptDir/Test-Documentation.ps1" `
        -Replace @{
            "Join-Path `$repositoryRoot '.config' 'DocumentationRules.psd1'" = "Join-Path `$repositoryRoot '$ConfigDir' 'DocumentationRules.psd1'"
        }

    # The rules file carries this project's front matter and site origin, so the
    # gate regenerates the homepage exactly as the preview script does.
    $rules = Get-Content -LiteralPath (Join-Path $templateDir 'DocumentationRules.psd1') -Raw
    $rules = $rules.Replace("Generator = 'build/ConvertTo-DocumentationHomepage.ps1'", "Generator = '$ScriptDir/ConvertTo-DocumentationHomepage.ps1'")
    $rules = $rules.Replace("Title = 'Home'", "Title = '$($Title.Replace("'", "''"))'")
    $rules = $rules.Replace("Description = ''", "Description = '$($Description.Replace("'", "''"))'")
    $rules = $rules.Replace("SiteUrl = ''", "SiteUrl = '$($SiteUrl.Replace("'", "''"))'")

    if (-not $generateHomepage) {
        # Drop the GeneratedFiles block entirely rather than leave a check for a
        # file this project does not generate. This also covers a project with
        # no README, where the generator was never installed and the check would
        # fail on a missing script rather than on real drift.
        #
        # Located by explicit marker lines (see DocumentationRules.psd1) rather
        # than matched by indentation depth, so reformatting the template file
        # cannot silently break this strip -- a missing marker throws instead.
        $startMarker = '    # --- GeneratedFiles:start ---'
        $endMarker = '    # --- GeneratedFiles:end ---'

        $ruleLines = @($rules -split "`r?`n")
        $startLine = [Array]::IndexOf($ruleLines, $startMarker)
        $endLine = [Array]::IndexOf($ruleLines, $endMarker)

        if ($startLine -lt 0 -or $endLine -lt 0) {
            throw (
                "DocumentationRules.psd1 template is missing the GeneratedFiles " +
                "markers ('$($startMarker.Trim())' / '$($endMarker.Trim())'); " +
                'cannot strip the block for -NoHomepage.'
            )
        }

        # Also drop one trailing blank line, so removing the block doesn't leave
        # a double gap between the sections on either side of it.
        $removeThrough = $endLine
        if ($endLine + 1 -lt $ruleLines.Count -and [string]::IsNullOrWhiteSpace($ruleLines[$endLine + 1])) {
            $removeThrough++
        }

        $before = if ($startLine -gt 0) { $ruleLines[0..($startLine - 1)] } else { @() }
        $after = if ($removeThrough + 1 -lt $ruleLines.Count) { $ruleLines[($removeThrough + 1)..($ruleLines.Count - 1)] } else { @() }
        $rules = ($before + $after) -join "`n"
    }

    Set-ProjectFile `
        -Destination (Join-Path $configTarget 'DocumentationRules.psd1') `
        -Content $rules `
        -Relative "$ConfigDir/DocumentationRules.psd1"
}

# --- Workflows --------------------------------------------------------------

if (-not $SkipWorkflow) {
    Copy-TemplateFile -Name 'docs.yml' `
        -Destination (Join-Path $workflowDir 'docs.yml') `
        -Relative '.github/workflows/docs.yml'

    $workflowInstaller = Join-Path $scriptRoot 'setup-docs-workflow.ps1'
    if (-not (Test-Path -LiteralPath $workflowInstaller -PathType Leaf)) {
        throw "Workflow installer not found at '$workflowInstaller'."
    }
    if ($PSCmdlet.ShouldProcess('.github/workflows', 'Install docs-ci.yml and docs-deploy.yml')) {
        & $workflowInstaller -CallerProjectDir $projectPath -Overwrite:$Overwrite
    }

    if (-not $SkipGate) {
        Copy-TemplateFile -Name 'docs-quality.yml' `
            -Destination (Join-Path $workflowDir 'docs-quality.yml') `
            -Relative '.github/workflows/docs-quality.yml' `
            -Replace @{
                'build/Test-Documentation.ps1' = "$ScriptDir/Test-Documentation.ps1"
                'build/ConvertTo-DocumentationHomepage.ps1' = "$ScriptDir/ConvertTo-DocumentationHomepage.ps1"
                '.config/DocumentationRules.psd1' = "$ConfigDir/DocumentationRules.psd1"
                './build/Test-Documentation.ps1' = "./$ScriptDir/Test-Documentation.ps1"
            }
    }
}

# --- Summary ----------------------------------------------------------------

Write-Host ''
foreach ($group in @(
        @{ Label = 'Created';  Items = $created;  Color = 'Green' }
        @{ Label = 'Replaced'; Items = $replaced; Color = 'Yellow' }
        @{ Label = 'Skipped';  Items = $skipped;  Color = 'DarkGray' }
    )) {
    if ($group.Items.Count -eq 0) { continue }
    Write-Host "[SETUP] $($group.Label) ($($group.Items.Count)):" -ForegroundColor $group.Color
    foreach ($item in $group.Items) { Write-Host "          $item" -ForegroundColor $group.Color }
}

# docs-ci.yml and docs-deploy.yml are installed by setup-docs-workflow.ps1,
# which reports them itself. Say so, or the counts above read as short by two.
if (-not $SkipWorkflow) {
    Write-Host ''
    Write-Host '[SETUP] docs-ci.yml and docs-deploy.yml are reported separately above' -ForegroundColor DarkGray
    Write-Host '        by setup-docs-workflow.ps1, which owns those two files.' -ForegroundColor DarkGray
}

if ($skipped.Count -gt 0 -and -not $Overwrite) {
    Write-Host ''
    Write-Host '[SETUP] Existing files were left alone. Re-run with -Overwrite to replace them.' -ForegroundColor DarkGray
}

Write-Host ''
Write-Host '[SETUP] Next steps:' -ForegroundColor Cyan
Write-Host '  1. Author documentation under docs/docs/' -ForegroundColor White
Write-Host '  2. Preview locally:  ./docs.ps1' -ForegroundColor White
if (-not $SkipGate) {
    Write-Host "  3. Check it:         ./$ScriptDir/Test-Documentation.ps1" -ForegroundColor White
}
if (-not $SkipWorkflow) {
    Write-Host '  4. Enable GitHub Pages for this repository, source: GitHub Actions' -ForegroundColor White
    Write-Host '  5. Make the docs checks required, or a red run will not block a merge' -ForegroundColor White
}
Write-Host ''
Write-Host '[SETUP] Note: packages published to GHCR are private by default. If your' -ForegroundColor DarkGray
Write-Host '        documentation tells readers to pull an image, confirm its visibility.' -ForegroundColor DarkGray
