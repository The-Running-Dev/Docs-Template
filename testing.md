What changed

- test: now calls test:run so pnpm test runs once (CI-friendly).
- test:components: consistent flag order: vitest run --coverage src/components.
- test:ci: new alias for coverage run to use in pipelines.
- quality: replaced invalid validate:github with validate:config.

Updated scripts

- test: runs unit tests once. Equivalent to test:run.
- test:run: single pass run for all tests.
- test:watch: watch mode for TDD.
- test:ui: Vitest UI for interactive debugging.
- test:coverage: single pass with coverage reports (config in vitest.config.ts).
- test:components: run only component tests with coverage.
- test:ci: alias for test:coverage; recommended for CI.
- test:all: run tests, typecheck, and schema/config validation locally.
- typecheck: TypeScript type-only check.
- validate:config: validates GitHub config (scripts/validate-github-config.ts).
- validate:schemas: validates component schema system (scripts/test-schema-system.ts).
- quality: formatting check, lint, typecheck, prebuild check, and config validation.
- quality:fix: auto-format + lint:fix.
- quality-ci: lighter CI gate (lint, typecheck, prebuild:check).

Usage tips

- Local dev: pnpm test:watch or pnpm test:ui.
- Quick run: pnpm test (single pass).
- Coverage: pnpm test:coverage (or pnpm test:ci).
- Components-only: pnpm test:components.
- Full local gate: pnpm test:all or pnpm quality before PR.
- API tests: pnpm test:api. api/ is a separate pnpm workspace with its own lockfile and dependencies, excluded from the root test run; this installs and runs its tests via its own package.json.

Notes

- If you see Rollup optional-deps errors when running tests, use Node 18–20. Node 23 can cause rollup native binary resolution issues.
- Coverage thresholds are configured in vitest.config.ts (see the coverage.thresholds block) — the config is the source of truth; this document deliberately does not restate the numbers.
  ────────────────────────────────────────────────
