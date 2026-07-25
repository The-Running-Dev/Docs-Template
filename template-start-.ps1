#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Starts Docusaurus development server with optional Docker template setup.

.PARAMETER SkipTemplateSetup
    Skip Docker template setup and go directly to development server.

.EXAMPLE
    .\scripts\docs.ps1                      # Full setup with Docker
    .\scripts\docs.ps1 -SkipTemplateSetup   # Skip Docker, just start dev server
#>
param(
    [string]$appDir = '.',
    [switch]$SkipTemplateSetup
)

# Suppress Docker warnings
$env:DOCKER_CLI_HINTS = "false"

Write-Host "Using Directory: $appDir" -ForegroundColor Cyan

# Phase 1: Optional Docker template setup
if (-not $SkipTemplateSetup) {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        Write-Host "❌ Docker not Found. Use -SkipTemplateSetup to Bypass." -ForegroundColor Red
        exit 1
    }
    
    try {
        & docker info | Out-Null
    } catch {
        Write-Host "❌ Docker not Running. Use -SkipTemplateSetup to Bypass." -ForegroundColor Red
        exit 1
    }

    Write-Host "🔨 Setting up Templates..." -ForegroundColor Cyan
    
    $ttyArgs = @()
    
    if ($Host.UI.RawUI.KeyAvailable -or $env:TERM) { $ttyArgs += '-it' }
    & docker run `
        --rm `
        -v "${PWD}:/workspace" `
        @ttyArgs `
        ghcr.io/the-running-dev/build-agent:latest `
        node-template-build `
        -AppDir $appDir `
        -PackageManager pnpm `
        -SkipInstall -IsProduction:$false
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ Template Setup Failed" -ForegroundColor Red       
        exit $LASTEXITCODE
    }
}

# Phase 2: Start development server in new window
$appDirPath = if ([System.IO.Path]::IsPathRooted($appDir)) { $appDir } else { 
    Join-Path (Get-Location) $appDir -Resolve 
}

$devCommand = @"
Set-Location '$appDirPath'
if (-not (Get-Command pnpm -ErrorAction SilentlyContinue)) {
  Write-Host '❌ pnpm not Found. Please Install pnpm.' -ForegroundColor Red
  exit 1
}
Write-Host '📦 Installing Dependencies...' -ForegroundColor Yellow
pnpm install
Write-Host '⚙️ Running prebuild:prod...' -ForegroundColor Yellow  
pnpm run prebuild:prod
Write-Host '🌐 Starting Server at http://localhost:3000' -ForegroundColor Green
pnpm start
"@

Write-Host "🚀 Starting Development Server..." -ForegroundColor Green
Start-Process pwsh -ArgumentList "-NoExit", "-Command", $devCommand
Write-Host "✅ Server Starting in New Window: http://localhost:3000" -ForegroundColor Green