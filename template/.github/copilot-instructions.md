# Docusaurus Template - AI Coding Instructions

## Architecture Overview

This is a **reusable Docusaurus 3.8.1 template** with TypeScript, designed for professional documentation sites with advanced theming, commenting, and project badging systems.

### Core Components

**Pre-Build System** (`scripts/pre-build.ts`):
- Automatically copies root `.md` files to `src/pages/` (README.md → index.md)
- Auto-generates `src/navbarLinks.ts` from markdown files (excludes index.md from navbar)
- Uses date-based versioning (YYYY.MM.DD format)
- Run before every start/build via `prestart` and `prebuild:prod` npm scripts

**Dynamic Theme System** (`src/components/ThemeSwitcher/`):
- 10 predefined themes in `static/themes/` (blue, sunset, purple, material-*, etc.)
- Dynamically injects CSS links with `data-theme-switcher` attribute
- Persists selection in localStorage as `docusaurus-theme-color`
- Default theme uses built-in `src/css/custom.css`

**GitHub Links System** (`src/components/GitHubLinks/`):
- Navbar component for GitHub-related links with FontAwesome icons
- Configuration in `src/config/github-links-config.ts` with TypeScript interfaces
- Supports dropdown or inline layouts with external link indicators
- Pre-configured with Docker BuildAgent project links

**GitHub Badge System** (`src/components/GitHubProjectBadges/`):
- Configuration in `src/config/badge-config.ts` with template variables
- Groups badges by categories (build, docs, demo, etc.)
- Supports FontAwesome icons and dynamic URL templating

**Comments Integration** (`src/components/GiscusComments/`):
- Consolidated GitHub Discussions integration via @giscus/react
- Auto-adapts to Docusaurus dark/light theme
- Configuration in `src/config/giscus-config.ts`
- Unified component with integrated validation and fallback UI
- Conditionally rendered via frontmatter `comments: false`

### Key Patterns

**Theme Integration**:
- Swizzled `src/theme/DocItem/index.tsx` wraps original DocItem with GiscusComments
- Uses `@theme-original/*` imports for extending default behavior
- Components use CSS custom properties: `var(--ifm-color-primary)`

**Configuration Architecture**:
- Static classes for configs: `GiscusConfig`, `BadgeConfig`, `VersionConfig`, `GitHubLinksConfig` in `src/config/`
- Template variables system for dynamic badge URLs
- TypeScript interfaces for type safety

**Build Workflow**:
```bash
pnpm run prestart  # Copies markdown + generates navbar
pnpm start         # Development server
pnpm run prebuild:prod && pnpm run build:prod  # Production
```

### Development Commands

**Essential Scripts**:
- `.\template-build.ps1` - Full development setup (install + prebuild + start)
- `pnpm run check-all` - Runs format:check + lint + typecheck
- `tsx ./scripts/pre-build.ts` - Manual pre-build execution

**File Generation**:
- `src/navbarLinks.ts` is AUTO-GENERATED - modify `scripts/pre-build.ts` instead
- Badge configs have both `.js` and `.ts` versions for compatibility

### Customization Points

**Theme Addition**:
1. Add CSS file to `static/themes/custom.{name}.css`
2. Update `themes` array in `src/components/ThemeSwitcher/ThemeSwitcher.tsx`
3. Add color preview CSS class: `.theme-switcher__color-preview--{name}`

**Content Structure**:
- Root markdown files → auto-copied to pages and navbar
- Docs content in `docs/template/` with hierarchical sidebars
- Static assets in `static/` (themes, images)

**Component Integration**:
- Use `useColorMode()` from `@docusaurus/theme-common` for theme awareness
- Follow swizzling pattern: import `@theme-original/*`, wrap with custom logic
- FontAwesome icons via `@fortawesome/react-fontawesome`

### Critical Dependencies

- **@docusaurus/core**: 3.8.1 (specific version dependencies)
- **@giscus/react**: GitHub Discussions comments
- **tsx**: TypeScript execution for pre-build scripts
- **pnpm**: Package manager (referenced in build scripts)

### Common Gotchas

- Pre-build step must run before start/build (handled by npm scripts)
- Theme CSS files load dynamically - ensure correct paths in `static/`
- Giscus requires exact repo format: `owner/repository`
- NavbarLinks auto-generation excludes `index.md` from navigation
