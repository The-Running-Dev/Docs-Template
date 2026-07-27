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

Risk to verify, not assume: `checkout@v5` and later run on Node 24, and these
jobs execute inside an Alpine/musl container. Node's musl support is the fragile
part of that combination. The bump needs a real CI run, and
`upload-pages-artifact` must stay version-compatible with `deploy-pages`.

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

| File              | Jobs                                | Permissions                              | Triggers               |
| ----------------- | ----------------------------------- | ---------------------------------------- | ---------------------- |
| `docs-ci.yml`     | `documentation` (gate) · `verify`   | `contents: read`, `packages: read`       | PR, push, dispatch     |
| `docs-deploy.yml` | `deploy`                            | above + `pages: write`, `id-token: write` | push to `main`, dispatch |

- [x] Fold the gate job from `docs-quality.yml` into
      `scripts/template/docs-ci.yml`; give that file real triggers (it is
      `workflow_call` only today) and keep its permissions read-only.
- [x] Add `push: branches: [main]` to `scripts/template/docs-deploy.yml`.
- [x] Declare the triggers without `paths:` filters, per the decision above, so
      a required check always reports.
- [x] Bump both the payload and this repository's own workflows to the target
      action versions in the table above.
      **Not yet confirmed with a real CI run** — Node 24 / Alpine-musl
      compatibility is asserted from the version bump, not from a CI execution.
      Verify in Phase 4's end-to-end pass.
- [x] Delete `scripts/template/docs.yml` (pure caller indirection) and
      `scripts/template/docs-quality.yml` (folded in).
- [x] Delete `scripts/setup-docs-workflow.ps1`; fold its two-file install back
      into `setup-docs.ps1`, removing the split-reporting note at
      `scripts/setup-docs.ps1:487-492`.
- [x] Rework `-SkipGate` so it excises a *job* from `docs-ci.yml` rather than
      skipping a whole file, using the same start/end marker technique the
      `GeneratedFiles` block already uses. Factored into a shared
      `Remove-MarkedBlock` helper used by both.
- [x] Keep job `name:` values byte-identical — `Documentation links and
      terminology`, `Verify Documentation Build`, `Build and Deploy
      Documentation` — so any required-status-check context keeps matching.
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
      **Caveat found and confirmed pre-existing, not a Phase 1 regression**:
      `setup-docs.ps1`'s `docusaurus.config.ts` copy has no `-Replace` block,
      so every install ships `title: ''`, which fails the Docusaurus build
      with `"title" is not allowed to be empty`. Reproduced identically
      against `main`'s unmodified script. Not fixed here — out of scope for a
      workflow-file consolidation — but tracked below for Phase 4.

### Follow-up found during Phase 1 (not yet fixed)

- [ ] `scripts/setup-docs.ps1`'s `Copy-TemplateFile` call for
      `docusaurus.config.ts` passes no `-Replace` hashtable, so `-Title`,
      `-Description`, and `-SiteUrl` never reach the installed file — every
      install ships `title: ''`, `tagline: ''`, `url: 'https://example.com'`,
      and `onBrokenLinks: 'warn'`/`routeBasePath: 'docs'` at their unconfigured
      template defaults. A real Docusaurus build fails on the empty title.
      `planning/Install-DocsSystem.ps1` already has the correct substitution
      block to port over. Fix before or during Phase 4's end-to-end pass, since
      that is the first phase that actually builds a real site.

## P2 — Container entrypoint and an importable module

Two blocking facts: the image has **no `ENTRYPOINT`** (`CMD` is the dev server),
and `PSModule/PSModule.psd1` is a *generator input* for
`SubZeroDev.ContainerPSGenerator` — `Id`/`Commands`/`SourcePath`, no
`RootModule`, no `FunctionsToExport`. It cannot be imported. Both were built,
separately, as planned.

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
`docker` themselves — they build/run *this same image* from the host side.
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

- [x] `docker run --rm -v <scratch>:/work -w /work <image> Invoke-SetupDocs
      -ProjectDir /work -Title '...'` installs successfully — verified with
      Phase 1 and Phase 2 mounted together, producing the same two-workflow,
      correctly-named output Phase 1 verified alone.
- [x] `-Overwrite` reaches the real script as a working switch through the
      dispatcher — confirmed `[SETUP] Replaced (11)` on a second run.
- [x] `Invoke-DocsBuild` runs the actual Docusaurus build inside the
      container and produces `artifacts/docs/index.html`.
- [x] A bare `docker run <image>` (and explicit `dev`) still starts the dev
      server; `pwsh`/`sh`/`bash` still drop into a shell.
- [x] An unrecognized command name fails immediately with the list of what
      the image actually exposes (`Invoke-DocsBuild, Invoke-SetupDocs`).
- [x] The `/template` guard fires on a bare `Invoke-SetupDocs` with no mount
      and no `-ProjectDir`, with a clear corrective message rather than a
      parameter-binding crash.
- [x] `Test-ModuleManifest` and the PowerShell AST parser both accept every
      new `.ps1`/`.psd1`/`.psm1` file with zero errors.
- [ ] Full image rebuild from the modified `Dockerfile` was **not** run in
      this session (would reinstall PowerShell + all pnpm dependencies from
      scratch). Everything above was verified by bind-mounting the new files
      over the currently published image, which carries an identical
      `/template` tree apart from these additions. Do a real `docker build`
      before merging, to catch anything specific to build-time layering (e.g.
      the `ENV PSModulePath` line, or `COPY . ./` picking up the new
      `PowerShell/` and `scripts/entrypoint.sh` correctly).

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
