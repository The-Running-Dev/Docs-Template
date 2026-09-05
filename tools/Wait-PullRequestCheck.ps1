#Requires -Version 7.0
<#
.SYNOPSIS
    Waits for a pull request's checks to reach a terminal state against a named head SHA,
    and refuses to report an outcome at all if the head moved while it was watching.

.DESCRIPTION
    Every command that says "confirm the checks are green on the new head SHA" today leaves
    the reader to do that by eye, which is how a stale result gets treated as a fresh one.
    This script is the one place that answer is computed: it polls `gh pr checks`, and if the
    pull request's head ever stops matching -HeadSha - before, during, or after a read - it
    reports NotEvaluated/HeadMoved rather than a pass or fail for a commit that is no longer
    what it evaluated.

    Terminal buckets, from `gh pr checks --help` (gh 2.97.0): "the `bucket` field... categorizes
    the `state` field into `pass`, `fail`, `pending`, `skipping`, or `cancel`." `pending` is the
    only one gh's own docs describe as not yet concluded. `pass` -> Passed and `fail` -> Failed
    are direct. `skipping` -> Passed and `cancel` -> Failed by explicit choice during this
    slice's implementation, mirroring GitHub's own branch-protection treatment (a skipped
    required check commonly satisfies the requirement; a cancelled run does not) - not yet
    recorded in design/90-decisions.md, which this slice does not touch. Any bucket outside
    these five fails closed as UnknownBucket rather than being guessed at.

    Never prompts. Never re-runs a check, merges, resolves, or writes anything - it only reads
    and reports.

.PARAMETER PullRequest
    The pull request number.

.PARAMETER HeadSha
    The commit this call is allowed to report on. Mandatory, with no default: defaulting it to
    the current head would defeat the invariant this script exists to enforce.

.PARAMETER Repository
    owner/repo. Defaults to the current git remote, via gh's own resolution.

.PARAMETER TimeoutSeconds
    How long to keep polling a non-terminal check before giving up. Default 900.

.PARAMETER PollSeconds
    Delay between polls. Default 20.

.PARAMETER Quiet
    Suppresses the progress line only. The WaitResult is always emitted.

.EXAMPLE
    ./tools/Wait-PullRequestCheck.ps1 -PullRequest 42 -HeadSha $sha
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [int]    $PullRequest,
    [Parameter(Mandatory)] [string] $HeadSha,
    [string] $Repository,
    [int]    $TimeoutSeconds = 900,
    [int]    $PollSeconds    = 20,
    [switch] $Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:PassingBuckets    = @('pass', 'skipping')
$script:FailingBuckets    = @('fail', 'cancel')
$script:NonTerminalBucket = 'pending'

function New-CheckRunResult {
    param([string]$Name, [string]$Bucket, [bool]$IsTerminal)
    [pscustomobject]@{ Name = $Name; Bucket = $Bucket; IsTerminal = $IsTerminal }
}

function New-WaitResult {
    param(
        [string]   $State,
        [string]   $HeadSha,
        [object[]] $Passed = @(),
        [object[]] $Failed = @(),
        [object[]] $NotRun = @(),
        [string]   $Failure,
        [int]      $PollCount
    )
    [pscustomobject]@{
        State     = $State
        HeadSha   = $HeadSha
        Passed    = @($Passed)
        Failed    = @($Failed)
        NotRun    = @($NotRun)
        Failure   = $Failure
        PollCount = $PollCount
    }
}

function Get-WaitExitCode {
    <# Pure State->exit-code map, contracted in this script's own param block comment.
       Kept separate so the mapping can be verified without a real process exit. #>
    param([string]$State)
    switch ($State) {
        'Passed'       { 0 }
        'Failed'       { 1 }
        'NotEvaluated' { 2 }
        default        { throw "Unknown WaitResult state: $State" }
    }
}

function Invoke-Gh {
    <# Every gh failure is reported as data on the return object, never thrown - a caller
       here treats every one of the contract's WaitFailure conditions as something to
       report, not an exception that would drop the partial check list. #>
    param([string[]]$Arguments)
    try {
        # Reset first: under Set-StrictMode, reading $LASTEXITCODE before anything in this
        # session has set it is an error, which a mocked `gh` that never touches it would hit.
        $global:LASTEXITCODE = 0
        $output = & gh @Arguments 2>&1
        [pscustomobject]@{ Text = ($output | Out-String); ExitCode = $LASTEXITCODE; CommandFound = $true }
    }
    catch [System.Management.Automation.CommandNotFoundException] {
        [pscustomobject]@{ Text = $_.Exception.Message; ExitCode = -1; CommandFound = $false }
    }
}

function New-GhLookupResult {
    <# Always carries both keys, so a `.Failure` or `.HeadSha`/`.Checks` read under
       Set-StrictMode never trips PropertyNotFoundException on the branch that didn't set it. #>
    param($HeadSha, $Checks, [string]$Failure)
    [pscustomobject]@{ HeadSha = $HeadSha; Checks = $Checks; Failure = $Failure }
}

function Get-PullRequestHead {
    <# .HeadSha set, or .Failure = 'GhUnavailable' | 'PullRequestMissing' #>
    param([int]$PullRequest, [string]$Repository)

    $ghArgs = @('pr', 'view', $PullRequest, '--json', 'headRefOid')
    if ($Repository) { $ghArgs += @('-R', $Repository) }
    $result = Invoke-Gh -Arguments $ghArgs

    if (-not $result.CommandFound) { return New-GhLookupResult -Failure 'GhUnavailable' }
    # gh's own documented convention: exit code 4 means the command requires authentication.
    if ($result.ExitCode -eq 4)    { return New-GhLookupResult -Failure 'GhUnavailable' }
    if ($result.ExitCode -ne 0)    { return New-GhLookupResult -Failure 'PullRequestMissing' }

    New-GhLookupResult -HeadSha ($result.Text | ConvertFrom-Json).headRefOid
}

function Get-PullRequestChecks {
    <# .Checks set, or .Failure = 'GhUnavailable' | 'NoChecksConfigured' | 'PullRequestMissing' #>
    param([int]$PullRequest, [string]$Repository)

    $ghArgs = @('pr', 'checks', $PullRequest, '--json', 'name,bucket')
    if ($Repository) { $ghArgs += @('-R', $Repository) }
    $result = Invoke-Gh -Arguments $ghArgs

    if (-not $result.CommandFound) { return New-GhLookupResult -Failure 'GhUnavailable' }
    if ($result.ExitCode -eq 4)    { return New-GhLookupResult -Failure 'GhUnavailable' }
    if ($result.ExitCode -ne 0) {
        # cli/cli's pkg/cmd/pr/checks (checked at implementation time): populateStatusChecks
        # returns fmt.Errorf("no checks reported on the '%s' branch", ...) when the rollup is
        # empty. Matched by text rather than assumed from the bare exit code, since a checks
        # call can fail for other reasons too.
        if ($result.Text -match 'no checks reported') { return New-GhLookupResult -Failure 'NoChecksConfigured' }
        return New-GhLookupResult -Failure 'PullRequestMissing'
    }

    New-GhLookupResult -Checks @($result.Text | ConvertFrom-Json)
}

function Invoke-Wait {
    param(
        [Parameter(Mandatory)] [int]    $PullRequest,
        [Parameter(Mandatory)] [string] $HeadSha,
        [string] $Repository,
        [int]    $TimeoutSeconds = 900,
        [int]    $PollSeconds    = 20,
        [switch] $Quiet
    )

    $pollCount = 0
    $deadline  = (Get-Date).AddSeconds($TimeoutSeconds)

    while ($true) {
        $pollCount++

        $head = Get-PullRequestHead -PullRequest $PullRequest -Repository $Repository
        if ($head.Failure) {
            return New-WaitResult -State 'NotEvaluated' -HeadSha $HeadSha -Failure $head.Failure -PollCount $pollCount
        }
        if ($head.HeadSha -ne $HeadSha) {
            return New-WaitResult -State 'NotEvaluated' -HeadSha $HeadSha -Failure 'HeadMoved' -PollCount $pollCount
        }

        $checks = Get-PullRequestChecks -PullRequest $PullRequest -Repository $Repository
        if ($checks.Failure) {
            return New-WaitResult -State 'NotEvaluated' -HeadSha $HeadSha -Failure $checks.Failure -PollCount $pollCount
        }

        # I2: re-verified after reading checks, not just before - a push landing mid-read
        # must not let a check list read for the old SHA be reported as this SHA's.
        $headAfter = Get-PullRequestHead -PullRequest $PullRequest -Repository $Repository
        if ($headAfter.Failure) {
            return New-WaitResult -State 'NotEvaluated' -HeadSha $HeadSha -Failure $headAfter.Failure -PollCount $pollCount
        }
        if ($headAfter.HeadSha -ne $HeadSha) {
            return New-WaitResult -State 'NotEvaluated' -HeadSha $HeadSha -Failure 'HeadMoved' -PollCount $pollCount
        }

        $passed  = [System.Collections.Generic.List[object]]::new()
        $failed  = [System.Collections.Generic.List[object]]::new()
        $pending = [System.Collections.Generic.List[object]]::new()
        $unknown = $null

        foreach ($check in $checks.Checks) {
            if ($script:PassingBuckets -contains $check.bucket) {
                $passed.Add((New-CheckRunResult -Name $check.name -Bucket $check.bucket -IsTerminal $true))
            }
            elseif ($script:FailingBuckets -contains $check.bucket) {
                $failed.Add((New-CheckRunResult -Name $check.name -Bucket $check.bucket -IsTerminal $true))
            }
            elseif ($check.bucket -eq $script:NonTerminalBucket) {
                $pending.Add((New-CheckRunResult -Name $check.name -Bucket $check.bucket -IsTerminal $false))
            }
            else {
                $unknown = New-CheckRunResult -Name $check.name -Bucket $check.bucket -IsTerminal $false
                break
            }
        }

        if ($unknown) {
            return New-WaitResult -State 'NotEvaluated' -HeadSha $HeadSha -NotRun @($unknown) -Failure 'UnknownBucket' -PollCount $pollCount
        }

        if ($failed.Count -gt 0) {
            return New-WaitResult -State 'Failed' -HeadSha $HeadSha -Passed @($passed) -Failed @($failed) -NotRun @($pending) -PollCount $pollCount
        }

        if ($pending.Count -eq 0) {
            return New-WaitResult -State 'Passed' -HeadSha $HeadSha -Passed @($passed) -PollCount $pollCount
        }

        if ((Get-Date) -ge $deadline) {
            return New-WaitResult -State 'NotEvaluated' -HeadSha $HeadSha -Passed @($passed) -NotRun @($pending) -Failure 'TimedOut' -PollCount $pollCount
        }

        if (-not $Quiet) {
            Write-Host "Waiting on $($pending.Count) check(s) for $HeadSha (poll $pollCount)..."
        }
        Start-Sleep -Seconds $PollSeconds
    }
}

# Guards the exit-calling wrapper so the script's tests can dot-source it instead - that
# defines every function above in the caller's scope, lets Mock intercept `gh`, and skips
# straight past this block rather than exiting the test runner's own process.
if ($MyInvocation.InvocationName -ne '.') {
    $result = Invoke-Wait -PullRequest $PullRequest -HeadSha $HeadSha -Repository $Repository `
        -TimeoutSeconds $TimeoutSeconds -PollSeconds $PollSeconds -Quiet:$Quiet
    $result
    exit (Get-WaitExitCode -State $result.State)
}
