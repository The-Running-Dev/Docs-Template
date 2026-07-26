---
id: automation-scripts
title: Automation
sidebar_position: 3
---

The template includes setup and development PowerShell scripts to streamline the workflow:

## `scripts/setup-docs.ps1` - Install the Documentation System

Installs everything a consuming project needs to author, preview, check, and
publish documentation from this template, in one command: the `docs/` overlay,
a root `docs.ps1` local preview entry point, the homepage generator, the
documentation gate, and the workflows that run them.

**Usage:**

```powershell
# Run from the target project directory
.\scripts\setup-docs.ps1 -ProjectDir "C:\path\to\project"

# Set the homepage title/description and the published site origin
.\scripts\setup-docs.ps1 -ProjectDir . -Title "My Project" -SiteUrl "https://docs.example.com/"

# Preview every action without writing anything
.\scripts\setup-docs.ps1 -Overwrite -WhatIf
```

**What it installs:**

- `docs/docusaurus.config.ts`, `docs/sidebar.ts` — site configuration
- `docs/Dockerfile`, `docs/.dockerignore` — local preview overlay on the
  published base image
- `docs/docs/index.md` — homepage, generated from the project `README.md`
- `docs.ps1` — local preview entry point (build/run the overlay, no Node
  install needed)
- `build/ConvertTo-DocumentationHomepage.ps1` — README-to-homepage generator
- `build/Test-Documentation.ps1` — the documentation gate: relative links,
  heading anchors, terminology casing, and drift between a generated file and
  its source
- `.config/DocumentationRules.psd1` — per-project gate rules
- `.github/workflows/docs.yml`, `docs-quality.yml`, plus `docs-ci.yml` /
  `docs-deploy.yml` (installed via `setup-docs-workflow.ps1`)

Idempotent: an existing file is left alone and reported as skipped unless
`-Overwrite` is passed, so the command can be re-run to pick up upstream fixes.
`-NoHomepage`, `-SkipWorkflow`, and `-SkipGate` narrow the install; `-ScriptDir`
(default `build`) and `-ConfigDir` (default `.config`) relocate the PowerShell
tooling and rules for projects that use different conventions.

The `docs/` directory is a self-contained overlay copied over the base image's
`/template` at build time: author markdown under `docs/docs/`, and override the
config/sidebar via `docs/docusaurus.config.ts` / `docs/sidebar.ts`.

## `scripts/preview-docs.ps1` - Local Live Server

Run-only helper for local development **of this template itself**. Runs the
published base image (pulling it if missing) and bind-mounts `./docs` over
`/template` for hot reload. It does not build the static site — that happens in
CI via `scripts/docs-build.ps1`.

This is not the `docs.ps1` that `setup-docs.ps1` installs into a
consuming project's root — that is a separate script under
`scripts/template/docs.ps1`, built and run by the consumer as `./docs.ps1`.

**Usage:**

```powershell
# Serve http://localhost:3000/docs with hot reload
.\scripts\preview-docs.ps1

# Use a different host port
.\scripts\preview-docs.ps1 -Port 8080
```

## `scripts/docs-build.ps1` - In-Image Static Build

Runs **inside** the base image (used by the CI workflows). Overlays `./docs` over
`/template`, runs `pnpm run build`, and copies the static site to the output
path. Not typically run by hand.

## `scripts/docs-build-image.ps1` - Build & Publish the Base Image

Builds the base `docs-template` image from the repository-root `Dockerfile` (the
image the docs workflows run inside) and optionally pushes it to a registry,
which creates/updates the registry package. This is the mechanism `release.yml`
uses to version, build, and publish the image on release, and it can also be run
locally.

**Usage:**

```powershell
# Build only (no push)
.\scripts\docs-build-image.ps1

# Build and push :latest to GHCR (already logged in via docker login)
.\scripts\docs-build-image.ps1 -Push

# Build, add a dated version tag, log in, and push both tags
.\scripts\docs-build-image.ps1 `
  -AdditionalTags ghcr.io/the-running-dev/docs-template:2026.07.25 `
  -Push -Username $env:GITHUB_ACTOR -Token $env:REGISTRY_TOKEN
```

Key parameters: `-Tag` (default `ghcr.io/the-running-dev/docs-template:latest`),
`-AdditionalTags`, `-Push`, `-Registry` (default `ghcr.io`), `-Username`,
`-Token`. With `-Token` the script logs in via `--password-stdin` before
pushing; without it, it assumes you are already authenticated.

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
