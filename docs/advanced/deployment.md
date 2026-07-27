---
id: deployment
title: Deployment
sidebar_position: 3
---

## Release Workflow

The repository release workflow combines two outputs in a single run:

1. Build the Docusaurus site and deploy it to GitHub Pages.
2. Build and publish the `docs-template` container image to GitHub Container Registry.

The workflow lives in `.github/workflows/release.yml` and runs on pull requests to `main`, `push` to `main`, and `workflow_dispatch`.

### GitHub Pages

1. Update `static/CNAME` with your domain if needed.
2. Configure GitHub Pages in repository settings.
3. Open a pull request to `main`, push to `main`, or run the Release workflow manually.

The `build` job:

- runs inside `ghcr.io/the-running-dev/build-agent:latest`
- installs dependencies
- runs `pnpm run quality-ci`
- runs `pnpm run build:prod`
- on pull requests, validates the container image builds (`scripts/docs-build-image.ps1`, no push)
- on push/manual runs, versions, builds, and pushes the container image (see Container Registry below)
- uploads the Pages artifact from `artifacts/`

The `deploy` job then publishes the built site to GitHub Pages on push or manual runs.

## Container Registry

The same release workflow publishes the template container image to GitHub Container Registry.

- Image: `ghcr.io/the-running-dev/docs-template`
- On push or manual runs, the build job logs in to GHCR and runs `scripts/docs-build-image.ps1` to build the image from the root `Dockerfile` and push it as `:latest` plus an immutable GitVersion tag computed from `GitVersion.yml`.
- On pull requests the image is built for validation only (no login, no push).
- The workflow grants `packages: write` so the build job can push the image.

### Base Image Project Copy Behavior

The base image build defined in `Dockerfile` uses `/template` as the application directory.

- Project files are copied into `/template` during the image build.
- Template docs are explicitly removed (`/template/docs`) so downstream projects do not inherit sample docs.
- This keeps the base image reusable for derived projects that provide their own docs content.

For a derived image, see `Dockerfile.example`:

- It starts from `ghcr.io/the-running-dev/docs-template:latest`.
- It copies local files over `/template` with `COPY . .`.
- It runs `pnpm install --frozen-lockfile` after copy so local dependency changes are applied.

### Other Platforms

Build the site with `pnpm run build:prod` and deploy the `artifacts/` directory to your hosting provider.
