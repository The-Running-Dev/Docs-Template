# TODO

Last updated: 2026-07-26 (added P1.13)

This TODO is based on the current repository audit (code, docs, tests, API package, and workflows).

## P0 - Stabilize Development Health

### 1) Fix root test failures (Vitest/jsdom/localStorage)

- [ ] Reproduce and categorize all failing test files.
- [ ] Fix test environment setup for storage APIs so `localStorage.getItem/setItem/clear` are available and stable in tests.
- [ ] Resolve the `--localstorage-file` warning source and remove test runtime noise.
- [ ] Validate by running `pnpm test:run` with zero failing tests.

Acceptance criteria:

- `pnpm test:run` passes locally.
- No storage-related TypeErrors remain in component/hook tests.

### 2) Align test documentation with actual configuration

- [ ] Update testing documentation to match real coverage thresholds.
- [ ] Decide target thresholds (current config vs desired policy) and enforce one source of truth.

Confirmed drift (2026-07-26) — three sources, two different answers:

| Source                            | lines | functions | branches | statements |
| --------------------------------- | ----- | --------- | -------- | ---------- |
| `vitest.config.ts:68-71` (actual) | 55    | 55        | 45       | 55         |
| `testing.md:36`                   | 75    | 70        | 60       | 75         |
| `AGENTS.md` (Testing Guidelines)  | 75    | 70        | 60       | 75         |

Both docs claimed the same wrong numbers, so this reads as config having been
lowered without the docs following. `AGENTS.md` has since been changed to point
at the config instead of restating values; `testing.md:36` still asserts the
wrong ones. Decide whether to raise config to the documented values or correct
the docs — see also P1.5, which targets 80 across the board.

Acceptance criteria:

- `testing.md`, `AGENTS.md`, and `vitest.config.ts` state identical thresholds.

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
6. P1.12 restore this site's 404 navigation.
7. P1.13 fix the homepage generator's relative-link handling.
8. P2.6 API moved out of default path and documented as Phase 2.
9. P2.7 API keep/remove decision checkpoint.
10. P2 hygiene and backlog cleanup.

## Open Decisions (Need Product/Owner Input)

- **P1.10 — test location.** Colocated (as documented) or `__tests__/` (as
  practiced)? Every other item in P1.10 follows from this one answer. No
  default is set here on purpose: both directions are defensible and the cost
  falls on whoever maintains the tree.
- **P0.2 / P1.5 — coverage thresholds.** Raise config to the documented
  75/70/60/75, go straight to the 80/80/80/80 target in P1.5, or correct the
  docs down to the actual 55/55/45/55.

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
