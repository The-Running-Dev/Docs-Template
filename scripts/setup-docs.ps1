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
      .github/workflows/             docs-ci.yml (gate + build), docs-deploy.yml

    Idempotent. Without -Overwrite an existing file is left alone and reported
    as skipped, which matters because the workflows are kept byte-identical to
    this template so the command can be re-run to pick up upstream fixes.

    Upgrading from a version that installed four workflow files also deletes
    the two now retired, docs.yml and docs-quality.yml, reporting them as
    Removed. They are not merely redundant: docs.yml drives the other two with
    `uses:` and neither declares workflow_call any more, and docs-quality.yml
    reports a check whose name now collides with docs-ci.yml's gate job. This
    happens on any run that installs workflows, with or without -Overwrite,
    since leaving them behind leaves the branch red either way.

    Only files this script owns are written. It never edits a workflow or script
    the project author wrote, which is why the gate and build live in their own
    docs-ci.yml rather than jobs appended to an existing test workflow. Deploy
    stays a second file: a workflow can never grant a job more permission than
    the workflow itself declares, so folding deploy's pages/id-token grant into
    docs-ci.yml would hand the gate and verify jobs credentials they never use.

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

.PARAMETER BaseImage
    Documentation image the installed files build on. Written to all four
    places an install references it -- docs/Dockerfile's BASE_IMAGE argument,
    docs.ps1's default, and the container image in both workflows -- so a
    project using a fork, a private mirror, or a pinned digest does not have to
    hand-edit each one. Defaults to the published image at :latest, which is
    the only tag the release workflow publishes.

.PARAMETER NoHomepage
    Do not generate the homepage from the README, and do not register it for
    drift checking. Use when the homepage is authored by hand.

.PARAMETER SkipWorkflow
    Install no GitHub Actions workflows.

.PARAMETER SkipGate
    Install no documentation gate: no checker, no rules, and the
    'documentation' job is removed from the installed docs-ci.yml.

.PARAMETER WorkflowsOnly
    Install only the GitHub Actions workflows, leaving the Docusaurus overlay,
    preview script, homepage, and gate files alone. Use it to refresh the
    workflows of a project that already has the rest, without touching
    anything else. Mutually exclusive with -SkipWorkflow.

.PARAMETER WorkflowDir
    Where the workflows are installed, relative to the project. Defaults to
    '.github/workflows', which is the only location GitHub Actions reads; it
    is a parameter so a caller staging files elsewhere can still use this.

.PARAMETER Overwrite
    Replace files that already exist.

.EXAMPLE
    ./scripts/setup-docs.ps1 -ProjectDir C:\src\my-project

.EXAMPLE
    ./scripts/setup-docs.ps1 -ProjectDir . -Title 'My Project' -SiteUrl 'https://docs.example.com/'

.EXAMPLE
    ./scripts/setup-docs.ps1 -Overwrite -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()][string]$ProjectDir = '.',
    [Parameter()][string]$Title,
    [Parameter()][string]$Description = '',
    [Parameter()][string]$SiteUrl = '',
    [Parameter()][string]$ScriptDir = 'build',
    [Parameter()][string]$ConfigDir = '.config',
    [Parameter()][string]$BaseImage = 'ghcr.io/the-running-dev/docs-template:latest',
    [Parameter()][switch]$NoHomepage,
    [Parameter()][switch]$SkipWorkflow,
    [Parameter()][switch]$SkipGate,
    [Parameter()][switch]$WorkflowsOnly,
    [Parameter()][string]$WorkflowDir = '.github/workflows',
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
$removed = [System.Collections.Generic.List[string]]::new()

# Workflow files earlier versions of this script installed, which the current
# two-file layout replaces. Left in place they do not merely clutter -- they
# break:
#
#   docs.yml         calls docs-ci.yml and docs-deploy.yml with `uses:`, and
#                    neither declares workflow_call any more, so every run
#                    fails outright.
#   docs-quality.yml runs the gate a second time under the job name
#                    'Documentation links and terminology' -- byte-identical
#                    to the new gate job's name, so two different workflows
#                    report the same check context.
#
# Removed rather than reported, because a re-run is how a project picks up
# upstream fixes, and an upgrade that leaves the branch red is not an upgrade.
$retiredWorkflows = @('docs.yml', 'docs-quality.yml')

function Resolve-ProjectPath {
    <#
    .SYNOPSIS
    Resolves -ProjectDir to a full path, creating it if it does not exist.

    An existing path must be a directory; a file is rejected with a clear
    error rather than silently accepted and used to build nonsensical paths
    underneath it later.

    Creation is gated behind ShouldProcess and the full path is always
    computed and returned directly -- not read back from New-Item's result --
    because New-Item is simulated under -WhatIf and returns $null, and
    Set-StrictMode turns a .FullName access on that into a terminating error
    instead of silently producing nothing.
    #>
    param([Parameter(Mandatory)][string]$Path)

    if (Test-Path -LiteralPath $Path) {
        if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
            throw "ProjectDir '$Path' exists but is not a directory."
        }
        return (Resolve-Path -LiteralPath $Path).Path
    }

    # Resolved against the current PowerShell location, not the process's raw
    # working directory ([IO.Path]::GetFullPath uses the latter, which can
    # differ from $PWD after Set-Location) -- and without requiring the path
    # to exist, unlike Resolve-Path.
    $fullPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)

    if ($PSCmdlet.ShouldProcess($fullPath, 'Create directory')) {
        New-Item -ItemType Directory -Path $fullPath -Force | Out-Null
    }

    return $fullPath
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

function Remove-RetiredFile {
    <#
    .SYNOPSIS
    Deletes one workflow file a previous version of this script installed.

    Scoped deliberately narrowly: only the fixed $retiredWorkflows names, only
    under .github/workflows, and only files -- never directories, never a
    caller-supplied path. This script installed these files and no longer
    does, so removing them on the next run is what makes an upgrade land in a
    working state rather than a half-migrated one.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Destination,
        [Parameter(Mandatory)][string]$Relative
    )

    if (-not (Test-Path -LiteralPath $Destination -PathType Leaf)) { return }

    if ($PSCmdlet.ShouldProcess($Destination, 'Remove retired workflow')) {
        Remove-Item -LiteralPath $Destination -Force
        $removed.Add($Relative)
    }
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

function ConvertTo-YamlSingleQuotedScalar {
    <#
    .SYNOPSIS
    Serializes a string as a single-line, single-quoted YAML scalar.

    Used for the no-README stub homepage's front matter. A raw, unescaped
    -Title could otherwise contain a newline and an embedded '---', closing
    the front matter block early and injecting fabricated keys after it --
    confirmed against ConvertTo-DocumentationHomepage.ps1's original
    unescaped interpolation before this fix. Collapsing newlines and doubling
    embedded single quotes closes both paths off entirely.
    #>
    param (
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Value
    )

    $collapsed = ($Value -replace '\r\n?|\n', ' ').Trim()
    return "'$($collapsed.Replace("'", "''"))'"
}

function ConvertTo-JavaScriptSingleQuoted {
    <#
    .SYNOPSIS
    Escapes a value for embedding in a single-quoted TypeScript string literal.

    Deliberately not the same rule as ConvertTo-YamlSingleQuotedScalar above,
    or as the psd1 substitutions further down, both of which escape an
    embedded single quote by doubling it. TypeScript reads 'Ben''s Docs' as
    two adjacent string literals and fails to parse -- confirmed against node
    -- so a title containing an apostrophe would otherwise install a
    docusaurus.config.ts that cannot be loaded at all.

    Backslash is escaped first, or it would re-escape the backslashes this
    function introduces for the quotes. Newlines are collapsed because a
    single-quoted JavaScript literal cannot span lines.
    #>
    param (
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Value
    )

    $collapsed = ($Value -replace '\r\n?|\n', ' ').Trim()
    return $collapsed.Replace('\', '\\').Replace("'", "\'")
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

function Remove-MarkedBlock {
    <#
    .SYNOPSIS
    Removes one marker-delimited block from templated content.

    Shared by the DocumentationRules.psd1 GeneratedFiles strip (-NoHomepage)
    and the docs-ci.yml documentation-job strip (-SkipGate). Both remove a
    section of a byte-identical-to-template file when a feature is opted out
    of, and both need the same two guarantees: locate by explicit marker
    lines rather than indentation depth, so reformatting the template cannot
    silently break the strip -- a missing marker throws instead -- and drop
    one trailing blank line so removal doesn't leave a double gap between the
    sections on either side of it.
    #>
    param(
        [Parameter(Mandatory)][string]$Content,
        [Parameter(Mandatory)][string]$StartMarker,
        [Parameter(Mandatory)][string]$EndMarker,
        [Parameter(Mandatory)][string]$FileLabel
    )

    $lines = @($Content -split "`r?`n")
    $startLine = [Array]::IndexOf($lines, $StartMarker)
    $endLine = [Array]::IndexOf($lines, $EndMarker)

    if ($startLine -lt 0 -or $endLine -lt 0) {
        throw (
            "$FileLabel template is missing the expected markers " +
            "('$($StartMarker.Trim())' / '$($EndMarker.Trim())'); cannot strip the block."
        )
    }

    $removeThrough = $endLine
    if ($endLine + 1 -lt $lines.Count -and [string]::IsNullOrWhiteSpace($lines[$endLine + 1])) {
        $removeThrough++
    }

    $before = if ($startLine -gt 0) { $lines[0..($startLine - 1)] } else { @() }
    $after = if ($removeThrough + 1 -lt $lines.Count) { $lines[($removeThrough + 1)..($lines.Count - 1)] } else { @() }

    return ($before + $after) -join "`n"
}

function Resolve-ContainedProjectDirectory {
    <#
    .SYNOPSIS
    Resolves a caller-supplied relative directory (-ScriptDir / -ConfigDir)
    and guarantees it stays inside the project root.

    Rejects a rooted path (an absolute path, on Windows or Unix) and any '..'
    segment outright -- IsPathRooted alone is not enough, since a traversal
    like '..\..\evil' is not rooted but still escapes the project root once
    resolved. The combined path is then canonicalized and containment is
    re-checked as a second, independent guard, so a separator or encoding
    trick that slips past the first two checks still cannot resolve outside
    -ProjectRoot.
    #>
    param (
        [Parameter(Mandatory)]
        [string] $Value,

        [Parameter(Mandatory)]
        [string] $ParameterName,

        [Parameter(Mandatory)]
        [string] $ProjectRoot
    )

    if ([IO.Path]::IsPathRooted($Value)) {
        throw "-$ParameterName must be a path relative to the project, not rooted: '$Value'."
    }

    if (@($Value -split '[\\/]') -contains '..') {
        throw "-$ParameterName must not contain '..' segments: '$Value'."
    }

    $resolved = [IO.Path]::GetFullPath((Join-Path $ProjectRoot $Value))
    $normalizedRoot = $ProjectRoot.TrimEnd('\', '/')

    if ($resolved -ne $normalizedRoot -and
        -not $resolved.StartsWith($normalizedRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw "-$ParameterName resolves outside the project directory: '$Value' -> '$resolved'."
    }

    return $resolved
}

# -BaseImage is interpolated into a Dockerfile ARG, a PowerShell string, and
# two YAML scalars. A container reference cannot legally contain whitespace or
# quotes, and any of those would corrupt one of the four files rather than fail
# visibly, so reject them here instead of installing something subtly broken.
if ($BaseImage -match '[\s''"]') {
    throw "-BaseImage must be a container reference with no whitespace or quotes: '$BaseImage'."
}
if ([string]::IsNullOrWhiteSpace($BaseImage)) {
    throw '-BaseImage must not be empty.'
}

$defaultBaseImage = 'ghcr.io/the-running-dev/docs-template:latest'

$projectPath = Resolve-ProjectPath -Path $ProjectDir
$docsDir = Join-Path $projectPath 'docs'
$contentDir = Join-Path $docsDir 'docs'
$scriptTarget = Resolve-ContainedProjectDirectory -Value $ScriptDir -ParameterName 'ScriptDir' -ProjectRoot $projectPath
$configTarget = Resolve-ContainedProjectDirectory -Value $ConfigDir -ParameterName 'ConfigDir' -ProjectRoot $projectPath
if ($WorkflowsOnly -and $SkipWorkflow) {
    throw '-WorkflowsOnly and -SkipWorkflow are mutually exclusive: one installs nothing but workflows, the other installs everything except them.'
}

# Same containment guard as -ScriptDir/-ConfigDir: a rooted path or a '..'
# segment would otherwise write outside the project entirely.
$workflowDir = Resolve-ContainedProjectDirectory -Value $WorkflowDir -ParameterName 'WorkflowDir' -ProjectRoot $projectPath

if ([string]::IsNullOrWhiteSpace($Title)) {
    $Title = Split-Path -Leaf $projectPath
}

Write-Host "[SETUP] Project:  $projectPath" -ForegroundColor Cyan
Write-Host "[SETUP] Scripts:  $ScriptDir" -ForegroundColor Cyan
Write-Host "[SETUP] Config:   $ConfigDir" -ForegroundColor Cyan

# --- Docusaurus overlay -----------------------------------------------------

# -WorkflowsOnly refreshes a project's workflows without touching the
# Docusaurus overlay, preview script, homepage, or gate files it already
# has. Everything up to the workflow section is what it skips.
if (-not $WorkflowsOnly) {
    foreach ($directory in @($docsDir, $contentDir)) {
        if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
            if ($PSCmdlet.ShouldProcess($directory, 'Create directory')) {
                New-Item -ItemType Directory -Path $directory -Force | Out-Null
            }
        }
    }

    # Without these, every install shipped the template's placeholder values --
    # title: '' most importantly, which Docusaurus rejects outright with
    # '"title" is not allowed to be empty', so the installed site could not build
    # until someone hand-edited it. 'title: '''' matches both the site title and
    # the navbar title, which should agree anyway.
    #
    # url is only substituted when -SiteUrl was given: the placeholder
    # 'https://example.com' is at least a valid absolute URL, and Docusaurus
    # rejects an empty one, so writing '' would trade one broken build for
    # another.
    #
    # onBrokenLinks ('warn') and routeBasePath ('docs') are deliberately left at
    # the template's values. Both are behavioural choices rather than unfilled
    # placeholders -- flipping routeBasePath to '/' would move every page's URL
    # for projects already serving from /docs.
    $configReplacements = @{
        "title: ''"   = "title: '$(ConvertTo-JavaScriptSingleQuoted -Value $Title)'"
        "tagline: ''" = "tagline: '$(ConvertTo-JavaScriptSingleQuoted -Value $Description)'"
    }

    if (-not [string]::IsNullOrWhiteSpace($SiteUrl)) {
        $configReplacements["url: 'https://example.com'"] =
            "url: '$(ConvertTo-JavaScriptSingleQuoted -Value $SiteUrl.TrimEnd('/'))'"
    }

    Copy-TemplateFile -Name 'docusaurus.config.ts' `
        -Destination (Join-Path $docsDir 'docusaurus.config.ts') `
        -Relative 'docs/docusaurus.config.ts' `
        -Replace $configReplacements

    Copy-TemplateFile -Name 'sidebar.ts' `
        -Destination (Join-Path $docsDir 'sidebar.ts') `
        -Relative 'docs/sidebar.ts'

    Copy-TemplateFile -Name 'Dockerfile' `
        -Destination (Join-Path $docsDir 'Dockerfile') `
        -Relative 'docs/Dockerfile' `
        -Replace @{
            "ARG BASE_IMAGE=$defaultBaseImage" = "ARG BASE_IMAGE=$BaseImage"
        }

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
            "[string]`$BaseImage = '$defaultBaseImage'" = "[string]`$BaseImage = '$BaseImage'"
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
        # Collapsed once and reused for both the front matter title and the
        # heading, so a -Title containing a newline shows the same value in each
        # place instead of silently differing between them.
        $safeTitle = ($Title -replace '\r\n?|\n', ' ').Trim()
        Set-ProjectFile `
            -Destination $indexPath `
            -Content "---`ntitle: $(ConvertTo-YamlSingleQuotedScalar -Value $Title)`nsidebar_position: 1`n---`n`n# $safeTitle`n" `
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
            $rules = Remove-MarkedBlock -Content $rules `
                -StartMarker '    # --- GeneratedFiles:start ---' `
                -EndMarker '    # --- GeneratedFiles:end ---' `
                -FileLabel 'DocumentationRules.psd1'
        }

        Set-ProjectFile `
            -Destination (Join-Path $configTarget 'DocumentationRules.psd1') `
            -Content $rules `
            -Relative "$ConfigDir/DocumentationRules.psd1"
    }
}

# --- Workflows --------------------------------------------------------------

if (-not $SkipWorkflow) {
    # docs-ci.yml invokes the gate at a fixed path, ./build/Test-Documentation.ps1
    # etc., unlike docs.ps1 and DocumentationRules.psd1 which are rewritten for
    # -ScriptDir/-ConfigDir. A non-default -ScriptDir or -ConfigDir therefore
    # requires -SkipWorkflow and hand-adjusting the installed workflow, same as
    # today; this is not a new limitation, only carried over from the file split.
    $docsCiContent = Get-Content -LiteralPath (Join-Path $templateDir 'docs-ci.yml') -Raw
    $docsCiContent = $docsCiContent.Replace("image: $defaultBaseImage", "image: $BaseImage")

    if ($SkipGate) {
        $docsCiContent = Remove-MarkedBlock -Content $docsCiContent `
            -StartMarker '    # --- DocumentationGate:start ---' `
            -EndMarker '    # --- DocumentationGate:end ---' `
            -FileLabel 'docs-ci.yml'
    }

    Set-ProjectFile -Destination (Join-Path $workflowDir 'docs-ci.yml') `
        -Content $docsCiContent `
        -Relative '.github/workflows/docs-ci.yml'

    Copy-TemplateFile -Name 'docs-deploy.yml' `
        -Destination (Join-Path $workflowDir 'docs-deploy.yml') `
        -Relative '.github/workflows/docs-deploy.yml' `
        -Replace @{
            "image: $defaultBaseImage" = "image: $BaseImage"
        }

    # Runs unconditionally, not only under -Overwrite: the retired files break
    # the two installed above whether or not those were themselves replaced,
    # so a plain re-run has to clear them too.
    foreach ($retired in $retiredWorkflows) {
        Remove-RetiredFile -Destination (Join-Path $workflowDir $retired) `
            -Relative ".github/workflows/$retired"
    }
}

# --- Summary ----------------------------------------------------------------

Write-Host ''
foreach ($group in @(
        @{ Label = 'Created';  Items = $created;  Color = 'Green' }
        @{ Label = 'Replaced'; Items = $replaced; Color = 'Yellow' }
        @{ Label = 'Removed';  Items = $removed;  Color = 'Magenta' }
        @{ Label = 'Skipped';  Items = $skipped;  Color = 'DarkGray' }
    )) {
    if ($group.Items.Count -eq 0) { continue }
    Write-Host "[SETUP] $($group.Label) ($($group.Items.Count)):" -ForegroundColor $group.Color
    foreach ($item in $group.Items) { Write-Host "          $item" -ForegroundColor $group.Color }
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
