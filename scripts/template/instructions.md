# Docs Workflow Installation

This repository provides two split docs workflow templates at:

- `scripts/template/docs-ci.yml` (verify)
- `scripts/template/docs-deploy.yml` (deploy)

The setup script copies both into caller repositories at:

- `.github/workflows/docs-ci.yml`
- `.github/workflows/docs-deploy.yml`

## Result

After running the installer, the caller repository has both docs workflows.
Each carries its own triggers rather than being driven by a caller workflow:

1. `docs-ci.yml` runs the gate and build verification on pull requests and
   pushes to `main`.
2. `docs-deploy.yml` builds and deploys to Pages on pushes to `main`.
3. Both are runnable manually from the Actions tab / `gh workflow run`.

Neither workflow runs on push or pull_request directly. Both run their steps
inside the published base image (`container:`), overlay the caller's `./docs`
over `/template`, and build via `scripts/docs-build.ps1`. Existing workflow files
are left untouched unless `-Overwrite` is passed.
