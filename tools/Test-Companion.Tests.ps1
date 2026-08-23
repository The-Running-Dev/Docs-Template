#Requires -Version 7.0
#Requires -Modules Pester

<#
  Test-Companion.ps1 exits the process on every path (0/1/2), so these tests dot-source it -
  the exit-calling wrapper is guarded on $MyInvocation.InvocationName, same structure as
  Test-WriteSurface.ps1 and Test-DesignDrift.ps1.

  The fixtures are real directories under $TestDrive rather than mocks. The seam this script
  actually has is parsing two Markdown shapes - the core's fenced block and the companion's
  headings - and a mock of a file read would test nothing about that.

  Every rule the script can emit has a negative case below. AGENTS.md, *Verification*: a
  validator that has never failed is not known to constrain anything.
#>

BeforeAll {
    $script:ScriptPath = Join-Path $PSScriptRoot 'Test-Companion.ps1'
    $script:PreDotSourceErrorActionPreference = $ErrorActionPreference
    . $script:ScriptPath -TargetRepo $TestDrive

    # A trimmed stand-in for the real .claude/COMPANIONS.md: the script reads only the table,
    # so the table is all a fixture needs. Keeping it minimal is deliberate - if the real
    # file's table shape changes, these tests keep passing while the repository's own check
    # starts failing, which is the correct split between a unit fixture and the live document.
    $script:CompanionsDoc = @(
        '# Command cores and their per-repo companions'
        ''
        '| Id | What it may override | Example |'
        '|---|---|---|'
        '| `vocabulary` | What this repository calls things | ids are `W<n>` |'
        '| `document-map` | Where a document lives | compound canonical files |'
        '| `extra-steps` | Repository-specific extra steps | regenerate the docs site |'
        '| `gate-commands` | The concrete commands a gate runs | `just verify` |'
        '| `tightened-authorization` | A narrowing of what may happen unasked | ask per thread |'
        ''
        '## Never'
        ''
        'A stop condition or a refusal.'
    ) -join "`n"

    function New-Fixture {
        param([Parameter(Mandatory)][string] $Name, [switch] $NoCompanionsDoc)
        $repo = Join-Path $TestDrive $Name
        New-Item -ItemType Directory -Path (Join-Path $repo '.claude/commands') -Force | Out-Null
        if (-not $NoCompanionsDoc) {
            [System.IO.File]::WriteAllText((Join-Path $repo '.claude/COMPANIONS.md'), $script:CompanionsDoc, [System.Text.UTF8Encoding]::new($false))
        }
        $repo
    }

    function Write-Fixture {
        param([Parameter(Mandatory)][string] $Repo, [Parameter(Mandatory)][string] $RelPath, [Parameter(Mandatory)][AllowEmptyString()][string] $Content)
        $full = Join-Path $Repo $RelPath
        $parent = Split-Path -Parent $full
        if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        [System.IO.File]::WriteAllText($full, $Content, [System.Text.UTF8Encoding]::new($false))
    }

    function New-Core {
        param(
            [Parameter(Mandatory)][string] $Repo,
            [Parameter(Mandatory)][string] $Name,
            [string[]] $Categories = @('vocabulary'),
            [string] $CompanionPath,
            [int] $BlockCount = 1
        )
        if (-not $CompanionPath) { $CompanionPath = ".claude/commands/$Name-local.md" }
        $cats = ($Categories | ForEach-Object { "``$_``" }) -join ', '
        $block = @(
            '<!-- companion:declared:start -->'
            "**Per-repo companion:** ``$CompanionPath``. Read it now, if it exists — an absent,"
            'empty, or frontmatter-only file is no companion, and this file then stands alone.'
            "It may override: $cats. It may never override anything in"
            '[`.claude/COMPANIONS.md`](../COMPANIONS.md) § *Never*, which is also where these categories are defined.'
            '<!-- companion:declared:end -->'
        ) -join "`n"

        $body = @("---", "description: fixture $Name", "---", "")
        for ($i = 0; $i -lt $BlockCount; $i++) { $body += @($block, '') }
        $body += @("Do the $Name thing.", '')
        Write-Fixture -Repo $Repo -RelPath ".claude/commands/$Name.md" -Content (($body -join "`n"))
    }

    function New-CoreWithoutBlock {
        param([Parameter(Mandatory)][string] $Repo, [Parameter(Mandatory)][string] $Name)
        Write-Fixture -Repo $Repo -RelPath ".claude/commands/$Name.md" -Content "---`ndescription: fixture $Name`n---`n`nDo the $Name thing.`n"
    }

    # The bare form means projected (AGENTS.md, *Marked regions*), so a core still carrying it
    # is indistinguishable from one with no fence at all - MissingBlock, not a parsed block.
    function New-CoreWithBareBlock {
        param([Parameter(Mandatory)][string] $Repo, [Parameter(Mandatory)][string] $Name)
        $block = @(
            '<!-- companion:start -->'
            "**Per-repo companion:** ``.claude/commands/$Name-local.md``."
            'It may override: `vocabulary`.'
            '<!-- companion:end -->'
        ) -join "`n"
        Write-Fixture -Repo $Repo -RelPath ".claude/commands/$Name.md" -Content "---`ndescription: fixture $Name`n---`n`n$block`n`nDo the $Name thing.`n"
    }
}

AfterAll {
    $ErrorActionPreference = $script:PreDotSourceErrorActionPreference
    Set-StrictMode -Off
}

Describe 'Test-Companion — positive cases' {

    It 'a core with a well-formed block and no companion is Valid, counted absent, exit 0' {
        $repo = New-Fixture -Name 'valid-no-companion'
        New-Core -Repo $repo -Name 'slice' -Categories @('vocabulary', 'document-map')

        $r = Invoke-CompanionCheck -TargetRepo $repo

        $r.State | Should -Be 'Valid'
        $r.Findings.Count | Should -Be 0
        $r.CoreCount | Should -Be 1
        $r.CompanionCount | Should -Be 0
        $r.AbsentCount | Should -Be 1
        Get-CompanionExitCode -State $r.State | Should -Be 0
    }

    It 'a companion overriding only declared categories is Valid' {
        $repo = New-Fixture -Name 'valid-companion'
        New-Core -Repo $repo -Name 'slice' -Categories @('vocabulary', 'document-map')
        Write-Fixture -Repo $repo -RelPath '.claude/commands/slice-local.md' -Content @"
## vocabulary

Slices are units here; their ids are ``W<n>``.

## document-map

The canonical design docs are compound files with marked blocks.
"@

        $r = Invoke-CompanionCheck -TargetRepo $repo

        $r.State | Should -Be 'Valid'
        $r.CompanionCount | Should -Be 1
        $r.AbsentCount | Should -Be 0
    }

    It 'every category id in the real .claude/COMPANIONS.md is parsed out of its table' {
        $ids = Get-CompanionCategory -CompanionsDoc (Join-Path (Split-Path -Parent $PSScriptRoot) '.claude/COMPANIONS.md')

        $ids | Should -Contain 'vocabulary'
        $ids | Should -Contain 'document-map'
        $ids | Should -Contain 'extra-steps'
        $ids | Should -Contain 'gate-commands'
        $ids | Should -Contain 'tightened-authorization'
        $ids.Count | Should -Be 5
    }

    It 'this repository itself is Valid' {
        $r = Invoke-CompanionCheck -TargetRepo (Split-Path -Parent $PSScriptRoot)

        $r.State | Should -Be 'Valid'
        $r.CoreCount | Should -BeGreaterThan 0
    }
}

Describe 'Test-Companion — absence is not an override' {

    It 'a missing companion is absent' {
        $repo = New-Fixture -Name 'absent-missing'
        New-Core -Repo $repo -Name 'slice'

        $r = Invoke-CompanionCheck -TargetRepo $repo
        $r.AbsentCount | Should -Be 1
        $r.State | Should -Be 'Valid'
    }

    It 'an empty companion is absent, not an override' {
        $repo = New-Fixture -Name 'absent-empty'
        New-Core -Repo $repo -Name 'slice'
        Write-Fixture -Repo $repo -RelPath '.claude/commands/slice-local.md' -Content ''

        $r = Invoke-CompanionCheck -TargetRepo $repo
        $r.AbsentCount | Should -Be 1
        $r.Findings.Count | Should -Be 0
    }

    It 'a whitespace-only companion is absent' {
        $repo = New-Fixture -Name 'absent-whitespace'
        New-Core -Repo $repo -Name 'slice'
        Write-Fixture -Repo $repo -RelPath '.claude/commands/slice-local.md' -Content "  `n`n`t`n"

        $r = Invoke-CompanionCheck -TargetRepo $repo
        $r.AbsentCount | Should -Be 1
        $r.Findings.Count | Should -Be 0
    }

    It 'a frontmatter-only companion is absent' {
        $repo = New-Fixture -Name 'absent-frontmatter'
        New-Core -Repo $repo -Name 'slice'
        Write-Fixture -Repo $repo -RelPath '.claude/commands/slice-local.md' -Content "---`ndescription: reserved`n---`n`n"

        $r = Invoke-CompanionCheck -TargetRepo $repo
        $r.AbsentCount | Should -Be 1
        $r.Findings.Count | Should -Be 0
    }
}

Describe 'Test-Companion — negative cases, one per rule' {

    It 'MissingBlock — a core with no fenced block' {
        $repo = New-Fixture -Name 'neg-missing-block'
        New-CoreWithoutBlock -Repo $repo -Name 'slice'

        $r = Invoke-CompanionCheck -TargetRepo $repo

        $r.State | Should -Be 'Invalid'
        $r.Findings.Rule | Should -Contain 'MissingBlock'
        Get-CompanionExitCode -State $r.State | Should -Be 1
    }

    It 'MissingBlock — a core carrying the bare (projected) form rather than the declared form' {
        $repo = New-Fixture -Name 'neg-bare-block'
        New-CoreWithBareBlock -Repo $repo -Name 'slice'

        $r = Invoke-CompanionCheck -TargetRepo $repo

        $r.State | Should -Be 'Invalid'
        $r.Findings.Rule | Should -Contain 'MissingBlock'
        $r.CoreCount | Should -Be 1
    }

    It 'DuplicateBlock — a core with two fenced blocks' {
        $repo = New-Fixture -Name 'neg-duplicate-block'
        New-Core -Repo $repo -Name 'slice' -BlockCount 2

        $r = Invoke-CompanionCheck -TargetRepo $repo

        $r.State | Should -Be 'Invalid'
        $r.Findings.Rule | Should -Contain 'DuplicateBlock'
    }

    It 'WrongCompanionPath — the block names another command''s companion' {
        $repo = New-Fixture -Name 'neg-wrong-path'
        New-Core -Repo $repo -Name 'slice' -CompanionPath '.claude/commands/track-local.md'

        $r = Invoke-CompanionCheck -TargetRepo $repo

        $r.State | Should -Be 'Invalid'
        $r.Findings.Rule | Should -Contain 'WrongCompanionPath'
    }

    It 'NoCategories — a core declaring an empty override list' {
        $repo = New-Fixture -Name 'neg-no-categories'
        New-Core -Repo $repo -Name 'slice' -Categories @()

        $r = Invoke-CompanionCheck -TargetRepo $repo

        $r.State | Should -Be 'Invalid'
        $r.Findings.Rule | Should -Contain 'NoCategories'
    }

    It 'UnknownCategory — a core declaring an id absent from COMPANIONS.md' {
        $repo = New-Fixture -Name 'neg-unknown-category'
        New-Core -Repo $repo -Name 'slice' -Categories @('vocabulary', 'behaviour')

        $r = Invoke-CompanionCheck -TargetRepo $repo

        $r.State | Should -Be 'Invalid'
        ($r.Findings | Where-Object Rule -eq 'UnknownCategory').Detail | Should -Match 'behaviour'
    }

    It 'OrphanCompanion — a companion with no core beside it' {
        $repo = New-Fixture -Name 'neg-orphan'
        New-Core -Repo $repo -Name 'slice'
        Write-Fixture -Repo $repo -RelPath '.claude/commands/ghost-local.md' -Content "## vocabulary`n`nSomething.`n"

        $r = Invoke-CompanionCheck -TargetRepo $repo

        $r.State | Should -Be 'Invalid'
        $r.Findings.Rule | Should -Contain 'OrphanCompanion'
    }

    It 'UnknownCompanionHeading — a companion heading that is not a category' {
        $repo = New-Fixture -Name 'neg-unknown-heading'
        New-Core -Repo $repo -Name 'slice'
        Write-Fixture -Repo $repo -RelPath '.claude/commands/slice-local.md' -Content "## stop-conditions`n`nNever stop.`n"

        $r = Invoke-CompanionCheck -TargetRepo $repo

        $r.State | Should -Be 'Invalid'
        $r.Findings.Rule | Should -Contain 'UnknownCompanionHeading'
    }

    It 'UndeclaredCategory — a valid category its core does not allow' {
        $repo = New-Fixture -Name 'neg-undeclared'
        New-Core -Repo $repo -Name 'slice' -Categories @('vocabulary')
        Write-Fixture -Repo $repo -RelPath '.claude/commands/slice-local.md' -Content "## tightened-authorization`n`nAsk per thread.`n"

        $r = Invoke-CompanionCheck -TargetRepo $repo

        $r.State | Should -Be 'Invalid'
        $r.Findings.Rule | Should -Contain 'UndeclaredCategory'
    }

    It 'EmptyCategory — a declared heading with nothing under it' {
        $repo = New-Fixture -Name 'neg-empty-category'
        New-Core -Repo $repo -Name 'slice' -Categories @('vocabulary', 'document-map')
        Write-Fixture -Repo $repo -RelPath '.claude/commands/slice-local.md' -Content "## vocabulary`n`n## document-map`n`nReal content.`n"

        $r = Invoke-CompanionCheck -TargetRepo $repo

        $r.State | Should -Be 'Invalid'
        $r.Findings.Rule | Should -Contain 'EmptyCategory'
    }
}

Describe 'Test-Companion — NotEvaluated' {

    It 'no .claude/commands/ directory is NotEvaluated, exit 2' {
        $bare = Join-Path $TestDrive 'not-a-kit'
        New-Item -ItemType Directory -Path $bare -Force | Out-Null

        $r = Invoke-CompanionCheck -TargetRepo $bare

        $r.State | Should -Be 'NotEvaluated'
        Get-CompanionExitCode -State $r.State | Should -Be 2
    }

    It 'no .claude/COMPANIONS.md is NotEvaluated rather than silently Valid' {
        $repo = New-Fixture -Name 'no-companions-doc' -NoCompanionsDoc
        New-Core -Repo $repo -Name 'slice'

        $r = Invoke-CompanionCheck -TargetRepo $repo

        $r.State | Should -Be 'NotEvaluated'
        $r.Detail | Should -Match 'COMPANIONS.md'
    }

    It 'a COMPANIONS.md with no parseable table is NotEvaluated, not an empty vocabulary' {
        $repo = New-Fixture -Name 'empty-table'
        Write-Fixture -Repo $repo -RelPath '.claude/COMPANIONS.md' -Content "# Companions`n`nNo table here.`n"
        New-Core -Repo $repo -Name 'slice'

        $r = Invoke-CompanionCheck -TargetRepo $repo

        $r.State | Should -Be 'NotEvaluated'
    }
}
