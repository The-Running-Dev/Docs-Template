<#
.SYNOPSIS
    Builds the documentation homepage content from the project README.

.DESCRIPTION
    Returns Docusaurus front matter followed by the README, with the published
    site origin rewritten to a root-relative path.

    That rewrite is the point. The README is rendered twice — on the code host,
    where links must be absolute to work, and as a site page, where the same
    absolute links would send a reader back out to the site they are already
    on. Writing absolute links and rewriting them here keeps one file correct
    in both places.

    Where the result is meant to be installed depends on -RouteBasePath, which
    this script does not write to disk itself:

    - '/' means the docs are served from the site root, so this page IS the
      docs index (docs/docs/index.md) and gets sidebar_position: 1 to sort
      first.
    - Anything else means the docs are served from a sub-path, so this page is
      the site ROOT instead (docs/src/pages/index.md) -- outside the docs
      sidebar entirely, hence no sidebar_position -- with a link into the docs
      appended, since a bare README otherwise has no path back to them.

    Both the preview script and the documentation gate call this. Keeping one
    implementation is deliberate: a second copy would be free to disagree with
    the first, which is the failure the gate's drift check exists to catch.

.PARAMETER ReadmePath
    Path to the project README.

.PARAMETER Title
    Front matter title. Shown in the sidebar and browser tab.

.PARAMETER Description
    Front matter description. Used for search and social previews.

.PARAMETER SiteUrl
    Published site origin to rewrite to '/'. Include the trailing slash, so
    'https://docs.example.com/' becomes '/' and a link to
    'https://docs.example.com/guide' becomes '/guide'.

.OUTPUTS
    The expected file content as a single string, using LF line endings.

.EXAMPLE
    ./ConvertTo-DocumentationHomepage.ps1 -ReadmePath ./README.md -Title 'My Project'
#>
[CmdletBinding()]
param(
    # Defaults to README.md beside the project root rather than being mandatory:
    # invoking this directly is a reasonable thing to do, and it used to fail
    # with "missing mandatory parameters: ReadmePath" before doing anything.
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ReadmePath,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$Title = 'Home',

    [Parameter()]
    [string]$Description = '',

    [Parameter()]
    [string]$SiteUrl = '',

    # Where documentation is served, matching routeBasePath in
    # docusaurus.config.ts. This is NOT the -SiteUrl rewrite target -- that is
    # always '/', since an absolute link resolves against the site root. Using
    # this value instead double-prefixes any link already pointing into the
    # docs; see the note beside $docsTarget below.
    #
    # Also decides what this script is generating, entirely from this one
    # value: '/' means the result is the docs index; anything else means the
    # result is the site root page, which changes the front matter (no
    # sidebar_position -- this page is not in the docs sidebar) and appends a
    # link into the docs (this page's only path there).
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$RouteBasePath = '/',

    # Writes the document to this path instead of returning it. Without it the
    # result goes to stdout, which is what setup-docs.ps1 and the documentation
    # gate consume, so their behaviour is unchanged.
    [Parameter()]
    [string]$OutputPath
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

function ConvertTo-YamlSingleQuotedScalar {
    <#
    .SYNOPSIS
    Serializes a string as a single-line, single-quoted YAML scalar.

    Front matter fields here are single-line browser-tab/meta-description
    text, so an embedded newline is collapsed to a space rather than kept --
    keeping it would either break the YAML block or require a block-scalar
    style this file does not otherwise use, and either way a raw newline is
    exactly what lets a value close the front matter early and inject
    fabricated keys after it. Embedded single quotes are doubled, which is
    single-quoted YAML's own escape and cannot reopen the block either.
    #>
    param (
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Value
    )

    $collapsed = ($Value -replace '\r\n?|\n', ' ').Trim()
    return "'$($collapsed.Replace("'", "''"))'"
}

# -ReadmePath is optional, so resolve it before the guard below. Walks up for
# the .git marker the same way the gate locates the project root, so running
# this from anywhere inside the repository works.
if ([string]::IsNullOrWhiteSpace($ReadmePath)) {
    $searchDir = (Get-Location).Path
    while ($searchDir -and -not (Test-Path -LiteralPath (Join-Path $searchDir '.git'))) {
        $parent = Split-Path -Parent $searchDir
        if ($parent -eq $searchDir) { $searchDir = $null; break }
        $searchDir = $parent
    }

    if (-not $searchDir) {
        throw 'Could not locate the project root (no .git found above the current directory). Pass -ReadmePath explicitly.'
    }

    $ReadmePath = Join-Path $searchDir 'README.md'
}

if (-not (Test-Path -LiteralPath $ReadmePath -PathType Leaf)) {
    throw [System.IO.FileNotFoundException]::new(
        "README not found at '$ReadmePath'."
    )
}

# '/' means this page IS the docs index -- sidebar_position sorts it first,
# and it needs no link into the docs because it already is one. Anything else
# means this page is the site ROOT, generated outside the docs sidebar
# entirely, where sidebar_position would be meaningless and a bare README
# otherwise has no path into the docs at all.
$isRootPage = $RouteBasePath.Trim('/') -ne ''

# Where the docs live, with a trailing slash so '/docs' and '/docs/' behave the
# same and the result never doubles a separator. Used only for the root-page
# docs link below, which is why it is computed even when -SiteUrl is empty.
#
# Deliberately NOT the -SiteUrl rewrite target: -SiteUrl is the site origin, so
# an absolute link resolves against the site root, not against the docs base.
# Rewriting to $docsTarget instead would prefix every link that already points
# into the docs a second time -- 'https://site/docs/guide' -> '/docs/docs/guide'.
$docsTarget = '/' + $RouteBasePath.Trim('/')
if ($docsTarget -ne '/') { $docsTarget += '/' }

$frontMatterLines = @(
    '---'
    "title: $(ConvertTo-YamlSingleQuotedScalar -Value $Title)"
)
if (-not [string]::IsNullOrWhiteSpace($Description)) {
    $frontMatterLines += "description: $(ConvertTo-YamlSingleQuotedScalar -Value $Description)"
}
if (-not $isRootPage) {
    $frontMatterLines += 'sidebar_position: 1'
}
$frontMatterLines += @(
    '---'
    ''
)
$frontMatter = $frontMatterLines -join "`n"

# Normalize to LF first so a comparison never degrades into a line-ending diff.
$readme = (Get-Content -LiteralPath $ReadmePath -Raw) -replace "`r`n?", "`n"

$body = if ([string]::IsNullOrWhiteSpace($SiteUrl)) {
    $readme
}
else {
    $readme.Replace($SiteUrl, '/')
}

if ($isRootPage) {
    $body = $body.TrimEnd("`n") + "`n`n[View the documentation]($docsTarget)`n"
}

$document = $frontMatter + "`n" + $body

if ($PSBoundParameters.ContainsKey('OutputPath') -and -not [string]::IsNullOrWhiteSpace($OutputPath)) {
    $outputDir = Split-Path -Parent $OutputPath
    if ($outputDir -and -not (Test-Path -LiteralPath $outputDir -PathType Container)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }

    # LF and no BOM, matching how setup-docs.ps1 writes it, so the gate's
    # byte-for-byte drift check sees the same content either way.
    [IO.File]::WriteAllText($OutputPath, ($document -replace "`r`n", "`n"), [Text.UTF8Encoding]::new($false))
    Write-Host "[HOMEPAGE] Wrote $OutputPath" -ForegroundColor Green
    return
}

return $document
