<#
.SYNOPSIS
    Sets a project up with the full documentation system in one command.

.DESCRIPTION
    Installs everything a project needs to author, preview, check, and publish
    documentation from this template:

      README.md                      Created from -Title/-Description if the
                                      project does not already have one
      <docs dir>/                    Docusaurus overlay copied over /template.
                                      'docs/' unless -DocsDirectory says
                                      otherwise.
        docusaurus.config.ts         Site configuration
        sidebar.ts                   Sidebar configuration
        Dockerfile, .dockerignore    Local preview only
        docs/index.md                Docs index (-RouteBasePath '/') or a
                                      landing page (any other value)
        src/pages/index.md           Site root, generated from the README --
                                      only when -RouteBasePath is not '/',
                                      where the docs index above is already
                                      the root
      docs.ps1                       Local preview entry point
      build/                         Homepage generator and documentation gate
      .config/                       Gate rules
      .github/workflows/             docs-ci.yml (gate + build), docs-deploy.yml

    Idempotent. Without -Overwrite an existing file is left alone and reported
    as skipped, which matters because the workflows are kept byte-identical to
    this template so the command can be re-run to pick up upstream fixes. The
    same applies to a project upgrading from before the README/site-root split
    above: re-run with -Overwrite once to pick it up, the same as any other
    upstream fix.

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

.PARAMETER DocsDirectory
    Where the Docusaurus overlay is installed, relative to the project.
    Defaults to 'docs'. Everything docs-build.ps1 copies onto /template lives
    under here: docusaurus.config.ts, sidebar.ts, the preview Dockerfile, and
    the authored docs/ and src/pages/ subdirectories -- renaming it does not
    change what is inside, only where the whole overlay sits in the project.

    A single directory name, not a path: no whitespace, quotes, or path
    separators. It is written into generated PowerShell, PSD1, and YAML
    literals, and a nested value could not be rediscovered by a later run
    that omits this parameter.

    An existing installation is detected, not merely trusted: if the project
    already has a directory this installer owns (found by the pair of files
    only it writes together, docusaurus.config.ts and sidebar.ts), a re-run
    that omits -DocsDirectory adopts that directory rather than reverting to
    'docs', the same way an existing -RouteBasePath is preserved. Passing
    -DocsDirectory that names a *different* directory than the one already
    installed is refused before anything is written -- this installer will not
    run two overlays or silently move one. Rename the directory yourself
    (`git mv <old> <new>`) and re-run.

.PARAMETER Title
    Homepage front matter title. Defaults to the project directory name.

.PARAMETER Description
    Homepage front matter description.

.PARAMETER SiteUrl
    Published site origin, with a trailing slash, rewritten to '/' in the
    generated homepage. Give this when the README links to the published site
    using absolute URLs, which is what makes one README work both on the code
    host and as the site homepage.

    Rewritten to '/' and not to -RouteBasePath: an absolute link resolves
    against the site root, so a link already pointing into the docs would
    otherwise be prefixed twice.

.PARAMETER ScriptDir
    Where PowerShell tooling is installed, relative to the project. Defaults to
    'build'. Not every project has one, so it is a parameter rather than a
    convention.

.PARAMETER ConfigDir
    Where the gate rules are installed, relative to the project. Defaults to
    '.config'.

.PARAMETER RouteBasePath
    Where documentation is served, written to routeBasePath in the installed
    docusaurus.config.ts. Defaults to '/', which serves the docs at the site
    root.

    That default matters for more than tidiness. The theme's 404 page and the
    docs navbar both link to '/'; with docs under '/docs' and nothing at the
    root, Docusaurus used to report two broken links the project never wrote --
    benign under the shipped onBrokenLinks 'warn', a failed build for anyone
    who raises it to 'throw'. With '/', the generated homepage IS the site
    root, so both resolve without anything else needed.

    Any other value is handled too, not merely avoided: the generated homepage
    is written to docs/src/pages/index.md instead, so it still becomes the
    site root, and docs/docs/index.md becomes a minimal landing page rather
    than a second copy of the same content.

    An existing docusaurus.config.ts is never silently re-pointed: under
    -Overwrite the value already in the file is preserved unless this parameter
    is passed explicitly, so a re-run to pick up upstream fixes cannot move a
    project's URLs.

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
    [Parameter()][ValidateNotNullOrEmpty()][string]$DocsDirectory = 'docs',
    [Parameter()][string]$Title,
    [Parameter()][string]$Description = '',
    [Parameter()][string]$SiteUrl = '',
    [Parameter()][string]$ScriptDir = 'build',
    [Parameter()][string]$ConfigDir = '.config',
    [Parameter()][string]$BaseImage = 'ghcr.io/the-running-dev/docs-template:latest',
    [Parameter()][ValidateNotNullOrEmpty()][string]$RouteBasePath = '/',
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
    <#
    .SYNOPSIS
    Copies one template asset into the project, substituting placeholders.

    -Replace matches literal text, applied with String.Replace. -RegexReplace
    matches a pattern, applied with a MatchEvaluator delegate rather than a
    replacement-pattern string, so a replacement value containing '$' is never
    misread as a capture-group reference.

    Every key in both is expected to match at least once, and a key that
    matches nothing throws rather than silently leaving the placeholder in
    place. The template file and the caller's substitution list are two files
    that can drift apart without either one's diff showing it: changing one
    without the other would otherwise leave a substitution silently inert
    while every install still reported success.
    #>
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Destination,
        [Parameter(Mandatory)][string]$Relative,
        [Parameter()][hashtable]$Replace = @{},
        [Parameter()][hashtable]$RegexReplace = @{}
    )

    $source = Join-Path $templateDir $Name
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw "Template asset '$Name' not found at '$source'."
    }

    $content = Get-Content -LiteralPath $source -Raw

    foreach ($token in $Replace.GetEnumerator()) {
        if (-not $content.Contains($token.Key)) {
            throw (
                "Template asset '$Name': replacement key '$($token.Key)' matched " +
                'nothing. The template has likely changed; update the caller.'
            )
        }
        $content = $content.Replace($token.Key, $token.Value)
    }

    foreach ($token in $RegexReplace.GetEnumerator()) {
        $pattern = $token.Key
        $value = $token.Value
        $regex = [regex]::new($pattern)

        if ($regex.Matches($content).Count -eq 0) {
            throw (
                "Template asset '$Name': regex replacement pattern '$pattern' matched " +
                'nothing. The template has likely changed; update the caller.'
            )
        }

        $evaluator = [System.Text.RegularExpressions.MatchEvaluator] { param($match) $value }
        $content = $regex.Replace($content, $evaluator)
    }

    Set-ProjectFile -Destination $Destination -Content $content -Relative $Relative
}

function Set-TemplateToken {
    <#
    .SYNOPSIS
    Replaces one literal token in already-loaded template content, throwing if
    the token is not present.

    DocumentationRules.psd1 and docs-ci.yml are templated by direct string
    manipulation rather than through Copy-TemplateFile -- docs-ci.yml also needs
    Remove-MarkedBlock applied in between substitutions, and the rules file is
    built up token by token rather than copied by name -- so neither got
    Copy-TemplateFile's throw-on-no-match guard for free. This gives them the
    same guarantee: a key that matches nothing is always a bug, the template has
    drifted from the caller, and it should fail loudly rather than silently
    leave the placeholder in place.
    #>
    param(
        [Parameter(Mandatory)][string]$Content,
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Value,
        [Parameter(Mandatory)][string]$FileLabel
    )

    if (-not $Content.Contains($Key)) {
        throw (
            "Template asset '$FileLabel': replacement key '$Key' matched " +
            'nothing. The template has likely changed; update the caller.'
        )
    }

    return $Content.Replace($Key, $Value)
}

function ConvertTo-YamlSingleQuotedScalar {
    <#
    .SYNOPSIS
    Serializes a string as a single-line, single-quoted YAML scalar.

    Used for the docs/docs/index.md landing page's front matter, written when
    routeBasePath is not '/'. A raw, unescaped -Title could otherwise contain a
    newline and an embedded '---', closing the front matter block early and
    injecting fabricated keys after it -- confirmed against
    ConvertTo-DocumentationHomepage.ps1's original unescaped interpolation
    before this fix. Collapsing newlines and doubling embedded single quotes
    closes both paths off entirely.
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

    # Each marker is located and validated in turn rather than by two bare
    # IndexOf calls. Finding both and trusting them is not enough: with the end
    # marker above the start marker the slice arithmetic below silently
    # duplicates the lines between them and leaves both markers in place,
    # producing malformed output and no error -- confirmed by reproduction.
    # A template that has been edited into that state should fail loudly, since
    # the alternative is installing a corrupted file into someone's project.
    $startLine = [Array]::IndexOf($lines, $StartMarker)
    if ($startLine -lt 0) {
        throw (
            "$FileLabel template is missing the start marker " +
            "('$($StartMarker.Trim())'); cannot strip the block."
        )
    }

    if ([Array]::IndexOf($lines, $StartMarker, $startLine + 1) -ge 0) {
        throw (
            "$FileLabel template has more than one start marker " +
            "('$($StartMarker.Trim())'); which block to strip is ambiguous."
        )
    }

    # Searched from after the start marker, so an end marker that only appears
    # above it reads as missing rather than as a valid pairing.
    $endLine = [Array]::IndexOf($lines, $EndMarker, $startLine + 1)
    if ($endLine -lt 0) {
        $strayEnd = [Array]::IndexOf($lines, $EndMarker)
        if ($strayEnd -ge 0) {
            throw (
                "$FileLabel template has its end marker ('$($EndMarker.Trim())') " +
                "on line $($strayEnd + 1), above the start marker on line " +
                "$($startLine + 1); the block is malformed."
            )
        }
        throw (
            "$FileLabel template is missing the end marker " +
            "('$($EndMarker.Trim())'); cannot strip the block."
        )
    }

    if ([Array]::IndexOf($lines, $EndMarker, $endLine + 1) -ge 0) {
        throw (
            "$FileLabel template has more than one end marker " +
            "('$($EndMarker.Trim())'); which block to strip is ambiguous."
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

    -DisallowProjectRoot additionally rejects an empty/whitespace value and a
    value that resolves to -ProjectRoot itself. Without it, an empty string
    passes every check above -- Join-Path with '' returns the root unchanged,
    which is exactly what -eq $normalizedRoot allows through -- so a caller
    could silently install into the project root instead of a subdirectory.
    Opt-in rather than the default: -ScriptDir/-ConfigDir/-WorkflowDir have
    always allowed this and changing that now would be a behaviour change
    unrelated to whatever added this switch.
    #>
    param (
        [Parameter(Mandatory)]
        [string] $Value,

        [Parameter(Mandatory)]
        [string] $ParameterName,

        [Parameter(Mandatory)]
        [string] $ProjectRoot,

        [Parameter()]
        [switch] $DisallowProjectRoot
    )

    if ($DisallowProjectRoot -and [string]::IsNullOrWhiteSpace($Value)) {
        throw "-$ParameterName must not be empty."
    }

    if ([IO.Path]::IsPathRooted($Value)) {
        throw "-$ParameterName must be a path relative to the project, not rooted: '$Value'."
    }

    if (@($Value -split '[\\/]') -contains '..') {
        throw "-$ParameterName must not contain '..' segments: '$Value'."
    }

    $resolved = [IO.Path]::GetFullPath((Join-Path $ProjectRoot $Value))
    $normalizedRoot = $ProjectRoot.TrimEnd('\', '/')

    if ($DisallowProjectRoot -and $resolved -eq $normalizedRoot) {
        throw "-$ParameterName must not resolve to the project directory itself: '$Value'."
    }

    if ($resolved -ne $normalizedRoot -and
        -not $resolved.StartsWith($normalizedRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw "-$ParameterName resolves outside the project directory: '$Value' -> '$resolved'."
    }

    return $resolved
}

function Find-InstalledDocsDirectory {
    <#
    .SYNOPSIS
    Finds this installer's existing Docusaurus overlay directory among
    -ProjectDir's immediate children, if any.

    Identified by the pair of files only this installer writes together:
    docusaurus.config.ts and sidebar.ts (singular). The singular name matters
    -- this repository's own site uses the plural sidebars.ts at its root, so
    running this script against this repository's own checkout cannot
    false-positive on its own docs/.

    Only immediate children are searched: an overlay this installer owns is
    never nested more than one level under the project root, so a config file
    found deeper belongs to something else.
    #>
    param([Parameter(Mandatory)][string]$ProjectRoot)

    return @(
        Get-ChildItem -LiteralPath $ProjectRoot -Directory -ErrorAction SilentlyContinue |
            Where-Object {
                (Test-Path -LiteralPath (Join-Path $_.FullName 'docusaurus.config.ts') -PathType Leaf) -and
                (Test-Path -LiteralPath (Join-Path $_.FullName 'sidebar.ts') -PathType Leaf)
            } |
            ForEach-Object { $_.Name }
    )
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

# -DocsDirectory is written verbatim into a PSD1 single-quoted literal
# (Path/GeneratedFiles), a PowerShell single-quoted literal (docs.ps1's
# Join-Path key), and an unquoted argument on a generated `run:` line in
# docs-ci.yml/docs-deploy.yml. A quote would break the first two the same way
# an unescaped -Title once did; whitespace would split the workflow argument
# into two, since nothing there is quoted for it. Reject rather than escape:
# a directory name has no reason to need either.
if ($DocsDirectory -match '[\s''"]') {
    throw "-DocsDirectory must not contain whitespace or quotes: '$DocsDirectory'."
}

# A single segment only. Find-InstalledDocsDirectory -- the mechanism a later
# re-run relies on to rediscover this directory without -DocsDirectory being
# passed again -- looks only at -ProjectDir's immediate children, by design
# (an overlay this installer owns is never nested more than one level deep).
# A multi-segment value like 'sites/documentation' would install correctly
# once but then go undetected on the very next omitted-parameter run,
# silently creating a second, default 'docs/' overlay beside it.
if ($DocsDirectory -match '[\\/]') {
    throw (
        "-DocsDirectory must be a single directory name, not a path: '$DocsDirectory'. " +
        'A nested path cannot be rediscovered by a later run that omits this parameter.'
    )
}

$defaultBaseImage = 'ghcr.io/the-running-dev/docs-template:latest'

$projectPath = Resolve-ProjectPath -Path $ProjectDir
$scriptTarget = Resolve-ContainedProjectDirectory -Value $ScriptDir -ParameterName 'ScriptDir' -ProjectRoot $projectPath
$configTarget = Resolve-ContainedProjectDirectory -Value $ConfigDir -ParameterName 'ConfigDir' -ProjectRoot $projectPath
if ($WorkflowsOnly -and $SkipWorkflow) {
    throw '-WorkflowsOnly and -SkipWorkflow are mutually exclusive: one installs nothing but workflows, the other installs everything except them.'
}

# Same containment guard as -ScriptDir/-ConfigDir: a rooted path or a '..'
# segment would otherwise write outside the project entirely.
$workflowDir = Resolve-ContainedProjectDirectory -Value $WorkflowDir -ParameterName 'WorkflowDir' -ProjectRoot $projectPath

# An existing overlay wins unless -DocsDirectory was passed explicitly -- the
# same "existing value wins" shape -RouteBasePath uses below, so a plain
# re-run to pick up an upstream fix cannot move a project's overlay out from
# under it. -DocsDirectory naming a *different* directory than the one
# already installed is refused rather than migrated: moving authored content
# is not something this installer can verify safe without pwsh available to
# run it here -- the same reasoning that keeps a stale docs/docs/index.md
# from being auto-migrated further down.
$docsDirectoryExplicit = $PSBoundParameters.ContainsKey('DocsDirectory')

# @() at the call site, not just around later uses: PowerShell enumerates an
# array crossing a function's output stream, so a single-match result arrives
# here as a bare string and a zero-match result as $null -- either would fail
# .Count under Set-StrictMode. Find-InstalledDocsDirectory's own `return @()`
# only guarantees array *shape* inside the function; it does not survive
# unless the caller re-wraps it too.
$installedDocsDirectories = @(Find-InstalledDocsDirectory -ProjectRoot $projectPath)

if ($docsDirectoryExplicit) {
    # Case-sensitive: PowerShell's default -ne treats 'documentation' and
    # 'Documentation' as equal, which would let a case-only respelling slip
    # past this conflict check entirely. The base image builds on Linux,
    # where the two are different directories -- comparing case-sensitively
    # here matches what actually happens on disk in CI, regardless of which
    # OS the installer itself runs on.
    $conflicting = @($installedDocsDirectories | Where-Object { $_ -cne $DocsDirectory })
    if ($conflicting.Count -gt 0) {
        throw (
            "This project's documentation is already installed at " +
            "'$($conflicting -join "', '")', but -DocsDirectory '$DocsDirectory' names a different " +
            'directory. This installer will not run two overlays or silently move one -- rename it ' +
            "yourself and re-run, e.g.: git mv $($conflicting[0]) $DocsDirectory"
        )
    }
    $effectiveDocsDirectory = $DocsDirectory
}
elseif ($installedDocsDirectories.Count -eq 1) {
    $effectiveDocsDirectory = $installedDocsDirectories[0]
    if ($effectiveDocsDirectory -cne $DocsDirectory) {
        Write-Host (
            "[SETUP] Keeping this project's documentation directory '$effectiveDocsDirectory' " +
            "rather than the default '$DocsDirectory'; pass -DocsDirectory to change it."
        ) -ForegroundColor DarkGray
    }
}
elseif ($installedDocsDirectories.Count -gt 1) {
    throw (
        "Found more than one existing documentation directory ('$($installedDocsDirectories -join "', '")'); " +
        'pass -DocsDirectory to say which one this run applies to.'
    )
}
else {
    $effectiveDocsDirectory = $DocsDirectory
}

$docsDir = Resolve-ContainedProjectDirectory -Value $effectiveDocsDirectory -ParameterName 'DocsDirectory' `
    -ProjectRoot $projectPath -DisallowProjectRoot

foreach ($other in @(
        @{ Name = 'ScriptDir'; RawValue = $ScriptDir; Path = $scriptTarget }
        @{ Name = 'ConfigDir'; RawValue = $ConfigDir; Path = $configTarget }
        @{ Name = 'WorkflowDir'; RawValue = $WorkflowDir; Path = $workflowDir }
    )) {
    if ($docsDir -eq $other.Path -or
        $docsDir.StartsWith($other.Path + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or
        $other.Path.StartsWith($docsDir + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw (
            "-DocsDirectory '$effectiveDocsDirectory' and -$($other.Name) '$($other.RawValue)' " +
            'must not nest in either direction, or installing one would write into the other.'
        )
    }
}

$contentDir = Join-Path $docsDir 'docs'
$docsDirectoryRelative = ($effectiveDocsDirectory -replace '\\', '/').Trim('/')

# Not a hard failure: the gate simply never sees this directory, rather than
# the install itself being wrong. ExcludedSegments is shipped, not generated,
# so it can only be read from the template this run is about to install, not
# from anything already in the project.
$excludedSegments = @((Import-PowerShellDataFile -LiteralPath (Join-Path $templateDir 'DocumentationRules.psd1')).ExcludedSegments)
$excludedSegmentHit = @($docsDirectoryRelative -split '/') | Where-Object { $_ -in $excludedSegments } | Select-Object -First 1
if ($excludedSegmentHit) {
    Write-Warning (
        "-DocsDirectory '$effectiveDocsDirectory' contains the segment '$excludedSegmentHit', which the " +
        'shipped documentation gate rules never scan (ExcludedSegments in DocumentationRules.psd1). ' +
        'Authored content under it will not be checked unless that rule is edited after install.'
    )
}

if ([string]::IsNullOrWhiteSpace($Title)) {
    $Title = Split-Path -Leaf $projectPath
}

Write-Host "[SETUP] Project:  $projectPath" -ForegroundColor Cyan
Write-Host "[SETUP] Docs:     $docsDirectoryRelative" -ForegroundColor Cyan
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
    # onBrokenLinks ('warn') is deliberately left at the template's value: it is
    # a behavioural choice rather than an unfilled placeholder.
    #
    # routeBasePath is substituted, defaulting to '/' -- see the parameter help
    # for why the root is not merely tidier. What keeps that default safe is the
    # block below: an existing config's value wins unless -RouteBasePath was
    # passed, so re-running with -Overwrite to pick up an upstream fix cannot
    # move a project's URLs.
    $effectiveRouteBasePath = $RouteBasePath
    $existingConfig = Join-Path $docsDir 'docusaurus.config.ts'

    if (-not $PSBoundParameters.ContainsKey('RouteBasePath') -and
        (Test-Path -LiteralPath $existingConfig -PathType Leaf)) {

        $existingMatch = [regex]::Match(
            (Get-Content -LiteralPath $existingConfig -Raw),
            "routeBasePath:\s*'([^']*)'")

        # Non-empty only: an empty routeBasePath is not a value worth preserving,
        # and adopting it would surface later as a ValidateNotNullOrEmpty failure
        # inside the homepage generator rather than anything a reader could act on.
        if ($existingMatch.Success -and
            -not [string]::IsNullOrWhiteSpace($existingMatch.Groups[1].Value) -and
            $existingMatch.Groups[1].Value -ne $RouteBasePath) {
            $effectiveRouteBasePath = $existingMatch.Groups[1].Value
            Write-Host (
                "[SETUP] Keeping this project's routeBasePath '$effectiveRouteBasePath' " +
                "rather than the default '$RouteBasePath'; pass -RouteBasePath to change it."
            ) -ForegroundColor DarkGray
        }
    }

    $configReplacements = @{
        "title: ''"   = "title: '$(ConvertTo-JavaScriptSingleQuoted -Value $Title)'"
        "tagline: ''" = "tagline: '$(ConvertTo-JavaScriptSingleQuoted -Value $Description)'"
    }

    if (-not [string]::IsNullOrWhiteSpace($SiteUrl)) {
        $configReplacements["url: 'https://example.com'"] =
            "url: '$(ConvertTo-JavaScriptSingleQuoted -Value $SiteUrl.TrimEnd('/'))'"
    }

    # Regex-keyed rather than a literal "routeBasePath: '<value>'" string, so
    # the template's own default value is free to change without this
    # substitution silently going inert. The "existing config wins" block
    # above already matches routeBasePath with this same pattern, so reading
    # and writing agree on one shape rather than two that could disagree.
    $configRegexReplacements = @{
        "routeBasePath:\s*'[^']*'" =
            "routeBasePath: '$(ConvertTo-JavaScriptSingleQuoted -Value $effectiveRouteBasePath)'"
    }

    Copy-TemplateFile -Name 'docusaurus.config.ts' `
        -Destination (Join-Path $docsDir 'docusaurus.config.ts') `
        -Relative "$docsDirectoryRelative/docusaurus.config.ts" `
        -Replace $configReplacements `
        -RegexReplace $configRegexReplacements

    Copy-TemplateFile -Name 'sidebar.ts' `
        -Destination (Join-Path $docsDir 'sidebar.ts') `
        -Relative "$docsDirectoryRelative/sidebar.ts"

    Copy-TemplateFile -Name 'Dockerfile' `
        -Destination (Join-Path $docsDir 'Dockerfile') `
        -Relative "$docsDirectoryRelative/Dockerfile" `
        -Replace @{
            "ARG BASE_IMAGE=$defaultBaseImage" = "ARG BASE_IMAGE=$BaseImage"
        }

    # Stored without the leading dot so it is not hidden, and not applied to this
    # template's own build context.
    Copy-TemplateFile -Name 'dockerignore' `
        -Destination (Join-Path $docsDir '.dockerignore') `
        -Relative "$docsDirectoryRelative/.dockerignore"

    Copy-TemplateFile -Name 'docs.ps1' `
        -Destination (Join-Path $projectPath 'docs.ps1') `
        -Relative 'docs.ps1' `
        -Replace @{
            "Join-Path `$root 'docs'" = "Join-Path `$root '$docsDirectoryRelative'"
            "Join-Path `$root 'build' 'ConvertTo-DocumentationHomepage.ps1'" = "Join-Path `$root '$ScriptDir' 'ConvertTo-DocumentationHomepage.ps1'"
            "Join-Path `$root '.config' 'DocumentationRules.psd1'" = "Join-Path `$root '$ConfigDir' 'DocumentationRules.psd1'"
            "[string]`$Tag = 'project-docs'" = "[string]`$Tag = '$(ConvertTo-DockerTagSegment -Value $Title)-docs'"
            "[string]`$BaseImage = '$defaultBaseImage'" = "[string]`$BaseImage = '$BaseImage'"
            "'docs/docs/index.md'" = "'$docsDirectoryRelative/docs/index.md'"
            "'docs/src/pages/index.md'" = "'$docsDirectoryRelative/src/pages/index.md'"
        }

    # --- Homepage ---------------------------------------------------------------

    $readmePath = Join-Path $projectPath 'README.md'
    $indexPath = Join-Path $contentDir 'index.md'

    # "Only when absent" is the entire guard here: an existing README is never
    # touched, and a created one runs through exactly the same generation path
    # below as one the project already had. There is no longer a second,
    # stub-only path for a project with no README -- every project ends up
    # with a real README, and the site root renders from it.
    if (-not $NoHomepage -and -not (Test-Path -LiteralPath $readmePath -PathType Leaf)) {
        $safeReadmeTitle = ($Title -replace '\r\n?|\n', ' ').Trim()
        $readmeLines = @("# $safeReadmeTitle", '')
        if (-not [string]::IsNullOrWhiteSpace($Description)) {
            $readmeLines += @($Description, '')
        }
        if ($PSCmdlet.ShouldProcess($readmePath, 'Create')) {
            [IO.File]::WriteAllText(
                $readmePath,
                (($readmeLines -join "`n") -replace "`r`n", "`n"),
                [Text.UTF8Encoding]::new($false))
            $created.Add('README.md')
        }
    }

    $generateHomepage = -not $NoHomepage -and (Test-Path -LiteralPath $readmePath -PathType Leaf)

    # Only install the generator when something actually runs it. With -NoHomepage
    # the gate has no drift check and docs.ps1 skips regeneration, so shipping it
    # would leave a script nothing calls.
    if ($generateHomepage) {
        Copy-TemplateFile -Name 'ConvertTo-DocumentationHomepage.ps1' `
            -Destination (Join-Path $scriptTarget 'ConvertTo-DocumentationHomepage.ps1') `
            -Relative "$ScriptDir/ConvertTo-DocumentationHomepage.ps1"

        $homepageScript = Join-Path $templateDir 'ConvertTo-DocumentationHomepage.ps1'
        $content = & $homepageScript `
            -ReadmePath $readmePath `
            -Title $Title `
            -Description $Description `
            -SiteUrl $SiteUrl `
            -RouteBasePath $effectiveRouteBasePath

        if ($effectiveRouteBasePath.Trim('/') -eq '') {
            # routeBasePath '/': the docs index already IS the site root, so
            # the README renders there directly. One file, one URL.
            Set-ProjectFile -Destination $indexPath -Content $content -Relative "$docsDirectoryRelative/docs/index.md"
        }
        else {
            # Any other routeBasePath: the README becomes a real page route at
            # the site root, generated into <docs dir>/src/pages so it overlays
            # onto /template/src/pages the same way docs-build.ps1 already
            # expects a consumer-authored page to -- see its comment on
            # stripping the image's own src/pages before the overlay, "so a
            # consumer supplying their own docs/src/pages is not mistaken for
            # the leak."
            $rootPagePath = Join-Path $docsDir 'src' 'pages' 'index.md'
            Set-ProjectFile -Destination $rootPagePath -Content $content -Relative "$docsDirectoryRelative/src/pages/index.md"

            # docs/docs/index.md still resolves at /docs/ -- typed, bookmarked,
            # or linked from before this change -- and must keep resolving. Its
            # content stops being a copy of the README (that now lives at '/',
            # not twice) and becomes a minimal landing page instead.
            #
            # A project upgrading from before this change already has
            # README-derived content here; recognizing that automatically
            # would mean reconstructing byte-for-byte what a since-removed
            # code path used to produce, which cannot be verified without
            # risking a false match overwriting a hand-authored /docs/ page.
            # -Overwrite already exists for exactly this -- "re-running to
            # pick up an upstream fix" -- so migrating this file follows the
            # same one-time step as every other installed file.
            $safeLandingTitle = ($Title -replace '\r\n?|\n', ' ').Trim()
            $landingLines = @(
                '---'
                "title: $(ConvertTo-YamlSingleQuotedScalar -Value $Title)"
            )
            if (-not [string]::IsNullOrWhiteSpace($Description)) {
                $landingLines += "description: $(ConvertTo-YamlSingleQuotedScalar -Value $Description)"
            }
            $landingLines += @('sidebar_position: 1', '---', '', "# $safeLandingTitle")
            if (-not [string]::IsNullOrWhiteSpace($Description)) {
                $landingLines += @('', $Description)
            }
            $landingContent = ($landingLines -join "`n") + "`n"

            Set-ProjectFile -Destination $indexPath -Content $landingContent -Relative "$docsDirectoryRelative/docs/index.md"
        }
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
        $rules = Set-TemplateToken -Content $rules -FileLabel 'DocumentationRules.psd1' `
            -Key "Generator = 'build/ConvertTo-DocumentationHomepage.ps1'" `
            -Value "Generator = '$ScriptDir/ConvertTo-DocumentationHomepage.ps1'"
        $rules = Set-TemplateToken -Content $rules -FileLabel 'DocumentationRules.psd1' `
            -Key "Title = 'Home'" -Value "Title = '$($Title.Replace("'", "''"))'"
        $rules = Set-TemplateToken -Content $rules -FileLabel 'DocumentationRules.psd1' `
            -Key "Description = ''" -Value "Description = '$($Description.Replace("'", "''"))'"
        $rules = Set-TemplateToken -Content $rules -FileLabel 'DocumentationRules.psd1' `
            -Key "SiteUrl = ''" -Value "SiteUrl = '$($SiteUrl.Replace("'", "''"))'"
        $rules = Set-TemplateToken -Content $rules -FileLabel 'DocumentationRules.psd1' `
            -Key "RouteBasePath = '/'" -Value "RouteBasePath = '$($effectiveRouteBasePath.Replace("'", "''"))'"

        # Path follows the same routeBasePath split as the file setup-docs.ps1
        # itself just wrote: the docs index when routeBasePath is '/', the
        # site root page otherwise. Computed the same way in both places
        # rather than read back from one, so there is one rule instead of two
        # that could disagree.
        $generatedFileRelativePath = if ($effectiveRouteBasePath.Trim('/') -eq '') {
            "$docsDirectoryRelative/docs/index.md"
        }
        else {
            "$docsDirectoryRelative/src/pages/index.md"
        }
        $rules = Set-TemplateToken -Content $rules -FileLabel 'DocumentationRules.psd1' `
            -Key "Path = 'docs/docs/index.md'" -Value "Path = '$generatedFileRelativePath'"

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
    $docsCiContent = Set-TemplateToken -Content $docsCiContent -FileLabel 'docs-ci.yml' `
        -Key "image: $defaultBaseImage" -Value "image: $BaseImage"
    $docsCiContent = Set-TemplateToken -Content $docsCiContent -FileLabel 'docs-ci.yml' `
        -Key '-SourceDocs ./docs' -Value "-SourceDocs ./$docsDirectoryRelative"

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
            '-SourceDocs ./docs' = "-SourceDocs ./$docsDirectoryRelative"
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
Write-Host "  1. Author documentation under $docsDirectoryRelative/docs/" -ForegroundColor White
Write-Host '  2. Preview locally:  ./docs.ps1' -ForegroundColor White
if (-not $SkipGate) {
    Write-Host "  3. Check it:         ./$ScriptDir/Test-Documentation.ps1" -ForegroundColor White
}
if (-not $SkipWorkflow) {
    Write-Host '  4. Enable GitHub Pages for this repository, source: GitHub Actions' -ForegroundColor White
    Write-Host '  5. Make the docs checks required, or a red run will not block a merge' -ForegroundColor White
}
Write-Host ''
Write-Host '[SETUP] Note: the base image is public, so CI needs no registry credentials.' -ForegroundColor DarkGray
Write-Host '        Pointing -BaseImage at a private fork or mirror does: set REGISTRY_TOKEN.' -ForegroundColor DarkGray
