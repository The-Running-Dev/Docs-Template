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
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$ReadmePath,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$Title = 'Home',

    [Parameter()]
    [string]$Description = '',

    [Parameter()]
    [string]$SiteUrl = ''
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
    $readme.Replace($SiteUrl, '/')
}

return $frontMatter + "`n" + $body
