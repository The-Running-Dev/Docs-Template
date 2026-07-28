<#
.SYNOPSIS
    Pester tests for scripts/setup-docs.ps1.

.DESCRIPTION
    Drives the real script against TestDrive: rather than unit-testing its
    internal functions in isolation. setup-docs.ps1 is a top-level script, not
    a module -- dot-sourcing it to reach a single function would also execute
    its main body against whatever -ProjectDir defaults to, which is not safe
    to do from a test. Invoking it with '&' runs it exactly as a consumer
    would, against a throwaway directory Pester cleans up automatically.

    Requires Pester 5+. The module the CI runner provides by default (3.4.0)
    does not understand this syntax.
#>

BeforeAll {
    $script:repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:setupScript = Join-Path $repoRoot 'scripts' 'setup-docs.ps1'
}

Describe 'setup-docs.ps1 -RouteBasePath substitution' {
    It 'installs the default routeBasePath of / when none is passed' {
        $projectDir = Join-Path $TestDrive 'default-route'
        & $script:setupScript -ProjectDir $projectDir -Title 'Test Project' -SkipWorkflow -SkipGate

        $config = Get-Content -LiteralPath (Join-Path $projectDir 'docs' 'docusaurus.config.ts') -Raw
        $config | Should -Match "routeBasePath:\s*'/'"
    }

    It 'installs a custom routeBasePath when one is passed' {
        $projectDir = Join-Path $TestDrive 'custom-route'
        & $script:setupScript -ProjectDir $projectDir -Title 'Test Project' -RouteBasePath 'docs' -SkipWorkflow -SkipGate

        $config = Get-Content -LiteralPath (Join-Path $projectDir 'docs' 'docusaurus.config.ts') -Raw
        $config | Should -Match "routeBasePath:\s*'docs'"
    }

    It 'still substitutes title and tagline alongside the regex-based routeBasePath' {
        $projectDir = Join-Path $TestDrive 'title-tagline'
        & $script:setupScript -ProjectDir $projectDir -Title 'My Project' -Description 'A test project' -SkipWorkflow -SkipGate

        $config = Get-Content -LiteralPath (Join-Path $projectDir 'docs' 'docusaurus.config.ts') -Raw
        $config | Should -Match "title: 'My Project'"
        $config | Should -Match "tagline: 'A test project'"
    }

    It 'preserves an existing routeBasePath on re-run unless -RouteBasePath is passed explicitly' {
        $projectDir = Join-Path $TestDrive 'preserve-route'
        & $script:setupScript -ProjectDir $projectDir -Title 'Test Project' -RouteBasePath 'docs' -SkipWorkflow -SkipGate
        & $script:setupScript -ProjectDir $projectDir -Title 'Test Project' -Overwrite -SkipWorkflow -SkipGate

        $config = Get-Content -LiteralPath (Join-Path $projectDir 'docs' 'docusaurus.config.ts') -Raw
        $config | Should -Match "routeBasePath:\s*'docs'"
    }
}

Describe 'Copy-TemplateFile unmatched-key guard' {
    BeforeAll {
        # Exercised through a corrupted copy of the whole scripts/ tree, not a
        # re-implementation of Copy-TemplateFile: setup-docs.ps1 resolves its
        # own template directory from $PSScriptRoot, so running the copy is
        # what actually invokes the guard as the real script does, rather than
        # asserting behaviour a hand-written stand-in might not share.
        $script:corruptedScripts = Join-Path $TestDrive 'corrupted-scripts'
        Copy-Item -Path (Join-Path $repoRoot 'scripts') -Destination $script:corruptedScripts -Recurse

        $corruptedConfig = Join-Path $script:corruptedScripts 'template' 'docusaurus.config.ts'
        $content = Get-Content -LiteralPath $corruptedConfig -Raw
        $content = $content -replace "routeBasePath:\s*'docs'", 'routeBasePath: "docs"'
        Set-Content -LiteralPath $corruptedConfig -Value $content -NoNewline

        $script:corruptedSetupScript = Join-Path $script:corruptedScripts 'setup-docs.ps1'
    }

    It 'throws instead of silently leaving the placeholder in place' {
        $projectDir = Join-Path $TestDrive 'corrupted-project'
        {
            & $script:corruptedSetupScript -ProjectDir $projectDir -Title 'Test Project' `
                -RouteBasePath 'docs' -SkipWorkflow -SkipGate
        } | Should -Throw '*matched nothing*'
    }
}
