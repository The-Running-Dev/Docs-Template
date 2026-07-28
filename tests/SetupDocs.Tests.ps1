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
        $content = $content -replace "routeBasePath:\s*'/'", 'routeBasePath: "/"'
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

Describe 'setup-docs.ps1 README creation' {
    It 'creates README.md from -Title/-Description when the project has none' {
        $projectDir = Join-Path $TestDrive 'no-readme'
        & $script:setupScript -ProjectDir $projectDir -Title 'Fresh Project' -Description 'A fresh project' `
            -SkipWorkflow -SkipGate

        $readmePath = Join-Path $projectDir 'README.md'
        Test-Path -LiteralPath $readmePath | Should -BeTrue
        $readme = Get-Content -LiteralPath $readmePath -Raw
        $readme | Should -Match '# Fresh Project'
        $readme | Should -Match 'A fresh project'
    }

    It 'never overwrites an existing README.md, even with -Overwrite' {
        $projectDir = Join-Path $TestDrive 'existing-readme'
        New-Item -ItemType Directory -Path $projectDir -Force | Out-Null
        $readmePath = Join-Path $projectDir 'README.md'
        Set-Content -LiteralPath $readmePath -Value "# Hand-authored`n`nDo not touch this." -NoNewline

        & $script:setupScript -ProjectDir $projectDir -Title 'Ignored Title' -Overwrite -SkipWorkflow -SkipGate

        (Get-Content -LiteralPath $readmePath -Raw) | Should -Match 'Do not touch this\.'
    }

    It 'reaches the same generation path for a created README as for an existing one' {
        # No behavioural assertion beyond "does not throw and produces a root
        # page either way" -- this is a smoke test that the -NoHomepage-stub
        # branch is really gone and both cases (README present, README
        # absent) fall into the one remaining path.
        $withReadme = Join-Path $TestDrive 'has-readme'
        New-Item -ItemType Directory -Path $withReadme -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $withReadme 'README.md') -Value '# Already Here' -NoNewline
        & $script:setupScript -ProjectDir $withReadme -Title 'Has Readme' -SkipWorkflow -SkipGate

        $withoutReadme = Join-Path $TestDrive 'no-readme-2'
        & $script:setupScript -ProjectDir $withoutReadme -Title 'No Readme' -SkipWorkflow -SkipGate

        Test-Path -LiteralPath (Join-Path $withReadme 'docs' 'docs' 'index.md') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $withoutReadme 'docs' 'docs' 'index.md') | Should -BeTrue
    }
}

Describe 'setup-docs.ps1 root page destination' {
    It 'writes the README-derived page to docs/docs/index.md when routeBasePath is /' {
        $projectDir = Join-Path $TestDrive 'root-slash'
        & $script:setupScript -ProjectDir $projectDir -Title 'Root Slash Project' -SkipWorkflow -SkipGate

        $indexPath = Join-Path $projectDir 'docs' 'docs' 'index.md'
        Test-Path -LiteralPath $indexPath | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $projectDir 'docs' 'src' 'pages' 'index.md') | Should -BeFalse

        $content = Get-Content -LiteralPath $indexPath -Raw
        $content | Should -Match 'sidebar_position: 1'
        $content | Should -Not -Match '\[View the documentation\]'
    }

    It 'writes the README-derived page to docs/src/pages/index.md when routeBasePath is not /' {
        $projectDir = Join-Path $TestDrive 'custom-root'
        & $script:setupScript -ProjectDir $projectDir -Title 'Custom Route Project' -RouteBasePath 'docs' `
            -SkipWorkflow -SkipGate

        $rootPagePath = Join-Path $projectDir 'docs' 'src' 'pages' 'index.md'
        Test-Path -LiteralPath $rootPagePath | Should -BeTrue

        $content = Get-Content -LiteralPath $rootPagePath -Raw
        $content | Should -Not -Match 'sidebar_position'
        $content | Should -Match '\[View the documentation\]\(/docs/\)'
    }

    It 'writes a landing page, not the README, to docs/docs/index.md when routeBasePath is not /' {
        $projectDir = Join-Path $TestDrive 'custom-landing'
        New-Item -ItemType Directory -Path $projectDir -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $projectDir 'README.md') `
            -Value "# Custom Landing Project`n`nThis exact sentence must not appear at /docs/." -NoNewline

        & $script:setupScript -ProjectDir $projectDir -Title 'Custom Landing Project' -RouteBasePath 'docs' `
            -SkipWorkflow -SkipGate

        $landingPath = Join-Path $projectDir 'docs' 'docs' 'index.md'
        Test-Path -LiteralPath $landingPath | Should -BeTrue
        $landing = Get-Content -LiteralPath $landingPath -Raw
        $landing | Should -Match 'sidebar_position: 1'
        $landing | Should -Not -Match 'This exact sentence must not appear at /docs/\.'
    }

    It 'requires -Overwrite to migrate a pre-existing docs/docs/index.md to a landing page' {
        $projectDir = Join-Path $TestDrive 'migration'
        New-Item -ItemType Directory -Path $projectDir -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $projectDir 'README.md') -Value '# Migration Project' -NoNewline
        $indexPath = Join-Path $projectDir 'docs' 'docs' 'index.md'
        New-Item -ItemType Directory -Path (Split-Path -Parent $indexPath) -Force | Out-Null
        Set-Content -LiteralPath $indexPath -Value "---`ntitle: 'Old'`n---`n`nOld README-derived content." -NoNewline

        & $script:setupScript -ProjectDir $projectDir -Title 'Migration Project' -RouteBasePath 'docs' `
            -SkipWorkflow -SkipGate

        (Get-Content -LiteralPath $indexPath -Raw) | Should -Match 'Old README-derived content\.'

        & $script:setupScript -ProjectDir $projectDir -Title 'Migration Project' -RouteBasePath 'docs' `
            -Overwrite -SkipWorkflow -SkipGate

        (Get-Content -LiteralPath $indexPath -Raw) | Should -Not -Match 'Old README-derived content\.'
    }
}
