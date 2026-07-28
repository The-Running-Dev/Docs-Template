<#
.SYNOPSIS
Runs the repository Markdown link and terminology gate.

.DESCRIPTION
Validates authored Markdown that the documentation site build never sees.

Docusaurus already fails on unresolved links inside docs/, so this gate covers
the rest: root Markdown such as README.md and TODO.md, and cross-file relative
links and heading anchors everywhere.

Relative link targets must exist on disk, and a #fragment must match a heading
in the target document. External and site-absolute links are reported as out of
scope rather than fetched, so the gate never depends on network reachability.

Terminology rules enforce consistent product-name casing over prose only.
Fenced code, inline code, link targets, and bare URLs are masked first, so
commands, file paths, and URLs are never flagged.

.PARAMETER Path
One or more files or directories to scan. Defaults to the repository root.

.PARAMETER SettingsPath
Rules file to apply. Defaults to .config/DocumentationRules.psd1.

.PARAMETER TreatWarningsAsErrors
Fail the gate on any finding, including 'Warning' severity (currently
Terminology only). Without this switch, only 'Error' findings fail the gate;
warnings are printed but do not block.
#>
[CmdletBinding()]
param (
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string[]] $Path,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string] $SettingsPath,

    [Parameter()]
    [switch] $TreatWarningsAsErrors
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

function Find-DocumentationRepositoryRoot {
    <#
    .SYNOPSIS
    Walks upward from a starting path to the nearest directory containing
    '.git', which may be a directory (a normal clone) or a file (a submodule
    or worktree). Not '..' from the script: this script can be installed at
    any depth via -ScriptDir, so the root cannot be assumed to be one level up.
    #>
    param (
        [Parameter(Mandatory)]
        [string] $StartPath
    )

    $current = [IO.Path]::GetFullPath($StartPath)
    while ($true) {
        if (Test-Path -LiteralPath (Join-Path $current '.git')) {
            return $current
        }

        $parent = Split-Path -Parent $current
        if ([string]::IsNullOrEmpty($parent) -or $parent -eq $current) {
            throw [System.IO.DirectoryNotFoundException]::new(
                "Could not locate the repository root above '$StartPath': " +
                "no '.git' was found in any parent directory."
            )
        }
        $current = $parent
    }
}

# Normally this script lives inside the project it checks, so its own location
# finds the root. It can also run from outside one -- the published image exposes
# it as Invoke-DocsTest from /PSModule/Scripts, where no '.git' exists above it --
# so fall back to the working directory, which is the mounted project. The script
# location is tried first so a consumer's installed copy keeps resolving to its
# own repository even when invoked from elsewhere.
$repositoryRoot = $null
foreach ($start in @($PSScriptRoot, (Get-Location).Path)) {
    if ([string]::IsNullOrWhiteSpace($start)) { continue }
    try {
        $repositoryRoot = Find-DocumentationRepositoryRoot -StartPath $start
        break
    }
    catch [System.IO.DirectoryNotFoundException] {
        continue
    }
}

if (-not $repositoryRoot) {
    throw [System.IO.DirectoryNotFoundException]::new(
        "Could not locate the repository root from '$PSScriptRoot' or " +
        "'$((Get-Location).Path)': no '.git' was found in any parent directory."
    )
}

if (-not $PSBoundParameters.ContainsKey('SettingsPath')) {
    $SettingsPath = Join-Path $repositoryRoot '.config' 'DocumentationRules.psd1'
}

if (-not (Test-Path -LiteralPath $SettingsPath -PathType Leaf)) {
    throw [System.IO.FileNotFoundException]::new(
        "Documentation rules file not found: '$SettingsPath'."
    )
}

$settings = Import-PowerShellDataFile -LiteralPath $SettingsPath

if (-not $PSBoundParameters.ContainsKey('Path')) {
    $Path = @($repositoryRoot)
}

function Get-RelativeDocumentationPath {
    param (
        [Parameter(Mandatory)]
        [string] $FullPath,

        [Parameter(Mandatory)]
        [string] $Root
    )

    return [IO.Path]::GetRelativePath($Root, $FullPath).Replace('\', '/')
}

function Test-ExcludedDocumentationPath {
    param (
        [Parameter(Mandatory)]
        [string] $RelativePath,

        [Parameter(Mandatory)]
        [hashtable] $Settings
    )

    $segments = $RelativePath.Split('/')
    foreach ($segment in $Settings.ExcludedSegments) {
        if ($segments -contains $segment) {
            return $true
        }
    }

    foreach ($excluded in $Settings.ExcludedFiles) {
        if ($RelativePath -eq $excluded -or $RelativePath.StartsWith("$excluded/")) {
            return $true
        }
    }

    return $false
}

function Get-DocumentationFile {
    param (
        [Parameter(Mandatory)]
        [string[]] $SearchPath,

        [Parameter(Mandatory)]
        [string] $Root,

        [Parameter(Mandatory)]
        [hashtable] $Settings
    )

    $files = foreach ($item in $SearchPath) {
        $resolved = [IO.Path]::GetFullPath(
            $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($item)
        )

        if (Test-Path -LiteralPath $resolved -PathType Leaf) {
            Get-Item -LiteralPath $resolved
        }
        elseif (Test-Path -LiteralPath $resolved -PathType Container) {
            Get-ChildItem -LiteralPath $resolved -Filter '*.md' -Recurse -File
        }
        else {
            throw [System.IO.FileNotFoundException]::new(
                "Documentation path not found: '$resolved'."
            )
        }
    }

    # Comma keeps a single match an array instead of unrolling it to a scalar.
    return , @(
        $files |
            Where-Object { $_.Extension -eq '.md' } |
            Where-Object {
                -not (Test-ExcludedDocumentationPath `
                        -RelativePath (Get-RelativeDocumentationPath -FullPath $_.FullName -Root $Root) `
                        -Settings $Settings)
            } |
            Sort-Object FullName -Unique
    )
}

function Get-MaskedDocumentationLine {
    <#
    .SYNOPSIS
    Blanks code so rules apply to prose only, preserving line and column numbers.
    #>
    param (
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]] $Line,

        [Parameter()]
        [switch] $MaskLinkTarget
    )

    $masked = [string[]]::new($Line.Count)
    $fenceMarker = $null

    for ($index = 0; $index -lt $Line.Count; $index++) {
        $current = $Line[$index]
        $fenceMatch = [regex]::Match($current, '^\s{0,3}(`{3,}|~{3,})')

        if ($fenceMarker) {
            # Inside a fence: blank everything, and close on a matching marker.
            $masked[$index] = ' ' * $current.Length
            if ($fenceMatch.Success -and $fenceMatch.Groups[1].Value[0] -eq $fenceMarker[0] -and
                $fenceMatch.Groups[1].Value.Length -ge $fenceMarker.Length) {
                $fenceMarker = $null
            }
            continue
        }

        if ($fenceMatch.Success) {
            $fenceMarker = $fenceMatch.Groups[1].Value
            $masked[$index] = ' ' * $current.Length
            continue
        }

        # Inline code spans, longest runs first so ``a`b`` is handled correctly.
        $value = [regex]::Replace($current, '(`+)(?:.*?)\1', { ' ' * $args[0].Length })

        if ($MaskLinkTarget) {
            # Link and image targets plus bare URLs are addresses, not prose.
            $value = [regex]::Replace($value, '\]\([^)]*\)', { ' ' * $args[0].Length })
            $value = [regex]::Replace($value, '^\s{0,3}\[[^\]]+\]:\s*\S+', { ' ' * $args[0].Length })
            $value = [regex]::Replace($value, '<?https?://\S+>?', { ' ' * $args[0].Length })
        }

        $masked[$index] = $value
    }

    return , $masked
}

function ConvertTo-HeadingSlug {
    param (
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text
    )

    $value = $Text
    # Reduce inline markup to the text a reader sees before slugifying.
    $value = [regex]::Replace($value, '!?\[([^\]]*)\]\([^)]*\)', '$1')
    $value = [regex]::Replace($value, '[`*_~]', '')
    $value = $value.Trim().ToLowerInvariant()
    $value = [regex]::Replace($value, '[^a-z0-9 \-]', '')
    # One hyphen per space, not one per run of whitespace. GitHub strips the
    # punctuation and hyphenates each remaining space, so '## Phase 1 — Fixes'
    # anchors as '#phase-1--fixes' with the doubled hyphen the removed em dash
    # leaves behind. Collapsing here produced '#phase-1-fixes', so a file whose
    # anchors worked on GitHub failed this gate and vice versa -- and the same
    # files are read in both places.
    $value = [regex]::Replace($value, '\s', '-')

    return $value.Trim('-')
}

function Get-DocumentationAnchor {
    param (
        [Parameter(Mandatory)]
        [string] $FullPath
    )

    $lines = @(Get-Content -LiteralPath $FullPath)
    $masked = Get-MaskedDocumentationLine -Line $lines
    $anchors = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    $counts = @{}

    foreach ($line in $masked) {
        $match = [regex]::Match($line, '^\s{0,3}#{1,6}\s+(.+?)\s*$')
        if (-not $match.Success) {
            continue
        }

        $heading = $match.Groups[1].Value

        # Docusaurus honors an explicit {#custom-id} over the generated slug.
        $explicit = [regex]::Match($heading, '\{#([^}]+)\}\s*$')
        if ($explicit.Success) {
            $null = $anchors.Add($explicit.Groups[1].Value)
            continue
        }

        $slug = ConvertTo-HeadingSlug -Text $heading
        if ([string]::IsNullOrWhiteSpace($slug)) {
            continue
        }

        # Repeated headings get -1, -2 suffixes, matching Docusaurus and GitHub.
        if ($counts.ContainsKey($slug)) {
            $counts[$slug]++
            $null = $anchors.Add("$slug-$($counts[$slug])")
        }
        else {
            $counts[$slug] = 0
            $null = $anchors.Add($slug)
        }
    }

    return , $anchors
}

$anchorCache = @{}

function Get-CachedDocumentationAnchor {
    param (
        [Parameter(Mandatory)]
        [string] $FullPath,

        [Parameter(Mandatory)]
        [hashtable] $Cache
    )

    if (-not $Cache.ContainsKey($FullPath)) {
        $Cache[$FullPath] = Get-DocumentationAnchor -FullPath $FullPath
    }

    return , $Cache[$FullPath]
}

function New-DocumentationFinding {
    param (
        [Parameter(Mandatory)]
        [string] $RelativePath,

        [Parameter(Mandatory)]
        [int] $Line,

        [Parameter(Mandatory)]
        [int] $Column,

        [Parameter(Mandatory)]
        [string] $Severity,

        [Parameter(Mandatory)]
        [string] $Rule,

        [Parameter(Mandatory)]
        [string] $Message
    )

    return [pscustomobject]@{
        RelativePath = $RelativePath
        Line = $Line
        Column = $Column
        Severity = $Severity
        Rule = $Rule
        Message = $Message
    }
}

function Test-DocumentationLink {
    param (
        [Parameter(Mandatory)]
        [System.IO.FileInfo] $File,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]] $MaskedLine,

        [Parameter(Mandatory)]
        [string] $Root,

        [Parameter(Mandatory)]
        [hashtable] $Cache
    )

    $relativePath = Get-RelativeDocumentationPath -FullPath $File.FullName -Root $Root
    $directory = $File.DirectoryName

    for ($index = 0; $index -lt $MaskedLine.Count; $index++) {
        $lineNumber = $index + 1
        $targets = @()

        # Two destination forms, because Markdown has two. An angle-bracket
        # destination (group 1) is the only way to write a target containing a
        # space, and a bare destination (group 2) may contain balanced
        # parentheses. A single [^)\s]+ class covers neither: it cannot match
        # across a space at all, so '<./some file.md>' was invisible to this
        # check rather than reported, and it stops at the first ')', so
        # './foo(bar).md' was captured as './foo(bar' and reported broken when
        # it was not. Exactly one group participates in any match.
        foreach ($match in [regex]::Matches(
                $MaskedLine[$index],
                '!?\[[^\]]*\]\(\s*(?:<([^<>]*)>|((?:[^()\s]|\([^()]*\))+))(?:\s+"[^"]*")?\s*\)')) {
            $group = if ($match.Groups[1].Success) { $match.Groups[1] } else { $match.Groups[2] }
            $targets += [pscustomobject]@{
                Value = $group.Value
                Column = $group.Index + 1
            }
        }

        foreach ($match in [regex]::Matches(
                $MaskedLine[$index],
                '^\s{0,3}\[[^\]]+\]:\s*(\S+)')) {
            $targets += [pscustomobject]@{
                Value = $match.Groups[1].Value
                Column = $match.Groups[1].Index + 1
            }
        }

        foreach ($target in $targets) {
            $value = $target.Value.Trim('<', '>')

            # Addresses this gate deliberately does not resolve. Site-absolute
            # routes are checked by the Docusaurus build's own broken-link pass.
            if ($value -match '^(https?|mailto|ftp):' -or $value.StartsWith('/')) {
                continue
            }

            $fragment = ''
            $filePart = $value
            $hashIndex = $value.IndexOf('#')
            if ($hashIndex -ge 0) {
                $fragment = $value.Substring($hashIndex + 1)
                $filePart = $value.Substring(0, $hashIndex)
            }

            if ([string]::IsNullOrEmpty($filePart)) {
                # Same-document anchor.
                $anchors = Get-CachedDocumentationAnchor -FullPath $File.FullName -Cache $Cache
                if ($fragment -and -not $anchors.Contains($fragment)) {
                    New-DocumentationFinding `
                        -RelativePath $relativePath `
                        -Line $lineNumber `
                        -Column $target.Column `
                        -Severity 'Error' `
                        -Rule 'MarkdownAnchor' `
                        -Message "No heading in this document produces the anchor '#$fragment'."
                }
                continue
            }

            $decoded = [uri]::UnescapeDataString($filePart)
            $resolved = [IO.Path]::GetFullPath((Join-Path $directory $decoded))

            if (-not (Test-Path -LiteralPath $resolved)) {
                New-DocumentationFinding `
                    -RelativePath $relativePath `
                    -Line $lineNumber `
                    -Column $target.Column `
                    -Severity 'Error' `
                    -Rule 'MarkdownLink' `
                    -Message "Link target '$filePart' does not exist."
                continue
            }

            if ($fragment -and $resolved.EndsWith('.md', [StringComparison]::OrdinalIgnoreCase)) {
                $anchors = Get-CachedDocumentationAnchor -FullPath $resolved -Cache $Cache
                if (-not $anchors.Contains($fragment)) {
                    New-DocumentationFinding `
                        -RelativePath $relativePath `
                        -Line $lineNumber `
                        -Column $target.Column `
                        -Severity 'Error' `
                        -Rule 'MarkdownAnchor' `
                        -Message "Link target '$filePart' has no heading producing the anchor '#$fragment'."
                }
            }
        }
    }
}

function Test-DocumentationTerminology {
    param (
        [Parameter(Mandatory)]
        [System.IO.FileInfo] $File,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]] $MaskedLine,

        [Parameter(Mandatory)]
        [string] $Root,

        [Parameter(Mandatory)]
        [hashtable] $Settings
    )

    $relativePath = Get-RelativeDocumentationPath -FullPath $File.FullName -Root $Root

    for ($index = 0; $index -lt $MaskedLine.Count; $index++) {
        foreach ($rule in $Settings.Terminology) {
            foreach ($variant in $rule.Variants) {
                $pattern = '(?<![\w-])' + [regex]::Escape($variant) + '(?![\w-])'
                foreach ($match in [regex]::Matches($MaskedLine[$index], $pattern)) {
                    New-DocumentationFinding `
                        -RelativePath $relativePath `
                        -Line ($index + 1) `
                        -Column ($match.Index + 1) `
                        -Severity 'Warning' `
                        -Rule 'Terminology' `
                        -Message "Use '$($rule.Required)' instead of '$variant'."
                }
            }
        }
    }
}

function Test-GeneratedDocumentationFile {
    <#
    .SYNOPSIS
    Reports a generated file whose committed copy no longer matches its source.
    #>
    param (
        [Parameter(Mandatory)]
        [hashtable] $Definition,

        [Parameter(Mandatory)]
        [string] $Root
    )

    # Repository configuration uses paths relative to the root; an absolute path
    # is honored as-is so a fixture can point somewhere else entirely.
    $resolve = {
        param([string] $Value)
        if ([IO.Path]::IsPathRooted($Value)) { $Value } else { Join-Path $Root $Value }
    }

    $generatedPath = & $resolve $Definition.Path
    $sourcePath = & $resolve $Definition.Source
    $generatorPath = & $resolve $Definition.Generator

    foreach ($required in @($generatedPath, $sourcePath, $generatorPath)) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
            New-DocumentationFinding `
                -RelativePath $Definition.Path `
                -Line 1 `
                -Column 1 `
                -Severity 'Error' `
                -Rule 'GeneratedFile' `
                -Message "Cannot check generated file: '$required' does not exist."
            return
        }
    }

    # Splatting needs a variable; an inline hashtable would be passed positionally.
    $generatorArguments = @{ $Definition.SourceParameter = $sourcePath }

    # Optional per-project values, such as the front matter title or the site
    # origin to rewrite. Kept in configuration so the generator itself stays
    # free of any one project's details.
    if ($Definition.ContainsKey('Arguments') -and $Definition.Arguments) {
        foreach ($argument in $Definition.Arguments.GetEnumerator()) {
            $generatorArguments[$argument.Key] = $argument.Value
        }
    }

    $expected = (& $generatorPath @generatorArguments) -join "`n"
    $actual = ([IO.File]::ReadAllText($generatedPath)) -replace "`r`n?", "`n"

    if ($expected.TrimEnd("`n") -ceq $actual.TrimEnd("`n")) {
        return
    }

    # Name the first differing line so the fix is obvious without a diff tool.
    $expectedLines = $expected -split "`n"
    $actualLines = $actual -split "`n"
    $limit = [Math]::Max($expectedLines.Count, $actualLines.Count)
    $firstDifference = $limit
    for ($i = 0; $i -lt $limit; $i++) {
        $e = if ($i -lt $expectedLines.Count) { $expectedLines[$i] } else { $null }
        $a = if ($i -lt $actualLines.Count) { $actualLines[$i] } else { $null }
        if ($e -cne $a) {
            $firstDifference = $i
            break
        }
    }

    New-DocumentationFinding `
        -RelativePath $Definition.Path `
        -Line ($firstDifference + 1) `
        -Column 1 `
        -Severity 'Error' `
        -Rule 'GeneratedFile' `
        -Message (
            "Generated from '$($Definition.Source)' but the committed copy differs. " +
            "Regenerate it, then commit the result."
        )
}

$documentationFiles = Get-DocumentationFile `
    -SearchPath $Path `
    -Root $repositoryRoot `
    -Settings $settings

$findings = @(
    if ($settings.Contains('GeneratedFiles')) {
        foreach ($generated in $settings.GeneratedFiles) {
            Test-GeneratedDocumentationFile -Definition $generated -Root $repositoryRoot
        }
    }

    foreach ($file in $documentationFiles) {
        $lines = @(Get-Content -LiteralPath $file.FullName)

        Test-DocumentationLink `
            -File $file `
            -MaskedLine (Get-MaskedDocumentationLine -Line $lines) `
            -Root $repositoryRoot `
            -Cache $anchorCache

        Test-DocumentationTerminology `
            -File $file `
            -MaskedLine (Get-MaskedDocumentationLine -Line $lines -MaskLinkTarget) `
            -Root $repositoryRoot `
            -Settings $settings
    }
)

if ($findings.Count -gt 0) {
    foreach ($finding in $findings | Sort-Object RelativePath, Line, Column, Rule) {
        Write-Host (
            "$($finding.RelativePath):$($finding.Line):$($finding.Column) " +
            "[$($finding.Severity)] $($finding.Rule): $($finding.Message)"
        )
    }
}

# Only 'Warning' is non-blocking. Anything else blocks, rather than matching
# 'Error' exactly -- a rule added later with a new or mistyped severity should
# fail loudly instead of being silently reported and passed over.
$warningFindings = @($findings | Where-Object Severity -eq 'Warning')
$blockingFindings = @($findings | Where-Object Severity -ne 'Warning')

if ($blockingFindings.Count -gt 0) {
    throw (
        "Documentation checks failed with $($blockingFindings.Count) error(s), " +
        "$($warningFindings.Count) warning(s)."
    )
}

if ($TreatWarningsAsErrors -and $warningFindings.Count -gt 0) {
    throw "Documentation checks failed with $($warningFindings.Count) warning(s) (-TreatWarningsAsErrors)."
}

if ($warningFindings.Count -gt 0) {
    Write-Host (
        "Documentation checks passed across $($documentationFiles.Count) Markdown file(s), " +
        "with $($warningFindings.Count) warning(s)."
    ) -ForegroundColor Yellow
}
else {
    Write-Host (
        "Documentation checks passed across $($documentationFiles.Count) Markdown file(s)."
    ) -ForegroundColor Green
}
