---
id: automation-scripts
title: Automation
sidebar_position: 3
---

The template includes setup and development PowerShell scripts to streamline the workflow:

## `scripts/setup-docs.ps1` - Docs Scaffold + Workflow Install

Orchestration only (no Docker). Creates the `docs/` overlay and installs the
docs CI/deploy workflows.

**Usage:**

```powershell
# Run from template directory
.\scripts\setup-docs.ps1

# Or specify a different project directory
.\scripts\setup-docs.ps1 -ProjectDir "C:\path\to\project"

# Scaffold only, skip installing the workflows
.\scripts\setup-docs.ps1 -SkipWorkflow
```

**What it does:**

- Creates `docs/docs/` and `docs/docs/index.md` when missing
- Seeds `docs/docs/index.md` from root `README.md` or `readme.md` when available
- Seeds `docs/docusaurus.config.ts` and `docs/sidebar.ts` from the template when
  missing (optional overrides of the base image defaults)
- Installs `docs-ci.yml` / `docs-deploy.yml` unless `-SkipWorkflow`
- Supports setup in any target folder via `-ProjectDir`

The `docs/` directory is a self-contained overlay copied over the base image's
`/template` at build time: author markdown under `docs/docs/`, and override the
config/sidebar via `docs/docusaurus.config.ts` / `docs/sidebar.ts`.

## `scripts/docs.ps1` - Local Live Server

Run-only helper for local development. Runs the published base image (pulling it
if missing) and bind-mounts `./docs` over `/template` for hot reload. It does not
build the static site — that happens in CI via `scripts/docs-build.ps1`.

**Usage:**

```powershell
# Serve http://localhost:3000/docs with hot reload
.\scripts\docs.ps1

# Use a different host port
.\scripts\docs.ps1 -Port 8080
```

## `scripts/docs-build.ps1` - In-Image Static Build

Runs **inside** the base image (used by the CI workflows). Overlays `./docs` over
`/template`, runs `pnpm run build`, and copies the static site to the output
path. Not typically run by hand.

## `scripts/setup-docs-workflow.ps1` - Docs Workflow Installer

Copies both split workflow templates (`docs-ci.yml`, `docs-deploy.yml`) into a
caller repository under `.github/workflows`. Existing files are skipped unless
`-Overwrite` is passed.

**Usage:**

```powershell
# Copy both docs workflows to a caller repository
.\scripts\setup-docs-workflow.ps1 -CallerProjectDir "C:\path\to\caller"

# Overwrite existing target files
.\scripts\setup-docs-workflow.ps1 -CallerProjectDir "C:\path\to\caller" -Overwrite
```

## `template-build.ps1` - Development Server Launcher

**⚠️ Note:** This script has been simplified and now runs the development server directly in the current terminal rather than a separate window.

Automates the development workflow with comprehensive PowerShell documentation.

**Usage:**

```powershell
# Run from template directory (uses current directory)
.\template-build.ps1

# Or specify a different app directory
.\template-build.ps1 -appDir ".\my-docs-site"
```

**What it does:**

- Resolves full path to the documentation directory
- Installs dependencies using `pnpm install`
- Runs pre-build steps (`pnpm run prebuild` - content preparation and versioning)
- Starts Docusaurus development server (`pnpm start`)
- Includes comprehensive PowerShell help documentation

**Features:**

- 📖 **Full PowerShell Help** - Run `Get-Help .\template-build.ps1 -Full` for complete documentation
- 🔧 **Parameter Validation** - Validates directory paths and provides helpful errors
- 🚀 **pnpm Integration** - Uses pnpm for faster dependency management
- ⚙️ **Pre-build Integration** - Automatically runs version generation
- 🎨 **Visual Feedback** - Colored progress indicators and status messages

**Requirements:**

- `pnpm` package manager installed and available in PATH
- PowerShell execution policy allowing script execution
- Valid `package.json` with required scripts (`prebuild`, `start`)
- PowerShell 5.0 or higher
