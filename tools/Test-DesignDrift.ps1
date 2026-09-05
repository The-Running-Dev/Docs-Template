#Requires -Version 7.0
<#
.SYNOPSIS
    Reports drift between design/30-slices.md and the GitHub tracker, and changes neither.

.DESCRIPTION
    Two comparisons that a model should never do by eye, because both are set arithmetic over
    files and both fail silently when done from memory (AGENTS.md, "What should stop being
    model work" - the red row):

      1. Criterion ids. Every `S<n>.<m>` under a slice's `Acceptance:` lines, against every
         `S<n>.<m>` checkbox in that slice's issue. Reworded criteria are not drift; an added,
         removed, or renumbered id is. A renumber is the finding that matters, because an
         existing ticked checkbox then refers to something else.

      2. Pin ancestry. Every `design/30-slices.md § S<n> @ <sha>` pin in an issue's agent
         block, against `git merge-base --is-ancestor <sha> HEAD`. This is the check
         design/90-decisions.md (2026-08-10) records as having been claimed done and not
         been: fourteen of seventeen issues cited a commit that was not an ancestor of main,
         and nothing in the repository could tell anyone that.

    Read-only on both sides, by contract (I13). Which side of a drift is wrong is the user's
    call, so this establishes only that the two disagree.

    Exit codes: 0 no drift, 1 drift found, 2 could not evaluate. **2 takes precedence over 1**
    - a run that found drift *and* failed to complete a comparison is an incomplete run, and
    reporting it as a finished one is exactly the failure I12 forbids. Never prompts.

.PARAMETER SlicesPath
    Path to the slices document. Defaults to design/30-slices.md beside this script's repo root.

.PARAMETER Repository
    owner/repo. Defaults to the current git remote, via gh's own resolution.

.PARAMETER Quiet
    Suppresses the human-readable report only. The result object is always emitted.

.EXAMPLE
    pwsh ./tools/Test-DesignDrift.ps1
#>
[CmdletBinding()]
param(
    [string] $SlicesPath,
    [string] $Repository,
    [switch] $Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Both comparisons below read a native command's *exit code* as their answer:
# `git merge-base --is-ancestor` returns 1 to mean "not an ancestor", which is a finding, not
# an error. On PowerShell 7.3+ this preference defaults to $true, which would turn that 1 into
# a terminating error under $ErrorActionPreference = 'Stop' and report every stale pin as
# unresolvable instead. Assigning it is inert on versions that predate it.
$PSNativeCommandUseErrorActionPreference = $false

function New-DriftResult {
    param(
        [string]   $State,
        [object[]] $Findings = @(),
        [object[]] $Failures = @(),
        [int]      $SlicesCompared = 0
    )
    [pscustomobject]@{
        State          = $State
        Findings       = @($Findings)
        Failures       = @($Failures)
        SlicesCompared = $SlicesCompared
    }
}

function New-Finding {
    param([string]$Kind, [string]$Slice, [string]$Detail, [int]$Issue)
    [pscustomobject]@{ Kind = $Kind; Slice = $Slice; Detail = $Detail; Issue = $Issue }
}

function New-Failure {
    param([string]$Reason, [string]$Detail)
    [pscustomobject]@{ Reason = $Reason; Detail = $Detail }
}

<#
    Criterion ids are read only from lines under a `## S<n>` heading, never from the whole
    file. Prose cites ids too - "exercised by S1.10" appears in this document's own Contract
    questions section - and a whole-file regex would count those as criteria that exist.
#>
function Get-SliceCriteria {
    param([Parameter(Mandatory)][string] $Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]@{
            Slices  = @{}
            Landed  = @()
            Failure = (New-Failure -Reason 'SlicesDocMissing' -Detail $Path)
        }
    }

    $slices  = @{}
    $landed  = [System.Collections.Generic.List[int]]::new()
    $current = $null

    foreach ($line in (Get-Content -LiteralPath $Path)) {
        if ($line -match '^##\s') {
            # A new second-level heading always ends the previous slice's body, so an
            # Acceptance line can never be attributed across a section boundary.
            $current = if ($line -match '^##\s+S(?<n>\d+)\b') { [int]$Matches['n'] } else { $null }
            if ($null -ne $current -and -not $slices.ContainsKey($current)) {
                $slices[$current] = [System.Collections.Generic.List[string]]::new()
            }
            continue
        }

        if ($line -match '^\|\s*\*\*S(?<n>\d+)\*\*\s*\|') {
            $landed.Add([int]$Matches['n'])
            continue
        }

        if ($null -ne $current -and $line -match '^\s*-\s+S(?<n>\d+)\.(?<m>\d+)\b') {
            if ([int]$Matches['n'] -ne $current) {
                # An id numbered for a different slice than the section it sits in. Reported
                # rather than silently filed under either, because it is a defect in the doc.
                if (-not $slices.ContainsKey(-1)) {
                    $slices[-1] = [System.Collections.Generic.List[string]]::new()
                }
                $slices[-1].Add("S$($Matches['n']).$($Matches['m']) (found under S$current)")
                continue
            }
            $slices[$current].Add("S$($Matches['n']).$($Matches['m'])")
        }
    }

    [pscustomobject]@{
        Slices  = $slices
        Landed  = @($landed)
        Failure = $null
    }
}

function Get-IssueCriteria {
    param([string] $Body)
    if ([string]::IsNullOrWhiteSpace($Body)) { return @() }

    $ids = [System.Collections.Generic.List[string]]::new()
    foreach ($line in ($Body -split "`r?`n")) {
        if ($line -match '^\s*-\s*\[[ xX]\]\s*\*{0,2}S(?<n>\d+)\.(?<m>\d+)\*{0,2}') {
            $ids.Add("S$($Matches['n']).$($Matches['m'])")
        }
    }
    @($ids)
}

function Get-IssuePin {
    param([string] $Body)
    if ([string]::IsNullOrWhiteSpace($Body)) { return $null }
    # The backtick after `.md` is not optional decoration: track.md's pin format is
    # `design/30-slices.md` § S3 @ `a1b2c3d`, so the path is code-fenced and the closing
    # fence sits between `.md` and the section mark. Omitting it here matched no real issue
    # at all - caught by the first CI run of this file's tests, not by reading it.
    if ($Body -match '30-slices\.md`?\s*§\s*S(?<n>\d+)\s*@\s*`?(?<sha>[0-9a-fA-F]{7,40})`?') {
        return [pscustomobject]@{ Slice = [int]$Matches['n']; Sha = $Matches['sha'] }
    }
    $null
}

function Get-TrackerIssue {
    param([string] $Repository)

    $ghArgs = @('issue', 'list', '--state', 'all', '--limit', '200', '--json', 'number,title,state,body')
    if ($Repository) { $ghArgs += @('-R', $Repository) }

    try {
        $json = & gh @ghArgs 2>$null
        if ($LASTEXITCODE -ne 0) {
            return [pscustomobject]@{ Issues = @(); Failure = (New-Failure -Reason 'GhUnavailable' -Detail "gh exited $LASTEXITCODE") }
        }
    } catch {
        return [pscustomobject]@{ Issues = @(); Failure = (New-Failure -Reason 'GhUnavailable' -Detail $_.Exception.Message) }
    }

    if ([string]::IsNullOrWhiteSpace(($json -join ''))) {
        return [pscustomobject]@{ Issues = @(); Failure = (New-Failure -Reason 'GhUnavailable' -Detail 'gh returned no output') }
    }

    try {
        $parsed = ($json -join "`n") | ConvertFrom-Json
    } catch {
        return [pscustomobject]@{ Issues = @(); Failure = (New-Failure -Reason 'TrackerUnreadable' -Detail $_.Exception.Message) }
    }

    [pscustomobject]@{ Issues = @($parsed); Failure = $null }
}

<#
    Three outcomes, not two. An unknown object - a shallow clone, or a commit that was never
    fetched - is not evidence the pin is stale, and folding it into NotAncestor would invent a
    finding. It is the absence of an answer, which I12 requires be reported as such.
#>
function Test-CommitIsAncestor {
    param([Parameter(Mandatory)][string] $Sha)

    try {
        & git merge-base --is-ancestor $Sha HEAD 2>$null | Out-Null
        switch ($LASTEXITCODE) {
            0       { 'Ancestor' }
            1       { 'NotAncestor' }
            default { 'Unresolvable' }
        }
    } catch {
        'Unresolvable'
    }
}

function Invoke-DriftCheck {
    param([string] $SlicesPath, [string] $Repository)

    $findings = [System.Collections.Generic.List[object]]::new()
    $failures = [System.Collections.Generic.List[object]]::new()

    $doc = Get-SliceCriteria -Path $SlicesPath
    if ($doc.Failure) {
        $failures.Add($doc.Failure)
        return New-DriftResult -State 'NotEvaluated' -Failures $failures
    }

    if ($doc.Slices.ContainsKey(-1)) {
        foreach ($stray in $doc.Slices[-1]) {
            $failures.Add((New-Failure -Reason 'UnparseableCriterion' -Detail $stray))
        }
        $doc.Slices.Remove(-1)
    }

    $tracker = Get-TrackerIssue -Repository $Repository
    if ($tracker.Failure) {
        $failures.Add($tracker.Failure)
        return New-DriftResult -State 'NotEvaluated' -Failures $failures
    }

    $landed = @($doc.Landed)
    $compared = 0

    foreach ($number in ($doc.Slices.Keys | Sort-Object)) {
        $docIds = @($doc.Slices[$number] | Sort-Object -Unique)
        $issue  = $tracker.Issues | Where-Object { $_.title -match "^S$number\b" } | Select-Object -First 1

        if (-not $issue) {
            $findings.Add((New-Finding -Kind 'NoIssue' -Slice "S$number" -Detail 'slice has no issue; /track opens one' -Issue 0))
            continue
        }

        $compared++
        $issueIds = @(Get-IssueCriteria -Body $issue.body | Sort-Object -Unique)

        foreach ($id in ($docIds | Where-Object { $_ -notin $issueIds })) {
            $findings.Add((New-Finding -Kind 'InDocNotIssue' -Slice "S$number" -Detail $id -Issue $issue.number))
        }
        foreach ($id in ($issueIds | Where-Object { $_ -notin $docIds })) {
            $findings.Add((New-Finding -Kind 'InIssueNotDoc' -Slice "S$number" -Detail $id -Issue $issue.number))
        }
    }

    # Landed slices carry no criteria in the doc by design - their bodies were retired once
    # their issues closed (design/30-slices.md, "How this document is kept"). Comparing ids
    # for one would report every criterion as removed, so only the pin is checked.
    foreach ($issue in $tracker.Issues) {
        $pin = Get-IssuePin -Body $issue.body
        if (-not $pin) { continue }

        switch (Test-CommitIsAncestor -Sha $pin.Sha) {
            'NotAncestor'  { $findings.Add((New-Finding -Kind 'PinNotAncestor' -Slice "S$($pin.Slice)" -Detail $pin.Sha -Issue $issue.number)) }
            'Unresolvable' { $failures.Add((New-Failure -Reason 'PinUnresolvable' -Detail "#$($issue.number) pins $($pin.Sha), which this clone cannot resolve")) }
        }
    }

    if ($landed.Count -gt 0) {
        Write-Verbose "Landed slices not compared on ids: $($landed -join ', ')"
    }

    $state = if ($failures.Count -gt 0) { 'NotEvaluated' }
             elseif ($findings.Count -gt 0) { 'Drifted' }
             else { 'Clean' }

    New-DriftResult -State $state -Findings $findings -Failures $failures -SlicesCompared $compared
}

function Get-DriftExitCode {
    param([string] $State)
    switch ($State) {
        'Clean'        { 0 }
        'Drifted'      { 1 }
        'NotEvaluated' { 2 }
        default        { throw "Unknown drift state: $State" }
    }
}

function Write-DriftReport {
    param([Parameter(Mandatory)][object] $Result)

    Write-Host "Slices compared: $($Result.SlicesCompared)"
    Write-Host "Findings: $($Result.Findings.Count)    Could not evaluate: $($Result.Failures.Count)"

    foreach ($f in $Result.Findings) {
        Write-Host "  [$($f.Kind)] $($f.Slice) $($f.Detail)$(if ($f.Issue) { " (#$($f.Issue))" })"
    }
    foreach ($f in $Result.Failures) {
        Write-Host "  [$($f.Reason)] $($f.Detail)"
    }

    switch ($Result.State) {
        'Clean'        { Write-Host 'No drift.' }
        'Drifted'      { Write-Host 'Drift found. Which side is wrong is not this script''s call.' }
        'NotEvaluated' { Write-Host 'Incomplete: at least one comparison did not run. This is NOT a clean result.' }
    }
}

# Guards the exit-calling wrapper so this script's tests can dot-source it instead - that
# defines every function above in the caller's scope, lets Mock intercept `gh` and `git`, and
# skips straight past this block rather than exiting the test runner's own process.
if ($MyInvocation.InvocationName -ne '.') {
    if (-not $SlicesPath) {
        $SlicesPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'design/30-slices.md'
    }
    $result = Invoke-DriftCheck -SlicesPath $SlicesPath -Repository $Repository
    if (-not $Quiet) { Write-DriftReport -Result $result }
    $result
    exit (Get-DriftExitCode -State $result.State)
}
