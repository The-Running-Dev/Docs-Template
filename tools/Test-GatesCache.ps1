#Requires -Version 7.0
<#
.SYNOPSIS
    Reads or writes .claude/gates.json - a cache of a repository's discovered gates, keyed
    to a hash of the files whose presence or content determines what the gate list is.

.DESCRIPTION
    /verify's own procedure (.claude/commands/verify.md, "Discover, do not assume") reads
    CI workflow files, package manifests, and known build-script paths every single run,
    even when none of them have changed since the last run. That discovery is genuine
    judgement the first time - CI is the authoritative list, and matching a workflow's
    steps to local commands takes reading, not just globbing - but re-deriving the same
    answer from an unchanged manifest on every run is the repeated-scan cost
    AGENTS.md's own model-work table calls out as maybe-avoidable.

    This script does not discover gates itself - that stays /verify's judgement call, and
    stays owned by verify.md. It only remembers the answer /verify already worked out, and
    says whether that answer is still trustworthy:

      (no -Write)   Compute the current manifest hash, compare it to .claude/gates.json.
                    Fresh   - hash matches. Emits the cached gates; /verify runs them
                              directly and skips discovery.
                    Stale   - a manifest file changed since the cache was written.
                              /verify re-discovers, then calls this script with -Write.
                    Missing - no cache yet. Same as Stale.

      -Write        Persist -GatesJson (an array of {name, command} objects) alongside the
                    current manifest hash. Call this once, right after /verify has done a
                    real discovery pass by hand.

    The manifest hash covers exactly the inputs verify.md's own discovery table reads:
    every `.github/workflows/*.yml` (content - a changed step is a changed gate list),
    `package.json` (content - scripts can be added, renamed, or removed), and the presence
    of `*.sln`/`*.csproj`, `build/Test-Documentation.ps1`,
    `build/Test-DocumentationArtifact.ps1`, and `docs.ps1` (existence only - what a project
    file contains is not this cache's concern, only whether the gate exists at all).
    Anything not in that list - a new `tools/*.Tests.ps1` file, for instance - will not
    invalidate the cache; the manifest is deliberately the same set verify.md already
    names, not a broader guess at what might matter.

.PARAMETER RepoRoot
    Repository to check or update. Defaults to the current directory.

.PARAMETER Write
    Write a new cache instead of checking the existing one. Requires -GatesJson.

.PARAMETER GatesJson
    A JSON array of gate objects, each with at least `name` and `command`. Only used with
    -Write.

.EXAMPLE
    ./tools/Test-GatesCache.ps1
    Check freshness; prints Fresh with the cached gates, or Stale/Missing.

.EXAMPLE
    ./tools/Test-GatesCache.ps1 -Write -GatesJson '[{"name":"Pester","command":"Invoke-Pester -Path tools"}]'
    Persist a freshly-discovered gate list against the current manifest hash.
#>
[CmdletBinding()]
param(
    [string] $RepoRoot = (Get-Location).Path,
    [switch] $Write,
    [string] $GatesJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($Write -and -not $GatesJson) {
    throw "-Write requires -GatesJson."
}

if (-not (Test-Path -LiteralPath $RepoRoot)) {
    throw "RepoRoot '$RepoRoot' does not exist."
}
$repoRootResolved = (Resolve-Path -LiteralPath $RepoRoot).Path
$cachePath = Join-Path $repoRootResolved '.claude/gates.json'

function Get-ManifestHash {
    <#
    Hashes exactly the inputs verify.md's discovery table reads: workflow and package
    manifest *content* (a step or script changing must invalidate the cache), and the
    *existence* of the known build-script paths (their content is not this cache's concern).
    #>
    param([string]$RepoRoot)

    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $parts = [System.Collections.Generic.List[string]]::new()

        $workflowDir = Join-Path $RepoRoot '.github/workflows'
        if (Test-Path -LiteralPath $workflowDir) {
            $workflows = Get-ChildItem -LiteralPath $workflowDir -Filter '*.yml' -File | Sort-Object Name
            foreach ($wf in $workflows) {
                $parts.Add("workflow:$($wf.Name):" + (Get-Content -LiteralPath $wf.FullName -Raw))
            }
        }

        $packageJsonPath = Join-Path $RepoRoot 'package.json'
        if (Test-Path -LiteralPath $packageJsonPath) {
            $parts.Add('package.json:' + (Get-Content -LiteralPath $packageJsonPath -Raw))
        }

        $existencePaths = @(
            'build/Test-Documentation.ps1',
            'build/Test-DocumentationArtifact.ps1',
            'docs.ps1'
        )
        foreach ($p in $existencePaths) {
            $exists = Test-Path -LiteralPath (Join-Path $RepoRoot $p)
            $parts.Add("exists:${p}:$exists")
        }

        $projectFiles = @(Get-ChildItem -LiteralPath $RepoRoot -Recurse -Depth 2 -Include '*.sln', '*.csproj' -File -ErrorAction SilentlyContinue |
            ForEach-Object { $_.FullName.Substring($RepoRoot.Length) } | Sort-Object)
        $parts.Add('projects:' + ($projectFiles -join '|'))

        $combined = $parts -join "`n---`n"
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($combined)
        $hashBytes = $sha256.ComputeHash($bytes)
        return [System.BitConverter]::ToString($hashBytes).Replace('-', '').ToLowerInvariant()
    } finally {
        $sha256.Dispose()
    }
}

$currentHash = Get-ManifestHash -RepoRoot $repoRootResolved

if ($Write) {
    $gates = $GatesJson | ConvertFrom-Json
    $cache = [pscustomobject]@{
        manifestHash = $currentHash
        generated    = (Get-Date -Format 'yyyy-MM-dd')
        gates        = $gates
    }
    $cacheDir = Split-Path -Parent $cachePath
    if (-not (Test-Path -LiteralPath $cacheDir)) {
        New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
    }
    ($cache | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $cachePath -NoNewline
    [pscustomobject]@{ Status = 'Written'; ManifestHash = $currentHash; GateCount = @($gates).Count }
    return
}

if (-not (Test-Path -LiteralPath $cachePath)) {
    [pscustomobject]@{ Status = 'Missing'; ManifestHash = $currentHash; Gates = @() }
    return
}

$existing = Get-Content -LiteralPath $cachePath -Raw | ConvertFrom-Json
if ($existing.manifestHash -ceq $currentHash) {
    [pscustomobject]@{ Status = 'Fresh'; ManifestHash = $currentHash; Generated = $existing.generated; Gates = @($existing.gates) }
} else {
    [pscustomobject]@{ Status = 'Stale'; ManifestHash = $currentHash; Gates = @() }
}
