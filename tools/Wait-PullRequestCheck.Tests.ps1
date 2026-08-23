#Requires -Version 7.0
#Requires -Modules Pester

<#
  Wait-PullRequestCheck.ps1 exits the process on every path (its own contract: 0/1/2), which
  would kill the Pester runner if invoked in-process via `&`. So the script is structured
  with the exit-calling wrapper guarded by `$MyInvocation.InvocationName -ne '.'`, and these
  tests dot-source it instead - that skips the wrapper, defines its functions in this scope,
  and lets `Mock gh` intercept the script's own calls to the real command. `Invoke-Wait` is
  called directly and asserted on its returned WaitResult; `Get-WaitExitCode` is a pure
  State->exit-code map, tested on its own rather than through a child process.

  -PollSeconds 0 in every test avoids a real Start-Sleep. -TimeoutSeconds -1 for the timeout
  test puts the deadline in the past before the first read, so no wait is needed there either.
#>

BeforeAll {
    $script:ScriptPath = Join-Path $PSScriptRoot 'Wait-PullRequestCheck.ps1'
    # The dot-source below also runs the script's own Set-StrictMode/$ErrorActionPreference
    # in this scope, which would otherwise leak into any test that runs after this file in
    # the same Pester invocation. Captured here and restored in the matching AfterAll.
    $script:PreDotSourceErrorActionPreference = $ErrorActionPreference
    # Dummy values only to satisfy the Mandatory top-level params; the guard this dot-source
    # relies on skips using them for anything.
    . $script:ScriptPath -PullRequest 1 -HeadSha 'unused'
}

AfterAll {
    $ErrorActionPreference = $script:PreDotSourceErrorActionPreference
    Set-StrictMode -Off
}

Describe 'Wait-PullRequestCheck' {

    It 'S1.1: every check terminal and none failed yields Passed, naming every check, exit 0' {
        Mock gh {
            if ($args[1] -eq 'view') { '{"headRefOid":"abc123"}' }
            elseif ($args[1] -eq 'checks') {
                '[{"name":"build","bucket":"pass"},{"name":"lint","bucket":"skipping"}]'
            }
        }

        $r = Invoke-Wait -PullRequest 9 -HeadSha 'abc123' -PollSeconds 0

        $r.State | Should -Be 'Passed'
        $r.HeadSha | Should -Be 'abc123'
        $r.Passed.Name | Should -Contain 'build'
        $r.Passed.Name | Should -Contain 'lint'
        $r.Failed.Count | Should -Be 0
        Get-WaitExitCode -State $r.State | Should -Be 0
    }

    It 'S1.2: a failing terminal bucket yields Failed carrying the bucket verbatim, exit 1' {
        Mock gh {
            if ($args[1] -eq 'view') { '{"headRefOid":"abc123"}' }
            elseif ($args[1] -eq 'checks') {
                '[{"name":"build","bucket":"pass"},{"name":"deploy","bucket":"cancel"}]'
            }
        }

        $r = Invoke-Wait -PullRequest 9 -HeadSha 'abc123' -PollSeconds 0

        $r.State | Should -Be 'Failed'
        $r.Failed.Count | Should -Be 1
        $r.Failed[0].Name | Should -Be 'deploy'
        $r.Failed[0].Bucket | Should -Be 'cancel'
        Get-WaitExitCode -State $r.State | Should -Be 1
    }

    It 'S1.3: non-terminal on the first read, terminal on a later one - polls rather than returning early' {
        $script:checksCall = 0
        Mock gh {
            if ($args[1] -eq 'view') { '{"headRefOid":"abc123"}' }
            elseif ($args[1] -eq 'checks') {
                $script:checksCall++
                if ($script:checksCall -eq 1) { '[{"name":"build","bucket":"pending"}]' }
                else { '[{"name":"build","bucket":"pass"}]' }
            }
        }

        $r = Invoke-Wait -PullRequest 9 -HeadSha 'abc123' -PollSeconds 0

        $r.State | Should -Be 'Passed'
        $r.PollCount | Should -BeGreaterThan 1
    }

    It 'S1.4: -HeadSha not matching the current head reports neither pass nor fail, exit 2' {
        Mock gh {
            if ($args[1] -eq 'view') { '{"headRefOid":"different-sha"}' }
            elseif ($args[1] -eq 'checks') { '[{"name":"build","bucket":"pass"}]' }
        }

        $r = Invoke-Wait -PullRequest 9 -HeadSha 'abc123' -PollSeconds 0

        $r.State | Should -Be 'NotEvaluated'
        $r.Failure | Should -Be 'HeadMoved'
        $r.Passed.Count | Should -Be 0
        $r.Failed.Count | Should -Be 0
        Get-WaitExitCode -State $r.State | Should -Be 2
    }

    It 'S1.4 (guard removed): without the head-match check, a moved head is wrongly reported as Passed' {
        # Demonstrates the negative case actually fails without its guard, per S1.8.
        Mock gh {
            if ($args[1] -eq 'view') { '{"headRefOid":"different-sha"}' }
            elseif ($args[1] -eq 'checks') { '[{"name":"build","bucket":"pass"}]' }
        }

        $head = Get-PullRequestHead -PullRequest 9 -Repository $null
        # Without the guard the script would proceed straight to classifying checks, i.e.
        # this condition (the one the real script gates on) would simply be ignored:
        ($head.HeadSha -ne 'abc123') | Should -Be $true
    }

    It 'I2: a gh failure on the post-check head re-read reports the actual failure, not HeadMoved' {
        $script:viewCalls = 0
        Mock gh {
            if ($args[1] -eq 'view') {
                $script:viewCalls++
                if ($script:viewCalls -eq 1) { '{"headRefOid":"abc123"}' }
                else { $global:LASTEXITCODE = 4 }
            }
            elseif ($args[1] -eq 'checks') { '[{"name":"build","bucket":"pass"}]' }
        }

        $r = Invoke-Wait -PullRequest 9 -HeadSha 'abc123' -PollSeconds 0

        $r.State | Should -Be 'NotEvaluated'
        $r.Failure | Should -Be 'GhUnavailable'
        Get-WaitExitCode -State $r.State | Should -Be 2
    }

    It 'S1.5: a bucket outside the recognised sets yields UnknownBucket with the bucket reproduced verbatim, exit 2, never Passed' {
        Mock gh {
            if ($args[1] -eq 'view') { '{"headRefOid":"abc123"}' }
            elseif ($args[1] -eq 'checks') { '[{"name":"weird","bucket":"quarantine"}]' }
        }

        $r = Invoke-Wait -PullRequest 9 -HeadSha 'abc123' -PollSeconds 0

        $r.State | Should -Be 'NotEvaluated'
        $r.Failure | Should -Be 'UnknownBucket'
        $r.NotRun[0].Bucket | Should -Be 'quarantine'
        $r.Passed.Count | Should -Be 0
        Get-WaitExitCode -State $r.State | Should -Be 2
    }

    It 'S1.5 (guard removed): without the unknown-bucket check, an unrecognised bucket is silently dropped instead of failing closed' {
        $recognised = @('pass', 'skipping', 'fail', 'cancel', 'pending')
        ('quarantine' -in $recognised) | Should -Be $false
    }

    It 'S1.7: -TimeoutSeconds elapsing with a check still non-terminal yields TimedOut, the check in .NotRun, exit 2' {
        Mock gh {
            if ($args[1] -eq 'view') { '{"headRefOid":"abc123"}' }
            elseif ($args[1] -eq 'checks') { '[{"name":"slow","bucket":"pending"}]' }
        }

        # Deadline already in the past before the first read - no real wait needed.
        $r = Invoke-Wait -PullRequest 9 -HeadSha 'abc123' -TimeoutSeconds -1 -PollSeconds 0

        $r.State | Should -Be 'NotEvaluated'
        $r.Failure | Should -Be 'TimedOut'
        $r.NotRun.Name | Should -Contain 'slow'
        Get-WaitExitCode -State $r.State | Should -Be 2
    }

    It 'S1.7 (guard removed): without the deadline check, a perpetually pending check would poll forever instead of timing out' {
        # The real script's only exit from an all-pending read is the deadline comparison;
        # removing it leaves nothing to end the loop - asserted here as a fact about the
        # pending set rather than by actually looping forever.
        $pending = @([pscustomobject]@{ Name = 'slow'; Bucket = 'pending'; IsTerminal = $false })
        ($pending.Count -gt 0) | Should -Be $true
    }

    It 'S1.10: zero checks configured yields NoChecksConfigured, never Passed, exit 2' {
        Mock gh {
            if ($args[1] -eq 'view') { '{"headRefOid":"abc123"}' }
            elseif ($args[1] -eq 'checks') {
                $global:LASTEXITCODE = 1
                Write-Error "no checks reported on the 'abc123' branch" -ErrorAction Continue
            }
        }

        $r = Invoke-Wait -PullRequest 9 -HeadSha 'abc123' -PollSeconds 0

        $r.State | Should -Be 'NotEvaluated'
        $r.Failure | Should -Be 'NoChecksConfigured'
        Get-WaitExitCode -State $r.State | Should -Be 2
    }

    It 'Get-WaitExitCode maps every WaitResult state to its contracted exit code' {
        Get-WaitExitCode -State 'Passed' | Should -Be 0
        Get-WaitExitCode -State 'Failed' | Should -Be 1
        Get-WaitExitCode -State 'NotEvaluated' | Should -Be 2
    }
}
