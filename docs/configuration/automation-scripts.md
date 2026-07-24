---
id: automation-scripts
title: Automation
sidebar_position: 3
---

The template includes setup and development PowerShell scripts to streamline the workflow:

### `scripts/setup-docs.ps1` - Template Configuration

Creates a baseline docs scaffold and prepares a copied template for first use.

**Usage:**

```powershell
# Run from template directory
.\scripts\setup-docs.ps1

# Or specify a different project directory
.\scripts\setup-docs.ps1 -ProjectDir "C:\path\to\project"
```

**What it does:**

- Creates `docs/` when missing
- Creates `docs/index.md` when missing
- Supports setup in any target folder via `-ProjectDir`
- Provides colored console output for progress tracking

**Perfect for:**

- Initializing a fresh copy of the template
- Bootstrapping docs folders in another repository
- Running a consistent setup step in local or CI workflows

### `template-build.ps1` - Development Server Launcher

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
