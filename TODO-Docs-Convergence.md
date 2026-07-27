# TODO — Documentation System Convergence

Created: 2026-07-27

Converges the two competing installers onto one, invocable from inside the
published container as `Invoke-SetupDocs`.

## Decision

`scripts/setup-docs.ps1` is the surviving installer.
`planning/Install-DocsSystem.ps1` is a consumer's re-derivation that dropped
three hardening guards present here — YAML front-matter injection escaping
(`ConvertTo-YamlSingleQuotedScalar`), `-ScriptDir`/`-ConfigDir` path-traversal
containment (`Resolve-ContainedProjectDirectory`), and Unicode-aware Docker tag
slugs (`ConvertTo-DockerTagSegment`) — and its `Get-PayloadFromImage` layer
becomes docker-in-docker once the installer runs inside the image. Its one good
idea, collapsing the workflow sprawl, is ported in Phase 1; the file is then
retired.

Each phase is a standalone pull request based on `feature/review`.

## Decisions taken

**Action versions — standardize on current majors.** Verified against the
GitHub API on 2026-07-27: every major currently in use resolves, so neither set
was broken. They were simply stale and inconsistent with each other, which made
consumer workflows and this repository's own workflows behave differently for no
stated reason.

| Action                  | This repo | Payload | Latest | Target |
| ----------------------- | --------- | ------- | ------ | ------ |
| `checkout`              | v4        | v6      | v7     | v7     |
| `upload-pages-artifact` | v3        | v4      | v5     | v5     |
| `configure-pages`       | —         | v5      | v6     | v6     |
| `deploy-pages`          | v4        | v4      | v5     | v5     |

The Node-on-musl risk originally recorded here has been **investigated and
resolved — no code change was needed**, and the original framing was wrong on
two counts:

- It implied the bump introduced Node 24. It does not: `actions/checkout@v6`,
  already in use before this work, declares `using: node24` — byte-identical to
  `v7`. The runtime is unchanged by the bump.
- It implied musl support was doubtful. GitHub's runner ships a musl build
  specifically for this case. `src/Misc/externals.sh` in `actions/runner`
  acquires `node24_alpine` from the `actions/alpine_nodejs` repository
  alongside the glibc `node24`, and that repository has `v24.18.0` published,
  matching the runner's pinned `NODE24_VERSION`. The runner detects a musl
  container and selects it.

Confirmed separately that the image itself has no glibc loader and no
`gcompat`/`libc6-compat` package, so it genuinely is musl-only — the runner's
alpine Node is what makes container jobs work, and adding a compat shim would
be cargo-culting.

Still worth noting: `upload-pages-artifact` and `deploy-pages` must stay
version-compatible with each other.

**Path filters — drop them.** Today's `docs.yml` filters on `docs/**`,
`README.md`, and `docs.ps1`. A required status check that never runs leaves a
pull request permanently blocked, and these checks are intended to be required.
The saving does not justify that failure mode.

**Pull request base — `feature/review`.** Each phase branches from and merges
back into `feature/review`; that branch reaches `main` once the series is
complete.

## P1 — Workflow split: four files to two

A single workflow must declare `pages: write` and `id-token: write` at workflow
scope, because a job can never hold more permissions than its workflow. That
hands deploy credentials to the gate and build jobs, which need only read.
Splitting is what preserves least privilege — this is why the consumer's
single-file `docs-ci.yml` is not adopted.

| File              | Jobs                              | Permissions                               | Triggers                 |
| ----------------- | --------------------------------- | ----------------------------------------- | ------------------------ |
| `docs-ci.yml`     | `documentation` (gate) · `verify` | `contents: read`, `packages: read`        | PR, push, dispatch       |
| `docs-deploy.yml` | `deploy`                          | above + `pages: write`, `id-token: write` | push to `main`, dispatch |

- [x] Fold the gate job from `docs-quality.yml` into
      `scripts/template/docs-ci.yml`; give that file real triggers (it is
      `workflow_call` only today) and keep its permissions read-only.
- [x] Add `push: branches: [main]` to `scripts/template/docs-deploy.yml`.
- [x] Declare the triggers without `paths:` filters, per the decision above, so
      a required check always reports.
- [x] Bump both the payload and this repository's own workflows to the target
      action versions in the table above. **Corrected after the fact:** this
      was recorded as done when only `scripts/template/*.yml` had been bumped.
      This repository's own workflows stayed on `checkout@v4`,
      `upload-pages-artifact@v3` and `deploy-pages@v4` until CI flagged the
      Node 20 deprecation on the first real run. They now match the table. The Node 24 / Alpine-musl concern
      first recorded against this item is resolved — see "Decisions taken"
      above. The bump does not change the Node runtime at all, and GitHub
      ships a musl Node 24 for container jobs.
- [x] Delete `scripts/template/docs.yml` (pure caller indirection) and
      `scripts/template/docs-quality.yml` (folded in).
- [x] Delete `scripts/setup-docs-workflow.ps1`; fold its two-file install back
      into `setup-docs.ps1`, removing the split-reporting note at
      `scripts/setup-docs.ps1:487-492`.
- [x] Rework `-SkipGate` so it excises a _job_ from `docs-ci.yml` rather than
      skipping a whole file, using the same start/end marker technique the
      `GeneratedFiles` block already uses. Factored into a shared
      `Remove-MarkedBlock` helper used by both.
- [x] Keep job `name:` values byte-identical, so any required-status-check
      context keeps matching. The three are `Documentation links and terminology`,
      `Verify Documentation Build`, and `Build and Deploy Documentation`.
- [x] Copy the workflow from the payload. Do **not** embed it as a here-string
      the way `planning/Install-DocsSystem.ps1:461-570` does; that reintroduces
      the drift this effort removes.
- [x] `AGENTS.md` did not name any of the retired files, so no correction was
      needed there. Added two "Recent Lessons Learned" entries instead: the
      permission-split rationale and the no-path-filters rationale, matching
      the file's existing pattern of repo-specific gotchas.

Acceptance criteria — all verified against the actual installer output and a
real `docker run` build, not just by reading:

- [x] A scratch install produces exactly two workflow files.
- [x] Both parse as valid YAML with the expected jobs, permissions, and
      triggers (verified with PyYAML; `actionlint` was not available in this
      environment to cross-check).
- [x] The gate job carries no `pages` or `id-token` permission — confirmed
      `docs-ci.yml`'s top-level `permissions:` is `contents: read`,
      `packages: read` only.
- [x] `-SkipGate` removes exactly the `documentation` job and keeps `verify` —
      confirmed by grepping the installed file.
- [x] `-WhatIf` writes nothing — confirmed 0 files on disk after a dry run.
- [x] The gate (`Test-Documentation.ps1`) and the build
      (`docs-build.ps1` inside `ghcr.io/the-running-dev/docs-template:latest`)
      both run successfully end-to-end against a Phase 1 install.
      A caveat found here — every install shipping an empty title, which
      Docusaurus rejects — was confirmed pre-existing rather than a Phase 1
      regression, and has since been fixed. See below.

### Upgrade path — found in final review, fixed

Collapsing four workflow files into two left every _existing_ consumer broken
on upgrade, because the installer wrote the two new files but never removed
the two it had retired:

- `docs.yml` drives the other workflows with `uses:`, and neither `docs-ci.yml`
  nor `docs-deploy.yml` declares `workflow_call` any more — so it fails
  outright on every run.
- `docs-quality.yml` runs the gate a second time under the job name
  `Documentation links and terminology`, byte-identical to the new gate job's
  name, so two different workflows report the same check context.

Reproduced by installing with `main`'s installer, then upgrading with the new
one and observing all four files still present. Fixed by having the installer
delete both retired files whenever it installs workflows.

- [x] `Remove-RetiredFile` deletes only the two fixed names, only under
      `.github/workflows`, only files — never a caller-supplied path.
- [x] Runs with or without `-Overwrite`: the retired files break the installed
      ones either way, so a plain re-run has to clear them too.
- [x] Reported under a `Removed` heading alongside Created/Replaced/Skipped.
- [x] Verified: `-Overwrite` upgrade cleans up, plain re-run cleans up,
      `-WhatIf` reports without deleting, a fresh install prints no spurious
      `Removed` section, and `-SkipWorkflow` leaves all four files untouched
      since the script is not managing workflows on that path.

### Generator fallback broke in a containerized job — found by CI, fixed

The first CI run failed `Build Documentation` with the specification "not
found" at `/workspace/PSModule/PSModule.psd1`, while `test` passed. The split
was the diagnosis: `test-and-coverage.yml` runs directly on the runner, and
`release.yml` runs inside the build-agent container.

The fallback bind-mounted the repository into a `docker run`. Inside a
container job the repository lives at `/__w/<repo>/<repo>`, and `-v` paths are
resolved by the Docker daemon on the **host**, where that path does not exist —
so the mount silently resolved to an empty directory.

The local "CI simulation" that preceded this gave false confidence: it removed
the sibling checkout but still ran on the host, never reproducing a
containerized job, which is the only condition that fails.

- [x] Replaced the bind mount with `docker create` + `docker cp`, extracting the
      generator module from the image and importing it locally. `docker cp`
      streams through the CLI rather than asking the daemon to mount a path, so
      it is indifferent to whether the caller is containerized. Nothing in the
      image is executed, which also removes the `--user` and writable-`HOME`
      workarounds the old approach needed.
- [x] Both sources now converge on one native build path, so local and CI runs
      execute identical code after the generator is resolved.
- [x] Verified in the failing condition this time: a container with the
      repository mounted at `/__w/...`, a path absent on the host, generates
      all five commands. Also re-verified the local and `-UseContainer` paths,
      with no staging directory or stray file left behind.
- [ ] Delete this fallback once the build agent ships SubZeroDev.PSGenerator
      itself. Extracting it from an image is a workaround at the wrong layer.

### Config substitution — found during Phase 1, fixed

`scripts/setup-docs.ps1`'s `Copy-TemplateFile` call for `docusaurus.config.ts`
passed no `-Replace` hashtable, so `-Title`, `-Description`, and `-SiteUrl`
never reached the installed file. Every install shipped the template's
placeholders, and Docusaurus rejects an empty title outright, so the installed
site could not build until someone hand-edited it. Pre-existing on `main`, not
introduced by this work.

`planning/Install-DocsSystem.ps1` has a substitution block for this, but
porting it verbatim would have introduced a **new** bug: it escapes values with
`ConvertTo-PowerShellSingleQuoted`, which doubles an embedded single quote.
That is the PowerShell and YAML rule, not the JavaScript one. TypeScript reads
the doubled form as two adjacent string literals and fails to parse — verified
against `node`, which reports `Expected a semicolon`. A title as ordinary as
`Ben's Docs` would have installed a config file Docusaurus cannot load.

- [x] Added `ConvertTo-JavaScriptSingleQuoted`, escaping backslash first, then
      the quote, and collapsing newlines, which a single-quoted JS literal
      cannot contain.
- [x] Substitutes title (both the site title and the navbar title, which
      should agree) and tagline.
- [x] Substitutes `url` **only when `-SiteUrl` was given**. The placeholder is
      at least a valid absolute URL and Docusaurus rejects an empty one, so
      writing `''` would trade one broken build for another.
- [x] Deliberately leaves `onBrokenLinks` and `routeBasePath` alone. Both are
      behavioural choices rather than unfilled placeholders, and flipping
      `routeBasePath` to `/` would move every page's URL for a project already
      serving from `/docs`.
- [x] Verified with an adversarial title and description containing both an
      apostrophe and double quotes: the installed config parses under `node`,
      the values round-trip exactly, and a real Docusaurus build in the
      published image now succeeds **with no hand-editing** — the same build
      that previously failed — rendering the title correctly into the output
      HTML. The no-`-SiteUrl` default path still installs a valid URL.

## P2 — Container entrypoint and an importable module

Two blocking facts: the image has **no `ENTRYPOINT`** (`CMD` is the dev server),
and `PSModule/PSModule.psd1` is a _generator input_ for
`SubZeroDev.ContainerPSGenerator` — `Id`/`Commands`/`SourcePath`, no
`RootModule`, no `FunctionsToExport`. It cannot be imported. Both were built,
separately, as planned.

> **Superseded — read this before the checklist below.** Two things recorded
> here as done were later replaced, so the details no longer describe the tree:
>
> - The hand-authored `PowerShell/DocusaurusTemplate/` module is **gone**. The
>   module is now generated from `PSModule/PSModule.psd1` by
>   SubZeroDev.PSGenerator, named `DocsTemplate`, and embedded at `/PSModule`.
>   `scripts/build-psmodule.ps1` builds it.
> - `ENV PSModulePath="/template/PowerShell..."` is **gone** with it. The
>   Dockerfile sets `ENV DOCS_TEMPLATE_MODULE="/PSModule/DocsTemplate.psd1"`
>   instead, because PowerShell only auto-loads a module whose directory name
>   matches its manifest and `/PSModule` does not, so the path is passed
>   explicitly rather than searched for.
>
> The checklist is kept as the record of what was done at the time.

- [x] Added `scripts/entrypoint.sh`: no arguments (or `dev`) execs the dev
      server, preserving today's `CMD` contract; `pwsh`/`sh`/`bash` exec
      directly; anything else is dispatched as a command name via
      `scripts/dispatch.ps1`.
- [x] `dispatch.ps1` imports `PowerShell/DocusaurusTemplate/DocusaurusTemplate.psd1`
      and calls the named exported command with the remaining arguments.
- [x] Wrote a hand-authored `PowerShell/DocusaurusTemplate/` module —
      `DocusaurusTemplate.psd1` + `.psm1` — separate from
      `PSModule/PSModule.psd1`, exporting `Invoke-SetupDocs` and
      `Invoke-DocsBuild` with parameter lists mirroring `setup-docs.ps1` and
      `docs-build.ps1` in full.
- [x] `Dockerfile`: `ENTRYPOINT ["/bin/sh", "/template/scripts/entrypoint.sh"]`,
      `CMD ["dev"]`, and `ENV PSModulePath="/template/PowerShell:${PSModulePath}"`
      so the module also auto-loads in a plain interactive
      `docker run -it <image> pwsh` session, not only through the dispatcher.
- [x] **Guard `/template`** — `Assert-NotTemplateDirectory` in
      `DocusaurusTemplate.psm1` resolves `-ProjectDir` before delegating and
      throws if it lands on `/template` or under it.
- [x] `.git` requirement and `--user` are documented (see below); neither
      needed a code change — `Test-Documentation.ps1` already throws a clear
      error when no `.git` is found.
- [x] Added `.gitattributes` (`*.sh text eol=lf`) — this is the repository's
      first shell script, and `AGENTS.md`'s own lessons-learned section
      already documents an `autocrlf` trap that hit generated docs output the
      same way.

### Scripts deliberately NOT wrapped as container commands

`scripts/docs-build-image.ps1` and `scripts/preview-docs.ps1` both invoke
`docker` themselves — they build/run _this same image_ from the host side.
Wrapping them as in-container commands would need a Docker socket and CLI the
image does not have, the identical docker-in-docker problem flagged against
`planning/Install-DocsSystem.ps1`'s payload acquisition in Phase 0. Only
`setup-docs.ps1` (pure file installer) and `docs-build.ps1` (already runs
inside this image via `docs-ci.yml`/`docs-deploy.yml`) are genuinely
container-side.

### Two real PowerShell bugs found and fixed during verification

Both are argument-forwarding pitfalls with no compiler or linter to catch
them; recorded here because the pattern (accept a command name + remaining
args, forward to a resolved command) will look reusable to a future editor.

1. **Splatting `@array` on a `[string[]]` captured via
   `ValueFromRemainingArguments` binds every element positionally, not by
   name.** `-ProjectDir /work -Title Foo` splatted this way lands `ProjectDir
= '-ProjectDir'`, `Title = '/work'` — confirmed by reproduction outside
   Docker before touching the container at all. Fixed by dropping the formal
   `param()` block entirely and slicing the script's own automatic `$args`
   instead (`$args[0]`, `$args[1..($args.Count-1)]`) — that shape reliably
   re-parses flag names on re-splat; a freshly constructed array with
   identical string content does not.
2. **Splatting a literal empty array is not the same as passing no
   arguments.** `& $resolved @()` bound every optional parameter to an empty
   string instead of its default; `& $resolved` with no splat correctly left
   defaults in place. Fixed by branching: splat only when `$rest.Count -gt 0`,
   call with no splat otherwise.

A third, smaller trap surfaced in the same file: `$rest = if (cond) { $x }
else { @() }` collapses the `@()` branch to `$null` on assignment (empty
pipeline output, not an empty array), which then throws under
`Set-StrictMode` the moment `.Count` is accessed. Fixed by a plain `$rest =
@()` assignment with a conditional overwrite, avoiding the collapsing
expression form.

### Usage instructions in the agent file

- [x] Rewrote the **Template Bootstrap** section of `AGENTS.md`, splitting it
      into three: consuming the template via the container (recommended, with
      the full `docker run` invocation, the `.git`/mount and `--user` notes,
      and the complete `Invoke-SetupDocs` parameter list), consuming it from a
      local checkout, and developing this repository's own site — the
      previous version blurred the three into one paragraph.
- [x] Cross-referenced `planning/AGENTS-docs-section.md` — noted as the
      consumer-facing equivalent that must not contradict this one. Not
      corrected against observed behavior yet; that is explicitly Phase 4's
      job, and the file still describes the superseded
      `planning/Install-DocsSystem.ps1`.

Acceptance criteria — all verified against the real published image via
`docker run`, bind-mounting the new files over `/template` rather than a full
image rebuild (the payload files were already proven byte-identical to the
image in Phase 0):

- [x] A real `docker run` against a scratch project, invoking `Invoke-SetupDocs`
      with `-ProjectDir /work` and a `-Title`, installs successfully — verified
      with Phase 1 and Phase 2 mounted together, producing the same
      two-workflow, correctly-named output Phase 1 verified alone.
- [x] `-Overwrite` reaches the real script as a working switch through the
      dispatcher — confirmed `[SETUP] Replaced (11)` on a second run.
- [x] `Invoke-DocsBuild` runs the actual Docusaurus build inside the
      container and produces `artifacts/docs/index.html`.
- [x] A bare `docker run <image>` (and explicit `dev`) runs the dev server;
      `pwsh`/`sh`/`bash` still drop into a shell. See the dev-path preflight
      below — this was first recorded here as "still starts the dev server",
      which was wrong, and then documented as a known wart, which was not good
      enough either.

### Dev-server preflight — reported by the user, fixed

A bare `docker run <image>` failed with a fifteen-frame Docusaurus stack trace
ending in `The docs folder does not exist for version "current"`. The image
deletes `/template/docs` on purpose so consumers do not inherit sample content,
so there is nothing to serve until a project's documentation is mounted over
it.

Two things made this worse than a bad error message:

- The container **stayed up afterwards**. `start:docker` runs the dev server
  under `concurrently` alongside a config watcher, and the watcher outlives the
  failed server, so a completely broken run still looks healthy to `docker ps`.
- Nothing in the output said what to actually do.

Pre-existing on `main`, and initially documented rather than fixed. That was
the wrong call: the image knows it has no documentation, so it can say so.

- [x] `entrypoint.sh` checks the docs directory before starting the dev server
      and exits non-zero with the mount commands to use, covering all three
      real intents — preview, build, and install.
- [x] Scoped to the dev path only. `pwsh`/`sh`/`bash` passthrough, module
      command dispatch, unknown-command errors, and `Invoke-SetupDocs` /
      `Invoke-DocsBuild` are all unaffected — verified individually.
- [x] Verified the recommended preview command actually works rather than just
      reading plausibly: mounting a project's `docs/docs`,
      `docusaurus.config.ts`, and `sidebar.ts` starts the server, which returns
      HTTP 200 and the project's own `<title>`.
- [x] An unrecognized command name fails immediately with the list of what
      the image actually exposes (`Invoke-DocsBuild, Invoke-SetupDocs`).
- [x] The `/template` guard fires on a bare `Invoke-SetupDocs` with no mount
      and no `-ProjectDir`, with a clear corrective message rather than a
      parameter-binding crash.
- [x] `Test-ModuleManifest` and the PowerShell AST parser both accept every
      new `.ps1`/`.psd1`/`.psm1` file with zero errors.
- [x] Full `docker build` run against the modified `Dockerfile` — caught two
      real issues the bind-mount tests couldn't, both fixed (the first
      concerned a `PSModulePath` line the Dockerfile no longer has at all —
      see the superseded note above): 1. `ENV PSModulePath="/template/PowerShell:${PSModulePath}"` referenced
      a Dockerfile build-arg that was never defined (Docker's `${VAR}`
      substitution only sees prior `ARG`/`ENV` values, not pwsh's own
      runtime environment), flagged by the builder's own linter and
      confirmed by inspecting the baked-in value: a bare trailing colon,
      not an appended path. Harmless in practice — pwsh always merges its
      own default module paths in ahead of whatever is preset, confirmed
      by `Get-Module -ListAvailable` still resolving built-ins — but fixed
      by dropping the meaningless suffix rather than leaving a warning
      uninvestigated. 2. **Real bug**: `--user "$(id -u):$(id -g)"` — the invocation
      `AGENTS.md` recommends specifically to avoid root-owned output —
      left an unmapped UID with `HOME=/`, which is not writable. pwsh
      fell back to writing its startup-profile cache
      (`StartupProfileData-NonInteractive`) into the caller's project
      directory instead. Root cause isolated by testing `-e HOME=/tmp`
      and `POWERSHELL_TELEMETRY_OPTOUT=1` independently — only `HOME`
      mattered. Fixed with `ENV HOME=/tmp` in the `Dockerfile` (`/tmp` is
      world-writable regardless of UID, unlike anywhere under
      `/template`, which root owns from the build) rather than expecting
      every caller to pass `-e HOME=/tmp` themselves. Verified the stray
      file is gone with `--user` and that root-run behavior (no `--user`)
      is unaffected.

## P3 — Manifest parameter surface

`Invoke-SetupDocs` currently exposes 3 of the script's 10 parameters
(`ProjectDir`, `SkipWorkflow`, `Overwrite`). `Title`, `Description`, `SiteUrl`,
`ScriptDir`, `ConfigDir`, `NoHomepage`, and `SkipGate` are unreachable through
the module.

- [ ] Regenerate `PSModule/PSModule.psd1` so all ten parameters are exposed.
- [ ] Confirm its container invocation mappings match the Phase 2 entrypoint.
- [ ] Drop the `Invoke-SetupDocsWorkflow` entry for the script Phase 1 deletes.
- [ ] Land the currently-uncommitted working-tree regeneration of
      `PSModule.psd1` here, as a deliberate change rather than incidental noise.

Acceptance criteria:

- Every `setup-docs.ps1` parameter is reachable through the module.
- No manifest entry points at a deleted script.

## P4 — End-to-end verification

Against a real consumer repository, not a scratch directory.

- [ ] Install via `docker run` into a real project.
- [ ] Author a page, run the gate, build the site.
- [ ] Confirm the Pages archive step succeeds (`tar --hard-dereference` needs
      GNU tar, which is why it is installed explicitly in the `Dockerfile`).
- [ ] Correct `planning/AGENTS-docs-section.md` against observed behavior and
      promote it out of `planning/`.
- [ ] Fix the stale `setup-docs.ps1` reference inside
      `scripts/template/DocumentationRules.psd1`.
- [ ] Re-check every `AGENTS.md` usage instruction from Phase 2 against what
      actually happened, and correct anything that drifted.

Acceptance criteria:

- A real project publishes documentation with no manual step beyond the
  repository settings the installer cannot change.

## P5 — Retire the planning branch

- [ ] Delete `planning/Install-DocsSystem.ps1` (superseded).
- [ ] Delete `planning/docs.ps1` (a consumer's copy, still tagged
      `gameoflife-docs`).
- [x] Delete `planning/AGENTS-docs-section.md.orig` and
      `planning/Install-DocsSystem.ps1.orig` (editor backups).
- [x] Remove `planning/llms-powershell-module-discovery.md` — it targets
      `The-Running-Dev/LLMs` and `SubZeroDev.PSGenerator`, not this repository.
- [ ] Split `TODO-Next.md`: §4 describes this repository; the rest (Pester,
      `SubZeroDev.PSGenerator` naming, pull requests #61/#62) belongs to
      PSGenerator. Move rather than delete.

Acceptance criteria:

- `planning/` is empty or gone.
- No file in this repository describes another repository's layout as its own.
