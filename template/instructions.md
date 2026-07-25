# Docs Workflow Installation

This repository provides a full docs workflow template at:

- `template/.github/workflows/docs.yml`

The setup script copies that file directly into caller repositories at:

- `.github/workflows/docs.yml`

## Result

After running `scripts/setup-docs-workflow.ps1`, the caller repository has a standalone Docs workflow that triggers on:

1. Pull requests (docs, workflow, and script changes)
2. Pushes to `main` (same paths)
3. Manual dispatch

No reusable workflow wiring is required.
