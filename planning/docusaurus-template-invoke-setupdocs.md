# Invoke-SetupDocs

> **Not published documentation.** A planning brief describing work in a
> *different* repository, `The-Running-Dev/Docusaurus-Template`. It lives outside
> `docs/` so it does not appear on the PSGenerator documentation site.

Build `scripts/Invoke-SetupDocs.ps1` in the template repository: one command that
sets a consumer repository up with the documentation system this repository
(`SubZeroDev.PSGenerator`) arrived at, so the next project does not have to
rediscover it.

## Decisions

| | |
| --- | --- |
| Scope | Scaffolding, local preview, **and** the documentation quality gate |
| Gate in CI | A standalone `docs-quality.yml` the script owns outright |
| README as homepage | On by default, with a switch to opt out |
| Delivery | `scripts/Invoke-SetupDocs.ps1`, beside the existing scripts |

## Already in the template — reuse, do not rewrite

- [ ] Read `scripts/setup-docs.ps1`. It creates `docs/` and `docs/docs/`, seeds
      `docs/docs/index.md` from a root README or a stub, seeds
      `docs/docusaurus.config.ts` and `docs/sidebar.ts` from `scripts/template/`,
      and calls the workflow installer unless `-SkipWorkflow`.
- [ ] Read `scripts/setup-docs-workflow.ps1`. It copies `docs-ci.yml` and
      `docs-deploy.yml` from `scripts/template/` into `.github/workflows`,
      honouring `-Overwrite`.
- [ ] Decide: absorb both into `Invoke-SetupDocs.ps1` and keep them as thin
      wrappers for compatibility, or have `Invoke-SetupDocs.ps1` call them.
      Prefer calling them — they already work and are tested by use.

## New assets to add to the template repository

These do not exist yet and must be authored in `scripts/template/` so the setup
script has something to copy.

- [ ] `scripts/template/docs.yml` — the trigger-carrying caller. `docs-ci.yml`
      and `docs-deploy.yml` declare `workflow_call` only, so **nothing runs them
      today**. This calls `docs-ci.yml` on `pull_request` and `docs-deploy.yml`
      on `push` to `main`, with `permissions` covering the superset the deploy
      needs (`contents: read`, `packages: read`, `pages: write`,
      `id-token: write`) and `secrets: inherit` so `REGISTRY_TOKEN` reaches the
      called workflow.
- [ ] `scripts/template/docs-quality.yml` — runs the documentation gate on
      `pull_request` and `push`. Ubuntu, `shell: pwsh`, checkout, then
      `./build/Test-Documentation.ps1`. No container needed: the gate is pure
      PowerShell.
- [ ] `scripts/template/Dockerfile` — local preview only. `FROM` the published
      base image, `WORKDIR /template`, remove the template's own `docs` and
      `src/pages`, then `COPY . .` to overlay the consumer's `docs/`.
      **Do not** remove `src/theme/NotFound`: since #33 the template's 404 only
      links to routes it is given, and CI's `docs-build.ps1` overlays without
      deleting, so removing it locally would make preview differ from the
      published site.
- [ ] `scripts/template/.dockerignore` — keep the preview build context small.
- [ ] `scripts/template/docs.ps1` — the consumer's root preview script. Wraps
      `docker build` and `docker run`, regenerates the homepage before building,
      and supports `-BuildOnly`, `-Live`, `-Port`, `-Tag`, `-BaseImage`.
- [ ] `scripts/template/ConvertTo-DocumentationHomepage.ps1` — returns the
      expected `docs/docs/index.md` content: Docusaurus front matter followed by
      the README with the production origin rewritten to `/`. **Both** the
      preview script and the gate must call this one implementation; a second
      copy would be free to disagree, which is the failure the drift check
      exists to catch.
- [ ] `scripts/template/Test-Documentation.ps1` — the gate. Reports
      `MarkdownLink`, `MarkdownAnchor`, `Terminology`, and `GeneratedFile`
      findings, prints `path:line:col [Severity] Rule: message`, and throws with
      a count. Port from `build/Test-Documentation.ps1` in this repository.
- [ ] `scripts/template/DocumentationRules.psd1` — terminology rules, excluded
      path segments, excluded files, and `GeneratedFiles`. Ship a **generic**
      default: product names any project would want (`PowerShell`, `GitHub`,
      `NuGet`, `Docusaurus`, `macOS`), not this project's rename guards.

## What Invoke-SetupDocs installs into a consumer

- [ ] `docs/docusaurus.config.ts` and `docs/sidebar.ts` (existing behaviour)
- [ ] `docs/docs/index.md`, generated from the root README unless `-NoHomepage`
- [ ] `docs/Dockerfile` and `docs/.dockerignore`
- [ ] `docs.ps1` at the repository root
- [ ] `build/ConvertTo-DocumentationHomepage.ps1`
- [ ] `build/Test-Documentation.ps1`
- [ ] `.config/DocumentationRules.psd1`
- [ ] `.github/workflows/docs.yml`, `docs-ci.yml`, `docs-deploy.yml`
- [ ] `.github/workflows/docs-quality.yml`

## Parameters

- [ ] `-ProjectDir` — target repository, default `.`
- [ ] `-ScriptDir` — where PowerShell tooling lands, default `build`. Not every
      repository has a `build/`; do not hardcode it.
- [ ] `-ConfigDir` — where the rules file lands, default `.config`
- [ ] `-NoHomepage` — skip the README homepage generator and the
      `GeneratedFiles` entry that checks it
- [ ] `-SkipWorkflow` — install no workflows
- [ ] `-SkipGate` — install no gate, for a consumer that only wants a site
- [ ] `-Overwrite` — replace existing files; without it, skip and report
- [ ] `-WhatIf` — via `SupportsShouldProcess`, so a consumer can see what would
      change before it changes

## Behaviour

- [ ] **Idempotent.** Re-running with no switches changes nothing and reports
      what it skipped. This matters because the workflows are deliberately kept
      byte-identical to the template so the script can be re-run to pick up
      upstream fixes.
- [ ] **Never edit a file the script does not own.** That is why the gate ships
      as its own workflow rather than a job appended to the consumer's test
      workflow.
- [ ] **Report a summary**: created, skipped, overwritten, with paths.
- [ ] **Rewrite paths inside copied assets.** `docs.ps1` and the gate reference
      `build/` and `.config/`; if `-ScriptDir` or `-ConfigDir` differ, the copied
      files must be adjusted, not copied verbatim.

## Verify against a scratch repository

- [ ] Run into an empty directory with a README; confirm every artifact lands.
- [ ] Run again; confirm nothing changes and the summary says so.
- [ ] Run with `-Overwrite`; confirm files are replaced.
- [ ] `./docs.ps1 -BuildOnly` builds; `pnpm run build` inside the image compiles
      with no broken links.
- [ ] `./build/Test-Documentation.ps1` passes on the scaffolded content.
- [ ] Break something on purpose and confirm each rule fires: a dangling
      relative link, a bad `#anchor`, a terminology violation, and a README
      edited without regenerating the homepage.
- [ ] Run with `-NoHomepage`; confirm no `GeneratedFiles` entry and no drift
      finding.

## Pitfalls, each of which cost time here

- [ ] **A `generated-index` category needs an explicit `slug`.** It defaults to
      `/category/<name>`, so linking to `/using` 404s until the slug is set. The
      site build catches it; nothing else does.
- [ ] **`docs-ci.yml` must archive the Pages artifact**, not just build. The
      archive step is where a deploy breaks, and it only runs on `main`
      otherwise — meaning a green pull request and a broken deploy seconds
      later. Already fixed upstream; keep it.
- [ ] **`upload-pages-artifact` needs GNU tar.** Alpine's BusyBox tar rejects
      `--hard-dereference`. The base image installs GNU tar for this reason; do
      not drop it.
- [ ] **README links must be absolute** (`https://<site>/...`), because the same
      file is rendered on GitHub and as the site homepage. The generator rewrites
      the production origin to `/`; a relative link would break one of the two.
- [ ] **`trailingSlash: false` means `/next/` 404s while `/next` works.** Expect
      it, and do not write trailing slashes in links.
- [ ] **GHCR packages are private by default.** A documented `docker pull` fails
      for everyone but the owner until visibility is changed. Worth a line in the
      generated README section, or a note in the script's final summary.
- [ ] **Do not add Docusaurus versioning.** It was set up here and removed: with
      one version, a snapshot is a second copy to keep in step, and re-cutting it
      requires temporarily removing `lastVersion` because Docusaurus refuses to
      load a config naming a version `versions.json` does not list.
