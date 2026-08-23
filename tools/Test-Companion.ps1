#Requires -Version 7.0
<#
.SYNOPSIS
    Validates the core/companion split in a repository's .claude/commands/ directory.

.DESCRIPTION
    Per .claude/COMPANIONS.md: every file in .claude/commands/ ships as a core the consuming
    repository never edits, optionally paired with a companion at
    .claude/commands/<name>-local.md. The core enumerates which categories the companion may
    override; COMPANIONS.md owns the category vocabulary and the never-list.

    The core's fence is a declared marked region, id "companion" (AGENTS.md, *Marked regions*):
    <!-- companion:declared:start --> ... <!-- companion:declared:end -->. The bare form means
    projected, so a core carrying it rather than the declared form is nonconforming.

    None of that is checkable by reading the core files alone, which is the whole reason this
    script exists - AGENTS.md, *Verification*: "A schema or validator change is not done until
    it has rejected something."

    The category ids are read out of .claude/COMPANIONS.md's own table rather than duplicated
    here. That file is the canonical copy; a second list in this script would be the copy that
    rots, and the divergence would be invisible because both would still parse.

    What is checked, per finding rule:

      MissingBlock            A core has no <!-- companion:declared:start --> ... :end fence
      DuplicateBlock          A core has more than one
      WrongCompanionPath      The fence names a path other than <name>-local.md
      NoCategories            A core declares an empty override list
      UnknownCategory         A core declares an id absent from COMPANIONS.md's table
      OrphanCompanion         A <name>-local.md with no <name>.md core beside it
      UnknownCompanionHeading A companion heading that is not a category id
      UndeclaredCategory      A companion overrides a category its core did not allow
      EmptyCategory           A companion heading with nothing under it

    A companion that is missing, empty, or frontmatter-only is *absent* - counted, never a
    finding. That is COMPANIONS.md's *Absence* rule, and treating any of the three as an
    override of nothing is precisely the bug this rule exists to prevent.

.PARAMETER TargetRepo
    Repository to validate. Defaults to the current directory.

.PARAMETER Quiet
    Suppress the printed report; the result object and exit code are unchanged.

.EXAMPLE
    ./tools/Test-Companion.ps1
    Validate this repository's command cores and companions.

.EXAMPLE
    ./tools/Test-Companion.ps1 -TargetRepo D:\Projects\Some.Repo
    Validate another repository's.
#>
[CmdletBinding()]
param(
    [string] $TargetRepo = (Get-Location).Path,
    [switch] $Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function New-CompanionFinding {
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][string] $Rule,
        [Parameter(Mandatory)][string] $Detail
    )
    [pscustomobject]@{ Path = $Path; Rule = $Rule; Detail = $Detail }
}

<#
    Reads the category ids out of COMPANIONS.md's table. Rows look like:
      | `vocabulary` | What this repository calls ... |
    The leading-pipe anchor is what keeps this from also matching the backticked ids used in
    the prose above and below the table.
#>
function Get-CompanionCategory {
    param([Parameter(Mandatory)][string] $CompanionsDoc)

    $text = [System.IO.File]::ReadAllText($CompanionsDoc) -replace "`r`n", "`n"
    $ids = [System.Collections.Generic.List[string]]::new()
    foreach ($m in [regex]::Matches($text, '(?m)^\|\s*`([a-z][a-z0-9-]*)`\s*\|')) {
        $id = $m.Groups[1].Value
        if (-not $ids.Contains($id)) { $ids.Add($id) }
    }
    , @($ids)
}

<#
    Strips a leading `---`-fenced frontmatter block. Returns the body only; a file with no
    frontmatter comes back unchanged.
#>
function Remove-Frontmatter {
    param([Parameter(Mandatory)][AllowEmptyString()][string] $Text)
    [regex]::Replace($Text, "(?s)\A---\n.*?\n---\n", '')
}

<#
    COMPANIONS.md, *Absence*: missing, empty and frontmatter-only are one case. Returns $true
    for all three, so a caller never has to know which it was.
#>
function Test-CompanionAbsent {
    param([Parameter(Mandatory)][string] $Path)

    if (-not (Test-Path -LiteralPath $Path)) { return $true }
    $text = [System.IO.File]::ReadAllText($Path) -replace "`r`n", "`n"
    if ([string]::IsNullOrWhiteSpace($text)) { return $true }
    return [string]::IsNullOrWhiteSpace((Remove-Frontmatter -Text $text))
}

<#
    Parses one core's fenced companion block. Returns $null when there is no fence at all;
    BlockCount lets the caller tell "one" from "more than one" without re-scanning.
#>
function Get-CoreDeclaration {
    param([Parameter(Mandatory)][string] $Path)

    $text = [System.IO.File]::ReadAllText($Path) -replace "`r`n", "`n"
    $blocks = [regex]::Matches($text, '(?s)<!-- companion:declared:start -->(.*?)<!-- companion:declared:end -->')
    if ($blocks.Count -eq 0) { return $null }

    $body = $blocks[0].Groups[1].Value

    $pathMatch = [regex]::Match($body, '`(\.claude/commands/[A-Za-z0-9._-]+\.md)`')
    $declaredPath = if ($pathMatch.Success) { $pathMatch.Groups[1].Value } else { '' }

    $categories = [System.Collections.Generic.List[string]]::new()
    $listMatch = [regex]::Match($body, '(?s)It may override:(.*?)\.\s')
    if ($listMatch.Success) {
        foreach ($m in [regex]::Matches($listMatch.Groups[1].Value, '`([a-z][a-z0-9-]*)`')) {
            $id = $m.Groups[1].Value
            if (-not $categories.Contains($id)) { $categories.Add($id) }
        }
    }

    [pscustomobject]@{
        BlockCount   = $blocks.Count
        CompanionPath = $declaredPath
        Categories   = @($categories)
    }
}

<#
    Returns one row per `##` heading in a companion, with whether anything but whitespace sits
    under it. An empty heading is an override that asserts nothing, which COMPANIONS.md keeps
    distinct from having no companion at all.
#>
function Get-CompanionHeading {
    param([Parameter(Mandatory)][string] $Path)

    $body = Remove-Frontmatter -Text ([System.IO.File]::ReadAllText($Path) -replace "`r`n", "`n")
    # Not $matches - that is an automatic variable, and clobbering it here would silently
    # corrupt any -match result the caller was still holding.
    $headings = [regex]::Matches($body, '(?m)^##[ \t]+(.+?)[ \t]*$')
    $rows = [System.Collections.Generic.List[object]]::new()

    for ($i = 0; $i -lt $headings.Count; $i++) {
        $start = $headings[$i].Index + $headings[$i].Length
        $end = if ($i + 1 -lt $headings.Count) { $headings[$i + 1].Index } else { $body.Length }
        $rows.Add([pscustomobject]@{
                Name    = $headings[$i].Groups[1].Value.Trim('`', ' ')
                HasBody = -not [string]::IsNullOrWhiteSpace($body.Substring($start, $end - $start))
            })
    }
    , @($rows)
}

function Invoke-CompanionCheck {
    param([Parameter(Mandatory)][string] $TargetRepo)

    $commandsDir = Join-Path $TargetRepo '.claude/commands'
    $companionsDoc = Join-Path $TargetRepo '.claude/COMPANIONS.md'

    if (-not (Test-Path -LiteralPath $commandsDir)) {
        return [pscustomobject]@{
            State = 'NotEvaluated'; Findings = @(); CoreCount = 0; CompanionCount = 0; AbsentCount = 0
            Detail = "'$TargetRepo' has no .claude/commands/ directory."
        }
    }
    if (-not (Test-Path -LiteralPath $companionsDoc)) {
        return [pscustomobject]@{
            State = 'NotEvaluated'; Findings = @(); CoreCount = 0; CompanionCount = 0; AbsentCount = 0
            Detail = "'$TargetRepo' has no .claude/COMPANIONS.md - the category vocabulary is read from it, so there is nothing to validate against."
        }
    }

    $validCategories = Get-CompanionCategory -CompanionsDoc $companionsDoc
    if ($validCategories.Count -eq 0) {
        return [pscustomobject]@{
            State = 'NotEvaluated'; Findings = @(); CoreCount = 0; CompanionCount = 0; AbsentCount = 0
            Detail = "No category ids found in '$companionsDoc' - its table is missing or its shape changed."
        }
    }

    $allFiles = @(Get-ChildItem -LiteralPath $commandsDir -Filter '*.md' -File | Sort-Object Name)
    $cores = @($allFiles | Where-Object { [System.IO.Path]::GetFileNameWithoutExtension($_.Name) -notlike '*-local' })
    $companions = @($allFiles | Where-Object { [System.IO.Path]::GetFileNameWithoutExtension($_.Name) -like '*-local' })

    $findings = [System.Collections.Generic.List[object]]::new()
    $declarations = @{}
    $absentCount = 0

    foreach ($core in $cores) {
        $name = [System.IO.Path]::GetFileNameWithoutExtension($core.Name)
        $rel = ".claude/commands/$($core.Name)"
        $decl = Get-CoreDeclaration -Path $core.FullName

        if ($null -eq $decl) {
            $findings.Add((New-CompanionFinding $rel 'MissingBlock' 'No <!-- companion:declared:start --> block. Every core must declare what its companion may override, even when the answer is a short list.'))
            continue
        }
        $declarations[$name] = $decl.Categories

        if ($decl.BlockCount -gt 1) {
            $findings.Add((New-CompanionFinding $rel 'DuplicateBlock' "$($decl.BlockCount) companion blocks; exactly one is allowed."))
        }
        $expectedPath = ".claude/commands/$name-local.md"
        if ($decl.CompanionPath -ne $expectedPath) {
            $findings.Add((New-CompanionFinding $rel 'WrongCompanionPath' "Block names '$($decl.CompanionPath)'; expected '$expectedPath'."))
        }
        if ($decl.Categories.Count -eq 0) {
            $findings.Add((New-CompanionFinding $rel 'NoCategories' 'Declares no overridable categories. A core that allows nothing needs no companion mechanism - say so by removing the block, not by leaving the list empty.'))
        }
        foreach ($cat in $decl.Categories) {
            if ($validCategories -notcontains $cat) {
                $findings.Add((New-CompanionFinding $rel 'UnknownCategory' "'$cat' is not a category in .claude/COMPANIONS.md."))
            }
        }

        if (Test-CompanionAbsent -Path (Join-Path $commandsDir "$name-local.md")) { $absentCount++ }
    }

    foreach ($companion in $companions) {
        $rel = ".claude/commands/$($companion.Name)"
        $coreName = [System.IO.Path]::GetFileNameWithoutExtension($companion.Name) -replace '-local$', ''

        if (-not (Test-Path -LiteralPath (Join-Path $commandsDir "$coreName.md"))) {
            $findings.Add((New-CompanionFinding $rel 'OrphanCompanion' "No core at .claude/commands/$coreName.md. A companion overrides a core; on its own it overrides nothing and will never be read."))
            continue
        }
        if (Test-CompanionAbsent -Path $companion.FullName) { continue }

        $declared = if ($declarations.ContainsKey($coreName)) { $declarations[$coreName] } else { @() }

        foreach ($heading in (Get-CompanionHeading -Path $companion.FullName)) {
            if ($validCategories -notcontains $heading.Name) {
                $findings.Add((New-CompanionFinding $rel 'UnknownCompanionHeading' "'## $($heading.Name)' is not a category in .claude/COMPANIONS.md."))
                continue
            }
            if ($declared -notcontains $heading.Name) {
                $findings.Add((New-CompanionFinding $rel 'UndeclaredCategory' "'$($heading.Name)' is a valid category, but .claude/commands/$coreName.md does not allow it to be overridden."))
            }
            if (-not $heading.HasBody) {
                $findings.Add((New-CompanionFinding $rel 'EmptyCategory' "'## $($heading.Name)' has nothing under it. An empty category still reads as an override; delete the heading instead."))
            }
        }
    }

    [pscustomobject]@{
        State          = if ($findings.Count -gt 0) { 'Invalid' } else { 'Valid' }
        Findings       = @($findings)
        CoreCount      = $cores.Count
        CompanionCount = $companions.Count
        AbsentCount    = $absentCount
        Detail         = ''
    }
}

function Get-CompanionExitCode {
    param([string] $State)
    switch ($State) {
        'Valid'        { 0 }
        'Invalid'      { 1 }
        'NotEvaluated' { 2 }
        default        { throw "Unknown companion state: $State" }
    }
}

function Write-CompanionReport {
    param([Parameter(Mandatory)][object] $Result)

    switch ($Result.State) {
        'Valid' {
            Write-Host "Companion split OK - $($Result.CoreCount) core(s) checked, $($Result.CompanionCount) companion file(s) present, $($Result.AbsentCount) core(s) with no companion."
        }
        'Invalid' {
            Write-Host "Companion split VIOLATED - $($Result.Findings.Count) finding(s) across $($Result.CoreCount) core(s) and $($Result.CompanionCount) companion file(s):"
            foreach ($f in $Result.Findings) { Write-Host "  [$($f.Rule)] $($f.Path) - $($f.Detail)" }
        }
        'NotEvaluated' {
            Write-Host "Could not evaluate: $($Result.Detail)"
        }
    }
}

# Guarded so the tests can dot-source this instead - same structure as Test-WriteSurface.ps1
# and Test-DesignDrift.ps1, and for the same reason.
if ($MyInvocation.InvocationName -ne '.') {
    $result = Invoke-CompanionCheck -TargetRepo $TargetRepo
    if (-not $Quiet) { Write-CompanionReport -Result $result }
    $result
    exit (Get-CompanionExitCode -State $result.State)
}
