# Docs Workflow Installation

This repository provides two split docs workflow templates at:

- `scripts/template/docs-ci.yml` (verify)
- `scripts/template/docs-deploy.yml` (deploy)

The setup script copies both into caller repositories at:

- `.github/workflows/docs-ci.yml`
- `.github/workflows/docs-deploy.yml`

## Result

After running `scripts/setup-docs-workflow.ps1`, the caller repository has both
docs workflows. Each declares `workflow_call` + `workflow_dispatch`, so:

1. The caller's **main** workflow drives them (verify vs deploy) via `uses:`.
2. Each is runnable manually from the Actions tab / `gh workflow run`.

Neither workflow runs on push or pull_request directly. Both run their steps
inside the published base image (`container:`), overlay the caller's `./docs`
over `/template`, and build via `scripts/docs-build.ps1`. Existing workflow files
are left untouched unless `-Overwrite` is passed.
