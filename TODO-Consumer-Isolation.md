# TODO — Consumer Isolation

Created: 2026-07-27

A consumer site built from `ghcr.io/the-running-dev/docs-template` inherits routes
from the image's own `src/pages/`, including the site root. This plan closes that,
and picks up the secondary findings reported alongside it.

## P0 — The image leaks its own pages into every consumer site

**Reproduced**, not taken on report. A scratch consumer with exactly one authored
Markdown file:

```text
/                 Welcome | Leak Repro
/cv               CV/Resume | Leak Repro
/portfolio        Portfolio | Leak Repro
/projects         Projects | Leak Repro
/admin/projects   Admin • Projects | Leak Repro
/docs             Leak Repro          <- the only route the consumer authored
```

Five routes the consumer never wrote, wearing the consumer's own `title`. The
root is the damaging one: with `routeBasePath: 'docs'` the consumer's landing
page is the template's "Welcome" page, and nothing in their `docs/` can displace
it.

### Root cause, and a detail the report did not cover

`src/pages/` compiles from the image's `siteDir`, not from the mounted content
directory, so a consumer cannot suppress it. But **the two build paths disagree**,
which is why this was not caught earlier:

| Path                                              | Strips `src/pages`? | Result  |
| ------------------------------------------------- | ------------------- | ------- |
| `docs/Dockerfile` — consumer local preview        | yes (`rm -rf`)      | no leak |
| `scripts/docs-build.ps1` — CI, and what publishes | **no**              | leaks   |

A consumer's local preview therefore does not match their published site, and
**that divergence is currently documented nowhere.** An earlier draft of the
consumer guide did describe it — the now-deleted `planning/AGENTS-docs-section.md`
said "what sits at `/` differs by build path", framing it as a quirk rather than
a defect. It was dropped when that file was condensed into
`docs/getting-started/installing-the-docs-system.md`, whose "Serving path"
section covers only `routeBasePath` and homepage link rewriting. So the one
description of the symptom that existed was lost before anyone recognised it was
the defect.

`.dockerignore` already excludes `src/pages/*.md` and `src/pages/demos/`, so the
image ships exactly the seven files the report lists — the exclusion mechanism is
in place and simply does not cover the rest.

### Decision needed before implementing: what should `/` do?

Removing the pages is not in question. What replaces the root is, and it changes
behaviour for existing consumer sites either way.

First, two things established by experiment, against an image built with
`src/pages` excluded:

- **Deleting the pages is mandatory, not one option among several.** Tested
  against the _current_ image, setting `routeBasePath: '/'` makes the template's
  `index.tsx` win the root and the README-derived homepage **disappear entirely** —
  no README content anywhere on the site. A consumer supplying their own
  `docs/src/pages/index.md` today gets `Duplicate routes found!` and wins only by
  ordering.
- Once the pages are gone, all three shapes below build cleanly with zero leaked
  routes and zero duplicate warnings. The difference is where the README lands.

| Option                                                    | README served at     | URL churn |
| --------------------------------------------------------- | -------------------- | --------- |
| **(a)** delete, keep `routeBasePath: 'docs'`              | `/docs/` only        | none      |
| **(b)** delete, also generate a second README page at `/` | `/` **and** `/docs/` | none      |
| **(c)** delete, set `routeBasePath: '/'`                  | `/` only             | yes       |

**(b) is the weakest and should not be built.** Verified: it serves
byte-identical content at two URLs. That means two generated files, two
`GeneratedFiles` drift checks, and two pages competing in search results. The
README already becomes a page; generating it twice does not give a consumer a
homepage they own, it gives them the same homepage twice.

**(c) is the strongest.** The README-derived page simply _is_ the site root — one
copy, one URL, no redirect machinery and no second generator output. It also
fixes a defect recorded elsewhere as unresolved: the homepage generator rewrites
the published site origin to `/`, which only resolves when docs serve from the
root. Confirmed under (c) a README link to `https://docs.example.com/guide`
becomes `href="/guide"`; under (a) it still points at a route that does not exist.

Recommendation: **(c) for new installs, (a) for existing ones** — the same code
path. Delete `src/pages` from the image and default `routeBasePath: '/'` in the
installed config. Existing consumers are untouched because the installer skips
files that already exist; their config changes only under `-Overwrite`, which is
opt-in. That meets the no-churn criterion without freezing new projects into the
worse shape. The cost is that `/docs/*` and `/*` are then both in the wild, so the
guide must state which shape a project is on.

### Tasks

- [ ] Exclude the remaining `src/pages/` from the image via `.dockerignore`. The
      template's own site is built from the repository by `release.yml`, not from
      the image, so its pages are unaffected.
- [ ] Make `scripts/docs-build.ps1` fail loudly if `siteDir` still contains
      `src/pages` at build time, so the two paths cannot silently diverge again.
- [ ] Reconcile `docs/Dockerfile`: once the image ships no pages, the line that
      removes `src/pages` there is dead. Remove it, or keep it as
      belt-and-braces with a comment saying which layer is authoritative.
- [ ] Implement the chosen root behaviour and document how a consumer owns `/`.
- [ ] Extend the "Serving path" section of the consumer guide. It does not
      currently mention leaked pages or the preview/CI divergence at all, so this
      is new content rather than a correction, and it should describe the fixed
      behaviour once P0 lands.

Acceptance criteria (from the report, plus one):

- [ ] A docs-only consumer build emits no route the consumer did not author,
      other than Docusaurus built-ins (`404.html`, `sitemap.xml`, `assets/`).
- [ ] `find <out> -name index.html` yields only `/docs/*` and, at most, a root
      that is empty-by-design or a redirect.
- [ ] A consumer can define `/` without shadowing an image file.
- [ ] Existing `/docs/*` routes are unchanged — no URL churn.
- [ ] **Local preview and the CI build produce the same route set.** Verify both,
      not just CI; their disagreement is what hid this.

## P1 — `Invoke-DocsBuild` fails under `--user`

Not in the report. Found while reproducing it.

```bash
docker run --rm -v "$PWD:/work" -w /work --user "$(id -u):$(id -g)" \
  ghcr.io/the-running-dev/docs-template:latest \
  Invoke-DocsBuild -SourceDocs /work/docs -OutputPath /work/artifacts/docs
```

```text
Access to the path '/template/Dockerfile' is denied.
```

`docs-build.ps1` overlays the consumer's `docs/` onto `/template`, which is
root-owned, so a non-root `--user` cannot write there. The report's reproduce
command omits `--user` and therefore works.

This matters because **the published consumer guide tells readers to use exactly
that command, with `--user`**, under "To reproduce what CI builds, without
pushing". The instruction fails for everyone who follows it. `--user` is correct
for `Invoke-SetupDocs`, which writes into the mount, and wrong for
`Invoke-DocsBuild`, which writes into the image.

- [ ] Fix the guide: drop `--user` from the `Invoke-DocsBuild` example and say why
      the two commands differ.
- [ ] Consider having `docs-build.ps1` stage into a writable directory instead of
      `/template`, so `--user` works uniformly. Larger change; the doc fix is the
      immediate one.

## P2 — Secondary findings from the report

Ordered as reported. All lower priority than P0.

### 1. Gate anchor slugs disagree with GitHub

`build/Test-Documentation.ps1` derives `#phase-1-correctness-fixes` where GitHub
derives `#phase-1--correctness-fixes` for `## Phase 1 — Correctness fixes`. The
same file cannot satisfy both, and both are read.

- [ ] Match GitHub's algorithm: strip the em dash, keep the separator either side,
      collapsing nothing.
- [ ] Add a regression test with an em dash heading, and one with an en dash.
- [ ] If matching is rejected, document the divergence in the consumer guide's
      gate section rather than leaving it to be discovered.

### 2. `Test-Documentation.ps1` is documented as runnable but is not exposed

The guide says `./build/Test-Documentation.ps1`; the dispatcher rejects it, since
only `Invoke-DocsBuild`, `Invoke-SetupDocs` and `Invoke-SetupDocsWorkflow` are
exposed. It works only with host `pwsh`, or via `--entrypoint pwsh`.

- [ ] Expose it as `Invoke-DocsTest` in `PSModule/PSModule.psd1` and regenerate,
      so the documented command works from the image.
- [ ] Note that the gate needs the consumer's `build/` and `.config/` at their
      installed paths, so the container invocation needs the mount — verify before
      documenting it.

### 3. `ConvertTo-DocumentationHomepage.ps1` is awkward to invoke directly

`-ReadmePath` is mandatory and undocumented, and output goes to stdout rather than
to a file, so the obvious invocation appears to do nothing.

- [ ] Default `-ReadmePath` to `<ProjectDir>/README.md`.
- [ ] Add `-OutputPath` that writes in place, keeping stdout as the default so
      existing callers — `setup-docs.ps1` and the gate — are unaffected.

### 4. Generated `sidebar.ts` carries a stale comment

Every consumer repo receives a comment referring to `engine/` and `games/`, folders
from the project this template was extracted from.

- [ ] Rewrite the comment in `scripts/template/sidebar.ts` in consumer terms.

## Confirmed working — do not regress

Verified in this investigation and worth protecting:

- `Invoke-SetupDocs` is non-destructive to existing content: 11 files created,
  only the `docs.yml` it replaces removed, every content file untouched.
- The "generator rewrites the site origin but not relative links" caveat is
  accurate, and the gate reports the resulting breakage precisely.
- `docs/static/CNAME` reaches the build output, so custom domains survive.
- The `docs-ci.yml` / `docs-deploy.yml` split keeps `pages`/`id-token` off the
  gate and build jobs.
