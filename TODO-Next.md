# Next

Open work for this repository, carried out of the documentation-system
convergence and the consumer-isolation fix. Nothing here is blocking; each item
says what it costs to leave alone.

> **This file previously described `SubZeroDev.PSGenerator`**, not this
> repository — nuget.org publishing, Pester matrices, that project's pull
> requests #61 and #62. Its one section about this repository, converging the
> docs workflows onto a single shape, shipped in #42. The PSGenerator content is
> preserved in git history at `c868bc6:TODO-Next.md` if it should be moved to
> that repository rather than lost.

## 1. `Invoke-DocsBuild` cannot run under `--user`

```text
Access to the path '/template/Dockerfile' is denied.
```

`docs-build.ps1` overlays the consumer's `docs/` onto `/template`, which the
image owns as root, so a non-root `--user` cannot write there. `Invoke-SetupDocs`
is unaffected — it writes into the mount.

The consumer guide documents the asymmetry, so nobody is blocked, but two
commands needing opposite invocations is a papercut that will keep being
rediscovered.

- [ ] Stage the overlay into a writable directory instead of building in
      `/template`, so `--user` behaves the same for every command.

Cost of leaving it: the guide has to keep explaining why one command takes
`--user` and the other must not.

## 2. No PowerShell test harness

The anchor-slug fix in #44 was verified by running the function directly,
because there is nowhere to put a test. The scripts under `scripts/` and
`scripts/template/` have no coverage at all, while the TypeScript side has
Vitest.

- [ ] Add Pester, and a first test for `ConvertTo-HeadingSlug` covering an em
      dash and an en dash — the case that made GitHub and the gate disagree.
- [ ] Decide whether it runs in `test-and-coverage.yml` or its own job.

Cost of leaving it: every future change to the gate, the installer, or the
generator is verified by hand, exactly as the ones in #42 and #44 were.

## 3. Compliance rule 1275448 conflicts with GitVersion tagging

The rule requires version strings, including Docker tags, to match
`YYYY.MM.DD`. Since #42 the image publishes `:latest` plus an immutable
`:1.0.0-<sha>` computed by GitVersion, which the rule flags on every pull
request.

This is a deliberate divergence, not a defect: the date tag was removed on
purpose, and a GitVersion tag carries the commit so it is genuinely immutable,
which a moving date tag is not.

- [ ] Amend or scope the rule so it stops flagging intended behaviour.

Cost of leaving it: a permanent false positive on every pull request, which
trains readers to skim compliance findings.

## 4. `-BaseUrl` is not an installer parameter

`-SiteUrl` sets Docusaurus `url` only. `baseUrl` keeps the template's `/`, which
is wrong for a GitHub Pages **project** site at
`https://<owner>.github.io/<repo>/` — every asset 404s until it is hand-edited
to `/<repo>/`.

The guide says so plainly, so it is a known manual step rather than a trap.

- [ ] Add `-BaseUrl`, substituted the same way `-SiteUrl` and `-RouteBasePath`
      are, so a project site installs correctly in one command.

Cost of leaving it: every project-site consumer edits a file immediately after
installing.

## 5. `ContainerImage` in the module specification is not an image reference

`PSModule/PSModule.psd1` carries `ContainerImage = 'DocsTemplate'`. It was
renamed alongside `ModuleName` and was never a real reference — the published
image is `ghcr.io/the-running-dev/docs-template`. Nothing reads it today,
because every generated command invokes its script directly rather than through
Docker.

- [ ] Set it to the real image reference before adding any container-kind
      command, or the first one will inherit a meaningless value.

Cost of leaving it: none today; a confusing failure the day a container command
is added.

## 6. Planning documents are accumulating

Five now sit at the repository root:

| File                         | What it is                                      |
| ---------------------------- | ----------------------------------------------- |
| `TODO.md`                    | Standing backlog — test health, coverage policy |
| `TODO-Next.md`               | This file: open follow-ups                      |
| `TODO-Docs-Convergence.md`   | Record of #42, complete                         |
| `TODO-Consumer-Isolation.md` | Record of #44, complete but for items 1 and 2   |
| `DOCS-BUILD-PLAN.md`         | Record of the container build split, complete   |

Three are finished-work records kept for their reasoning, which is worth having
— several findings in #44 were only diagnosable because #42's record said what
had already been tried. But the repository root is not where a reader looks for
them.

- [ ] Decide whether completed records move under `docs/` (published, and
      covered by the gate) or into an `archive/` directory, and whether
      `TODO.md` and this file stay at the root as the two live ones.

Cost of leaving it: a reader cannot tell which of the five describe work still
to do.

## Not tracked here

- **`archive/feature-more_http_provider_support`** — 29 commits, last touched
  2025-09-03, 295 files diverged, and its substance already reached `main` by
  another route. Do not merge it. If the branch list should be tidy, tag it
  first so the commits stay reachable, then delete the branch.
- **`SubZeroDev.WinGet` review findings** — the `PackageTest` environment
  assumption and the three non-blocking observations belong to that repository.
