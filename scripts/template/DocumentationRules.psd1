@{
    # Product and technology names whose casing must stay consistent across
    # authored documentation. Each Required spelling lists the incorrect
    # variants to reject. Matching is case-sensitive and whole-word, and runs
    # only over prose: fenced code, inline code, link targets, and bare URLs are
    # masked before these rules apply, so `npm install`, ```powershell fences,
    # and github.com URLs are never flagged.
    #
    # These are the names most projects share. Add your own product name and its
    # common misspellings; that is usually the rule that earns its keep.
    Terminology = @(
        @{ Required = 'GitHub'; Variants = @('Github', 'GitHUB', 'Git Hub') }
        @{ Required = 'GitLab'; Variants = @('Gitlab', 'Git Lab') }
        @{ Required = 'PowerShell'; Variants = @('Powershell', 'Power Shell') }
        @{ Required = 'JavaScript'; Variants = @('Javascript', 'Java Script') }
        @{ Required = 'TypeScript'; Variants = @('Typescript', 'Type Script') }
        @{ Required = 'Node.js'; Variants = @('NodeJS', 'Nodejs', 'node js') }
        @{ Required = 'npm'; Variants = @('NPM', 'Npm') }
        @{ Required = 'Docusaurus'; Variants = @('DocuSaurus', 'docusaurus') }
        @{ Required = 'Dockerfile'; Variants = @('DockerFile', 'docker file', 'Docker file') }
        @{ Required = 'Docker Compose'; Variants = @('docker compose', 'Docker-Compose') }
        @{ Required = 'macOS'; Variants = @('MacOS', 'Mac OS', 'macos', 'OSX') }
        @{ Required = 'JSON'; Variants = @('Json') }
        @{ Required = 'YAML'; Variants = @('Yaml', 'yaml file') }
    )

    # Path segments never scanned. Generated, vendored, and dependency trees are
    # not authored here.
    ExcludedSegments = @(
        '.git'
        'artifacts'
        'build'
        'coverage'
        'dist'
        'node_modules'
    )

    # --- GeneratedFiles:start ---
    # Files generated from another file, checked for drift rather than scanned.
    # Each entry names the generated file, its source, and the script that
    # produces the expected content, all relative to the project root. The
    # generator and this check share that script so they cannot disagree.
    #
    # Set SiteUrl to the published origin, with a trailing slash, so absolute
    # links in the README resolve to site-relative links on the homepage.
    #
    # Path here follows Arguments.RouteBasePath: 'docs/docs/index.md' when it
    # is '/' (the README becomes the docs index), or 'docs/src/pages/index.md'
    # for any other value (the README becomes the site root instead, since
    # nothing else routes '/' at a non-root routeBasePath). setup-docs.ps1
    # substitutes both together from the same value, so they cannot disagree.
    #
    # The start/end markers above and below are load-bearing: setup-docs.ps1
    # locates this exact block by those two comment lines to remove it entirely
    # when -NoHomepage is passed. Keep them if you edit this block by hand.
    GeneratedFiles = @(
        @{
            Path = 'docs/docs/index.md'
            Source = 'README.md'
            Generator = 'build/ConvertTo-DocumentationHomepage.ps1'
            SourceParameter = 'ReadmePath'
            Arguments = @{
                Title = 'Home'
                Description = ''
                SiteUrl = ''
                RouteBasePath = '/'
            }
        }
    )
    # --- GeneratedFiles:end ---

    # Individual files excluded from scanning, relative to the project root.
    ExcludedFiles = @(
        'CHANGELOG.md'
    )
}
