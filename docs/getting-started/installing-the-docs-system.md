---
id: installing-the-docs-system
title: Installing the Docs System
sidebar_position: 5
---

How to add this documentation system to a project that is not this repository.
Everything below runs from the published container image — no Node install, no
template checkout to keep in sync.

The same content is written to be pasted into a consumer project's `AGENTS.md`,
so an agent working in that repository has it to hand.

## Install

```bash
docker run --rm -v "$PWD:/work" -w /work --user "$(id -u):$(id -g)" \
  ghcr.io/the-running-dev/docs-template:latest \
  Invoke-SetupDocs -ProjectDir /work -Title 'My Project' -SiteUrl 'https://docs.example.com/'
```

- **Mount the whole project, including `.git`.** The documentation gate finds
  the project root by walking up for a `.git` marker and fails without it.
- **`--user "$(id -u):$(id -g)"`** matters on Linux hosts; without it the
  container writes root-owned files into the repository.
- **`-ProjectDir` must point at the mount.** It defaults to `.`, and the image's
  own working directory is `/template`. Omit both and the command refuses to run
  rather than installing into the image itself.

Re-run with `-Overwrite` to pick up upstream fixes. `-BaseImage` pins a specific
image tag instead of tracking `:latest`, and is written to all four places an
install references the image.

Other commands the image exposes:

| Command                    | Purpose                                                  |
| -------------------------- | -------------------------------------------------------- |
| `Invoke-SetupDocs`         | Install or update the whole system.                      |
| `Invoke-SetupDocsWorkflow` | Install only the two workflows, leaving everything else. |
| `Invoke-DocsBuild`         | Build the static site, the same way CI does.             |
| `Invoke-DocsTest`          | Run the documentation gate.                              |

`Invoke-DocsBuildImage` and `Invoke-PreviewDocs` are in the module too, but they
drive Docker themselves, so they only run on a host — not inside the image.

## What gets installed

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

Upgrading from a version that installed four workflow files also deletes the two
now retired, `docs.yml` and `docs-quality.yml`. They are not merely redundant:
`docs.yml` drives the others with `uses:` and neither declares `workflow_call`
any more, and `docs-quality.yml` reports a check whose name collides with the
gate job in `docs-ci.yml`.

## Deploying

The workflows do the work; two things must be set up once, by hand, because the
installer cannot do them.

**1. Enable GitHub Pages.** Repository → _Settings_ → _Pages_ → _Source_:
**GitHub Actions**. Without this the deploy job fails at `configure-pages`.

**2. Make the checks required** on the default branch, or a red run reports but
does not block a merge. Require exactly these two — the ones that run on a pull
request, named as CI reports them:

```text
Documentation links and terminology
Verify Documentation Build
```

**Do not require `Build and Deploy Documentation`.** It comes from
`docs-deploy.yml`, which triggers only on push to `main`, so it never reports on
a pull request. Requiring it leaves every pull request waiting forever on a
check that will not arrive.

No registry credentials are needed: `ghcr.io/the-running-dev/docs-template` is a
public package, so the `github.token` the workflows already fall back to is
enough. The `REGISTRY_TOKEN` secret they also accept is only required when
`-BaseImage` points at a private fork or mirror.

Then the flow is automatic:

- **Pull request** → the gate runs and the site builds, archiving the Pages
  artifact. Nothing is published.
- **Push to `main`** → `docs-deploy.yml` builds the site in the base image,
  uploads the Pages artifact, and deploys it.

The published URL is the `url` plus `baseUrl` in `docs/docusaurus.config.ts`.
`-SiteUrl` sets **`url` only** — `baseUrl` keeps the template's `/`, and is
independent of `-RouteBasePath`. For a
GitHub Pages _project_ site, served at `https://<owner>.github.io/<repo>/`, that
is wrong and every asset 404s, so set `baseUrl: '/<repo>/'` by hand after
installing. A user or organisation site, or a custom domain served from the
root, can leave it alone. Deployments appear under the repository's
_Environments → github-pages_.

To reproduce what CI builds, without pushing:

```bash
docker run --rm -v "$PWD:/work" -w /work \
  ghcr.io/the-running-dev/docs-template:latest \
  Invoke-DocsBuild -SourceDocs /work/docs -OutputPath /work/artifacts/docs
```

Note the missing `--user` here, unlike the install command above. `Invoke-DocsBuild`
overlays your `docs/` onto the image's root-owned `/template` before building, so a
non-root user cannot write there and the run fails with
`Access to the path '/template/Dockerfile' is denied`. `Invoke-SetupDocs` writes
into the mount instead, which is where `--user` matters.

## Local preview

```bash
./docs.ps1              # build and serve
./docs.ps1 -Live        # bind-mount docs/ for hot reload
./docs.ps1 -BuildOnly   # build only; regenerates the homepage
```

Requires Docker and nothing else. `-Port`, `-Tag`, and `-BaseImage` are also
available. The homepage is regenerated on every run unless `-NoHomepage` is
passed.

## The homepage is generated

`docs/docs/index.md` is produced from `README.md`. The gate re-runs the generator
and fails if the committed copy differs, so a hand edit cannot survive.

To change the homepage, edit `README.md`, then run `./docs.ps1 -BuildOnly` and
commit both together. A README change committed without the regenerated homepage
fails the gate with `GeneratedFile: Generated from 'README.md' but the committed
copy differs`.

The title, description, and site origin the generator uses live in the
`GeneratedFiles` block of `.config/DocumentationRules.psd1`, not on the command
line, so the preview script and the gate cannot disagree about what the homepage
should contain.

:::warning Relative links in the README
The generator rewrites the published site origin to `/`, but does **not** rewrite
relative links. A link valid at the project root breaks once the content is
copied two directories deeper — `docs/guide.md` becomes `docs/docs/docs/guide.md`
and the gate reports a `MarkdownLink` error. Prefer absolute links to the
published site for anything the homepage needs to reach.
:::

## The documentation gate

```bash
./build/Test-Documentation.ps1
./build/Test-Documentation.ps1 -Path README.md
```

Those need PowerShell on the host. Without it, run the gate from the image:

```bash
docker run --rm -v "$PWD:/work" -w /work --user "$(id -u):$(id -g)" \
  ghcr.io/the-running-dev/docs-template:latest Invoke-DocsTest
```

| Rule             | Severity | Meaning                                                      |
| ---------------- | -------- | ------------------------------------------------------------ |
| `MarkdownLink`   | Error    | Relative link target does not exist on disk.                 |
| `MarkdownAnchor` | Error    | `#fragment` matches no heading in the target document.       |
| `GeneratedFile`  | Error    | A generated file no longer matches its source.               |
| `Terminology`    | Warning  | Product name cased inconsistently, e.g. `Github` → `GitHub`. |

Errors fail the run, locally and in CI. **Warnings are reported but do not fail
anything**, because the installed `docs-ci.yml` runs the gate without
`-TreatWarningsAsErrors`. Add that switch to the gate step if a terminology slip
should block a merge.

Fenced blocks, inline code spans, link targets, and bare URLs are blanked before
the rules run, so a sample that deliberately shows `Github` is not a finding. If
prose is flagged that should not be, edit `.config/DocumentationRules.psd1`
rather than working around the gate.

## Serving path

Documentation is served from the **site root** by default — the installer writes
`routeBasePath: '/'`, so the README-derived `docs/docs/index.md` is your landing
page at `/`.

Pass `-RouteBasePath docs` to serve under `/docs` instead. Two things to know if
you do:

- **The theme links to `/`.** Its 404 page and the docs navbar both do, so with
  nothing at the root Docusaurus reports two broken links your project never
  wrote. Harmless under the shipped `onBrokenLinks: 'warn'`, a failed build if
  you raise it to `'throw'`. You can supply your own root by adding
  `docs/src/pages/index.md`, which the overlay copies into place.
- **The homepage generator rewrites the published site origin to `/`**, which
  assumes serving from the root, so under `/docs` those rewritten links do not
  land on the generated homepage.

Neither applies on the default. Re-running the installer with `-Overwrite` will
**not** move an existing project: it keeps whatever `routeBasePath` your config
already has, and says so, unless you pass `-RouteBasePath` explicitly.

The template's own pages are not part of your site. Earlier images compiled
`src/pages` from the image into every consumer build, so sites inherited `/`,
`/cv`, `/portfolio`, `/projects` and `/admin/projects` under their own title.
They are no longer shipped, and the build removes any that a stale image still
carries.

## Before committing documentation changes

1. Edited `README.md`? Run `./docs.ps1 -BuildOnly` and commit the regenerated
   `docs/docs/index.md` alongside it.
2. Run `./build/Test-Documentation.ps1` and resolve every error. Warnings do not
   block CI, but fix them anyway — nothing else will.
3. Added a page under `docs/docs/`? Confirm it appears where you expect in the
   sidebar.
