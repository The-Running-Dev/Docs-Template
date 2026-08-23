#Requires -Version 7.0
#Requires -Modules Pester

<#
  Test-VerifyReport.ps1 exits the process on every path (0/1/2), same hazard
  Test-DesignDrift.Tests.ps1 documents for its own script. Dot-sourcing defines its functions
  here and skips the exit-calling wrapper; Invoke-VerifyReportCheck is called directly against
  an in-memory object (ConvertFrom-Json of a here-string), the same way Invoke-DriftCheck is
  called against a fixture path in that file. Get-VerifyReportExitCode is a pure state->code
  map tested alone.
#>

BeforeAll {
    $script:ScriptPath = Join-Path $PSScriptRoot 'Test-VerifyReport.ps1'
    $script:PreDotSourceErrorActionPreference = $ErrorActionPreference
    . $script:ScriptPath

    function New-Report {
        param([Parameter(Mandatory)][string] $Json)
        $Json | ConvertFrom-Json
    }
}

AfterAll {
    $ErrorActionPreference = $script:PreDotSourceErrorActionPreference
    Set-StrictMode -Off
}

Describe 'Test-VerifyReport' {

    Context 'well-formed reports' {

        It 'a Passed gate needs no detail, Valid, exit 0' {
            $report = New-Report -Json '{"generated":"2026-08-12","gates":[{"name":"Pester","status":"Passed"}]}'

            $r = Invoke-VerifyReportCheck -Report $report

            $r.State | Should -Be 'Valid'
            $r.Findings.Count | Should -Be 0
            $r.GateCount | Should -Be 1
            Get-VerifyReportExitCode -State $r.State | Should -Be 0
        }

        It 'a Failed gate with real pasted output is Valid' {
            $report = New-Report -Json '{"gates":[{"name":"npm test","status":"Failed","detail":"Expected 200, got 500 at line 42 of api.test.js"}]}'

            (Invoke-VerifyReportCheck -Report $report).State | Should -Be 'Valid'
        }

        It 'a DidNotRun gate with a stated reason is Valid' {
            $report = New-Report -Json '{"gates":[{"name":"docs.ps1","status":"DidNotRun","reason":"Docker unavailable"}]}'

            (Invoke-VerifyReportCheck -Report $report).State | Should -Be 'Valid'
        }

        It 'several gates with distinct names and valid outcomes together are Valid' {
            $report = New-Report -Json '{"gates":[
                {"name":"Pester","status":"Passed"},
                {"name":"lint","status":"Failed","detail":"3 errors: unused var x at line 9, missing semi at line 22"},
                {"name":"docs.ps1","status":"DidNotRun","reason":"Docker unavailable"}
            ]}'

            $r = Invoke-VerifyReportCheck -Report $report
            $r.State | Should -Be 'Valid'
            $r.GateCount | Should -Be 3
        }
    }

    Context 'malformed reports - each rejected for a stated reason' {

        It 'an unknown status is rejected rather than silently dropped from every list' {
            $report = New-Report -Json '{"gates":[{"name":"Pester","status":"Skipped"}]}'

            $r = Invoke-VerifyReportCheck -Report $report

            $r.State | Should -Be 'Invalid'
            $r.Findings.Kind | Should -Contain 'UnknownStatus'
            Get-VerifyReportExitCode -State $r.State | Should -Be 1
        }

        It 'a Failed gate with no detail is rejected' {
            $report = New-Report -Json '{"gates":[{"name":"npm test","status":"Failed"}]}'

            $r = Invoke-VerifyReportCheck -Report $report

            $r.State | Should -Be 'Invalid'
            $r.Findings.Kind | Should -Contain 'MissingDetail'
        }

        It 'a Failed gate whose detail is a one-word label, not pasted output, is rejected' {
            $report = New-Report -Json '{"gates":[{"name":"npm test","status":"Failed","detail":"broken"}]}'

            $r = Invoke-VerifyReportCheck -Report $report

            $r.State | Should -Be 'Invalid'
            $r.Findings.Kind | Should -Contain 'TrivialDetail'
        }

        It 'a DidNotRun gate with no reason is rejected' {
            $report = New-Report -Json '{"gates":[{"name":"docs.ps1","status":"DidNotRun"}]}'

            $r = Invoke-VerifyReportCheck -Report $report

            $r.State | Should -Be 'Invalid'
            $r.Findings.Kind | Should -Contain 'MissingReason'
        }

        It 'two gates sharing a name is rejected - one outcome would be silently lost' {
            $report = New-Report -Json '{"gates":[{"name":"Pester","status":"Passed"},{"name":"Pester","status":"Failed","detail":"the second run disagreed with the first, full trace attached"}]}'

            $r = Invoke-VerifyReportCheck -Report $report

            $r.State | Should -Be 'Invalid'
            $r.Findings.Kind | Should -Contain 'DuplicateGate'
        }

        It 'a gate with no name is rejected' {
            $report = New-Report -Json '{"gates":[{"status":"Passed"}]}'

            $r = Invoke-VerifyReportCheck -Report $report

            $r.State | Should -Be 'Invalid'
            $r.Findings.Kind | Should -Contain 'EmptyName'
        }

        It 'an empty gates array is rejected - a report claiming nothing was checked is not a report' {
            $report = New-Report -Json '{"gates":[]}'

            $r = Invoke-VerifyReportCheck -Report $report

            $r.State | Should -Be 'Invalid'
            $r.Findings.Kind | Should -Contain 'NoGates'
        }
    }

    Context 'incomplete runs never report Valid' {

        It 'a report with no gates property at all is NotEvaluated, exit 2, never Invalid' {
            $report = New-Report -Json '{"generated":"2026-08-12"}'

            $r = Invoke-VerifyReportCheck -Report $report

            $r.State | Should -Be 'NotEvaluated'
            $r.Failures.Reason | Should -Contain 'NoGatesProperty'
            Get-VerifyReportExitCode -State $r.State | Should -Be 2
        }

        It 'a missing report file is NotEvaluated' {
            $doc = Get-VerifyReportDocument -Path (Join-Path $TestDrive 'nothing-here.json')

            $doc.Failure.Reason | Should -Be 'ReportMissing'
        }

        It 'a file that is not valid JSON is NotEvaluated, not Invalid' {
            $path = Join-Path $TestDrive 'bad.json'
            Set-Content -LiteralPath $path -Value '{ this is not json' -Encoding utf8

            $doc = Get-VerifyReportDocument -Path $path

            $doc.Failure.Reason | Should -Be 'ReportUnreadable'
        }
    }

    Context 'exit code map' {

        It 'maps each state, and refuses an unknown one rather than defaulting to 0' {
            Get-VerifyReportExitCode -State 'Valid'        | Should -Be 0
            Get-VerifyReportExitCode -State 'Invalid'      | Should -Be 1
            Get-VerifyReportExitCode -State 'NotEvaluated' | Should -Be 2
            { Get-VerifyReportExitCode -State 'Something' } | Should -Throw
        }
    }
}
