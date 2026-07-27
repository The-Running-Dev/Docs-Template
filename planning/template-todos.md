# docs-template — bugs and issues from the 2026-07-27 audit

Findings from a repository inspection on 2026-07-27, verified by running
`pnpm install`, `pnpm run build`, and `pnpm test` against `main` at `3965669`
(#47). Arranged as file-ready reports: **Bugs** are defects observable in a
build or test run today; **Issues** are drift and gaps that mislead but do not
break. Each entry carries its evidence, root cause, a worked fix, and
acceptance criteria.

---

## Bugs

### Bug 1 — Duplicate route: `src/pages/index.md` and `src/pages/index.tsx` both claim `/`

**Severity:** medium — which page serves the homepage is non-deterministic.
**Suggested labels:** `bug`, `build`

#### Description

Docusaurus turns every file in `src/pages/` into a route. Two files map to the
root route:

- `src/pages/index.tsx` — the real homepage: hero banner with the site title
  plus feature-flagged Portfolio/CV buttons.
- `src/pages/index.md` — a stale copy of the README's "Key Features" content,
  duplicating what `docs/index.md` already publishes at `/docs`.

Every production build warns:

```
[WARNING] Duplicate routes found!
- Attempting to create page at /, but a page already exists at this route.
This could lead to non-deterministic routing behavior.
```

Which of the two wins depends on plugin processing order, not on anything the
repository controls. This is the template repository's own homepage — distinct
from the consumer root-404 problem planned in `consumer-root-404.md`, where
consumers get *no* root page. Here the template gets two.

#### How to fix

1. Delete the stale page:

   ```bash
   git rm src/pages/index.md
   ```

   Nothing links to it: its content is the README, which `docs/index.md`
   (route `/docs`) already carries in maintained form.

2. Rebuild and confirm the warning is gone:

   ```bash
   pnpm run build 2>&1 | grep -i "duplicate routes"   # expect no output
   ```

3. Serve `./artifacts` and confirm `/` renders the hero banner from
   `index.tsx`.

#### Acceptance criteria

- `pnpm run build` emits no "Duplicate routes found!" warning.
- `/` deterministically renders the `index.tsx` homepage.
- `/docs` still serves the overview content.

---

### Bug 2 — `pnpm test` is red on a fresh clone: 9 `api/` test files cannot resolve imports

**Severity:** high — the root test command cannot be used as a local gate.
**Suggested labels:** `bug`, `tests`, `api`

#### Description

On a fresh clone, `pnpm install && pnpm test` fails with 9 test files erroring
at load time, all under `api/`:

```
Error: Failed to resolve import "fastify" from "api/src/routes/__tests__/authRoutes.test.ts"
Error: Failed to resolve import "typeorm" from "api/src/repositories/database-project-repository.ts"
Error: Failed to resolve import "jsonwebtoken" from "api/src/services/jwtService.ts"
Error: Failed to resolve import "node-cron" from "api/src/services/__tests__/syncService.test.ts"
Error: Failed to resolve import "@octokit/rest" from "api/src/services/githubProvider.ts"
```

Result: `Test Files 9 failed | 86 passed (95)` — the 308 tests that do load
all pass.

#### Root cause

The failure is structural, not flaky:

- `api/` is a standalone package: it has its own `package.json`,
  `pnpm-lock.yaml`, and `pnpm-workspace.yaml`.
- The root `pnpm-workspace.yaml` lists only `packages: [.]`, so a root
  `pnpm install` never installs `api/`'s dependencies.
- The root `vitest.config.ts` sets no `include`/`exclude` for test discovery,
  so Vitest's default glob sweeps up `api/**/__tests__/**` — tests whose
  dependencies were never installed.

CI never sees this because `test-and-coverage.yml` runs only
`pnpm test:components` (scoped to `src/components`). Anyone running the
documented `pnpm test` locally gets a red run, and real regressions hide
behind the known failures.

#### How to fix

Three coherent options — pick one and apply it consistently:

**Option A (recommended now, smallest change):** exclude `api/**` from root
test discovery, since `api/` is already a self-contained package with its own
`test` script. In `vitest.config.ts`:

```ts
import { defineConfig, configDefaults } from 'vitest/config';

export default defineConfig({
  // ...existing plugins/resolve...
  test: {
    // ...existing environment/setup/coverage...
    exclude: [...configDefaults.exclude, 'api/**']
  }
});
```

API tests then run where their lockfile lives:

```bash
cd api && pnpm install && pnpm test
```

Optionally add a root convenience script:
`"test:api": "pnpm --dir api install && pnpm --dir api test"`.

**Option B:** make `api` a real workspace member — add `- api` to the root
`pnpm-workspace.yaml` `packages` list and delete `api/pnpm-lock.yaml` and
`api/pnpm-workspace.yaml` so one root install covers everything. This makes
`pnpm test` genuinely run all 95 files, but couples the API's dependency tree
(TypeORM, Fastify, better-sqlite3 with native builds) to the docs template's
install — the opposite of `TODO.md` P2, which wants the API isolated as
Phase 2 scope.

**Option C:** move `api/` out of this repository entirely, per `TODO.md` P2
("Move API to Phase 2"). The right end state, but a bigger lift; Option A is
compatible with doing this later.

#### Acceptance criteria

- Fresh clone: `pnpm install && pnpm test` exits 0 with zero failing files.
- API tests still runnable and passing via a documented command.
- `testing.md` documents where API tests run.

---

### Bug 3 — Committed debug credentials: `cookies.txt` (JWT) and `api/test-login.json` (admin/admin)

**Severity:** high as hygiene, low as live risk — the token is expired and
localhost-scoped, but tracked credential files invite a live one next time.
**Suggested labels:** `bug`, `security`

#### Description

Two credential-bearing debug files are tracked in git:

- **`cookies.txt`** (repo root) — a Netscape-format curl cookie jar holding a
  real `refresh_token` JWT for `localhost`, subject `admin-001`, HS256-signed,
  expired 2025-09-09. Committed since PR #21 ("Improved CV, Projects Layout
  and UI").
- **`api/test-login.json`** — a curl request body containing
  `{"username": "admin", "password": "admin"}`.

Neither is referenced by any script; both are leftovers from hand-testing the
API's auth flow. Cost of leaving them: secret scanners flag the repository on
every run, and the precedent means the next debug session may commit a token
that is *not* expired.

#### How to fix

1. Remove both files:

   ```bash
   git rm cookies.txt api/test-login.json
   ```

2. Keep them out permanently — add to `.gitignore`:

   ```gitignore
   # Local API debug artifacts — never commit tokens or login payloads
   cookies.txt
   api/test-login.json
   ```

3. Rotate the signing secret if it is shared: the JWT is HS256, so whatever
   `JWT_SECRET` signed it can mint new tokens. If that secret ever appears in
   a deployed environment (not just a local default), rotate it there.

4. Decide on history: the token is expired and localhost-only, so rewriting
   history (`git filter-repo`) is likely not worth the disruption — but note
   the value stays retrievable from history either way, which is why rotation
   is the real mitigation, not deletion.

5. Optionally run GitHub secret scanning on the repository to confirm nothing
   else of this kind is tracked.

#### Acceptance criteria

- `git ls-files | grep -iE "cookie|token|login"` returns no credential files.
- `.gitignore` covers both paths.
- A note in the API README says how to hand-test login without committing
  artifacts (e.g. an untracked `test-login.local.json`).

---

### Bug 4 — Prebuild warns "Projects Configuration Missing" on every build; the check tests a key that never exists

**Severity:** low — cosmetic, but a warning that always fires trains readers
to ignore warnings.
**Suggested labels:** `bug`, `build`

#### Description

Every build prints:

```
[WARN] Projects Configuration Missing, Using Defaults
```

even though `config/projects.yml` exists and converts to `data/projects.json`
successfully in the same run.

#### Root cause

In `scripts/pre-build.ts` (config loader, ~line 689):

```ts
// Add default values for missing Projects properties
if (!configData.projects) {
  console.warn('[WARN] Projects Configuration Missing, Using Defaults');

  // Note: projects is not part of GlobalConfig interface - this line should be removed or handled differently
}
```

The check inspects `configData.projects` on the parsed
`config/globalConfig.yml` — but that file has no `projects` key and never did:
projects data lives in its own `config/projects.yml`, and the page-level
switch in `globalConfig.yml` is named `projectsPage`. The block warns, sets
nothing, and its own inline comment already concedes it should be removed.
`projects` is also absent from the `GlobalConfig` interface, so no code could
consume the "default" the warning implies.

#### How to fix

Delete the entire `if (!configData.projects) { ... }` block. If the original
intent was to validate the page switch, replace it with a check that matches
reality:

```ts
if (configData.preBuild?.projectsPage && !configData.projectsPage) {
  console.warn('[WARN] projectsPage enabled but not configured in globalConfig.yml');
}
```

Then run `pnpm run prebuild` and confirm the warning no longer appears while
`projects.yml → data/projects.json` conversion still logs success.

#### Acceptance criteria

- `pnpm run prebuild` on an unmodified checkout prints no `[WARN]` for
  projects.
- A genuinely missing/misconfigured projects setup still surfaces an accurate
  message.

---

## Issues

### Issue 1 — Deprecated `onBrokenMarkdownLinks` placement; broken-link policy can never fail a build

**Suggested labels:** `maintenance`, `config`

#### Description

Two related link-checking problems in `docusaurus.config.ts`:

1. `onBrokenMarkdownLinks: 'warn'` sits at the top level. Docusaurus warns on
   every build that this location is deprecated and will be removed in v4;
   the supported home is `markdown.hooks.onBrokenMarkdownLinks`.
2. `onBrokenLinks: 'warn'` means a genuinely broken internal link can never
   fail a build — it scrolls by in CI output. The only broken links today are
   the five *intentional* ones on `/demos/404` (they exist to demonstrate the
   custom 404 page), which is presumably why the setting is `'warn'`.

#### How to fix

1. Move the markdown hook (mechanical):

   ```ts
   // remove: onBrokenMarkdownLinks: 'warn',
   markdown: {
     mermaid: true,
     hooks: {
       onBrokenMarkdownLinks: 'warn'
     }
   },
   ```

2. Make `'throw'` viable by exempting the demo links. Docusaurus's broken-link
   checker only tracks links rendered through `@docusaurus/Link` (and markdown
   links); plain anchors are invisible to it. `src/pages/demos/404.tsx`
   currently renders its intentionally-broken list via `Link` — switch those
   five to plain `<a href={link}>` elements (behaviour for the visitor is
   identical: a full-page navigation to a 404), then set:

   ```ts
   onBrokenLinks: 'throw',
   ```

3. Rebuild: the build must pass, and introducing a deliberate typo in any
   docs link must now fail it.

#### Acceptance criteria

- No deprecation warning for `onBrokenMarkdownLinks` in build output.
- `pnpm run build` fails on a real broken internal link.
- `/demos/404` still demonstrates the custom 404 page.

---

### Issue 2 — Version drift: three docs advertise "Docusaurus 3.8.1"; the dependency is 3.10.1

**Suggested labels:** `documentation`

#### Description

The pinned dependency is `"@docusaurus/core": "3.10.1"` (`package.json:83`),
but three prose locations still advertise 3.8.1:

| File | Line | Text |
| --- | --- | --- |
| `README.md` | 9 | "🚀 **Modern Docusaurus 3.8.1** with TypeScript support" |
| `docs/index.md` | 13 | "🚀 **Modern Docusaurus 3.8.1** with full TypeScript support" |
| `docs/getting-started/features.md` | 9 | "🚀 **Modern Docusaurus 3.8.1** - Latest version with TypeScript support" |

Already flagged as `TODO.md` P1.3; this pins the exact occurrences.

#### How to fix

Preferred: stop hardcoding the patch version in prose — "Modern Docusaurus 3"
in all three places, so the claim can't rot again. If the number should stay,
update all three to 3.10.1 in the same commit, and add the trio to the release
checklist (or extend the doc gate's GeneratedFiles/terminology rules to catch
version strings) so the next bump can't miss one.

Note `docs/index.md` mirrors README content by design — check whether the
consumer-side generator (`ConvertTo-DocumentationHomepage.ps1`) regenerates it
before hand-editing, so the fix lands in the source, not the artifact.

#### Acceptance criteria

- `grep -rn "3\.8\.1" README.md docs/` returns nothing.
- Either no hardcoded patch version remains in prose, or a checklist/gate item
  guards the ones that do.

---

### Issue 3 — Coverage thresholds: `testing.md` documents 75/70/60/75, config enforces 55/55/45/55

**Suggested labels:** `documentation`, `tests`

#### Description

`testing.md:36` states: "Coverage thresholds are configured in
vitest.config.ts (lines: 75, functions: 70, branches: 60, statements: 75)."
The actual `vitest.config.ts` thresholds are lines 55, functions 55,
branches 45, statements 55.

`TODO.md` P0.2 tracks this and records that `AGENTS.md` (which repeated the
same wrong numbers) was already fixed to point at the config instead of
restating values. `testing.md` was not given the same treatment, so the drift
survives in one of the two documents.

#### How to fix

Apply the same fix that worked for `AGENTS.md` — make the config the single
source of truth. Replace the sentence at `testing.md:36` with:

> Coverage thresholds are configured in `vitest.config.ts` (see the
> `coverage.thresholds` block) — the config is the source of truth; this
> document deliberately does not restate the numbers.

Separately decide the *policy* question `TODO.md` P0.2/P1.5 raises (current
55s vs a target of 80): that's a config change with its own PR, not a docs
edit, and shouldn't block this correction.

#### Acceptance criteria

- No file outside `vitest.config.ts` states numeric coverage thresholds.
- `testing.md` and `AGENTS.md` both point at the config.

---

### Issue 4 — Undocumented components: `DataProvider`, `DebugInfo`, `ReaderMode`, `TextSizeSwitcher`

**Suggested labels:** `documentation`, `components`

#### Description

Doc coverage is uneven across `src/components/`:

- **`DataProvider`** and **`DebugInfo`** appear nowhere in `docs/` — no
  core-systems page, no mention in `key-components.md` — despite both having
  test suites (so they are maintained code, not scraps).
- **`ReaderMode`** and **`TextSizeSwitcher`** have live demo pages
  (`src/pages/demos/reader-mode.tsx`, `src/pages/demos/text-size-switcher.tsx`)
  and navbar toggles, but only a one-line mention in
  `docs/configuration/key-components.md` — while sibling navbar toggles get
  full pages (`docs/core-systems/theme-system.md`,
  `docs/core-systems/version-display-system.md`).

A reader following the core-systems section will conclude the reader-mode and
text-size features don't exist, or aren't supported.

#### How to fix

1. Write `docs/core-systems/reader-mode.md` and
   `docs/core-systems/text-size-switcher.md`, modeled on
   `theme-system.md`: what the toggle does, where it persists state
   (localStorage key), how a consumer enables/disables it (feature flag or
   navbar item), and a link to the demo page.
2. For `DataProvider` and `DebugInfo`, decide first whether they are public
   surface or internal plumbing:
   - Public → document them the same way.
   - Internal → say so once (a short "internal components" note in
     `docs/core-systems/components-system.md`) so their absence reads as a
     decision, not an omission.
3. Cross-link each new page from the demos and from `key-components.md`.

#### Acceptance criteria

- Every navbar-visible feature has a core-systems page.
- Every component under `src/components/` is either documented or explicitly
  listed as internal.

---

### Issue 5 — `docs/guides/` has no `_category_.json` or index page

**Suggested labels:** `documentation`

#### Description

Every docs section (`getting-started/`, `configuration/`, `core-systems/`,
`advanced/`, `pull-requests/`) carries a `_category_.json` and an index or
equivalent — except `docs/guides/`, which holds four files
(`api-specs.md`, `admin-projects-interface-specs.md`,
`unified-projects-auth-specs.md`, `projects-manager.md`) with no category
metadata. Its sidebar label, position, and collapse behaviour are whatever the
autogenerated defaults produce, inconsistent with the rest of the tree.

The four files are also *specification* documents for the API/admin work, not
how-to guides — which raises the prior question of whether they belong in the
published docs at all, given `TODO.md` P2 wants the API out of Phase 1
docs/navigation paths.

#### How to fix

1. Decide placement first (cheapest moment is now):
   - If they stay published: add `docs/guides/_category_.json` matching the
     siblings' shape, e.g.

     ```json
     {
       "label": "Guides",
       "position": 6,
       "collapsed": true,
       "link": {
         "type": "generated-index",
         "description": "Specifications and working guides for the projects and admin systems."
       }
     }
     ```

   - If the API specs move to Phase 2 per `TODO.md` P2: relocate the three
     spec files out of `docs/` (repo-root `planning/` or the API package),
     leaving `projects-manager.md` in a properly-categorized section.
2. Rebuild and check the sidebar renders the section with an explicit label
   and position either way.

#### Acceptance criteria

- No docs section relies on autogenerated category defaults.
- Spec documents are either deliberately published under a labeled section or
  moved out of the published tree, consistent with the API's Phase 2 status.

---

## Already tracked elsewhere

Known open work recorded in `TODO-Next.md` (updated with #47) is not
duplicated here: the `--user` asymmetry in `Invoke-DocsBuild`, no Pester
harness for the PowerShell scripts, the missing `-BaseUrl` installer
parameter, and five planning documents accumulating at the repository root.
The consumer root-404 regression has its own plan in `consumer-root-404.md`.

## Not verified

The PowerShell doc gate (`Test-Documentation.ps1`) could not be run in the
inspection environment — no `pwsh` available — so the terminology and drift
checks it enforces were not re-verified.
