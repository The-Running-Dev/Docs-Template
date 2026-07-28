# TODO

Last updated: 2026-07-27 (added P1.13, P1.14, P1.15)

This TODO is based on the current repository audit (code, docs, tests, API package, and workflows).

## P0 - Stabilize Development Health

### 1) Fix root test failures (Vitest/jsdom/localStorage)

- [x] Reproduce and categorize all failing test files. All 9 failures were
      `api/` test files failing to resolve imports (`fastify`, `typeorm`,
      `jsonwebtoken`, `node-cron`, `@octokit/rest`) — `api/` is a separate
      pnpm workspace whose deps a root `pnpm install` never installs; no
      storage-related failures were among them.
- [x] Fix test environment setup for storage APIs so `localStorage.getItem/setItem/clear` are available and stable in tests. Already handled in `vitest.setup.ts` (a global mock, cleared between tests); verified no storage-related TypeErrors in the current passing run.
- [x] Resolve the `--localstorage-file` warning source and remove test runtime noise. No such warning appears in the current test output.
- [x] Validate by running `pnpm test:run` with zero failing tests. `vitest.config.ts` now excludes `api/**` from root discovery (its dependencies were never installable from root); `pnpm run test:api` runs it via its own lockfile instead.

Acceptance criteria:

- `pnpm test:run` passes locally.
- No storage-related TypeErrors remain in component/hook tests.

### 2) Align test documentation with actual configuration

- [x] Update testing documentation to match real coverage thresholds. `testing.md` now points at `vitest.config.ts` as the source of truth instead of restating numbers, matching the fix already applied to `AGENTS.md`.
- [ ] Decide target thresholds (current config vs desired policy). Still open — see P1.5. This PR does not raise or lower the numbers, only removes the doc drift around them.

Confirmed drift (2026-07-26) — three sources, two different answers:

| Source                            | lines | functions | branches | statements |
| --------------------------------- | ----- | --------- | -------- | ---------- |
| `vitest.config.ts:68-71` (actual) | 55    | 55        | 45       | 55         |
| `testing.md:36`                   | 75    | 70        | 60       | 75         |
| `AGENTS.md` (Testing Guidelines)  | 75    | 70        | 60       | 75         |

Both docs claimed the same wrong numbers, so this reads as config having been
lowered without the docs following. Both `AGENTS.md` and `testing.md` now point
at the config instead of restating values, so this drift cannot recur. Whether
to raise the config itself is still open — see P1.5, which targets 80 across
the board.

Acceptance criteria:

- `vitest.config.ts` is the only place that states numeric coverage thresholds; `testing.md` and `AGENTS.md` both point at it instead of restating values.

## P1 - Documentation and Workflow Consistency

### 3) Version and narrative cleanup (3.8.1 vs 3.10.1)

- [ ] Update README/docs/workflow comments that still describe 3.8.1.
- [ ] Ensure package metadata description matches actual dependency versions.
- [ ] Include docs alignment tasks as first-class backlog work (not optional cleanup).

Acceptance criteria:

- Public docs and metadata consistently describe Docusaurus 3.10.1.
- Documentation tasks are tracked alongside code tasks in this TODO.

### 4) Workflow comment cleanup

- [ ] Remove unrelated/stale commentary from release workflow (Angular/barstrad references).
- [ ] Keep workflow comments accurate and scoped to this repository.

Acceptance criteria:

- CI/release workflow docs are relevant and trustworthy.

### 5) Raise and enforce stricter coverage policy

- [ ] Increase coverage thresholds in `vitest.config.ts` above current values.
- [ ] Set target thresholds to: lines 80, functions 80, branches 80, statements 80.
- [ ] Align `testing.md`, `AGENTS.md`, and related docs to strict targets.
- [ ] Fix or add tests to meet the stricter threshold policy.

Acceptance criteria:

- Coverage gates are stricter than current defaults and enforced in CI/local checks.
- Docs and config state the same threshold values.

## P1 - Convention and Review Debt

Raised by the review of PR #33 (merged 2026-07-25, `171ea59`).

### 10) Resolve the test-location contradiction

The written standard and the actual tree disagree, and the automated reviewer
sides with the standard — so every PR that touches a test file gets flagged.

- Documented: `AGENTS.md:6` ("tests (next to code)") and `AGENTS.md:33`
  ("Tests colocated: `*.test.ts` / `*.test.tsx` alongside source").
- Practiced: ~40 test files under `__tests__/` directories; 8 colocated, all in
  `src/components/Projects/`.
- Enforced: Qodo rule 1275332 flags `__tests__/`, correctly derived from the
  documented standard.

- [ ] Decide which convention is real: colocated, or `__tests__/`.
- [ ] If colocated wins, migrate the ~40 `__tests__/` files in a dedicated PR.
- [ ] If `__tests__/` wins, update `AGENTS.md:6` and `AGENTS.md:33`, and relax
      Qodo rule 1275332.
- [ ] Do not leave this split — it is the reason the rule keeps firing.

Acceptance criteria:

- One convention is documented, practiced, and enforced consistently.
- Rule 1275332 stops producing findings on conforming PRs.

### 11) Carve out full-replacement swizzles in Qodo rule 1275477

Rule 1275477 requires swizzled components under `src/theme/**` to wrap
`@theme-original/*`. That is correct for decorating swizzles and wrong for
replacing ones, and the repo already contains both:

- `src/theme/DocItem/index.tsx` wraps `@theme-original/DocItem` — it adds to doc
  pages, so upstream must still render.
- `src/theme/NotFound/Content/index.tsx` does not — it fully replaces the 404
  body. Wrapping would render Docusaurus' stock "could not find" block _and_ the
  custom 404 beneath it.

- [ ] Add a rule exception for `src/theme/NotFound/**`, or scope the rule to
      decorating swizzles only.
- [ ] Record the decorate-vs-replace distinction where reviewers will see it.

Acceptance criteria:

- Rule 1275477 stops flagging `NotFound/Content` on every PR that touches it.

### 12) Restore this site's own 404 navigation without re-breaking consumers

PR #33 removed the hardcoded `/docs` and `/demos` buttons from the shared 404.
Correct for downstream sites, but this template's own 404 now offers only Home.

Proposed: source `links` from `config/globalConfig.yml`, defaulting to empty.
Consumers already overlay `config/` (see note in Notes below), so this site can
declare its own routes while a consumer that declares nothing stays safe.

- [ ] Verify the config hook is reachable from the `NotFound` theme context —
      this is the open technical question and is not yet confirmed.
- [ ] Add the `links` entries to `config/globalConfig.yml`.
- [ ] Keep the empty default and the wrapper test asserting one link, to `/`.

Acceptance criteria:

- This site's 404 offers Docs and Demos again.
- `src/theme/NotFound/Content/__tests__/index.test.tsx` still passes unchanged
  for a consumer that configures nothing.

## P1 - Documentation Gate System (Invoke-SetupDocs)

Raised by the review of PR #38 (`feat/invoke-setupdocs`, adds
`scripts/setup-docs.ps1` and the documentation gate under
`scripts/template/`).

### 13) Homepage generator does not rewrite relative README links

Confirmed 2026-07-26. `ConvertTo-DocumentationHomepage.ps1` rewrites the
absolute `SiteUrl` to `/`, but does nothing with relative links. A README that
links to another file in the repository is valid at the repository root and
broken once copied into `docs/docs/index.md`, because the target is now one
directory level too shallow.

Reproduction:

```
README.md (repo root):        See [the guide](docs/guide.md).
docs/docs/index.md (copied):  See [the guide](docs/guide.md).
                               → resolves to docs/docs/docs/guide.md, which
                                 does not exist.
```

Running the gate against a fresh install with this README produces:

```
docs/docs/index.md:8:17 [Error] MarkdownLink: Link target 'docs/guide.md' does not exist.
```

So a fresh install can fail its own gate on the very first run, for any
project whose README links to another file in the repository — not a rare
case.

Candidate fixes, not yet chosen:

- **Rewrite relative links to absolute repo-host URLs.** Add a `-RepoUrl`
  parameter (e.g. `https://github.com/org/repo`) to
  `ConvertTo-DocumentationHomepage.ps1`; rewrite `docs/guide.md` to
  `https://github.com/org/repo/blob/main/docs/guide.md` during generation, the
  same way `SiteUrl` is already rewritten. Correct on both the code host and
  the published site. Needs the parameter threaded through
  `setup-docs.ps1`, the rules file `Arguments`, and `docs.ps1`, plus a
  decision on the default branch name.
- **Exclude generated files from link scanning.** Add
  `docs/docs/index.md` to `ExcludedFiles` in `DocumentationRules.psd1`. One
  line, but the gate then says nothing about broken links in the one file most
  likely to contain README-authored links — Docusaurus's own broken-link check
  becomes the only backstop, and that check defaults to `'warn'`, not `'throw'`.

- [ ] Decide between the two approaches above (or another).
- [ ] Implement the fix in `ConvertTo-DocumentationHomepage.ps1` and/or
      `DocumentationRules.psd1`.
- [ ] Add a regression test/fixture: a README with a relative link, verifying
      the gate passes after the fix.

Acceptance criteria:

- A project with a README containing relative links to other repository files
  passes the gate immediately after `setup-docs.ps1`, with no manual
  edits.

### 14) Setup docs conflate a template copy with a consumer repository

Confirmed 2026-07-27. `README.md`, `AGENTS.md`, `docs/getting-started/quick-start.md`,
and `src/pages/index.md` all describe the same bootstrap: copy this template to
a new folder, `pnpm install`, then run `.\scripts\setup-docs.ps1`. That script
builds a _consumer overlay_, which is a different shape from a template copy.

Running the documented flow against a template-shaped project produces a hybrid:

```
docusaurus.config.ts        ← the template's own config, at the root
docs/docusaurus.config.ts   ← a second config, consumer-overlay shape
docs/guides/intro.md        ← template content, directly under docs/
docs/docs/index.md          ← consumer content, nested one level deeper
```

The two layouts being conflated:

- **Template copy** — `docs/` _is_ the content directory; the config lives at
  the repository root. This is how this repository builds itself.
- **Consumer overlay** — `docs/` is a self-contained overlay copied over
  `/template` in the published image, so it carries its own
  `docusaurus.config.ts`, `sidebar.ts`, and a nested `docs/` for content.

Nothing crashes: stray `.ts` files inside the content directory are ignored by
the docs plugin, and `docs/docs/index.md` merely becomes an oddly routed page.
The sharper edge is the root `docs.ps1` the script installs, which builds
`docs/` _as an overlay_ — wrong for a template copy whose `docs/` is content.

Pre-existing, not introduced by PR #38: the previous `setup-docs.ps1` on `main`
already created `docs/docs/index.md`, `docs/docusaurus.config.ts`, and
`docs/sidebar.ts`. PR #38 makes it more pronounced by additionally installing
`docs.ps1`, `build/`, `.config/`, and two more workflows, and by stating the
bootstrap claim more confidently in `AGENTS.md`.

Candidate fixes, not yet chosen:

- **Scope the documentation (recommended).** State plainly that
  `setup-docs.ps1` targets a _consumer_ repository, and give template-copy
  users a different step or none. A documentation fix for a documentation
  problem, and it adds no branching to a script that already carries a lot.
- **Detect and adapt.** Have the script recognise a template-shaped project
  (root `docusaurus.config.ts` with no `docs/docs/`) and either refuse or
  install only the template-appropriate subset. More behaviour to maintain.
- **Leave it.** Nothing breaks outright and it has been this way for a while.

- [ ] Decide between the approaches above.
- [ ] If scoping the docs: update `README.md`, `AGENTS.md`,
      `docs/getting-started/quick-start.md`, and `src/pages/index.md` together,
      since all four carry the same claim.

Acceptance criteria:

- A reader following the documented bootstrap ends up with a coherent layout,
  or is told plainly that the step does not apply to them.

### 15) `ConvertTo-YamlSingleQuotedScalar` is duplicated

Introduced 2026-07-26 by the YAML front-matter injection fix, and deliberately
left in place. The function — two lines of logic — is defined identically in:

- `scripts/setup-docs.ps1` (the stub homepage written when a project has no
  README)
- `scripts/template/ConvertTo-DocumentationHomepage.ps1` (the real homepage
  generated from a README)

The duplication is forced rather than careless. The generator is installed into
consumer projects and invoked by three separate callers — `setup-docs.ps1` at
install time, the gate's drift check via the rules file `Generator` entry, and
the consumer's own `docs.ps1` preview — so it has to stand alone inside someone
else's repository. The stub path cannot delegate to it, because that path only
runs when there is no README, and in that case the generator is never
installed. It cannot dot-source it either: the generator is a script with a
mandatory `-ReadmePath`, so dot-sourcing executes it.

Severity is low. The two copies serve mutually exclusive paths and can never
disagree about the same file: a README means the generator runs and the stub
does not, and no README means the stub runs and the generator is not installed.
The real risk is that someone changes the escaping rules in one copy and not
the other, so two _different_ projects get differently escaped front matter.
Nothing catches that automatically — the drift check only compares the
generated homepage, and when the stub runs, the `GeneratedFiles` block is
stripped from the rules, so the stub file is not drift-checked at all.

A shared dot-sourced helper was implemented and then reverted, deliberately:
it gave the generator a run-time dependency on a sibling file that must ship
and stay in sync with it, which is a worse trade for a two-line function.

Candidate fixes, not yet chosen:

- **Cross-reference comments (recommended).** A comment in each copy naming the
  other, so anyone editing one is told to change both. No structural change, no
  new file, no run-time dependency.
- **Leave it.** Two lines, mutually exclusive paths, no correctness impact.
- **Shared helper.** Only worth revisiting if this helper grows beyond a couple
  of lines, or a third caller appears.

- [ ] Decide between the approaches above.
- [ ] If the escaping rules are ever changed, change both copies together.

Acceptance criteria:

- Either the duplication is gone, or both copies point at each other so a future
  edit cannot silently touch only one.

## P2 - API Deferred Scope and Hygiene

### 6) Move API to Phase 2 (single scope)

- [ ] Treat API as Phase 2 scope only (not a primary template requirement in Phase 1).
- [ ] Remove API from default onboarding/docs/navigation paths in Phase 1.
- [ ] Keep API isolated as optional/experimental until Phase 2 execution starts.

Acceptance criteria:

- Main template workflow does not require running API.
- API is clearly labeled as Phase 2/optional in documentation.

### 7) API evaluation checkpoint (keep vs remove)

- [ ] Decision locked: keep API for now because current auth/admin/project-editing flows depend on it.
- [ ] Keep API scoped as Phase 2 optional (not part of default Phase 1 setup).
- [ ] Revisit removal only after API-dependent flows are replaced or intentionally removed.

Acceptance criteria:

- Decision is explicit and documented as keep-for-now.
- No breaking changes are introduced by premature API removal.

### 8) Remove obvious config/code noise

- [ ] Remove duplicate imports in `vitest.config.ts` — confirmed 2026-07-26:
      `import path from 'node:path';` appears on both line 3 and line 4, and
      `path` is never used (the file resolves via `fileURLToPath(new URL(...))`).
      In progress in a separate session.
- [ ] Scan for low-risk cleanup items introduced by recent refactors.

Acceptance criteria:

- No duplicate imports or lint-level hygiene regressions in touched files.

### 9) Audit and triage remaining TODO/FIXME items

- [ ] Convert inline TODOs into tracked issues or resolve them.
- [ ] Keep only TODOs that have an owner and expected completion window.

Acceptance criteria:

- Inline TODO count reduced and linked to explicit backlog items.

## Suggested Execution Order

1. P0.1 root tests green.
2. P0.2 testing docs and thresholds aligned.
3. P1.10/P1.11 convention decisions — cheap, and they stop the automated
   reviewer producing findings on every PR until resolved.
4. P1.3/P1.4 docs + workflow consistency pass.
5. P1.5 stricter coverage policy + enforcement.
6. P1.14 scope the setup docs — cheap, and it stops readers following a
   bootstrap that does not fit them.
7. P1.12 restore this site's 404 navigation.
8. P1.13 fix the homepage generator's relative-link handling.
9. P2.6 API moved out of default path and documented as Phase 2.
10. P2.7 API keep/remove decision checkpoint.
11. P2 hygiene and backlog cleanup.
12. P1.15 the duplicated YAML escaper — lowest priority; no correctness impact,
    worth doing only alongside other work in these files.

## Open Decisions (Need Product/Owner Input)

- **P1.10 — test location.** Colocated (as documented) or `__tests__/` (as
  practiced)? Every other item in P1.10 follows from this one answer. No
  default is set here on purpose: both directions are defensible and the cost
  falls on whoever maintains the tree.
- **P0.2 / P1.5 — coverage thresholds.** The docs-drift half of P0.2 is closed
  — `testing.md` and `AGENTS.md` now point at `vitest.config.ts` instead of
  restating numbers, so they cannot state a wrong value again. What remains
  open is the config's actual value: raise it to the previously-documented
  75/70/60/75, go straight to the 80/80/80/80 target in P1.5, or leave it at
  the current 55/55/45/55.

## Notes

Observations from the PR #33 review (2026-07-25/26) worth keeping.

- **Consumers can override any path, not just `docs/`.** `scripts/docs-build.ps1`
  walks the caller's `docs/` directory and copies every file over the _template
  root_, preserving relative paths. So a consumer's `docs/config/globalConfig.yml`
  replaces `/template/config/globalConfig.yml`, and `docs/src/theme/...` replaces
  a swizzle. Override reach is never the constraint when weighing a config-driven
  design — the question is only which way the default fails.
- **Default-safe beats default-broken for anything downstream inherits.** A
  shared component carrying routes that only this site has means a consumer who
  does nothing gets a broken page. An empty default means doing nothing is
  correct and adding routes is an explicit opt-in.
- **Docs in this repo have drifted from reality more than once.**
  `404-error-page.md` described a `src/pages/404.tsx` that has never existed in
  git history — across its file tree, integration section, and usage example.
  The coverage-threshold drift in P0.2 is the same failure. Worth a periodic
  pass that checks docs against the tree rather than against other docs.
- **`prettier --check` gives false positives on a Windows working tree.**
  `core.autocrlf=true` yields CRLF locally while the committed blob is LF, which
  is what CI checks out. Check the blob (`git show HEAD:<path> | prettier
--stdin-filepath <path> --check`) before "fixing" a formatting failure that CI
  never saw.
- **After a squash merge, `git branch -d` reports the branch unmerged.** The
  squash commit shares no history with the branch tip. Confirm with
  `git diff <branch> main` returning empty before deleting.
- **Verify a regression test by reverting the fix.** Both tests added in PR #33
  were confirmed to fail without their fix. A test that passes either way
  documents intent but guards nothing.
