# docs-template — `pnpm test` is red on a fresh clone, and the threshold docs disagree with the config

**Status:** Open
**Severity:** high — the root test command cannot be used as a local gate
**Labels:** `bug`, `tests`, `api`
**Found:** 2026-07-27 audit, against `main` at `3965669` (#47)

Two problems that share a fix window: the root test run fails, and the document
telling you what it should enforce states numbers the config does not.

Both are already named in `TODO.md` — P0.1 ("Fix root test failures") and P0.2
("Align test documentation with actual configuration"). This file pins the root
causes and the concrete fixes.

## Problem 1 — 9 `api/` test files cannot resolve imports

### Evidence

On a fresh clone, `pnpm install && pnpm test`:

```
Error: Failed to resolve import "fastify" from "api/src/routes/__tests__/authRoutes.test.ts"
Error: Failed to resolve import "typeorm" from "api/src/repositories/database-project-repository.ts"
Error: Failed to resolve import "jsonwebtoken" from "api/src/services/jwtService.ts"
Error: Failed to resolve import "node-cron" from "api/src/services/__tests__/syncService.test.ts"
Error: Failed to resolve import "@octokit/rest" from "api/src/services/githubProvider.ts"

Test Files  9 failed | 86 passed (95)
     Tests  308 passed | 4 skipped (312)
```

Every test that loads, passes. The 9 failures are all load-time resolution
errors under `api/`.

### Root cause

Structural, not flaky:

- `api/` is a standalone package: its own `package.json`, `pnpm-lock.yaml`,
  and `pnpm-workspace.yaml`.
- The root `pnpm-workspace.yaml` lists only `packages: [.]`, so a root
  `pnpm install` never installs `api/`'s dependencies.
- The root `vitest.config.ts` sets no `include`/`exclude` for test discovery,
  so Vitest's default glob sweeps up `api/**/__tests__/**` — tests whose
  dependencies were never installed.

CI never sees this: `test-and-coverage.yml` runs only `pnpm test:components`,
scoped to `src/components`. Anyone running the documented `pnpm test` locally
gets a red run, and real regressions hide behind the known failures.

### Required fix

Three coherent options — pick one and apply it consistently.

**Option A (recommended, smallest change).** Exclude `api/**` from root test
discovery; `api/` already has its own `test` script and lockfile. In
`vitest.config.ts`:

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

**Option B.** Make `api` a real workspace member — add `- api` to the root
`pnpm-workspace.yaml` and delete `api/pnpm-lock.yaml` and
`api/pnpm-workspace.yaml`, so one root install covers everything. This makes
`pnpm test` genuinely run all 95 files, but couples the API's dependency tree
(TypeORM, Fastify, better-sqlite3 with native builds) to the docs template's
install — the opposite of `TODO.md` P2, which wants the API isolated as
Phase 2 scope.

**Option C.** Move `api/` out of this repository entirely, per `TODO.md` P2.
The right end state, but a bigger lift. Option A is compatible with doing this
later.

## Problem 2 — `testing.md` states thresholds the config does not enforce

### Evidence

| Source | lines | functions | branches | statements |
| --- | --- | --- | --- | --- |
| `vitest.config.ts` `coverage.thresholds` (actual) | 55 | 55 | 45 | 55 |
| `testing.md:36` | 75 | 70 | 60 | 75 |

`TODO.md` P0.2 records that `AGENTS.md` carried the same wrong numbers and was
already fixed to point at the config instead of restating values. `testing.md`
did not get the same treatment, so the drift survives in one of the two
documents.

### Required fix

Apply the fix that already worked for `AGENTS.md` — make the config the single
source of truth. Replace the sentence at `testing.md:36` with:

> Coverage thresholds are configured in `vitest.config.ts` (see the
> `coverage.thresholds` block) — the config is the source of truth; this
> document deliberately does not restate the numbers.

The *policy* question (`TODO.md` P0.2/P1.5: current 55s versus a target of 80)
is a config change with its own PR. It should not block this correction.

## Acceptance criteria

- Fresh clone: `pnpm install && pnpm test` exits 0 with zero failing files.
- API tests remain runnable and passing via a documented command.
- `testing.md` documents where API tests run.
- No file outside `vitest.config.ts` states numeric coverage thresholds.
