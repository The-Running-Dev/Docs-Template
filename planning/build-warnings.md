# docs-template — the build warns on every run, and broken links can never fail it

**Status:** Open
**Severity:** low individually; together they make build output unreadable
**Labels:** `bug`, `build`, `config`
**Found:** 2026-07-27 audit, against `main` at `3965669` (#47)

Two defects that share a goal: make build output mean something. A warning that
always fires trains readers to ignore warnings — including the real ones.

## Problem 1 — "Projects Configuration Missing" fires on every build

### Evidence

Every `pnpm run prebuild` prints:

```
[WARN] Projects Configuration Missing, Using Defaults
```

even though `config/projects.yml` exists and converts to `data/projects.json`
successfully in the same run.

### Root cause

In `scripts/pre-build.ts` (config loader, ~line 689):

```ts
// Add default values for missing Projects properties
if (!configData.projects) {
  console.warn('[WARN] Projects Configuration Missing, Using Defaults');

  // Note: projects is not part of GlobalConfig interface - this line should be removed or handled differently
}
```

The check inspects `configData.projects` on the parsed `config/globalConfig.yml`
— a key that file has never had. Projects data lives in its own
`config/projects.yml`, and the page-level switch in `globalConfig.yml` is named
`projectsPage`. The block warns, sets nothing, and its own inline comment
already concedes it should be removed. `projects` is also absent from the
`GlobalConfig` interface, so no code could consume the "default" the warning
implies.

### Required fix

Delete the `if (!configData.projects) { ... }` block. If the original intent was
to validate the page switch, replace it with a check that matches reality:

```ts
if (configData.preBuild?.projectsPage && !configData.projectsPage) {
  console.warn('[WARN] projectsPage enabled but not configured in globalConfig.yml');
}
```

## Problem 2 — deprecated option placement, and a link policy that cannot fail

### Evidence

`docusaurus.config.ts` sets `onBrokenMarkdownLinks: 'warn'` at the top level.
Every build warns:

```
[WARNING] The `siteConfig.onBrokenMarkdownLinks` config option is deprecated
and will be removed in Docusaurus v4.
Please migrate and move this option to `siteConfig.markdown.hooks.onBrokenMarkdownLinks`.
```

Separately, `onBrokenLinks: 'warn'` means a genuinely broken internal link can
never fail a build — it scrolls past in CI output. The only broken links today
are the five *intentional* ones on `/demos/404`, which exist to demonstrate the
custom 404 page, and are presumably why the setting is `'warn'`.

### Required fix

1. Move the markdown hook:

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
   checker only tracks links rendered through `@docusaurus/Link` and markdown
   links; plain anchors are invisible to it. `src/pages/demos/404.tsx` currently
   renders its intentionally-broken list through `Link` — switch those five to
   plain `<a href={link}>` elements. Visitor behaviour is identical: a full-page
   navigation to a 404, which is the point of the demo. Then set:

   ```ts
   onBrokenLinks: 'throw',
   ```

3. Verify both directions: a clean build must pass, and a deliberate typo in
   any docs link must now fail it.

## Acceptance criteria

- `pnpm run prebuild` on an unmodified checkout prints no `[WARN]` for
  projects, while a genuinely missing projects setup still warns accurately.
- No deprecation warning for `onBrokenMarkdownLinks` in build output.
- `pnpm run build` fails on a real broken internal link.
- `/demos/404` still demonstrates the custom 404 page.
