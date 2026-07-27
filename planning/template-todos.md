# docs-template — inspection findings and open TODOs

Findings from a repository inspection on 2026-07-27, verified by running
`pnpm install`, `pnpm run build`, and `pnpm test` against `main` at `3965669`
(#47). Each item says how it was verified and what it costs to leave alone.

## Issues (verified by building and testing)

### 1. Duplicate route at `/`

Both `src/pages/index.md` and `src/pages/index.tsx` exist, and each claims the
homepage route. The production build warns:

```
[WARNING] Duplicate routes found!
- Attempting to create page at /, but a page already exists at this route.
This could lead to non-deterministic routing behavior.
```

The `.tsx` is the real homepage — the hero banner with the feature-flagged
Portfolio/CV buttons. The `.md` is a stale copy of the README that duplicates
what `docs/index.md` already publishes.

This is the **template repository's own** homepage, distinct from the consumer
root-404 problem in `template-fixes.md` — consumers get no root page, the
template gets two.

- [ ] Remove `src/pages/index.md` so `index.tsx` is the single owner of `/`.
- [ ] Verify `pnpm run build` no longer emits the duplicate-route warning.

Cost of leaving it: which page serves `/` is non-deterministic per build.

### 2. Root test run fails — 9 test files

`pnpm test` fails because every test under `api/` cannot resolve its imports
(`fastify`, `typeorm`, `jsonwebtoken`, `node-cron`, `@octokit/rest`). The cause
is structural: `api/` is a standalone package with its own `pnpm-lock.yaml`,
and the root workspace (`pnpm-workspace.yaml` lists only `.`) never installs
its dependencies — yet the root Vitest config sweeps up `api/**/__tests__`.

CI dodges this by running only `pnpm test:components`. The other 86 test files
pass (308 tests). This lines up with `TODO.md`'s P0 "test health" and P2
"isolate the API" items.

- [ ] Either exclude `api/**` from the root Vitest config, add `api` to the
      workspace, or move the API out — one decision, applied consistently.

Cost of leaving it: `pnpm test` is red on a fresh clone, so nobody can use it
as a local gate, and real regressions hide behind the known failures.

### 3. Committed debug credentials

`cookies.txt` at the repository root contains a real JWT refresh token
(localhost dev token, expired September 2025 — committed since #21), and
`api/test-login.json` holds `admin/admin`.

- [ ] Delete both files and add them to `.gitignore`.

Cost of leaving it: secret scanners flag the repository, and the files invite
the next debug session to commit a token that is not expired.

### 4. Deprecated `onBrokenMarkdownLinks` config option

`onBrokenMarkdownLinks` at the top level of `docusaurus.config.ts` will be
removed in Docusaurus v4; the build warns to move it under `markdown.hooks`.

Related: `onBrokenLinks: 'warn'` means broken links can never fail a build.
The only broken links today are the intentional demo links on `/demos/404`, so
switching to `'throw'` would need those excluded.

- [ ] Move the option to `markdown.hooks.onBrokenMarkdownLinks`.
- [ ] Decide whether `onBrokenLinks` should be `'throw'` with the demo page
      exempted, so real broken links fail the build.

Cost of leaving it: a warning on every build now, a broken build on the v4
upgrade later, and broken links ship silently in the meantime.

### 5. Prebuild warning fires on every build

"Projects Configuration Missing, Using Defaults" (`scripts/pre-build.ts:691`)
fires on every build even though `projects.yml` converts fine — either a
config file is genuinely missing or the check misfires.

- [ ] Find out which, then fix the config or the check.

Cost of leaving it: a warning that is always present trains readers to ignore
warnings.

## Missing / stale docs

### Version drift: 3.8.1 vs 3.10.1

`README.md`, `docs/index.md`, and `docs/getting-started/features.md` all
advertise "Docusaurus 3.8.1"; the actual dependency is 3.10.1. Already flagged
as `TODO.md` P1.3.

- [ ] Update the three files, or stop hardcoding the version in prose.

### Coverage thresholds: docs say 75/70/60/75, config enforces 55/55/45/55

`testing.md:36` documents thresholds of 75/70/60/75, but `vitest.config.ts`
enforces 55/55/45/55. `TODO.md` P0.2 already tracks this and notes `AGENTS.md`
was fixed to point at the config; `testing.md` was not.

- [ ] Fix `testing.md` the same way, or raise the config — one source of truth.

### Undocumented components

`DataProvider` and `DebugInfo` have no doc coverage anywhere. `ReaderMode` and
`TextSizeSwitcher` have demo pages and a one-line mention in
`key-components.md`, but no core-systems page — while sibling toggles (theme
switcher, version display) each have a full doc.

- [ ] Write core-systems pages for the four, or state deliberately which
      components are internal and undocumented.

### `docs/guides/` has no category metadata

The section holds four spec files but no `_category_.json` or index page,
unlike every other docs section, so its sidebar presentation is whatever
Docusaurus autogenerates.

- [ ] Add `_category_.json` and an index, matching the other sections.

## Already tracked elsewhere

Known open work is well-recorded in `TODO-Next.md` (updated with #47): the
`--user` asymmetry in `Invoke-DocsBuild`, no Pester harness for the PowerShell
scripts, the missing `-BaseUrl` installer parameter, and five planning
documents accumulating at the repository root. Not duplicated here.

## Not verified

The PowerShell doc gate (`Test-Documentation.ps1`) could not be run in the
inspection environment — no `pwsh` available — so the terminology and drift
checks it enforces were not re-verified.
