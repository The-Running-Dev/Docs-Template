---
id: quick-start
title: Quick Start
sidebar_position: 1
---

### 1. Copy and Setup

```bash
# Copy this template to your new project directory
cp -r Docusaurus-Template my-docs-site
cd my-docs-site

# Install dependencies
pnpm install

# Run setup script to configure template files (PowerShell)
.\scripts\Invoke-SetupDocs.ps1
```

### 2. Configure Your Site

Edit the following YAML configuration files to customize your documentation:

#### Core Configuration Files

- **`config/globalConfig.yml`** - Site metadata (title, tagline, description)
- **`config/navBarLinks.yml`** - Navigation bar links (position defaults to 'left')
- **`config/projects.yml`** - Projects component data
- **`config/portfolioData.yml`** - Portfolio component showcase
- **`config/cvData.yml`** - CV/resume timeline data
- **`config/badges.yml`** - GitHub badge system configuration
- **`config/giscus.yml`** - Comment system configuration

#### Framework Configuration

- **`docusaurus.config.ts`** - Docusaurus framework settings (plugins, themes)
- **`sidebars.ts`** - Documentation navigation structure
- **`src/css/custom.css`** - Custom styling and theme variables

**Note**: The template uses a YAML-based configuration system with automatic TypeScript type generation and validation.

### 3. Add Your Content

- Create markdown files in a `docs/` directory
- Add images to `static/img/`
- Customize the homepage in `src/pages/index.tsx` (if created)

### 4. Start Development

```bash
pnpm start
```
