---
id: real-world-examples
title: Real-World Examples
sidebar_position: 4
---

This section showcases how the Docusaurus Template is used in actual production environments, including automated deployment scenarios and integration with CI/CD pipelines.

## Which Script to Use

- Use `./scripts/setup-docs.ps1` when you want to initialize a docs folder in a project.
- Use `./scripts/setup-docs.ps1 -DockerDocs -Live` when you want setup plus local Docker docs serving in one command.
- Use `./scripts/docs.ps1` when you only want the dedicated Docker docs build/run workflow.

## Docker Build Agent Integration

One of the most powerful use cases for this template is integration with containerized build environments. Here's how the template is deployed for the **Docker Build Agent** project using an automated PowerShell script.

### Overview

The Docker Build Agent project uses this template to generate documentation dynamically as part of its build process. The approach demonstrates:

- **Containerized Template Deployment**: Using Docker to ensure consistent environments
- **Automated Content Generation**: Copying template files and configuring the documentation
- **Development Workflow Integration**: Seamless local development with hot-reload

### The Deployment Script

The following script (`scripts/docs.ps1`) shows a complete real-world implementation:

```powershell
#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Builds and serves the Docker Build Agent documentation locally for development.

.DESCRIPTION
    This script provides a streamlined way to build and serve the Docusaurus documentation
    for local development. It performs two main phases:

    1. Template Build Phase: Uses the Docker Build Agent to prepare the documentation
       environment and copy necessary template files
    2. Development Server Phase: Installs dependencies and starts a local development
       server with hot-reload capabilities

.EXAMPLE
    .\scripts\docs.ps1

    Builds the documentation and starts a development server at http://localhost:3000

.NOTES
    Requirements:
    - Docker must be installed and running
    - pnpm must be available in the host system PATH
    - The documentation directory must contain a valid Docusaurus project
#>

# Configuration
$appDir = '.\documentation'

# Phase 1: Template Build using Docker Build Agent
Write-Host "🔨 Phase 1: Preparing Documentation Environment..." -ForegroundColor Cyan

& docker run `
    --rm `
    -v ./:/workspace `
    -it ghcr.io/the-running-dev/build-agent:latest `
    node-template-build `
        -AppDir $appDir `
        -PackageManager 'pnpm' `
        -NodeTemplateRepositoryUrl 'https://github.com/The-Running-Dev/Docusaurus-Template.git#feature/comments_badges' `
        -SkipInstall `
        -IsProduction:$false

# Phase 2: Local Development Server Setup
Write-Host "🚀 Phase 2: Starting Development Server..." -ForegroundColor Green

$appDirPath = Join-Path . $appDir -Resolve

# Create command script for the new PowerShell session
$command = @"
Write-Host "📁 Changing to App Directory: $appDirPath" -ForegroundColor Yellow
Set-Location '$appDirPath'

Write-Host "📦 Installing Dependencies with pnpm..." -ForegroundColor Yellow
& pnpm install

Write-Host "⚙️ Running Pre-Build Step..." -ForegroundColor Yellow
& pnpm run prebuild:prod

Write-Host "🌐 Starting Development Server..." -ForegroundColor Green
Write-Host "   📍 URL: http://localhost:3000" -ForegroundColor Cyan
Write-Host "   🔄 Hot-Reload Enabled for Live Editing" -ForegroundColor Cyan
& pnpm start
"@

Start-Process pwsh `
    -ArgumentList "-NoExit", "-Command", $command

Write-Host "✅ Documentation Build Complete!" -ForegroundColor Green
Write-Host "   The Development Server Should Start Shortly in the New Window." -ForegroundColor White
Write-Host "   Visit http://localhost:3000 to View Your Documentation." -ForegroundColor White
```

### How It Works

#### Phase 1: Template Deployment

```powershell
& docker run `
    --rm `
    -v ./:/workspace `
    -it ghcr.io/the-running-dev/build-agent:latest `
    node-template-build `
        -AppDir $appDir `
        -PackageManager 'pnpm' `
        -NodeTemplateRepositoryUrl 'https://github.com/The-Running-Dev/Docusaurus-Template.git#feature/comments_badges' `
        -SkipInstall `
        -IsProduction:$false
```

**What happens here:**

1. **Container Execution**: Runs the build agent in a Docker container
2. **Workspace Mounting**: Maps the current directory to `/workspace` in the container
3. **Template Fetching**: Downloads the latest template from the specified Git branch
4. **Configuration**: Sets up the documentation in the `documentation/` directory
5. **Package Manager**: Configures for pnpm usage
6. **Skip Installation**: Defers package installation to the host system for better performance

#### Phase 2: Development Server

```powershell
$command = @"
Set-Location '$appDirPath'
& pnpm install
& pnpm run prebuild:prod
& pnpm start
"@

Start-Process pwsh -ArgumentList "-NoExit", "-Command", $command
```

**What happens here:**

1. **Dependency Installation**: Runs `pnpm install` on the host system
2. **Pre-build Processing**: Executes template-specific preparation scripts
3. **Development Server**: Starts Docusaurus with hot-reload in a new PowerShell window
4. **Persistent Window**: Keeps the server window open for monitoring and control

### Key Benefits of This Approach

#### 🐳 **Containerized Consistency**

- Ensures the same template version across all environments
- Eliminates "works on my machine" issues
- Provides isolated, reproducible builds

#### 🚀 **Automated Workflow**

- Single command execution: `.\scripts\docs.ps1`
- No manual template copying or configuration
- Integrated dependency management

#### 🔄 **Development-Friendly**

- Hot-reload enabled for instant preview
- Separate PowerShell window for server monitoring
- Easy to stop/start development cycles

#### 🎯 **Production-Ready**

- Same script can be adapted for CI/CD pipelines
- Version-controlled template references
- Flexible configuration options

### Customization Options

You can adapt this approach for your own projects by modifying key parameters:

#### Template Source

```powershell
-NodeTemplateRepositoryUrl 'https://github.com/YourOrg/Your-Template.git#main'
```

#### Output Directory

```powershell
$appDir = '.\docs'  # or any directory you prefer
```

#### Package Manager

```powershell
-PackageManager 'npm'  # or 'yarn'
```

#### Production Mode

```powershell
-IsProduction:$true  # for production builds
```

### Integration Scenarios

#### CI/CD Pipeline Integration

```yaml
# GitHub Actions example
- name: Generate Documentation
  run: |
    docker run --rm -v ${{ github.workspace }}:/workspace \
      ghcr.io/the-running-dev/build-agent:latest \
      node-template-build \
        -AppDir ./docs \
        -PackageManager 'npm' \
        -NodeTemplateRepositoryUrl 'https://github.com/YourOrg/Template.git#main' \
        -IsProduction:$true
```

#### Multi-Project Documentation

```powershell
# Generate docs for multiple projects
$projects = @('api-docs', 'user-guides', 'admin-docs')
foreach ($project in $projects) {
    & docker run --rm -v ./:/workspace `
        ghcr.io/the-running-dev/build-agent:latest `
        node-template-build `
            -AppDir ".\$project" `
            -NodeTemplateRepositoryUrl 'https://github.com/YourOrg/Template.git#main'
}
```

### Prerequisites

Before using this approach in your own projects:

#### Required Tools

- **Docker**: Must be installed and running
- **PowerShell**: Cross-platform PowerShell (pwsh)
- **Package Manager**: pnpm, npm, or yarn available in PATH

#### Docker Image

The script uses `ghcr.io/the-running-dev/build-agent:latest` which includes:

- Node.js runtime
- Template deployment tools
- Git for repository cloning
- Build automation scripts

#### Network Access

- Internet connection for template downloading
- Docker Hub/GitHub Container Registry access
- Git repository access for template source

### Troubleshooting Common Issues

#### Container Permission Issues

```powershell
# On Linux/macOS, you might need:
& docker run --rm -v ./:/workspace --user $(id -u):$(id -g) `
    ghcr.io/the-running-dev/build-agent:latest `
    node-template-build # ... rest of parameters
```

#### Port Conflicts

```powershell
# If port 3000 is in use, modify the start command:
& pnpm start -- --port 3001
```

#### Template Branch Issues

```powershell
# Ensure the branch exists and is accessible:
-NodeTemplateRepositoryUrl 'https://github.com/YourOrg/Template.git#feature-branch'
```

This real-world example demonstrates how the Docusaurus Template can be seamlessly integrated into complex development workflows, providing consistency and automation while maintaining flexibility for different project needs.
