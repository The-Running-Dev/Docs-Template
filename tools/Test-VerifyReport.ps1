#Requires -Version 7.0
<#
.SYNOPSIS
    Validates .claude/verify-report.json - the structured artifact /verify writes - before its
    contents are trusted to become a pull request's Verified section.

.DESCRIPTION
    Same pattern as Test-DesignDrift.ps1 (AGENTS.md, "structured artifact plus deterministic
    validator"), ported to a second agent output: /verify's gate report. verify.md's own report
    is currently free-form prose that /pr copies "verbatim" into a PR description - which means
    the honesty rules in AGENTS.md's Verification section ("never write all checks pass unless
    every gate is in the first list", "quote failures, a summary of a failure is a claim about
    a failure", "the did-not-run list goes in word for word, including the reason") are enforced
    by nothing but the agent re-reading its own prose. This script makes three of those rules
    mechanical instead of asserted:

      - every gate has exactly one outcome, from a fixed vocabulary (Passed/Failed/DidNotRun) -
        a typo'd status is not silently dropped from every list, it is a validation failure.
      - a Failed gate must carry actual output, not a one-word summary - "detail" must be
        present and long enough to plausibly be pasted output rather than a label.
      - a DidNotRun gate must carry a reason - "why: tool missing, Docker down, no such
        script" is the report table's own words, and an empty reason fails validation.

    It does not decide what the gates are or whether a gate should have passed - that is
    /verify's judgement, same division as Test-DesignDrift.ps1 not deciding which side of a
    drift is correct. It only refuses to let a malformed report reach a PR body unnoticed.

    Exit codes: 0 Valid, 1 Invalid - the report parses but breaks an invariant, 2 NotEvaluated -
    the file is missing or is not readable JSON at all, so no invariant could even be checked.
    NotEvaluated takes precedence the same way Test-DesignDrift.ps1's does: a run that could not
    read the artifact has nothing to say about whether it is valid, and reporting Invalid or
    Valid either one would be inventing an answer. Never prompts.

.PARAMETER Path
    Path to the verify report. Defaults to .claude/verify-report.json beside this script's repo
    root.

.PARAMETER Quiet
    Suppresses the human-readable report only. The result object is always emitted.

.EXAMPLE
    pwsh ./tools/Test-VerifyReport.ps1
#>
[CmdletBinding()]
param(
    [string] $Path,
    [switch] $Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:KnownStatuses = @('Passed', 'Failed', 'DidNotRun')
# Below this many characters, a "detail" reads as a label ("failed", "broken") rather than
# pasted output. Not a claim that longer text IS the real output - only that shorter text
# provably is not (AGENTS.md, "quote failures... a summary of a failure is a claim about one").
$script:MinDetailLength = 15

function New-ReportResult {
    param(
        [string]   $State,
        [object[]] $Findings = @(),
        [object[]] $Failures = @(),
        [int]      $GateCount = 0
    )
    [pscustomobject]@{
        State     = $State
        Findings  = @($Findings)
        Failures  = @($Failures)
        GateCount = $GateCount
    }
}

function New-Finding {
    param([string]$Kind, [string]$Gate, [string]$Detail)
    [pscustomobject]@{ Kind = $Kind; Gate = $Gate; Detail = $Detail }
}

function New-Failure {
    param([string]$Reason, [string]$Detail)
    [pscustomobject]@{ Reason = $Reason; Detail = $Detail }
}

function Get-VerifyReportDocument {
    param([Parameter(Mandatory)][string] $Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]@{
            Report  = $null
            Failure = (New-Failure -Reason 'ReportMissing' -Detail $Path)
        }
    }

    $raw = Get-Content -LiteralPath $Path -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return [pscustomobject]@{
            Report  = $null
            Failure = (New-Failure -Reason 'ReportEmpty' -Detail $Path)
        }
    }

    try {
        $parsed = $raw | ConvertFrom-Json
    } catch {
        return [pscustomobject]@{
            Report  = $null
            Failure = (New-Failure -Reason 'ReportUnreadable' -Detail $_.Exception.Message)
        }
    }

    [pscustomobject]@{ Report = $parsed; Failure = $null }
}

<#
    The one function that reads meaning out of the parsed object, kept separate from file I/O
    so tests can hand it an in-memory object the same way Test-DesignDrift.Tests.ps1 hands
    Invoke-DriftCheck a fixture path.
#>
function Invoke-VerifyReportCheck {
    param([Parameter(Mandatory)] $Report)

    $findings = [System.Collections.Generic.List[object]]::new()
    $failures = [System.Collections.Generic.List[object]]::new()

    if (-not ($Report.PSObject.Properties.Name -contains 'gates')) {
        $failures.Add((New-Failure -Reason 'NoGatesProperty' -Detail 'report has no "gates" property'))
        return New-ReportResult -State 'NotEvaluated' -Failures $failures
    }

    $gates = @($Report.gates)
    if ($gates.Count -eq 0) {
        $findings.Add((New-Finding -Kind 'NoGates' -Gate '' -Detail 'gates array is empty'))
    }

    $seenNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($gate in $gates) {
        $name = if ($gate.PSObject.Properties.Name -contains 'name') { [string]$gate.name } else { $null }
        if ([string]::IsNullOrWhiteSpace($name)) {
            $findings.Add((New-Finding -Kind 'EmptyName' -Gate '(unnamed)' -Detail 'gate has no name'))
            continue
        }

        if (-not $seenNames.Add($name)) {
            $findings.Add((New-Finding -Kind 'DuplicateGate' -Gate $name -Detail 'gate name appears more than once'))
        }

        $status = if ($gate.PSObject.Properties.Name -contains 'status') { [string]$gate.status } else { $null }
        if ([string]::IsNullOrWhiteSpace($status) -or $status -cnotin $script:KnownStatuses) {
            $findings.Add((New-Finding -Kind 'UnknownStatus' -Gate $name -Detail "status: '$status'"))
            continue
        }

        $detail = if ($gate.PSObject.Properties.Name -contains 'detail') { [string]$gate.detail } else { $null }
        $reason = if ($gate.PSObject.Properties.Name -contains 'reason') { [string]$gate.reason } else { $null }

        if ($status -eq 'Failed') {
            if ([string]::IsNullOrWhiteSpace($detail)) {
                $findings.Add((New-Finding -Kind 'MissingDetail' -Gate $name -Detail 'Failed gate has no detail'))
            } elseif ($detail.Trim().Length -lt $script:MinDetailLength) {
                $findings.Add((New-Finding -Kind 'TrivialDetail' -Gate $name -Detail "detail too short to be pasted output: '$detail'"))
            }
        }

        if ($status -eq 'DidNotRun' -and [string]::IsNullOrWhiteSpace($reason)) {
            $findings.Add((New-Finding -Kind 'MissingReason' -Gate $name -Detail 'DidNotRun gate has no reason'))
        }
    }

    $state = if ($failures.Count -gt 0) { 'NotEvaluated' }
             elseif ($findings.Count -gt 0) { 'Invalid' }
             else { 'Valid' }

    New-ReportResult -State $state -Findings $findings -Failures $failures -GateCount $gates.Count
}

function Get-VerifyReportExitCode {
    param([string] $State)
    switch ($State) {
        'Valid'        { 0 }
        'Invalid'      { 1 }
        'NotEvaluated' { 2 }
        default        { throw "Unknown verify-report state: $State" }
    }
}

function Write-VerifyReportResult {
    param([Parameter(Mandatory)][object] $Result)

    Write-Host "Gates in report: $($Result.GateCount)"
    Write-Host "Findings: $($Result.Findings.Count)    Could not evaluate: $($Result.Failures.Count)"

    foreach ($f in $Result.Findings) {
        Write-Host "  [$($f.Kind)] $($f.Gate) - $($f.Detail)"
    }
    foreach ($f in $Result.Failures) {
        Write-Host "  [$($f.Reason)] $($f.Detail)"
    }

    switch ($Result.State) {
        'Valid'        { Write-Host 'Report is valid.' }
        'Invalid'      { Write-Host 'Report is malformed. Do not copy it into a pull request.' }
        'NotEvaluated' { Write-Host 'Incomplete: the report could not be read at all. This is NOT a valid result.' }
    }
}

# Same dot-source guard as Test-DesignDrift.ps1: lets this script's tests define every function
# above in the caller's scope without exiting the test runner's process.
if ($MyInvocation.InvocationName -ne '.') {
    if (-not $Path) {
        $Path = Join-Path (Split-Path -Parent $PSScriptRoot) '.claude/verify-report.json'
    }

    $doc = Get-VerifyReportDocument -Path $Path
    if ($doc.Failure) {
        $result = New-ReportResult -State 'NotEvaluated' -Failures @($doc.Failure)
    } else {
        $result = Invoke-VerifyReportCheck -Report $doc.Report
    }

    if (-not $Quiet) { Write-VerifyReportResult -Result $result }
    $result
    exit (Get-VerifyReportExitCode -State $result.State)
}
