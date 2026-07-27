# Documentation System

Documentation lives under `docs/` and is published as a Docusaurus site. The
site itself is never checked into this project: `docs/Dockerfile` extends a
published base image and overlays `docs/` on top of it, so `docker build` pulls
everything needed. There is no Node install to maintain and no template
checkout to keep in sync.

Installed by `Invoke-SetupDocs`, either from the published image:

```bash
docker run --rm -v "$PWD:/work" -w /work --user "$(id -u):$(id -g)" \
  ghcr.io/the-running-dev/docs-template:latest \
  Invoke-SetupDocs -ProjectDir /work -Title 'My Project'
```

or as `scripts/setup-docs.ps1` from a template checkout. Re-run either with
`-Overwrite` to pick up upstream fixes. Pass `-BaseImage` to pin a specific
image tag instead of tracking `:latest`.

## Layout

| Path                                        | Notes                                                      |
| ------------------------------------------- | ---------------------------------------------------------- |
| `docs/docs/**`                              | Authored Markdown. Add pages here.                         |
| `docs/docs/index.md`                        | **Generated from `README.md`. Do not edit.**               |
| `docs/docusaurus.config.ts`                 | Site title, URL, navbar, broken-link policy.               |
| `docs/sidebar.ts`                           | Sidebar structure. Note the singular filename.             |
| `docs/Dockerfile`                           | `FROM` the base image, `COPY . .` to overlay this folder.  |
| `docs/.dockerignore`                        | Keeps the build context to the overlay.                    |
| `docs.ps1`                                  | Local preview entry point.                                 |
| `build/ConvertTo-DocumentationHomepage.ps1` | README to homepage generator.                              |
| `build/Test-Documentation.ps1`              | The documentation gate.                                    |
| `.config/DocumentationRules.psd1`           | Gate rules: terminology, exclusions, generated-file drift. |
| `.github/workflows/docs-ci.yml`             | Gate and build verification.                               |
| `.github/workflows/docs-deploy.yml`         | Build and deploy to GitHub Pages.                          |

Documentation is served under `/docs` by default — the installed
`docusaurus.config.ts` keeps `routeBasePath: 'docs'`. Two consequences worth
knowing, because they are easy to trip over:

- **`docs/docs/index.md` is not the site root.** It is the landing page of the
  documentation section, at `/docs/`. What sits at `/` differs by build path:
  local preview via `docs.ps1` strips `src/pages`, so `/` has no page at all,
  while the CI build overlays onto the full template and inherits the
  template's own landing page there.
- **The homepage generator rewrites the published site origin to `/`**, which
  assumes documentation is served from the root. Under `routeBasePath: 'docs'`
  those rewritten links do not land on the generated homepage.

Setting `routeBasePath: '/'` in `docs/docusaurus.config.ts` makes all of this
coherent — the generated homepage becomes the site root and the origin rewrite
resolves — at the cost of moving every page's URL. The installer does not do it
for you, because for a project already serving from `/docs` that is a breaking
change rather than a fix.

## The homepage is generated — never edit it by hand

`docs/docs/index.md` is produced from `README.md`. The gate re-runs the
generator and fails if the committed copy differs, so a hand edit cannot
survive: the next regeneration overwrites it, and CI stays red until the two
agree.

**To change the homepage, edit `README.md`,** then regenerate:

```bash
./docs.ps1 -BuildOnly
```

That regenerates `docs/docs/index.md` as a side effect of building the preview
image. Commit `README.md` and the regenerated homepage together. A README change
committed without it fails with:

```
docs/docs/index.md:13:1 [Error] GeneratedFile: Generated from 'README.md' but the committed copy differs. Regenerate it, then commit the result.
```

The title, description, and site origin the generator uses are recorded in the
`GeneratedFiles` block of `.config/DocumentationRules.psd1`, not passed on the
command line. The preview script and the gate both read them from there, so the
two cannot disagree about what the homepage should contain.

### Known trap: relative links in the README

The generator rewrites the published site origin to `/`, but does **not** rewrite
relative links. A README link that is valid at the project root breaks once the
content is copied two directories deeper:

```
README.md            See [the guide](docs/guide.md)     valid
docs/docs/index.md   See [the guide](docs/guide.md)     resolves to docs/docs/docs/guide.md
```

The gate reports it as a `MarkdownLink` error against `docs/docs/index.md`. In
the README, prefer absolute links to the published site for anything the homepage
needs to reach — they become site-relative automatically.

## Running the gate

```bash
./build/Test-Documentation.ps1
```

```bash
./build/Test-Documentation.ps1 -Path README.md
```

`-Path` takes one or more files or directories and defaults to the whole project.
`-SettingsPath` overrides the rules file. `-TreatWarningsAsErrors` fails the run
on warnings too.

The project root is found by walking up for a `.git` marker, so the gate works
wherever it is installed, but the project must be a git repository.

### What it checks

| Rule             | Severity | Meaning                                                      |
| ---------------- | -------- | ------------------------------------------------------------ |
| `MarkdownLink`   | Error    | Relative link target does not exist on disk.                 |
| `MarkdownAnchor` | Error    | `#fragment` matches no heading in the target document.       |
| `GeneratedFile`  | Error    | A generated file no longer matches its source.               |
| `Terminology`    | Warning  | Product name cased inconsistently, e.g. `Github` → `GitHub`. |

Errors always fail the run, locally and in CI. **Warnings are reported but do
not fail anything**, because the installed `docs-ci.yml` invokes the gate
without `-TreatWarningsAsErrors`. If you want a terminology slip to block a
merge, add that switch to the gate step in `.github/workflows/docs-ci.yml`;
until then, treat a warning as something to fix by habit rather than something
CI will catch for you.

External `http(s)`, `mailto`, and site-absolute (`/...`) links are deliberately
out of scope. The gate makes no network calls, and Docusaurus' own broken-link
pass covers site-absolute routes at build time.

### It will not flag your code samples

Fenced blocks, inline code spans, link targets, and bare URLs are blanked before
the rules run, with line and column numbers preserved, so a sample that
deliberately shows `Github` or `npm install` is not a finding.

If something in prose is flagged that should not be, edit
`.config/DocumentationRules.psd1` rather than working around the gate. It has
four keys:

- `Terminology` — required spellings and the variants to reject.
- `ExcludedSegments` — path segments never scanned, such as build output.
- `ExcludedFiles` — individual files to skip, relative to the project root.
- `GeneratedFiles` — drift checks, wrapped in `# --- GeneratedFiles:start ---`
  and `# --- GeneratedFiles:end ---` markers. **Keep the markers**; the installer
  locates the block by them to remove it when a project has no generated
  homepage.

Adding this project's own name and its common misspellings to `Terminology` is
usually the rule that earns its keep.

## Local preview

```bash
./docs.ps1
```

```bash
./docs.ps1 -Live
```

```bash
./docs.ps1 -BuildOnly
```

Requires Docker and nothing else. `-Live` bind-mounts `docs/` for hot reload;
`-Port`, `-Tag`, and `-BaseImage` are also available. The homepage is
regenerated on every run unless `-NoHomepage` is passed.

## CI

Two workflows. They are split rather than combined because a job can never
hold more permission than the workflow declaring it, so folding deploy in would
hand the gate and build jobs the `pages`/`id-token` grant they never use.

| Workflow          | Job             | Runs on        | Does                                                               |
| ----------------- | --------------- | -------------- | ------------------------------------------------------------------ |
| `docs-ci.yml`     | `documentation` | every trigger  | The gate. Pure PowerShell, no container. Read-only permissions.    |
| `docs-ci.yml`     | `verify`        | pull requests  | Builds the site in the base image and archives the Pages artifact. |
| `docs-deploy.yml` | `deploy`        | push to `main` | Builds and deploys to GitHub Pages. Holds `pages`/`id-token`.      |

Neither carries `paths:` filters: these are meant to be required status checks,
and a required check that never runs leaves a pull request permanently blocked.

The gate and the build are **not** the same check, which is why both exist. The
build catches what Docusaurus itself rejects — unresolved routes, MDX,
TypeScript, and config errors. The gate covers what the site build never sees:
`README.md`, which is not part of the site at all, plus relative link targets,
heading anchors, terminology, and drift between a generated file and its source.

`verify` archives the Pages artifact even though it deploys nothing. That step
tars the site with `tar --hard-dereference` and is the part most likely to break
on an image change, so running it on pull requests means the failure blocks a
merge instead of first appearing on `main`.

`deploy` holds the `github-pages` environment and concurrency group, so verify
runs never contend for the Pages lock.

## Setup the installer cannot do

- Enable GitHub Pages for the repository with source **GitHub Actions**.
- Make the docs checks **required** on the default branch, or a red run will not
  block a merge.
- If the base image is a private package, set the `REGISTRY_TOKEN` secret or make
  the package visible to this repository — CI cannot pull it otherwise.

## Before you commit documentation changes

1. Edited `README.md`? Run `./docs.ps1 -BuildOnly` and commit the regenerated
   `docs/docs/index.md` alongside it.
2. Run `./build/Test-Documentation.ps1` and resolve every finding — warnings
   included, since CI blocks on them.
3. Added a page under `docs/docs/`? Confirm it appears where you expect in the
   sidebar.
