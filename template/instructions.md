# Common Docs Workflow Wiring

This repository provides a reusable docs workflow template at:

- `template/.github/workflow/docs.yml`

The setup script copies that file into caller repositories at:

- `.github/workflow/common/docs.yml`

## Why Two Locations?

- `.github/workflow/common` is used as a project-level source-of-truth location.
- GitHub reusable workflow calls (`jobs.<job>.uses`) require the callee file to live under `.github/workflows`.

Because of that GitHub requirement, add a copy/sync step in the caller repository:

1. Source: `.github/workflow/common/docs.yml`
2. Target: `.github/workflows/docs.yml`

## Caller Entry Workflow Example

Create `.github/workflows/docs-build.yml` in the caller repository:

```yaml
name: Docs

on:
  pull_request:
    paths:
      - '.github/workflows/docs-build.yml'
      - '.github/workflows/docs.yml'
      - '.github/workflow/common/docs.yml'
      - 'docs/**'
      - 'scripts/docs.ps1'
      - 'scripts/setup-docs.ps1'
      - 'README.md'
  push:
    branches:
      - main
    paths:
      - '.github/workflows/docs-build.yml'
      - '.github/workflows/docs.yml'
      - '.github/workflow/common/docs.yml'
      - 'docs/**'
      - 'scripts/docs.ps1'
      - 'scripts/setup-docs.ps1'
      - 'README.md'
  workflow_dispatch:

permissions:
  contents: read
  packages: read
  pages: write
  id-token: write

jobs:
  docs:
    uses: ./.github/workflows/docs.yml
    with:
      docs-script: ./scripts/docs.ps1
      image-tag-prefix: docs-site
      output-path: artifacts/docs
    secrets: inherit
```

## Optional Sync Helper (Caller Repo)

If you want to keep `.github/workflow/common/docs.yml` authoritative, add a sync script:

```powershell
Copy-Item \
  -LiteralPath .github/workflow/common/docs.yml \
  -Destination .github/workflows/docs.yml \
  -Force
```

Run this before pushing workflow updates.
