# docs-template — `src/pages/index.md` and `index.tsx` both claim `/`

**Status:** Open
**Severity:** medium — which page serves the homepage is non-deterministic
**Labels:** `bug`, `build`
**Found:** 2026-07-27 audit, against `main` at `3965669` (#47)

## Summary

Docusaurus turns every file in `src/pages/` into a route. Two files map to the
root route:

- `src/pages/index.tsx` — the real homepage: hero banner with the site title
  plus feature-flagged Portfolio/CV buttons.
- `src/pages/index.md` — a stale copy of the README's "Key Features" content,
  duplicating what `docs/index.md` already publishes at `/docs`.

Which of the two wins depends on plugin processing order, not on anything the
repository controls.

This is the **template repository's own** homepage — distinct from the consumer
problem in `consumer-root-404.md`, where consumers get *no* root page. Here the
template gets two. The two are worth fixing in the same sitting, because both
are about who owns `/`.

## Evidence

Every production build warns:

```
[WARNING] Duplicate routes found!
- Attempting to create page at /, but a page already exists at this route.
This could lead to non-deterministic routing behavior.
```

Reproduce with `pnpm run build`.

## Required fix

Delete the stale page:

```bash
git rm src/pages/index.md
```

Nothing links to it: its content is the README, which `docs/index.md`
(route `/docs`) already carries in maintained form.

Then rebuild and confirm the warning is gone:

```bash
pnpm run build 2>&1 | grep -i "duplicate routes"   # expect no output
```

Serve `./artifacts` and confirm `/` renders the hero banner from `index.tsx`.

## Acceptance criteria

- `pnpm run build` emits no "Duplicate routes found!" warning.
- `/` deterministically renders the `index.tsx` homepage.
- `/docs` still serves the overview content.
