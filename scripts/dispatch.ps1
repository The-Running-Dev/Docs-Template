<#
.SYNOPSIS
    Container command dispatcher. Not run directly by a user -- entrypoint.sh
    execs this for any argv[0] that is not 'dev', 'pwsh', 'sh', or 'bash'.

.DESCRIPTION
    Imports the DocusaurusTemplate module and calls the exported command named
    by the first argument, passing the rest through as its parameters.

    Deliberately has no param() block. A formal parameter that collects the
    remainder via ValueFromRemainingArguments (e.g. [string[]]$Arguments) does
    capture '-ProjectDir', '/work', '-Title', 'My Title' correctly, but
    splatting that array back with @Arguments then binds every element
    POSITIONALLY -- '-ProjectDir' ends up as the literal value of the first
    parameter, not re-recognized as a flag name. Confirmed by reproduction:
    identical string content only re-binds correctly by name when it comes
    from this script's own automatic $args, sliced and re-splatted with @ --
    not when reconstructed into a new array first. This is exactly that shape,
    so -ProjectDir /work -Title "My Title" -Overwrite reaches Invoke-SetupDocs
    as real named parameters and switches, not as positional string literals.
#>
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

if ($args.Count -lt 1) {
    throw 'dispatch.ps1 requires a command name as the first argument.'
}

$command = $args[0]

# Not `$rest = if (...) { ... } else { @() }`: an empty array returned from an
# if/else expression's branch collapses to $null on assignment, not an empty
# array, so $rest.Count below would throw under Set-StrictMode. A plain
# assignment followed by a conditional overwrite avoids the collapse.
$rest = @()
if ($args.Count -gt 1) { $rest = $args[1..($args.Count - 1)] }

$moduleManifest = Join-Path $PSScriptRoot '../PowerShell/DocusaurusTemplate/DocusaurusTemplate.psd1'
Import-Module $moduleManifest -Force -ErrorAction Stop

$resolved = Get-Command -Name $command -Module DocusaurusTemplate -ErrorAction SilentlyContinue
if (-not $resolved) {
    $available = (Get-Command -Module DocusaurusTemplate).Name -join ', '
    throw "'$command' is not a command this image exposes. Available: $available"
}

# Splatting a literal empty array is not the same as passing no arguments:
# `& $resolved @()` binds every optional parameter to an empty string instead
# of applying its default, where `& $resolved` with no splat at all correctly
# leaves defaults in place. Confirmed by reproduction. So a bare command name
# with no further arguments must skip the splat entirely, not splat @rest
# while it happens to be empty.
if ($rest.Count -gt 0) {
    & $resolved @rest
}
else {
    & $resolved
}
