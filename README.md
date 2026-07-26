# Docusaurus Template

[![codecov](https://codecov.io/gh/The-Running-Dev/Docusaurus-Template/branch/main/graph/badge.svg)](https://codecov.io/gh/The-Running-Dev/Docusaurus-Template)

A comprehensive, reusable Docusaurus template for creating professional documentation sites with modern features, YAML-based configuration, and data-driven components.

## ✨ Key Features

- 🚀 **Modern Docusaurus 3.8.1** with TypeScript support
- 🎨 **Dynamic Theme System** - 10+ themes with cross-route compatibility
- 📊 **Data-Driven Components** - Portfolio, Projects, CV components with YAML configuration
- 🏷️ **GitHub Badge System** - Automated project status badges
- 💬 **Giscus Comments** - GitHub Discussions integration
- ⚡ **Schema Validation** - Zod-based validation for all configuration data
- 🔧 **Developer Tools** - ESLint, Prettier, quality gates
- 📦 **Enhanced Build System** - Configurable output directory with pre-build automation
- 🛠️ **YAML Configuration** - User-friendly configuration system with automatic validation

## 🆕 Latest Features

### 📊 Component System

- **Portfolio Component**: Professional project showcase with filtering (`/portfolio`)
- **Projects Component**: Advanced project listing with search and URL state (`/projects`)
- **CV Component**: Professional timeline display with configurable data (`/cv`)
- **Live Demos**: Interactive demo pages for all components (`/demos/`)

### 🔧 Enhanced Configuration System

- **YAML-Based**: Replaced TypeScript configs with user-friendly YAML files
- **Schema Validation**: Automatic validation using Zod schemas
- **Type Safety**: Full TypeScript support with generated types
- **Live Reload**: Configuration changes trigger automatic reloads
- **New**: Cross-platform build script compatibility

## 🚀 Quick Start

```bash
# Copy template and install dependencies
cp -r Docusaurus-Template my-docs-site
cd my-docs-site
pnpm install

# Configure the template (PowerShell)
.\scripts\setup-docs.ps1

# Start development server with quality checks
pnpm run start
```

## 🛠️ Development Workflow

The template includes comprehensive development tooling:

```bash
# Development
pnpm run start          # Start dev server with pre-build
pnpm run build:prod     # Production build to ./artifacts

# Code Quality
pnpm run lint           # ESLint checking
pnpm run format         # Code formatting with Prettier
pnpm run typecheck      # TypeScript validation
pnpm run check-all      # Run all quality checks

# Utilities
pnpm run clear          # Clear Docusaurus cache
pnpm run serve          # Serve production build
```

## 🧩 Admin Editor (Phase 2 Optional)

Admin editing and API-backed project management are intentionally outside the default Phase 1 path.

- Admin route: `/admin/projects`
- Status: optional / Phase 2
- Recommendation: keep enabled only when you need authenticated project editing workflows
- Detailed API + admin operational guidance: `api/README.md`

### Unified Projects Manager

Run the same UI for public display and admin editing through one component.

- Components
  - `ProjectsManager`: Core component; toggles admin features with `isAdmin`/`adminToken`.
  - `ProjectsDisplay`: Thin wrapper for public display.
  - `ProjectsAdmin`: Thin wrapper that wires admin token settings and callbacks.

- Admin features
  - Selection actions: Select All (filtered), Clear, Bulk Delete.
  - Per-card Delete and click-to-edit form with Save.
  - Quick actions: Copy Slug / Link.
  - Import/Export JSON for filtered projects.
  - Toasts for quick feedback on Save/Delete/Import.
  - State persistence for Search and Filter in localStorage.

- Usage
  - Public: `import Projects from 'src/components/Projects'` or `import { ProjectsDisplay } from 'src/components/Projects'`.
  - Admin: `src/pages/admin/projects.tsx` renders `<ProjectsAdmin />` within the page layout.

See docs at `docs/guides/projects-manager.md` for details.

## 📊 Coverage Reports

- Local: `pnpm test:components:cov` generates HTML + LCOV in `coverage/` (open `coverage/index.html`).
- CI: GitHub Actions publishes a `coverage-report` artifact. If Codecov is configured (CODECOV_TOKEN), view coverage via the badge above.

## 📖 Documentation

**👉 [Visit the Documentation](https://docs-template.subzerodev.com/docs)**

For detailed setup guides, configuration options, theme customization, and examples, visit the complete documentation site.

### Key Documentation Sections

- **[Development Workflow](/docs/advanced/development-workflow)** - Enhanced tooling and quality assurance
- **[Theme System](/docs/core-systems/theme-system)** - 10 dynamic color themes
- **[Component Architecture](/docs/core-systems/)** - Badge system, GitHub links, comments
- **[Configuration](/docs/configuration/)** - YAML-based configuration system and setup options

## 🎯 Recent Updates

### Enhanced Development Experience

- **Modern ESLint v9**: Flat configuration with TypeScript support
- **Prettier Integration**: Automated code formatting with consistent styling
- **Quality Gates**: Pre-commit hooks and CI/CD integration
- **Enhanced Build System**: Configurable artifacts directory (`./artifacts`)
- **YAML Configuration**: User-friendly configuration with automatic validation

## 📄 License

This template is provided as-is for creating documentation sites. Check the LICENSE file for specific terms.
