<#
.SYNOPSIS
    Pester tests for scripts/template/Test-Documentation.ps1 — the documentation gate.

.DESCRIPTION
    Drives the real gate against fixtures under TestDrive:, the same way
    SetupDocs.Tests.ps1 drives the installer, rather than unit-testing its
    internal functions. Both -Path and -SettingsPath are parameters, so a
    fixture needs neither a '.git' marker nor an installed rules file: the
    gate's own root discovery still resolves to this repository, but link
    targets resolve relative to the file being checked, which is what these
    exercise.

    The gate throws on a blocking finding, so each invocation catches that and
    folds it into the captured output alongside anything written before it.

    Focused on link extraction, and asserting both directions: a broken target
    must be reported, and a valid one must not be. A target the extractor
    cannot parse is skipped silently rather than reported — a check that
    quietly stops checking looks identical to one that passes, which is the
    failure mode these exist to catch.

    Requires Pester 5+.
#>

BeforeAll {
    $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:gateScript = Join-Path $repoRoot 'scripts' 'template' 'Test-Documentation.ps1'

    # No GeneratedFiles and no terminology, so a fixture exercises link
    # resolution alone and nothing else can colour the result.
    $script:rulesPath = Join-Path $TestDrive 'MinimalRules.psd1'
    Set-Content -LiteralPath $script:rulesPath -NoNewline -Value @'
@{
    Terminology = @()
    ExcludedSegments = @('.git')
    GeneratedFiles = @()
    ExcludedFiles = @()
}
'@

    function New-GateFixture {
        param(
            [Parameter(Mandatory)][string] $Name,
            [Parameter(Mandatory)][string] $Markdown,
            [string[]] $AlsoCreate = @()
        )

        $dir = Join-Path $TestDrive $Name
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $dir 'index.md') -Value $Markdown -NoNewline
        foreach ($file in $AlsoCreate) {
            $path = Join-Path $dir $file
            $parent = Split-Path -Parent $path
            if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
            Set-Content -LiteralPath $path -Value "# Target" -NoNewline
        }
        return $dir
    }

    function Invoke-Gate {
        param([Parameter(Mandatory)][string] $FixtureDir)

        # The inner catch turns the gate's terminating error into an output
        # object, so findings written before it are not lost with it.
        return & {
            try { & $script:gateScript -Path $FixtureDir -SettingsPath $script:rulesPath }
            catch { $_ }
        } *>&1 | Out-String
    }
}

Describe 'Test-Documentation.ps1 link extraction' {
    It 'reports a broken relative link' {
        $dir = New-GateFixture -Name 'broken-plain' -Markdown @'
# Doc

See [the target](./missing.md).
'@
        Invoke-Gate -FixtureDir $dir | Should -Match 'missing\.md'
    }

    It 'accepts a relative link whose target exists' {
        $dir = New-GateFixture -Name 'valid-plain' -AlsoCreate @('target.md') -Markdown @'
# Doc

See [the target](./target.md).
'@
        Invoke-Gate -FixtureDir $dir | Should -Not -Match 'does not exist'
    }

    It 'sees an angle-bracket destination containing a space' {
        # A single [^)\s]+ class cannot match across the space, so this link was
        # skipped entirely -- never checked rather than reported.
        $dir = New-GateFixture -Name 'angle-space-broken' -Markdown @'
# Doc

See [the target](<./some missing file.md>).
'@
        Invoke-Gate -FixtureDir $dir | Should -Match 'some missing file\.md'
    }

    It 'accepts an angle-bracket destination whose target exists' {
        $dir = New-GateFixture -Name 'angle-space-valid' -AlsoCreate @('some file.md') -Markdown @'
# Doc

See [the target](<./some file.md>).
'@
        Invoke-Gate -FixtureDir $dir | Should -Not -Match 'does not exist'
    }

    It 'does not truncate a bare destination at a balanced parenthesis' {
        # './foo(bar).md' was captured as './foo(bar' and reported broken even
        # with the real file present, so this asserts the false positive is gone
        # rather than merely that something was reported.
        $dir = New-GateFixture -Name 'balanced-parens' -AlsoCreate @('foo(bar).md') -Markdown @'
# Doc

See [the target](./foo(bar).md).
'@
        Invoke-Gate -FixtureDir $dir | Should -Not -Match 'does not exist'
    }
}
