# Docusaurus Template

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

### � Enhanced User Experience

- **Custom 404 Page**: Interactive animated error page with engaging content
- **Related Resources**: Reusable component for contextual navigation
- **Theme System**: 12+ professional themes with live switching
- **Focus Management**: Enhanced accessibility with proper focus handling
- **New**: Cross-platform build script compatibility

## 🚀 Quick Start

```bash
# Copy template and install dependencies
cp -r Docusaurus-Template my-docs-site
cd my-docs-site
pnpm install

# Configure the template (PowerShell)
.\scripts\Invoke-SetupDocs.ps1

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

## 📖 Documentation

**👉 [Visit the Full Documentation](https://docs-template.subzerodev.com/template)**

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
