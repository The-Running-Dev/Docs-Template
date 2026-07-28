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

    It 'rewrites absolute README links against the site root, not the docs base' {
        # -SiteUrl is the site ORIGIN, so an absolute link resolves against '/'.
        # Rewriting it to the docs base instead double-prefixes any link that
        # already points into the docs -- the shape every consumer README uses
        # once its links are absolute so they also work on the code host.
        $projectDir = Join-Path $TestDrive 'siteurl-rewrite'
        New-Item -ItemType Directory -Path $projectDir -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $projectDir 'README.md') -NoNewline -Value @'
# Site Url Project

- [Vision](https://example.com/docs/engine/vision)
- [Home](https://example.com/)
'@

        & $script:setupScript -ProjectDir $projectDir -Title 'Site Url Project' -RouteBasePath 'docs' `
            -SiteUrl 'https://example.com/' -SkipWorkflow -SkipGate

        $content = Get-Content -LiteralPath (Join-Path $projectDir 'docs' 'src' 'pages' 'index.md') -Raw
        $content | Should -Match '\(/docs/engine/vision\)'
        $content | Should -Not -Match '/docs/docs/'
        $content | Should -Match '\(/\)'
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

Describe 'setup-docs.ps1 -DocsDirectory' {
    It 'installs the full overlay under a custom directory, and creates no docs/' {
        $projectDir = Join-Path $TestDrive 'custom-dir'
        & $script:setupScript -ProjectDir $projectDir -Title 'Custom Dir Project' -DocsDirectory 'documentation' `
            -SkipWorkflow -SkipGate

        Test-Path -LiteralPath (Join-Path $projectDir 'documentation' 'docusaurus.config.ts') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $projectDir 'documentation' 'sidebar.ts') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $projectDir 'documentation' 'docs' 'index.md') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $projectDir 'docs') | Should -BeFalse
    }

    It 'reproduces the default docs/ layout when -DocsDirectory is omitted' {
        $projectDir = Join-Path $TestDrive 'default-dir'
        & $script:setupScript -ProjectDir $projectDir -Title 'Default Dir Project' -SkipWorkflow -SkipGate

        Test-Path -LiteralPath (Join-Path $projectDir 'docs' 'docusaurus.config.ts') | Should -BeTrue
    }

    It 'adopts an existing custom directory on re-run when -DocsDirectory is omitted' {
        $projectDir = Join-Path $TestDrive 'adopt-dir'
        & $script:setupScript -ProjectDir $projectDir -Title 'Adopt Dir Project' -DocsDirectory 'documentation' `
            -SkipWorkflow -SkipGate
        & $script:setupScript -ProjectDir $projectDir -Title 'Adopt Dir Project Updated' -Overwrite `
            -SkipWorkflow -SkipGate

        $config = Get-Content -LiteralPath (Join-Path $projectDir 'documentation' 'docusaurus.config.ts') -Raw
        $config | Should -Match "title: 'Adopt Dir Project Updated'"
        Test-Path -LiteralPath (Join-Path $projectDir 'docs') | Should -BeFalse
    }

    It 'refuses to move an existing custom directory when -DocsDirectory names a different one' {
        $projectDir = Join-Path $TestDrive 'refuse-dir'
        & $script:setupScript -ProjectDir $projectDir -Title 'Refuse Dir Project' -DocsDirectory 'documentation' `
            -SkipWorkflow -SkipGate

        {
            & $script:setupScript -ProjectDir $projectDir -Title 'Refuse Dir Project' -DocsDirectory 'other-docs' `
                -Overwrite -SkipWorkflow -SkipGate
        } | Should -Throw '*names a different*'

        Test-Path -LiteralPath (Join-Path $projectDir 'other-docs') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $projectDir 'documentation' 'docusaurus.config.ts') | Should -BeTrue
    }

    It 'rejects a rooted -DocsDirectory before writing anything' {
        # A rooted value always contains a path separator, so the
        # single-directory-name check (which runs first) catches it before
        # Resolve-ContainedProjectDirectory's own rootedness check ever
        # would -- still rejected, just by the earlier, more specific gate.
        $projectDir = Join-Path $TestDrive 'invalid-rooted'
        {
            & $script:setupScript -ProjectDir $projectDir -Title 'Invalid' -DocsDirectory $TestDrive `
                -SkipWorkflow -SkipGate
        } | Should -Throw '*single directory name*'
        Test-Path -LiteralPath (Join-Path $projectDir 'docusaurus.config.ts') | Should -BeFalse
    }

    It "rejects a '..' segment in -DocsDirectory before writing anything" {
        # Same reasoning as the rooted case: '../evil' contains a path
        # separator, so the single-directory-name check catches it first.
        $projectDir = Join-Path $TestDrive 'invalid-traversal'
        {
            & $script:setupScript -ProjectDir $projectDir -Title 'Invalid' -DocsDirectory '../evil' `
                -SkipWorkflow -SkipGate
        } | Should -Throw '*single directory name*'
    }

    It 'rejects a whitespace-only -DocsDirectory before writing anything' {
        # Whitespace is rejected by the whitespace-or-quotes check before
        # Resolve-ContainedProjectDirectory's own empty-value check runs.
        $projectDir = Join-Path $TestDrive 'invalid-whitespace'
        {
            & $script:setupScript -ProjectDir $projectDir -Title 'Invalid' -DocsDirectory '   ' `
                -SkipWorkflow -SkipGate
        } | Should -Throw '*must not contain whitespace or quotes*'
    }

    It 'rejects -DocsDirectory resolving to the project directory itself' {
        $projectDir = Join-Path $TestDrive 'invalid-root'
        {
            & $script:setupScript -ProjectDir $projectDir -Title 'Invalid' -DocsDirectory '.' `
                -SkipWorkflow -SkipGate
        } | Should -Throw '*project directory itself*'
    }

    It 'rejects -DocsDirectory that nests with -ScriptDir' {
        $projectDir = Join-Path $TestDrive 'invalid-nesting'
        {
            & $script:setupScript -ProjectDir $projectDir -Title 'Invalid' -DocsDirectory 'build' `
                -SkipWorkflow -SkipGate
        } | Should -Throw '*must not nest*'
    }

    It 'rejects a -DocsDirectory that is a symlink resolving outside the project' {
        # Lexical containment (GetFullPath plus a prefix check) does not
        # follow links, so a pre-planted symlink at the docs directory's own
        # path would otherwise pass validation and then receive this
        # installer's real writes at the external target.
        $projectDir = Join-Path $TestDrive 'symlink-escape'
        New-Item -ItemType Directory -Path $projectDir -Force | Out-Null
        $externalTarget = Join-Path $TestDrive 'symlink-escape-external'
        New-Item -ItemType Directory -Path $externalTarget -Force | Out-Null
        New-Item -ItemType SymbolicLink -Path (Join-Path $projectDir 'documentation') -Target $externalTarget | Out-Null

        {
            & $script:setupScript -ProjectDir $projectDir -Title 'Invalid' -DocsDirectory 'documentation' `
                -SkipWorkflow -SkipGate
        } | Should -Throw '*pointing outside the project directory*'

        Test-Path -LiteralPath (Join-Path $externalTarget 'docusaurus.config.ts') | Should -BeFalse
    }

    It 'accepts a -DocsDirectory that is a symlink resolving inside the project' {
        # A link is not inherently unsafe -- only one that escapes the
        # project. This is the negative case for the check above, confirming
        # it does not also reject an internal symlink a project legitimately
        # set up itself.
        $projectDir = Join-Path $TestDrive 'symlink-internal'
        New-Item -ItemType Directory -Path $projectDir -Force | Out-Null
        $internalTarget = Join-Path $projectDir 'actual-docs'
        New-Item -ItemType Directory -Path $internalTarget -Force | Out-Null
        New-Item -ItemType SymbolicLink -Path (Join-Path $projectDir 'documentation') -Target $internalTarget | Out-Null

        {
            & $script:setupScript -ProjectDir $projectDir -Title 'Symlink Internal' -DocsDirectory 'documentation' `
                -SkipWorkflow -SkipGate
        } | Should -Not -Throw

        Test-Path -LiteralPath (Join-Path $internalTarget 'docusaurus.config.ts') | Should -BeTrue
    }

    It 'rejects a -DocsDirectory containing whitespace' {
        $projectDir = Join-Path $TestDrive 'invalid-whitespace-name'
        {
            & $script:setupScript -ProjectDir $projectDir -Title 'Invalid' -DocsDirectory 'project docs' `
                -SkipWorkflow -SkipGate
        } | Should -Throw '*must not contain whitespace or quotes*'
    }

    It 'rejects a -DocsDirectory containing a quote' {
        $projectDir = Join-Path $TestDrive 'invalid-quote-name'
        {
            & $script:setupScript -ProjectDir $projectDir -Title 'Invalid' -DocsDirectory "project's-docs" `
                -SkipWorkflow -SkipGate
        } | Should -Throw '*must not contain whitespace or quotes*'
    }

    It 'rejects a multi-segment -DocsDirectory' {
        $projectDir = Join-Path $TestDrive 'invalid-multi-segment'
        {
            & $script:setupScript -ProjectDir $projectDir -Title 'Invalid' -DocsDirectory 'sites/documentation' `
                -SkipWorkflow -SkipGate
        } | Should -Throw '*single directory name*'
    }

    It 'treats a case-only respelling of an installed directory as a conflict, not a match' {
        $projectDir = Join-Path $TestDrive 'case-conflict'
        & $script:setupScript -ProjectDir $projectDir -Title 'Case Conflict Project' -DocsDirectory 'documentation' `
            -SkipWorkflow -SkipGate

        {
            & $script:setupScript -ProjectDir $projectDir -Title 'Case Conflict Project' -DocsDirectory 'Documentation' `
                -Overwrite -SkipWorkflow -SkipGate
        } | Should -Throw '*names a different*'
    }

    It 'warns, but does not fail, when -DocsDirectory collides with an ExcludedSegments entry' {
        $projectDir = Join-Path $TestDrive 'excluded-segment'
        $output = & $script:setupScript -ProjectDir $projectDir -Title 'Excluded Segment Project' `
            -DocsDirectory 'artifacts' -SkipWorkflow -SkipGate 3>&1
        ($output | Out-String) | Should -Match 'ExcludedSegments'
        Test-Path -LiteralPath (Join-Path $projectDir 'artifacts' 'docusaurus.config.ts') | Should -BeTrue
    }

    It 'writes both root-page destinations under a custom directory for both routeBasePath values' {
        $rootSlash = Join-Path $TestDrive 'custom-dir-route-slash'
        & $script:setupScript -ProjectDir $rootSlash -Title 'Route Slash' -DocsDirectory 'documentation' `
            -SkipWorkflow -SkipGate
        Test-Path -LiteralPath (Join-Path $rootSlash 'documentation' 'docs' 'index.md') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $rootSlash 'documentation' 'src' 'pages' 'index.md') | Should -BeFalse

        $customRoute = Join-Path $TestDrive 'custom-dir-route-docs'
        & $script:setupScript -ProjectDir $customRoute -Title 'Route Docs' -DocsDirectory 'documentation' `
            -RouteBasePath 'docs' -SkipWorkflow -SkipGate
        Test-Path -LiteralPath (Join-Path $customRoute 'documentation' 'src' 'pages' 'index.md') | Should -BeTrue
    }

    It 'points the installed GeneratedFiles Path into the selected directory' {
        $projectDir = Join-Path $TestDrive 'custom-dir-rules'
        & $script:setupScript -ProjectDir $projectDir -Title 'Rules Project' -DocsDirectory 'documentation' `
            -SkipWorkflow

        $rules = Import-PowerShellDataFile -LiteralPath (Join-Path $projectDir '.config' 'DocumentationRules.psd1')
        $rules.GeneratedFiles[0].Path | Should -Be 'documentation/docs/index.md'
    }

    It 'substitutes -SourceDocs in both generated workflows and leaves no ./docs behind' {
        $projectDir = Join-Path $TestDrive 'custom-dir-workflows'
        & $script:setupScript -ProjectDir $projectDir -Title 'Workflow Project' -DocsDirectory 'documentation' `
            -SkipGate

        $ci = Get-Content -LiteralPath (Join-Path $projectDir '.github' 'workflows' 'docs-ci.yml') -Raw
        $deploy = Get-Content -LiteralPath (Join-Path $projectDir '.github' 'workflows' 'docs-deploy.yml') -Raw

        $ci | Should -Match '-SourceDocs \./documentation'
        $ci | Should -Not -Match '-SourceDocs \./docs '
        $deploy | Should -Match '-SourceDocs \./documentation'
        $deploy | Should -Not -Match '-SourceDocs \./docs '
    }

    It 'is idempotent under -Overwrite for a custom directory' {
        $projectDir = Join-Path $TestDrive 'custom-dir-idempotent'
        & $script:setupScript -ProjectDir $projectDir -Title 'Idempotent Project' -DocsDirectory 'documentation' `
            -SkipWorkflow -SkipGate
        {
            & $script:setupScript -ProjectDir $projectDir -Title 'Idempotent Project' -DocsDirectory 'documentation' `
                -Overwrite -SkipWorkflow -SkipGate
        } | Should -Not -Throw

        Test-Path -LiteralPath (Join-Path $projectDir 'documentation' 'docusaurus.config.ts') | Should -BeTrue
    }
}
