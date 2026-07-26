#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Launches a Docusaurus development server with automated dependency installation and pre-build steps.

.DESCRIPTION
    This script automates the complete Docusaurus development workflow by:
    - Resolving the full path to the documentation directory
    - Installing dependencies using pnpm
    - Running pre-build steps (version generation)
    - Starting the development server with hot-reload in a separate PowerShell window
    
    The development server runs in an isolated window, allowing you to monitor logs
    and stop the server with Ctrl+C while keeping your main terminal free for other tasks.

.PARAMETER appDir
    The directory containing the Docusaurus application. Defaults to current directory ('.').
    Can be a relative or absolute path.

.EXAMPLE
    .\template-build.ps1
    Starts development server for Docusaurus app in current directory.

.EXAMPLE
    .\template-build.ps1 -appDir ".\my-docs-site"
    Starts development server for Docusaurus app in the specified subdirectory.

.EXAMPLE
    .\template-build.ps1 -appDir "C:\Projects\Documentation"
    Starts development server for Docusaurus app at the specified absolute path.

.INPUTS
    String - Directory path where the Docusaurus application is located

.OUTPUTS
    None - Opens development server in separate PowerShell window

.NOTES
    File Name      : template-build.ps1
    Author         : Docusaurus Template
    Prerequisite   : PowerShell 5.0+, pnpm package manager
    
    Requirements:
    - pnpm must be installed and available in PATH
    - Valid package.json with required scripts (prebuild:prod, start)
    - PowerShell execution policy allowing script execution
    
    The script performs Phase 2 of the development workflow:
    Phase 1 would typically be initial setup (scripts/Invoke-SetupDocs.ps1)
    Phase 2 (this script) handles dependency installation and server startup

.LINK
    https://docusaurus.io/docs/installation
    
.LINK
    https://pnpm.io/installation
#>

[CmdletBinding()]
param(
    [Parameter(
        Position = 0,
        ValueFromPipeline = $true,
        ValueFromPipelineByPropertyName = $true,
        HelpMessage = "Directory containing the Docusaurus application (default: current directory)"
    )]
    [ValidateNotNullOrEmpty()]
    [string]$appDir = '.'
)

$appDirPath = Join-Path . $appDir -Resolve

Write-Host "🚀 Phase 2: Starting Development Server..." -ForegroundColor Green
Write-Host "📁 Changing to App Directory: $appDirPath" -ForegroundColor Yellow
Set-Location $appDirPath

Write-Host "📦 Installing Dependencies with pnpm..." -ForegroundColor Yellow
& pnpm install

Write-Host "⚙️ Running Pre-Build Step..." -ForegroundColor Yellow
& pnpm run prebuild:prod

Write-Host "🌐 Starting Docusaurus Development Server..." -ForegroundColor Green
Write-Host "   📍 URL: http://localhost:3000" -ForegroundColor Cyan
Write-Host "   🔄 Hot-Reload Enabled for Live Editing" -ForegroundColor Cyan
Write-Host "✅ Build Complete!" -ForegroundColor Green
& pnpm start