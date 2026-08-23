#Requires -Version 7.0
<#
.SYNOPSIS
    The design-state divergence checker: validator, projection checker, budget meter, freeze
    gate, and the three-list report (design/20-contract.md § tools/Test-DesignState.ps1).

.DESCRIPTION
    Reads design/state/ via Read-DesignState.ps1, then runs every class in the closed list
    design/20-contract.md § "The divergence classes" declares, and only those - a class not on
    that list does not exist here, and ClassListDisagreement is what makes a drift between the
    two documents visible rather than silent.

    Emits three lists, always all three: Findings (blocking), Reported (never blocking), and
    CouldNotEvaluate. An omitted empty list would read as an absent category rather than an
    empty one (I12's shape, one level up). Exit codes: 0 clean, 1 findings, 2 could not
    evaluate - 2 always takes precedence over 1 (I20).

    Never clean on an absent or empty state set (I19) - that is the expected shape in every
    installed target, where design/state/ does not exist by design (INSTALL.md phase 1 never
    ships the kit's own design/).

    Regenerates before comparing, by invoking the projector with -DryRun if it exists.
    tools/Update-DesignProjection.ps1 (S7) exists and is invoked this way, so ProjectionStale
    is computed on every run today. Where the projector is absent or exits non-zero, that run
    instead reports ProjectorFailed and names ProjectionStale as uncomputed rather than clean
    (S5.10): a contracted case, not a gap.

    Writes nothing, ever (I18): not design/, not a record, not an issue, not git.

.PARAMETER Path
    Repository root. Defaults to the current directory. Has no -Fix, no -Force, and resolves
    nothing - the checker only ever establishes that something disagrees.

.PARAMETER Repository
    owner/repo, for the tracker classes only (MirrorStale needs no network; WorkStateDivergence
    and PinAncestry do). Defaults to the current git remote via gh's own resolution.

.PARAMETER Quiet
    Suppresses the human-readable report only. The result object is always emitted.

.EXAMPLE
    pwsh ./tools/Test-DesignState.ps1
#>
[CmdletBinding()]
param(
    [string] $Path = (Get-Location).Path,
    [string] $Repository,
    [switch] $Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Read-DesignState.ps1's relative-path substring math assumes $Path is already absolute (a
# pre-existing defect outside this slice's Touches list, not fixed here - AGENTS.md, "You find
# a defect outside this slice. Note it, do not fix it."). Resolving here, once, keeps every
# call into it well-formed without touching that file.
$Path = (Resolve-Path -LiteralPath $Path).Path

# See Test-DesignDrift.ps1's identical assignment: `git merge-base --is-ancestor` and
# `gh`/the projector all return non-zero to mean "the answer is no", not "something broke", and
# PowerShell 7.3+ would otherwise turn that into a terminating error under -Stop.
$PSNativeCommandUseErrorActionPreference = $false

# ---------------------------------------------------------------------------------------------
# The closed class list (design/20-contract.md § "The divergence classes"). This is the
# checker's own declaration; ClassListDisagreement compares it against the contract document's
# copy, which is the one restatement in the system that cannot be checked any other way
# (design/10-design.md § Module boundaries).
# ---------------------------------------------------------------------------------------------
$script:BlockingClasses = @(
    'UnresolvedId', 'AnchorMissing', 'OwnerMismatch', 'UnrecordedArtifact', 'ProjectionStale',
    'RegionMalformed', 'IdCollision', 'DecisionAnchorAmbiguous', 'LogEntryUnrecorded',
    'EnforcementUnevidenced', 'ClosureOverBudget', 'ClassListDisagreement', 'GlobDisagreement'
)
$script:ReportedClasses = @(
    'MirrorStale', 'WorkStateDivergence', 'PinAncestry', 'SemanticDisagreement'
)
$script:CouldNotEvaluateClasses = @(
    'StateSetAbsent', 'RecordUnparseable', 'TrackerUnavailable', 'ShallowCheckout',
    'ProjectorFailed', 'ContractListUnreadable'
)

$script:ClosureBudgetBytes = 16384

function New-DesignFinding {
    <# design/20-contract.md § "What the checker emits" - the scaffolded factory, unchanged. #>
    param(
        [Parameter(Mandatory)][string] $Class,
        [Parameter(Mandatory)][string] $Subject,
        [Parameter(Mandatory)][string] $Detail,
        [Parameter(Mandatory)][bool]   $Blocking
    )
    [pscustomobject]@{
        Class    = $Class
        Subject  = $Subject
        Detail   = $Detail
        Blocking = $Blocking
    }
}

function New-CouldNotEvaluate {
    param(
        [Parameter(Mandatory)][string] $Reason,
        [string] $Detail = ''
    )
    [pscustomobject]@{ Reason = $Reason; Detail = $Detail }
}

function New-DesignStateResult {
    param(
        [object[]]        $Findings,
        [object[]]        $Reported,
        [object[]]        $CouldNotEvaluate,
        [Parameter(Mandatory)][int] $ExitCode,
        [pscustomobject]  $LargestClosure,
        [string[]]        $ReportLines,
        [int]             $DowngradedCount = 0
    )
    [pscustomobject]@{
        Findings         = @($Findings)
        Reported         = @($Reported)
        CouldNotEvaluate = @($CouldNotEvaluate)
        ExitCode         = $ExitCode
        LargestClosure   = $LargestClosure
        ReportLines      = @($ReportLines)
        DowngradedCount  = $DowngradedCount
    }
}

# ---------------------------------------------------------------------------------------------
# The reader. Dot-sourced at script scope - not inside a function, which would confine its
# functions (Read-DesignStateGraph, Get-DesignPathInfo, the New-DesignState* factories) to that
# function's own local scope - so every function below can reuse them rather than duplicating
# them (AGENTS.md, Single ownership). The guard inside Read-DesignState.ps1 means dot-sourcing
# it here never runs its own top-level invocation.
# ---------------------------------------------------------------------------------------------
$script:ReaderPath = Join-Path $PSScriptRoot 'Read-DesignState.ps1'
if (-not (Test-Path -LiteralPath $script:ReaderPath)) {
    throw "tools/Read-DesignState.ps1 not found beside tools/Test-DesignState.ps1 at $script:ReaderPath"
}
. $script:ReaderPath -Path $Path

# ---------------------------------------------------------------------------------------------
# design/20-contract.md's own class list, parsed from the document so ClassListDisagreement has
# something independent to compare $script:BlockingClasses etc. against. The "Could not
# evaluate" table's header row names its own row-type, `DesignStateFailure`, in the same
# backticked-first-column shape every real class row uses - it is excluded by name because it
# is a type name, never a class id.
# ---------------------------------------------------------------------------------------------
function Get-ContractClassIds {
    param([Parameter(Mandatory)][string] $ContractPath)

    if (-not (Test-Path -LiteralPath $ContractPath)) {
        return [pscustomobject]@{ Ids = $null; Failure = 'ContractPathMissing' }
    }

    $text = Get-Content -LiteralPath $ContractPath -Raw
    if ($null -eq $text) { $text = '' }
    $start = $text.IndexOf('### The divergence classes')
    $end = $text.IndexOf('### The freeze')
    if ($start -lt 0 -or $end -lt 0 -or $end -le $start) {
        return [pscustomobject]@{ Ids = $null; Failure = 'SectionNotFound' }
    }
    $section = $text.Substring($start, $end - $start)

    $blockingEnd = $section.IndexOf('**Reported, never blocking.**')
    $reportedEnd = $section.IndexOf('**Could not evaluate.**')
    if ($blockingEnd -lt 0 -or $reportedEnd -lt 0 -or $reportedEnd -le $blockingEnd) {
        return [pscustomobject]@{ Ids = $null; Failure = 'SubsectionNotFound' }
    }

    $blockingText = $section.Substring(0, $blockingEnd)
    $reportedText = $section.Substring($blockingEnd, $reportedEnd - $blockingEnd)
    $cneText = $section.Substring($reportedEnd)

    function Get-RowIds {
        param([string] $Chunk)
        $ids = [System.Collections.Generic.List[string]]::new()
        foreach ($line in ($Chunk -split "`n")) {
            if ($line -match '^\|\s*`([A-Za-z]+)`\s*\|') {
                $id = $Matches[1]
                if ($id -eq 'DesignStateFailure') { continue }
                $ids.Add($id)
            }
        }
        ,@($ids | Sort-Object -Unique)
    }

    [pscustomobject]@{
        Ids = [pscustomobject]@{
            Blocking         = Get-RowIds -Chunk $blockingText
            Reported         = Get-RowIds -Chunk $reportedText
            CouldNotEvaluate = Get-RowIds -Chunk $cneText
        }
        Failure = $null
    }
}

<#
    design/20-contract.md's own Invariants table, parsed so UnrecordedArtifact's invariant half
    has a set to take a difference against. The section is the invariant unit set per
    § "Artifacts of a unit kind"; a citation scan is deliberately not what defines membership.
    An unreadable section is ContractListUnreadable - the caller reports the invariant half as
    uncomputed rather than as an empty difference, which would be a clean run over a table
    nobody could read.
#>
function Get-ContractInvariantIds {
    param([Parameter(Mandatory)][string] $ContractPath)

    if (-not (Test-Path -LiteralPath $ContractPath)) {
        return [pscustomobject]@{ Ids = $null; Failure = 'ContractPathMissing' }
    }

    $text = Get-Content -LiteralPath $ContractPath -Raw
    if ($null -eq $text) { $text = '' }
    $start = $text.IndexOf("`n## Invariants")
    if ($start -lt 0) {
        return [pscustomobject]@{ Ids = $null; Failure = 'InvariantsSectionNotFound' }
    }
    $rest = $text.Substring($start + 1)
    $end = $rest.IndexOf("`n## ", 1)
    $section = if ($end -lt 0) { $rest } else { $rest.Substring(0, $end) }

    $ids = [System.Collections.Generic.List[string]]::new()
    foreach ($line in ($section -split "`n")) {
        if ($line -match '^\|\s*\*\*(I\d+)\*\*\s*\|') { $ids.Add($Matches[1]) }
    }


    [pscustomobject]@{ Ids = @($ids | Sort-Object -Unique); Failure = $null }
}

function Test-ClassListAgreement {
    param([Parameter(Mandatory)][string] $ContractPath)

    $parsed = Get-ContractClassIds -ContractPath $ContractPath
    if ($parsed.Failure) {
        return [pscustomobject]@{
            CouldNotEvaluate = (New-CouldNotEvaluate -Reason 'ContractListUnreadable' -Detail "$($parsed.Failure): $ContractPath")
            Finding          = $null
        }
    }

    $declared = [pscustomobject]@{
        Blocking         = @($script:BlockingClasses | Sort-Object -Unique)
        Reported         = @($script:ReportedClasses | Sort-Object -Unique)
        CouldNotEvaluate = @($script:CouldNotEvaluateClasses | Sort-Object -Unique)
    }
    $doc = $parsed.Ids

    $onlyInScript = [System.Collections.Generic.List[string]]::new()
    $onlyInDoc = [System.Collections.Generic.List[string]]::new()

    foreach ($tier in 'Blocking', 'Reported', 'CouldNotEvaluate') {
        $s = @($declared.$tier)
        $d = @($doc.$tier)
        foreach ($id in $s) { if ($id -notin $d) { $onlyInScript.Add("$tier`:$id") } }
        foreach ($id in $d) { if ($id -notin $s) { $onlyInDoc.Add("$tier`:$id") } }
    }

    if ($onlyInScript.Count -eq 0 -and $onlyInDoc.Count -eq 0) {
        return [pscustomobject]@{ CouldNotEvaluate = $null; Finding = $null }
    }

    $detail = "declared-only: [$($onlyInScript -join ', ')]; contract-only: [$($onlyInDoc -join ', ')]"
    [pscustomobject]@{
        CouldNotEvaluate = $null
        Finding          = (New-DesignFinding -Class 'ClassListDisagreement' -Subject 'tools/Test-DesignState.ps1' -Detail $detail -Blocking $true)
    }
}

# ---------------------------------------------------------------------------------------------
# Id resolution. Every list/scalar field whose value is documented as an id in
# design/10-design.md § Data model, excluding Archival (excluded from closures, not from
# UnresolvedId - a live record naming a retired id is still resolvable and raises nothing) and
# excluding Work (documented as "issue numbers", not a design-state id) and Evidence
# (documented as "tree pointers", checked by AnchorMissing's sibling logic, not here).
# ---------------------------------------------------------------------------------------------
$script:IdListFields = @('Consumes', 'Exposes', 'Binds', 'Live', 'Archival', 'Questions')
$script:IdScalarFields = @('Owner', 'SupersededBy', 'AnsweredBy')

function Test-UnresolvedId {
    param([Parameter(Mandatory)][hashtable] $ById, [Parameter(Mandatory)][AllowEmptyCollection()][object[]] $Records)

    $findings = [System.Collections.Generic.List[object]]::new()
    foreach ($record in $Records) {
        foreach ($field in $script:IdListFields) {
            if (-not $record.Lists.ContainsKey($field)) { continue }
            foreach ($id in $record.Lists[$field]) {
                if ([string]::IsNullOrWhiteSpace($id)) { continue }
                if (-not $ById.ContainsKey($id)) {
                    $findings.Add((New-DesignFinding -Class 'UnresolvedId' -Subject $record.Id -Detail "$field names '$id', which has no record" -Blocking $true))
                }
            }
        }
        foreach ($field in $script:IdScalarFields) {
            if (-not $record.Scalars.ContainsKey($field)) { continue }
            $id = $record.Scalars[$field]
            if ([string]::IsNullOrWhiteSpace($id)) { continue }
            if (-not $ById.ContainsKey($id)) {
                $findings.Add((New-DesignFinding -Class 'UnresolvedId' -Subject $record.Id -Detail "$field names '$id', which has no record" -Blocking $true))
            }
        }
    }
    ,@($findings)
}

# ---------------------------------------------------------------------------------------------
# AnchorMissing. Every tree-pointer field an active record carries, not only a unit's Anchor:
# a Contract's Declaration and the Evidence list on a Unit or an Invariant are restatements of
# a tree path in exactly the same way (design/20-contract.md § The divergence classes). Three
# exemptions, each of which would otherwise block forever: a retired record (I30); an
# Invariant's Anchor, which is the invariant number and resolves by well-formedness and
# uniqueness rather than Test-Path; and a Contract Declaration of the literal `prose`, which is
# the field's documented second value for a Markdown command surface with nothing to point at.
# ---------------------------------------------------------------------------------------------
function Test-AnchorMissing {
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]] $Records, [Parameter(Mandatory)][string] $RepoPath)

    $findings = [System.Collections.Generic.List[object]]::new()
    foreach ($record in $Records) {
        if ($record.Kind -notin @('Unit', 'Invariant', 'Contract')) { continue }
        if ($record.Scalars['Status'] -ne 'active') { continue }

        $pointers = [System.Collections.Generic.List[object]]::new()

        if ($record.Kind -eq 'Unit') {
            $anchor = $record.Scalars['Anchor']
            if (-not [string]::IsNullOrWhiteSpace($anchor)) {
                $pointers.Add([pscustomobject]@{ Field = 'Anchor'; Value = $anchor })
            }
        }
        if ($record.Kind -eq 'Contract') {
            $declaration = $record.Scalars['Declaration']
            if (-not [string]::IsNullOrWhiteSpace($declaration) -and $declaration -ne 'prose') {
                $pointers.Add([pscustomobject]@{ Field = 'Declaration'; Value = $declaration })
            }
        }
        if ($record.Lists.ContainsKey('Evidence')) {
            foreach ($entry in $record.Lists['Evidence']) {
                if ([string]::IsNullOrWhiteSpace($entry)) { continue }
                $pointers.Add([pscustomobject]@{ Field = 'Evidence'; Value = $entry })
            }
        }

        foreach ($pointer in $pointers) {
            $full = Join-Path $RepoPath $pointer.Value
            if (-not (Test-Path -LiteralPath $full)) {
                $findings.Add((New-DesignFinding -Class 'AnchorMissing' -Subject $record.Id -Detail "$($pointer.Field) '$($pointer.Value)' does not exist in the tree" -Blocking $true))
            }
        }
    }
    ,@($findings)
}

# ---------------------------------------------------------------------------------------------
# OwnerMismatch. A Contract record's Owner must be the unique active Unit whose Exposes names
# that contract id.
# ---------------------------------------------------------------------------------------------
function Test-OwnerMismatch {
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]] $Records)

    $findings = [System.Collections.Generic.List[object]]::new()
    $contracts = @($Records | Where-Object { $_.Kind -eq 'Contract' })
    if ($contracts.Count -eq 0) { return ,@() }

    $exposers = @{}
    foreach ($record in $Records) {
        if (-not $record.Lists.ContainsKey('Exposes')) { continue }
        if ($record.Scalars['Status'] -ne 'active') { continue }
        foreach ($contractId in $record.Lists['Exposes']) {
            if ([string]::IsNullOrWhiteSpace($contractId)) { continue }
            if (-not $exposers.ContainsKey($contractId)) { $exposers[$contractId] = [System.Collections.Generic.List[string]]::new() }
            $exposers[$contractId].Add($record.Id)
        }
    }

    foreach ($contract in $contracts) {
        $owner = $contract.Scalars['Owner']
        $who = @(if ($exposers.ContainsKey($contract.Id)) { @($exposers[$contract.Id]) } else { @() })
        $isUnique = ($who.Count -eq 1 -and $who[0] -eq $owner)
        if (-not $isUnique) {
            $whoText = if ($who.Count -eq 0) { '(nobody)' } else { $who -join ', ' }
            $findings.Add((New-DesignFinding -Class 'OwnerMismatch' -Subject $contract.Id -Detail "Owner declared as '$owner'; units exposing it: $whoText" -Blocking $true))
        }
    }
    ,@($findings)
}

# ---------------------------------------------------------------------------------------------
# UnrecordedArtifact. design/20-contract.md § "Artifacts of a unit kind" - a glob with a named
# exclusion list, per kind, plus the invariant kind's citation-based set difference.
# ---------------------------------------------------------------------------------------------
function Get-DocumentGlobFiles {
    param([Parameter(Mandatory)][string] $RepoPath)

    $set = [System.Collections.Generic.SortedSet[string]]::new()
    $add = {
        param($p)
        if (Test-Path -LiteralPath $p) {
            $rel = ([IO.Path]::GetRelativePath($RepoPath, $p)) -replace '\\', '/'
            [void]$set.Add($rel)
        }
    }

    Get-ChildItem -LiteralPath (Join-Path $RepoPath 'design') -Filter '*.md' -File -ErrorAction SilentlyContinue |
        ForEach-Object { & $add $_.FullName }
    $templatesDesign = Join-Path $RepoPath 'templates/design'
    if (Test-Path -LiteralPath $templatesDesign) {
        Get-ChildItem -LiteralPath $templatesDesign -Filter '*.md' -File -ErrorAction SilentlyContinue |
            ForEach-Object { & $add $_.FullName }
    }
    Get-ChildItem -LiteralPath $RepoPath -Filter '*.md' -File -ErrorAction SilentlyContinue |
        ForEach-Object { & $add $_.FullName }
    & $add (Join-Path $RepoPath '.claude/COMPANIONS.md')
    $issueTemplates = Join-Path $RepoPath '.github/ISSUE_TEMPLATE'
    if (Test-Path -LiteralPath $issueTemplates) {
        Get-ChildItem -LiteralPath $issueTemplates -Filter '*.md' -File -ErrorAction SilentlyContinue |
            ForEach-Object { & $add $_.FullName }
    }
    & $add (Join-Path $RepoPath 'codex/PROFILES.md')

    $excluded = @('design/FROZEN.md', 'CLAUDE.md')
    ,@($set | Where-Object { $_ -notin $excluded })
}

function Get-CommandGlobFiles {
    param([Parameter(Mandatory)][string] $RepoPath)

    $dir = Join-Path $RepoPath '.claude/commands'
    if (-not (Test-Path -LiteralPath $dir)) { return ,@() }
    ,@(
        Get-ChildItem -LiteralPath $dir -Filter '*.md' -File |
            Where-Object { $_.Name -notlike '*-local.md' } |
            ForEach-Object { ([IO.Path]::GetRelativePath($RepoPath, $_.FullName)) -replace '\\', '/' } |
            Sort-Object
    )
}

function Get-ScriptGlobFiles {
    param([Parameter(Mandatory)][string] $RepoPath)

    $dir = Join-Path $RepoPath 'tools'
    if (-not (Test-Path -LiteralPath $dir)) { return ,@() }
    ,@(
        Get-ChildItem -LiteralPath $dir -Filter '*.ps1' -File |
            Where-Object { $_.Name -notlike '*.Tests.ps1' } |
            ForEach-Object { ([IO.Path]::GetRelativePath($RepoPath, $_.FullName)) -replace '\\', '/' } |
            Sort-Object
    )
}

<#
    design/20-contract.md § "Artifacts of a unit kind"'s own glob table, parsed so
    GlobDisagreement has something to expand and compare against the three Get-*GlobFiles
    enumerations. The third parsed source this document carries, after the class list and
    § Invariants; ContractListUnreadable covers all three.

    Both cells carry patterns and nothing else, which is what makes this parse a token scan
    rather than a prose reader. The invariant row has no pattern in either cell and drops out
    for that reason, not by being named here.
#>
function Get-ContractGlobPatterns {
    param([Parameter(Mandatory)][string] $ContractPath)

    if (-not (Test-Path -LiteralPath $ContractPath)) {
        return [pscustomobject]@{ Kinds = $null; Failure = 'ContractPathMissing' }
    }

    $text = Get-Content -LiteralPath $ContractPath -Raw
    if ($null -eq $text) { $text = '' }
    $start = $text.IndexOf('| Kind | Glob | Excluded |')
    if ($start -lt 0) {
        return [pscustomobject]@{ Kinds = $null; Failure = 'GlobTableNotFound' }
    }
    $rest = $text.Substring($start)
    $end = $rest.IndexOf("`n`n")
    $table = if ($end -lt 0) { $rest } else { $rest.Substring(0, $end) }

    $kinds = @{}
    foreach ($line in ($table -split "`n")) {
        if ($line -notmatch '^\|\s*([a-z]+)\s*\|(.*)\|(.*)\|\s*$') { continue }
        $kind = $Matches[1]
        $globCell = $Matches[2]
        $excludedCell = $Matches[3]
        $globs = @([regex]::Matches($globCell, '`([^`]+)`') | ForEach-Object { $_.Groups[1].Value })
        if ($globs.Count -eq 0) { continue }
        $kinds[$kind] = [pscustomobject]@{
            Glob     = $globs
            Excluded = @([regex]::Matches($excludedCell, '`([^`]+)`') | ForEach-Object { $_.Groups[1].Value })
        }
    }

    if ($kinds.Count -eq 0) {
        return [pscustomobject]@{ Kinds = $null; Failure = 'GlobTableHasNoPatterns' }
    }
    [pscustomobject]@{ Kinds = $kinds; Failure = $null }
}

<#
    Expands one parsed pattern against the checkout. A pattern is repository-relative and
    wildcards only its final segment, so the directory half is literal and the file half is a
    -Filter. This is deliberately not a general glob engine: the table's own rule is the whole
    grammar, and anything outside it should fail to resolve rather than be guessed at.
#>
function Expand-ContractGlobPattern {
    param(
        [Parameter(Mandatory)][string] $RepoPath,
        [Parameter(Mandatory)][string] $Pattern
    )

    $normalised = $Pattern -replace '\\', '/'
    $dir = [IO.Path]::GetDirectoryName($normalised) -replace '\\', '/'
    $leaf = [IO.Path]::GetFileName($normalised)
    $searchRoot = if ([string]::IsNullOrEmpty($dir)) { $RepoPath } else { Join-Path $RepoPath $dir }
    if (-not (Test-Path -LiteralPath $searchRoot)) { return ,@() }

    if ($leaf -notmatch '[*?]') {
        $full = Join-Path $searchRoot $leaf
        if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { return ,@() }
        return ,@($normalised)
    }

    ,@(
        Get-ChildItem -LiteralPath $searchRoot -Filter $leaf -File -ErrorAction SilentlyContinue |
            ForEach-Object { ([IO.Path]::GetRelativePath($RepoPath, $_.FullName)) -replace '\\', '/' }
    )
}

<#
    GlobDisagreement. design/20-contract.md § "The divergence classes" - the file set the
    contract's patterns resolve to, against the set the checker's own enumeration returns, per
    globbed kind and in both directions.

    File sets, never pattern text: an exclusion applied at the wrong level or a directory quietly
    skipped diverges semantically while the tokens still match, and that is the case this class
    exists for. The parsed patterns only ever compare - UnrecordedArtifact keeps reading the
    Get-*GlobFiles enumerations - so a mis-parse can report a disagreement or report
    ContractListUnreadable, and can never narrow the world being checked.
#>
function Test-GlobDisagreement {
    param(
        [Parameter(Mandatory)][string] $RepoPath,
        [Parameter(Mandatory)][string] $ContractPath
    )

    $parsed = Get-ContractGlobPatterns -ContractPath $ContractPath
    if ($parsed.Failure) {
        return [pscustomobject]@{
            CouldNotEvaluate = (New-CouldNotEvaluate -Reason 'ContractListUnreadable' -Detail "$($parsed.Failure): $ContractPath; GlobDisagreement is uncomputed, not clean")
            Findings         = @()
        }
    }

    $enumerators = @{
        command  = { Get-CommandGlobFiles  -RepoPath $RepoPath }
        script   = { Get-ScriptGlobFiles   -RepoPath $RepoPath }
        document = { Get-DocumentGlobFiles -RepoPath $RepoPath }
    }

    $findings = [System.Collections.Generic.List[object]]::new()
    foreach ($kind in @($enumerators.Keys | Sort-Object)) {
        if (-not $parsed.Kinds.ContainsKey($kind)) {
            $findings.Add((New-DesignFinding -Class 'GlobDisagreement' -Subject $kind `
                -Detail "the checker enumerates the $kind kind and design/20-contract.md § Artifacts of a unit kind carries no patterns for it" -Blocking $true))
            continue
        }
        $spec = $parsed.Kinds[$kind]

        $resolved = [System.Collections.Generic.SortedSet[string]]::new()
        foreach ($pattern in $spec.Glob) {
            # Expand-ContractGlobPattern and the Get-*GlobFiles enumerations all emit `,@(...)`,
            # a single object that *is* an array. Both sides are cast flat before comparing;
            # without it the set difference compares arrays and reports every path as divergent.
            [string[]] $hits = Expand-ContractGlobPattern -RepoPath $RepoPath -Pattern $pattern
            foreach ($hit in $hits) { [void]$resolved.Add($hit) }
        }
        # An exclusion carrying a wildcard is matched against the basename; one without is a
        # repository-relative path. That is the table's own stated grammar, and matching it
        # exactly is the point - a matcher looser than the enumeration would report a
        # disagreement of its own making rather than the one in the tree.
        $contractSide = @($resolved | Where-Object {
            $path = $_
            $leaf = [IO.Path]::GetFileName($path)
            -not (@($spec.Excluded) | Where-Object {
                if ($_ -match '[*?]') { $leaf -like $_ } else { $path -eq $_ }
            })
        })

        [string[]] $checkerSide = & $enumerators[$kind]

        [string[]] $onlyContract = @($contractSide | Where-Object { $_ -notin $checkerSide })
        [string[]] $onlyChecker  = @($checkerSide  | Where-Object { $_ -notin $contractSide })
        if ($onlyContract.Count -gt 0) {
            $findings.Add((New-DesignFinding -Class 'GlobDisagreement' -Subject $kind `
                -Detail "the contract's patterns reach $($onlyContract.Count) path(s) the checker does not enumerate: $($onlyContract -join ', ')" -Blocking $true))
        }
        if ($onlyChecker.Count -gt 0) {
            $findings.Add((New-DesignFinding -Class 'GlobDisagreement' -Subject $kind `
                -Detail "the checker enumerates $($onlyChecker.Count) path(s) the contract's patterns do not reach: $($onlyChecker -join ', ')" -Blocking $true))
        }
    }

    foreach ($kind in @($parsed.Kinds.Keys | Sort-Object)) {
        if (-not $enumerators.ContainsKey($kind)) {
            $findings.Add((New-DesignFinding -Class 'GlobDisagreement' -Subject $kind `
                -Detail "design/20-contract.md § Artifacts of a unit kind carries patterns for the $kind kind and the checker enumerates no such kind" -Blocking $true))
        }
    }

    [pscustomobject]@{ CouldNotEvaluate = $null; Findings = @($findings) }
}

function Test-UnrecordedArtifact {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]] $Records,
        [Parameter(Mandatory)][string] $RepoPath,
        [AllowNull()][string[]] $InvariantIds
    )

    $findings = [System.Collections.Generic.List[object]]::new()
    $units = @($Records | Where-Object { $_.Kind -eq 'Unit' -and $_.Scalars['Status'] -eq 'active' })

    $byUnitKind = @{ command = @(); script = @(); document = @() }
    foreach ($u in $units) {
        $k = $u.Scalars['Kind']
        if ($byUnitKind.ContainsKey($k)) { $byUnitKind[$k] += $u }
    }

    $kindGlobs = @{
        command  = (Get-CommandGlobFiles -RepoPath $RepoPath)
        script   = (Get-ScriptGlobFiles -RepoPath $RepoPath)
        document = (Get-DocumentGlobFiles -RepoPath $RepoPath)
    }

    foreach ($kind in 'command', 'script', 'document') {
        $anchors = @($byUnitKind[$kind] | ForEach-Object { $_.Scalars['Anchor'] })
        $files = @($kindGlobs[$kind])

        foreach ($file in $files) {
            if ($file -notin $anchors) {
                $findings.Add((New-DesignFinding -Class 'UnrecordedArtifact' -Subject $file -Detail "tree artifact of kind '$kind' has no active unit record naming it as Anchor" -Blocking $true))
            }
        }
        foreach ($u in $byUnitKind[$kind]) {
            $anchor = $u.Scalars['Anchor']
            if ($anchor -notin $files) {
                $findings.Add((New-DesignFinding -Class 'UnrecordedArtifact' -Subject $u.Id -Detail "Anchor '$anchor' is not matched by the '$kind' glob (or was excluded from it)" -Blocking $true))
            }
        }
    }

    # Invariant kind: "not a tree path" - the set is every I<n> row in design/20-contract.md
    # § Invariants (design/20-contract.md § "Artifacts of a unit kind"). $InvariantIds is $null
    # when that section could not be read; the caller has already recorded ContractListUnreadable
    # and this half stays uncomputed rather than reporting an empty difference as agreement.
    if ($null -ne $InvariantIds) {
        $declaredIds = @($InvariantIds)
        $invariantRecords = @($Records | Where-Object { $_.Kind -eq 'Invariant' })
        $recordedIds = @($invariantRecords | ForEach-Object { $_.Id })

        foreach ($id in $declaredIds) {
            if ($id -notin $recordedIds) {
                $findings.Add((New-DesignFinding -Class 'UnrecordedArtifact' -Subject $id -Detail "a row in design/20-contract.md - Invariants, with no invariant record" -Blocking $true))
            }
        }
        foreach ($record in $invariantRecords) {
            if ($record.Scalars['Status'] -ne 'active') { continue }
            if ($record.Id -notin $declaredIds) {
                $findings.Add((New-DesignFinding -Class 'UnrecordedArtifact' -Subject $record.Id -Detail "invariant record exists but is no row in design/20-contract.md - Invariants" -Blocking $true))
            }
        }
    }

    ,@($findings)
}

# ---------------------------------------------------------------------------------------------
# Marked regions: RegionMalformed (balance/nesting) and the region half of IdCollision (an id
# appearing as both the projected and the declared form). Scoped to the document and command
# globs - the only checkout-local carriers of a real region today; an issue's `agent:start`
# block lives on GitHub and is not evaluable from the checkout alone (I22), so it is out of
# reach for a blocking class regardless. Matching requires the marker to be the entire
# (trimmed) line, which is what keeps prose that merely *mentions* the marker syntax - this
# document does, at length - from being misread as a region.
# ---------------------------------------------------------------------------------------------
function Get-MarkedRegions {
    param([Parameter(Mandatory)][string] $RepoPath, [Parameter(Mandatory)][AllowEmptyCollection()][string[]] $Files)

    $findings = [System.Collections.Generic.List[object]]::new()
    $inventory = [System.Collections.Generic.List[object]]::new() # { Id; Form; File }

    $startRe = '^<!--\s*([A-Za-z][\w-]*)(:declared)?:start\s*-->$'
    $endRe = '^<!--\s*([A-Za-z][\w-]*)(:declared)?:end\s*-->$'

    foreach ($file in $Files) {
        $full = Join-Path $RepoPath $file
        if (-not (Test-Path -LiteralPath $full)) { continue }
        $lines = @(Get-Content -LiteralPath $full)
        $stack = [System.Collections.Generic.List[object]]::new() # { Id; Form }

        for ($i = 0; $i -lt $lines.Count; $i++) {
            $line = $lines[$i].Trim()

            if ($line -match $startRe) {
                $id = $Matches[1]
                $form = if ($Matches[2]) { 'Declared' } else { 'Projected' }

                if ($stack | Where-Object { $_.Id -eq $id }) {
                    $findings.Add((New-DesignFinding -Class 'RegionMalformed' -Subject $file -Detail "region '$id' opened again before its enclosing region closed (line $($i + 1))" -Blocking $true))
                }
                $stack.Add([pscustomobject]@{ Id = $id; Form = $form; Line = ($i + 1) })
                $inventory.Add([pscustomobject]@{ Id = $id; Form = $form; File = $file })
                continue
            }

            if ($line -match $endRe) {
                $id = $Matches[1]
                $form = if ($Matches[2]) { 'Declared' } else { 'Projected' }

                if ($stack.Count -eq 0 -or $stack[$stack.Count - 1].Id -ne $id -or $stack[$stack.Count - 1].Form -ne $form) {
                    $findings.Add((New-DesignFinding -Class 'RegionMalformed' -Subject $file -Detail "closing marker for '$id' ($form) at line $($i + 1) does not match the innermost open region" -Blocking $true))
                    continue
                }
                $stack.RemoveAt($stack.Count - 1)
                continue
            }
        }

        foreach ($open in $stack) {
            $findings.Add((New-DesignFinding -Class 'RegionMalformed' -Subject $file -Detail "region '$($open.Id)' ($($open.Form)) opened at line $($open.Line) is never closed" -Blocking $true))
        }
    }

    [pscustomobject]@{ Findings = @($findings); Inventory = @($inventory) }
}

function Test-RegionFormCollision {
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]] $Inventory)

    $findings = [System.Collections.Generic.List[object]]::new()
    $byId = @{}
    foreach ($entry in $Inventory) {
        if (-not $byId.ContainsKey($entry.Id)) { $byId[$entry.Id] = [System.Collections.Generic.SortedSet[string]]::new() }
        [void]$byId[$entry.Id].Add($entry.Form)
    }
    foreach ($id in $byId.Keys) {
        if ($byId[$id].Count -gt 1) {
            $findings.Add((New-DesignFinding -Class 'IdCollision' -Subject $id -Detail "region id '$id' appears in both the projected and the declared marker form" -Blocking $true))
        }
    }
    ,@($findings)
}

# ---------------------------------------------------------------------------------------------
# IdCollision over records: a duplicated id, an id disagreeing with the id its file path
# implies (S4.7), plus the region-form collision above.
# ---------------------------------------------------------------------------------------------
function Test-RecordIdCollision {
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]] $Records)

    $findings = [System.Collections.Generic.List[object]]::new()
    $byId = @{}
    foreach ($record in $Records) {
        if (-not $byId.ContainsKey($record.Id)) { $byId[$record.Id] = [System.Collections.Generic.List[object]]::new() }
        $byId[$record.Id].Add($record)
    }
    foreach ($id in $byId.Keys) {
        if ($byId[$id].Count -gt 1) {
            $paths = ($byId[$id] | ForEach-Object { $_.Path }) -join ', '
            $findings.Add((New-DesignFinding -Class 'IdCollision' -Subject $id -Detail "id is claimed by more than one file: $paths" -Blocking $true))
        }
    }

    foreach ($record in $Records) {
        $info = Get-DesignPathInfo -RelativeToState ($record.Path -replace '^design/state/', '')
        if (-not $info) { continue }
        if ($info.PathId -ne $record.Id) {
            $findings.Add((New-DesignFinding -Class 'IdCollision' -Subject $record.Id -Detail "record's own id disagrees with the id implied by its file path '$($record.Path)' (path implies '$($info.PathId)')" -Blocking $true))
        }
    }
    ,@($findings)
}

# ---------------------------------------------------------------------------------------------
# DecisionAnchorAmbiguous and LogEntryUnrecorded: design/90-decisions.md heading text against
# Decision.Anchor.
# ---------------------------------------------------------------------------------------------
function Test-DecisionAnchors {
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]] $Records, [Parameter(Mandatory)][string] $LogPath)

    $findings = [System.Collections.Generic.List[object]]::new()
    if (-not (Test-Path -LiteralPath $LogPath)) { return ,@() }

    $headings = [System.Collections.Generic.List[string]]::new()
    foreach ($line in (Get-Content -LiteralPath $LogPath)) {
        if ($line -match '^###\s+(.+?)\s*$') { $headings.Add($Matches[1]) }
    }

    $decisions = @($Records | Where-Object { $_.Kind -eq 'Decision' })
    foreach ($decision in $decisions) {
        $anchor = $decision.Scalars['Anchor']
        $count = @($headings | Where-Object { $_ -eq $anchor }).Count
        if ($count -ne 1) {
            $findings.Add((New-DesignFinding -Class 'DecisionAnchorAmbiguous' -Subject $decision.Id -Detail "Anchor '$anchor' resolves to $count heading(s) in $LogPath" -Blocking $true))
        }
    }

    $decisionAnchors = @($decisions | ForEach-Object { $_.Scalars['Anchor'] })
    foreach ($heading in $headings) {
        if ($heading -notin $decisionAnchors) {
            $findings.Add((New-DesignFinding -Class 'LogEntryUnrecorded' -Subject $heading -Detail "log heading has no decision record naming it as Anchor" -Blocking $true))
        }
    }

    ,@($findings)
}

# ---------------------------------------------------------------------------------------------
# EnforcementUnevidenced: a conditionally-required field absent on a record whose own Status or
# Enforcement requires it - an Invariant with Enforcement 'code' and no Evidence, a Decision with
# Status 'superseded' and no SupersededBy, or a Question with Status 'answered' and no AnsweredBy
# (design/20-contract.md § "The divergence classes"; design/90-decisions.md, 2026-08-19).
# ---------------------------------------------------------------------------------------------
function Test-EnforcementUnevidenced {
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]] $Records)

    $findings = [System.Collections.Generic.List[object]]::new()
    foreach ($record in @($Records | Where-Object { $_.Kind -eq 'Invariant' })) {
        if ($record.Scalars['Enforcement'] -ne 'code') { continue }
        $evidence = @(if ($record.Lists.ContainsKey('Evidence')) { @($record.Lists['Evidence'] | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) } else { @() })
        if ($evidence.Count -eq 0) {
            $findings.Add((New-DesignFinding -Class 'EnforcementUnevidenced' -Subject $record.Id -Detail "field 'Evidence' is required because Enforcement is 'code', and is absent" -Blocking $true))
        }
    }
    foreach ($record in @($Records | Where-Object { $_.Kind -eq 'Decision' })) {
        if ($record.Scalars['Status'] -ne 'superseded') { continue }
        if ([string]::IsNullOrWhiteSpace($record.Scalars['SupersededBy'])) {
            $findings.Add((New-DesignFinding -Class 'EnforcementUnevidenced' -Subject $record.Id -Detail "field 'SupersededBy' is required because Status is 'superseded', and is absent" -Blocking $true))
        }
    }
    foreach ($record in @($Records | Where-Object { $_.Kind -eq 'Question' })) {
        if ($record.Scalars['Status'] -ne 'answered') { continue }
        if ([string]::IsNullOrWhiteSpace($record.Scalars['AnsweredBy'])) {
            $findings.Add((New-DesignFinding -Class 'EnforcementUnevidenced' -Subject $record.Id -Detail "field 'AnsweredBy' is required because Status is 'answered', and is absent" -Blocking $true))
        }
    }
    ,@($findings)
}

# ---------------------------------------------------------------------------------------------
# The budget meter. closure(U) = record(U), plus the record of every id record(U) names
# directly, excluding Archival and excluding any named record whose Status is retired
# (design/10-design.md § "The orientation closure"; S5.5). Size is the sum of the closure
# members' own file sizes on disk, because the measurement must equal what a reader actually
# opens.
# ---------------------------------------------------------------------------------------------
function Get-RecordFileBytes {
    param([Parameter(Mandatory)][string] $RepoPath, [Parameter(Mandatory)]$Record)
    $full = Join-Path $RepoPath $Record.Path
    if (-not (Test-Path -LiteralPath $full)) { return 0 }
    (Get-Item -LiteralPath $full).Length
}

function Get-DesignClosure {
    param([Parameter(Mandatory)]$Root, [Parameter(Mandatory)][hashtable] $ById)

    $members = [System.Collections.Generic.List[object]]::new()
    $members.Add($Root)
    $seen = [System.Collections.Generic.HashSet[string]]::new()
    [void]$seen.Add($Root.Id)

    $namedFields = @('Consumes', 'Exposes', 'Binds', 'Live', 'Questions')
    foreach ($field in $namedFields) {
        if (-not $Root.Lists.ContainsKey($field)) { continue }
        foreach ($id in $Root.Lists[$field]) {
            if ([string]::IsNullOrWhiteSpace($id)) { continue }
            if (-not $ById.ContainsKey($id)) { continue }
            $named = $ById[$id]
            if ($named.Scalars.ContainsKey('Status') -and $named.Scalars['Status'] -eq 'retired') { continue }
            if ($seen.Contains($id)) { continue }
            [void]$seen.Add($id)
            $members.Add($named)
        }
    }
    foreach ($field in $script:IdScalarFields) {
        if (-not $Root.Scalars.ContainsKey($field)) { continue }
        $id = $Root.Scalars[$field]
        if ([string]::IsNullOrWhiteSpace($id)) { continue }
        if (-not $ById.ContainsKey($id)) { continue }
        $named = $ById[$id]
        if ($named.Scalars.ContainsKey('Status') -and $named.Scalars['Status'] -eq 'retired') { continue }
        if ($seen.Contains($id)) { continue }
        [void]$seen.Add($id)
        $members.Add($named)
    }

    ,@($members)
}

function Test-ClosureBudget {
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]] $Records, [Parameter(Mandatory)][hashtable] $ById, [Parameter(Mandatory)][string] $RepoPath)

    $findings = [System.Collections.Generic.List[object]]::new()
    $largest = $null

    $roots = @($Records | Where-Object {
            if ($_.Kind -eq 'WorkRef') { return $true }
            -not ($_.Scalars.ContainsKey('Status') -and $_.Scalars['Status'] -eq 'retired')
        })

    foreach ($root in $roots) {
        $members = Get-DesignClosure -Root $root -ById $ById
        $sized = @($members | ForEach-Object { [pscustomobject]@{ Record = $_; Bytes = (Get-RecordFileBytes -RepoPath $RepoPath -Record $_) } })
        $total = ($sized | Measure-Object -Property Bytes -Sum).Sum
        $biggest = $sized | Sort-Object Bytes -Descending | Select-Object -First 1

        if (-not $largest -or $total -gt $largest.Bytes) {
            $largest = [pscustomobject]@{
                Unit               = $root.Id
                Bytes              = $total
                LargestContributor = $biggest.Record.Id
            }
        }

        if ($total -gt $script:ClosureBudgetBytes) {
            $findings.Add((New-DesignFinding -Class 'ClosureOverBudget' -Subject $root.Id -Detail "closure is $total bytes (ceiling $($script:ClosureBudgetBytes)); largest contributor '$($biggest.Record.Id)'" -Blocking $true))
        }
    }

    [pscustomobject]@{ Findings = @($findings); Largest = $largest }
}

# ---------------------------------------------------------------------------------------------
# The projector (S7). Its absence, or a non-zero exit, is a contracted case (ProjectorFailed) -
# S5's own Out of scope line, unchanged now that S7 has written it. -DryRun's output is the
# projector's own JSON rendering of every region it would write (design/20-contract.md §
# tools/Update-DesignProjection.ps1); a caller comparing region content, not just the exit code,
# is what makes ProjectionStale (S7.9) computable rather than permanently uncomputed.
# ---------------------------------------------------------------------------------------------
function Invoke-Projector {
    param([Parameter(Mandatory)][string] $RepoPath)

    $projectorPath = Join-Path $RepoPath 'tools/Update-DesignProjection.ps1'
    if (-not (Test-Path -LiteralPath $projectorPath)) {
        return [pscustomobject]@{ Ran = $false; Detail = 'tools/Update-DesignProjection.ps1 does not exist'; Regions = @() }
    }
    try {
        $raw = & pwsh -NoProfile -File $projectorPath -Path $RepoPath -DryRun 2>$null
        if ($LASTEXITCODE -ne 0) {
            return [pscustomobject]@{ Ran = $false; Detail = "exited $LASTEXITCODE"; Regions = @() }
        }
    } catch {
        return [pscustomobject]@{ Ran = $false; Detail = $_.Exception.Message; Regions = @() }
    }

    $regions = @()
    try {
        if ($raw) {
            $regions = @(($raw -join "`n") | ConvertFrom-Json)
        }
    } catch {
        return [pscustomobject]@{ Ran = $false; Detail = "unparseable projector output: $($_.Exception.Message)"; Regions = @() }
    }

    [pscustomobject]@{ Ran = $true; Detail = $null; Regions = $regions }
}

# ---------------------------------------------------------------------------------------------
# ProjectionStale (S7.9). A region the projector rendered but has no document (the `agent`
# projection - it targets GitHub, not the tree) is not comparable here and is skipped; every
# other region is compared, CRLF-normalised, against the tree's own copy of that region's body.
# ---------------------------------------------------------------------------------------------
function Get-RegionBody {
    param([Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][string[]] $Lines, [Parameter(Mandatory)][string] $Id)

    $startPattern = "<!-- $Id`:start -->"
    $endPattern = "<!-- $Id`:end -->"
    $startIndex = -1
    $endIndex = -1
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $t = $Lines[$i].Trim()
        if ($startIndex -lt 0 -and $t -eq $startPattern) { $startIndex = $i; continue }
        if ($startIndex -ge 0 -and $endIndex -lt 0 -and $t -eq $endPattern) { $endIndex = $i; continue }
    }
    if ($startIndex -lt 0 -or $endIndex -lt 0 -or $endIndex -le $startIndex) { return $null }
    if ($endIndex -eq $startIndex + 1) { return '' }
    ,@($Lines[($startIndex + 1)..($endIndex - 1)])
}

function ConvertTo-NormalisedNewlines {
    param([string] $Text)
    ($Text -replace "`r`n", "`n") -replace "`r", "`n"
}

function Test-ProjectionStale {
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]] $Regions, [Parameter(Mandatory)][string] $RepoPath)

    $findings = [System.Collections.Generic.List[object]]::new()
    foreach ($region in $Regions) {
        if (-not $region.Document) { continue } # e.g. `agent` - no tree region to compare against
        $full = Join-Path $RepoPath $region.Document
        if (-not (Test-Path -LiteralPath $full)) {
            $findings.Add((New-DesignFinding -Class 'ProjectionStale' -Subject "$($region.Document)#$($region.Id)" -Detail 'document named by the projector does not exist in the tree' -Blocking $true))
            continue
        }
        $lines = @(Get-Content -LiteralPath $full)
        $body = Get-RegionBody -Lines $lines -Id $region.Id
        if ($null -eq $body) { continue } # a missing/malformed region is RegionMissing/RegionMalformed's territory, not this one's

        $current = (ConvertTo-NormalisedNewlines -Text (($body -join "`n"))).Trim("`n")
        $rendered = (ConvertTo-NormalisedNewlines -Text $region.Content).Trim("`n")
        if ($current -ne $rendered) {
            $findings.Add((New-DesignFinding -Class 'ProjectionStale' -Subject "$($region.Document)#$($region.Id)" -Detail 'the tree''s copy of this region differs from its regeneration' -Blocking $true))
        }
    }
    ,@($findings)
}

# ---------------------------------------------------------------------------------------------
# The tracker classes: MirrorStale (no network - compares MirroredAt to HEAD), PinAncestry and
# WorkStateDivergence (need gh / git history). TrackerUnavailable is could-not-evaluate for the
# gh-dependent classes only; MirrorStale still runs without gh.
# ---------------------------------------------------------------------------------------------
function Get-CurrentCommitSha {
    param([Parameter(Mandatory)][string] $RepoPath)
    try {
        Push-Location $RepoPath
        $sha = (& git rev-parse HEAD 2>$null)
        if ($LASTEXITCODE -ne 0) { return $null }
        return $sha.Trim()
    } finally {
        Pop-Location
    }
}

function Test-CommitIsAncestor {
    param([Parameter(Mandatory)][string] $RepoPath, [Parameter(Mandatory)][string] $Sha)
    try {
        Push-Location $RepoPath
        & git merge-base --is-ancestor $Sha HEAD 2>$null | Out-Null
        switch ($LASTEXITCODE) {
            0 { 'Ancestor' }
            1 { 'NotAncestor' }
            default { 'Unresolvable' }
        }
    } finally {
        Pop-Location
    }
}

function Test-TrackerAvailable {
    param([string] $Repository)
    $ghArgs = @('issue', 'list', '--state', 'all', '--limit', '1', '--json', 'number')
    if ($Repository) { $ghArgs += @('-R', $Repository) }
    try {
        & gh @ghArgs 2>$null | Out-Null
        return ($LASTEXITCODE -eq 0)
    } catch {
        return $false
    }
}

function Test-TrackerClasses {
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]] $Records, [Parameter(Mandatory)][string] $RepoPath, [string] $Repository)

    $reported = [System.Collections.Generic.List[object]]::new()
    $couldNotEvaluate = [System.Collections.Generic.List[object]]::new()

    $workRefs = @($Records | Where-Object { $_.Kind -eq 'WorkRef' })
    $headSha = Get-CurrentCommitSha -RepoPath $RepoPath

    foreach ($ref in $workRefs) {
        $mirroredAt = $ref.Scalars['MirroredAt']
        if (-not [string]::IsNullOrWhiteSpace($mirroredAt) -and $headSha -and $mirroredAt -ne $headSha) {
            $reported.Add((New-DesignFinding -Class 'MirrorStale' -Subject $ref.Id -Detail "MirroredAt '$mirroredAt' is not the current commit '$headSha'" -Blocking $false))
        }
    }

    $ghOk = Test-TrackerAvailable -Repository $Repository
    if (-not $ghOk) {
        $couldNotEvaluate.Add((New-CouldNotEvaluate -Reason 'TrackerUnavailable' -Detail 'gh missing or unauthenticated; WorkStateDivergence not compared'))
    } else {
        foreach ($ref in $workRefs) {
            $number = $ref.Scalars['Issue']
            if ([string]::IsNullOrWhiteSpace($number)) { continue }
            $json = & gh issue view $number --json title, state 2>$null
            if ($LASTEXITCODE -ne 0 -or -not $json) {
                $couldNotEvaluate.Add((New-CouldNotEvaluate -Reason 'TrackerUnavailable' -Detail "could not read issue #$number for $($ref.Id)"))
                continue
            }
            try {
                $issue = ($json -join "`n") | ConvertFrom-Json
            } catch {
                $couldNotEvaluate.Add((New-CouldNotEvaluate -Reason 'TrackerUnavailable' -Detail "unparseable gh output for issue #$number"))
                continue
            }
            $mirroredState = $ref.Scalars['State']
            $mirroredTitle = $ref.Scalars['Title']
            if ($mirroredState -and $issue.state -and ($mirroredState -ne $issue.state)) {
                $reported.Add((New-DesignFinding -Class 'WorkStateDivergence' -Subject $ref.Id -Detail "mirrored State '$mirroredState' disagrees with tracker's '$($issue.state)'" -Blocking $false))
            }
            if ($mirroredTitle -and $issue.title -and ($mirroredTitle -ne $issue.title)) {
                $reported.Add((New-DesignFinding -Class 'WorkStateDivergence' -Subject $ref.Id -Detail "mirrored Title disagrees with tracker's current title" -Blocking $false))
            }
        }
    }

    foreach ($ref in $workRefs) {
        $mirroredAt = $ref.Scalars['MirroredAt']
        if ([string]::IsNullOrWhiteSpace($mirroredAt)) { continue }
        if (-not $headSha) {
            $couldNotEvaluate.Add((New-CouldNotEvaluate -Reason 'ShallowCheckout' -Detail "no history to resolve HEAD for $($ref.Id)"))
            continue
        }
        $ancestry = Test-CommitIsAncestor -RepoPath $RepoPath -Sha $mirroredAt
        switch ($ancestry) {
            'NotAncestor' { $reported.Add((New-DesignFinding -Class 'PinAncestry' -Subject $ref.Id -Detail "MirroredAt '$mirroredAt' is not an ancestor of HEAD" -Blocking $false)) }
            'Unresolvable' { $couldNotEvaluate.Add((New-CouldNotEvaluate -Reason 'ShallowCheckout' -Detail "ancestry of '$mirroredAt' could not be resolved for $($ref.Id) - no history for merge-base")) }
        }
    }

    [pscustomobject]@{ Reported = @($reported); CouldNotEvaluate = @($couldNotEvaluate) }
}

# ---------------------------------------------------------------------------------------------
# The freeze gate. While design/FROZEN.md exists, every blocking class is downgraded to
# reported, the count downgraded is stated, and the marker's Frozen because / Lifts when lines
# are reproduced verbatim (AGENTS.md § "The design freeze"; S5.8). Exit 2 still stands.
# ---------------------------------------------------------------------------------------------
function Get-FreezeMarker {
    param([Parameter(Mandatory)][string] $RepoPath)

    $markerPath = Join-Path $RepoPath 'design/FROZEN.md'
    if (-not (Test-Path -LiteralPath $markerPath)) { return $null }

    $text = Get-Content -LiteralPath $markerPath
    $because = ($text | Where-Object { $_ -match '^Frozen because:' }) | Select-Object -First 1
    $lifts = ($text | Where-Object { $_ -match '^Lifts when:' }) | Select-Object -First 1

    [pscustomobject]@{
        FrozenBecause = if ($because) { $because } else { '(Frozen because: line not found in design/FROZEN.md)' }
        LiftsWhen     = if ($lifts) { $lifts } else { '(Lifts when: line not found in design/FROZEN.md)' }
    }
}

# ---------------------------------------------------------------------------------------------
# The main entry point.
# ---------------------------------------------------------------------------------------------
function Invoke-DesignStateCheck {
    param([Parameter(Mandatory)][string] $RepoPath, [string] $Repository)

    $contractPath = Join-Path $RepoPath 'design/20-contract.md'
    $classListResult = Test-ClassListAgreement -ContractPath $contractPath
    $invariantSet = Get-ContractInvariantIds -ContractPath $contractPath

    $graph = Read-DesignStateGraph -Path $RepoPath

    $couldNotEvaluate = [System.Collections.Generic.List[object]]::new()
    if ($classListResult.CouldNotEvaluate) { $couldNotEvaluate.Add($classListResult.CouldNotEvaluate) }
    if ($invariantSet.Failure) {
        $couldNotEvaluate.Add((New-CouldNotEvaluate -Reason 'ContractListUnreadable' -Detail "$($invariantSet.Failure): $contractPath; UnrecordedArtifact's invariant half is uncomputed, not clean"))
    }

    $blockingFindings = [System.Collections.Generic.List[object]]::new()
    if ($classListResult.Finding) { $blockingFindings.Add($classListResult.Finding) }

    foreach ($f in $graph.Failures) {
        $couldNotEvaluate.Add((New-CouldNotEvaluate -Reason 'RecordUnparseable' -Detail "$($f.Path):$($f.Line): $($f.Text)"))
    }

    if ($graph.Root -eq '' -or $graph.Records.Count -eq 0) {
        $couldNotEvaluate.Add((New-CouldNotEvaluate -Reason 'StateSetAbsent' -Detail 'design/state/ is missing or holds zero records'))
        return New-DesignStateResult -Findings @() -Reported @() -CouldNotEvaluate @($couldNotEvaluate) -ExitCode 2 -LargestClosure $null -ReportLines @('StateSetAbsent: nothing to check.')
    }

    $records = @($graph.Records)
    $byId = @{}
    foreach ($r in $records) {
        if (-not $byId.ContainsKey($r.Id)) { $byId[$r.Id] = $r }
    }

    $reportedFindings = [System.Collections.Generic.List[object]]::new()

    $blockingFindings.AddRange((Test-UnresolvedId -ById $byId -Records $records))
    $blockingFindings.AddRange((Test-AnchorMissing -Records $records -RepoPath $RepoPath))
    $blockingFindings.AddRange((Test-OwnerMismatch -Records $records))
    $blockingFindings.AddRange((Test-UnrecordedArtifact -Records $records -RepoPath $RepoPath -InvariantIds $invariantSet.Ids))
    $blockingFindings.AddRange((Test-RecordIdCollision -Records $records))
    $blockingFindings.AddRange((Test-DecisionAnchors -Records $records -LogPath (Join-Path $RepoPath 'design/90-decisions.md')))
    $blockingFindings.AddRange((Test-EnforcementUnevidenced -Records $records))

    $globResult = Test-GlobDisagreement -RepoPath $RepoPath -ContractPath $contractPath
    if ($globResult.CouldNotEvaluate) { $couldNotEvaluate.Add($globResult.CouldNotEvaluate) }
    $blockingFindings.AddRange($globResult.Findings)

    $regionFiles = @((Get-DocumentGlobFiles -RepoPath $RepoPath) + (Get-CommandGlobFiles -RepoPath $RepoPath) | Sort-Object -Unique)
    $regionResult = Get-MarkedRegions -RepoPath $RepoPath -Files $regionFiles
    $blockingFindings.AddRange($regionResult.Findings)
    $blockingFindings.AddRange((Test-RegionFormCollision -Inventory $regionResult.Inventory))

    $projector = Invoke-Projector -RepoPath $RepoPath
    if (-not $projector.Ran) {
        $couldNotEvaluate.Add((New-CouldNotEvaluate -Reason 'ProjectorFailed' -Detail "$($projector.Detail); ProjectionStale is uncomputed, not clean"))
    } else {
        # S7.9. A working projector's -DryRun regions are compared, CRLF-normalised, against the
        # tree's own copy of each region. Reporting clean here would be the I19/I20 pass this
        # design forbids only when the projector itself could not run; once it can, "regenerate
        # and compare" is exactly what this class exists to do.
        $blockingFindings.AddRange((Test-ProjectionStale -Regions $projector.Regions -RepoPath $RepoPath))
    }

    $budget = Test-ClosureBudget -Records $records -ById $byId -RepoPath $RepoPath
    $blockingFindings.AddRange($budget.Findings)

    $tracker = Test-TrackerClasses -Records $records -RepoPath $RepoPath -Repository $Repository
    $reportedFindings.AddRange($tracker.Reported)
    foreach ($cne in $tracker.CouldNotEvaluate) { $couldNotEvaluate.Add($cne) }

    $freeze = Get-FreezeMarker -RepoPath $RepoPath
    $downgraded = 0
    $finalFindings = [System.Collections.Generic.List[object]]::new()
    $finalReported = [System.Collections.Generic.List[object]]::new($reportedFindings)

    if ($freeze) {
        foreach ($f in $blockingFindings) {
            $finalReported.Add($f)
            $downgraded++
        }
    } else {
        foreach ($f in $blockingFindings) { $finalFindings.Add($f) }
    }

    $reportLines = [System.Collections.Generic.List[string]]::new()
    if ($budget.Largest) {
        $reportLines.Add("Largest closure: $($budget.Largest.Unit), $($budget.Largest.Bytes) bytes (ceiling $($script:ClosureBudgetBytes)), largest contributor $($budget.Largest.LargestContributor)")
    }
    if ($freeze) {
        $reportLines.Add("Freeze active: $downgraded blocking finding(s) downgraded to reported.")
        $reportLines.Add($freeze.FrozenBecause)
        $reportLines.Add($freeze.LiftsWhen)
    }

    $exitCode = if ($couldNotEvaluate.Count -gt 0) { 2 } elseif ($finalFindings.Count -gt 0) { 1 } else { 0 }

    New-DesignStateResult -Findings @($finalFindings) -Reported @($finalReported) -CouldNotEvaluate @($couldNotEvaluate) -ExitCode $exitCode -LargestClosure $budget.Largest -ReportLines @($reportLines) -DowngradedCount $downgraded
}

function Write-DesignStateReport {
    param([Parameter(Mandatory)] $Result)

    Write-Host "Findings ($($Result.Findings.Count)):"
    foreach ($f in $Result.Findings) { Write-Host "  [$($f.Class)] $($f.Subject): $($f.Detail)" }

    Write-Host "Reported ($($Result.Reported.Count)):"
    foreach ($f in $Result.Reported) { Write-Host "  [$($f.Class)] $($f.Subject): $($f.Detail)" }

    Write-Host "Could not evaluate ($($Result.CouldNotEvaluate.Count)):"
    foreach ($c in $Result.CouldNotEvaluate) { Write-Host "  [$($c.Reason)] $($c.Detail)" }

    foreach ($line in $Result.ReportLines) { Write-Host $line }

    Write-Host "Exit code: $($Result.ExitCode)"
}

# Guards the invocation so this script's tests can dot-source it - the same shape
# Test-DesignDrift.ps1, Wait-PullRequestCheck.ps1 and Read-DesignState.ps1 already use.
if ($MyInvocation.InvocationName -ne '.') {
    $result = Invoke-DesignStateCheck -RepoPath $Path -Repository $Repository
    if (-not $Quiet) { Write-DesignStateReport -Result $result }
    $result
    exit $result.ExitCode
}
