<#
.SYNOPSIS
    Builds the documentation homepage content from the project README.

.DESCRIPTION
    Returns what docs/docs/index.md should contain: Docusaurus front matter
    followed by the README, with the published site origin rewritten to a
    root-relative path.

    That rewrite is the point. The README is rendered twice — on the code host,
    where links must be absolute to work, and as the site homepage, where the
    same absolute links would send a reader back out to the site they are
    already on. Writing absolute links and rewriting them here keeps one file
    correct in both places.

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
    # docusaurus.config.ts. Absolute links to -SiteUrl are rewritten to this, so
    # a project serving under '/docs' gets links that resolve there instead of
    # at a site root that has no page.
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

$frontMatterLines = @(
    '---'
    "title: $(ConvertTo-YamlSingleQuotedScalar -Value $Title)"
)
if (-not [string]::IsNullOrWhiteSpace($Description)) {
    $frontMatterLines += "description: $(ConvertTo-YamlSingleQuotedScalar -Value $Description)"
}
$frontMatterLines += @(
    'sidebar_position: 1'
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
    # Trailing slash on both sides so '/docs' and '/docs/' behave the same and
    # the result never doubles a separator.
    $target = '/' + $RouteBasePath.Trim('/')
    if ($target -ne '/') { $target += '/' }
    $readme.Replace($SiteUrl, $target)
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
