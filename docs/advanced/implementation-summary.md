---
id: implementation-summary
title: Architecture
sidebar_position: 2
---

This section consolidates key enhancements and the current technical architecture:

## 1. Enhancements

- **Automatic Versioning**: Eliminated `VERSION.txt`, now uses `PreBuild.getVersion()` for on-the-fly YYYY.MM.DD versions.
- **README Integration**: Markdown files from project root are copied to `src/pages` and indexed for navigation via pre-build.
- **Navbar Autogeneration**: Scans root `.md` files and emits `src/navbarLinks.ts` before each build.
- **Badge System**: `BadgeConfig` static class + `useConfig` hook for dynamic GitHub badges.
- **Comments**: `GiscusConfig` static class for Giscus-powered discussions.
- **Theme System**: Ten built-in themes in `static/themes/` with live light/dark switching.

## 2. Architecture

- **Scripts**: TypeScript class `PreBuild` handles both content preparation and versioning.
- **Components**: Modular React hooks and components for badges and comments.
- **Config Classes**: Strongly-typed classes (`BadgeConfig`, `GiscusConfig`, `VersionConfig`) replace JSON imports for static access.

## 3. Workflow

- **Development**: `pnpm run start` runs pre-build tasks then starts `docusaurus start`.
- **Production Build**: `pnpm run build:prod` triggers production pre-build, then `docusaurus build --out-dir ./artifacts`.
- **Release Workflow**: `.github/workflows/release.yml` validates the container image build on pull requests and, on push/manual runs, builds and pushes it via `scripts/docs-build-image.ps1` (`:latest` + an immutable GitVersion tag), then deploys Pages.
- **Type Checking**: `pnpm run typecheck` ensures all TS scripts and components validate.
