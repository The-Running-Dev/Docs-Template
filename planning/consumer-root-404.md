# docs-template — removing `src/pages` left consumers with no root page

**Status:** Open
**Severity:** medium — silently breaks the canonical URL of every consumer site
using the default `routeBasePath`
**Labels:** `bug`, `consumer-impact`
**Found:** follow-up to #44, verified against the CI-built Pages artifact for
`The-Running-Dev/SubZeroDev.WinGet`

Follow-up to the `src/pages` leakage fix. That fix is **confirmed working** — this
is the side effect it introduced.

## Summary

The previous fix removed `/template/src/pages/*` wholesale, which correctly
eliminated the leaked `/cv`, `/portfolio`, `/projects` and `/admin/projects`
routes. But `index.tsx` went with them, so a build now emits **no root page at
all**.

With the default `routeBasePath: 'docs'`, content lives at `/docs/*` and the bare
domain 404s. For most consumers the bare domain is the advertised URL — the thing
in the README, the repo's About field, and any existing inbound links — so the
fix trades a wrong homepage for a missing one.

Severity: **medium.** Not as bad as serving someone else's CV, but it silently
breaks the canonical URL of every consumer site that uses the default
`routeBasePath`.

## Evidence

Verified against the CI-built Pages artifact for
`The-Running-Dev/SubZeroDev.WinGet` (`baseUrl: '/'`, `routeBasePath: 'docs'`).

Image before fix — `config.digest sha256:a1357293…`:

```
/                    <- "Welcome" (template's index.tsx)  ← wrong page
/cv, /portfolio, /projects, /admin/projects                ← leaked
/docs/*              <- consumer content                   ← correct
```

Image after fix — `config.digest sha256:3c370cc0…`:

```
artifact root: 404.html  CNAME  assets  docs  img  sitemap.xml  themes
                                                    ↑ no index.html

/docs/*              <- consumer content                   ← correct
                     <- nothing at /                       ← now 404s
```

The leakage fix worked exactly as specified. The only regression is the empty
root.

## Reproduce

```bash
docker run --rm -v "$PWD:/work" -w /work \
  ghcr.io/the-running-dev/docs-template:latest \
  Invoke-DocsBuild -SourceDocs /work/docs -OutputPath /work/artifacts/docs

ls artifacts/docs/index.html   # absent
```

Then serve `artifacts/docs` and request `/` → 404.

## Why the previous spec allowed this

The earlier acceptance criteria said the root should be *"either empty-by-design or
a redirect."* Removing it satisfied the letter of that. In practice the
empty-by-design option is the wrong default: it only works for consumers whose
advertised URL already includes `/docs`, and nothing in the template steers them
there. Treat this as a correction to that criterion, not a new requirement.

## Required fix

Ship a root that forwards to `routeBasePath`, so the bare domain resolves out of
the box.

Constraints:

- Must **not** reintroduce branded template content. A redirect only — no
  "Welcome" page, no marketing copy, nothing carrying the consumer's `title` that
  the consumer did not write.
- Must be a no-op when `routeBasePath: '/'`, where the docs homepage is already the
  root and a redirect would loop.
- Must remain overridable: a consumer that wants a real landing page must be able
  to supply one without fighting an image file.

### Implementation options

1. **`@docusaurus/plugin-client-redirects`** (most idiomatic). Configure
   `redirects: [{ from: '/', to: '/${routeBasePath}/' }]` when `routeBasePath !== '/'`.
   Generates the redirect at build time and is a supported Docusaurus feature.
2. **A generated static `index.html`.** Emit a minimal meta-refresh document into
   the build root during `docs-build`, derived from the configured
   `routeBasePath`. No dependency, but hand-rolled.
3. **Leave it to consumers, and document it.** Acceptable only if the README calls
   it out prominently — otherwise every consumer ships a 404 at their advertised
   URL and finds out from a user.

Preference: option 1, falling back to 2 if the plugin dependency is unwanted.

### Acceptance criteria

- With default `routeBasePath: 'docs'`, a consumer build emits a root that
  resolves — request `/`, land on the docs homepage.
- With `routeBasePath: '/'`, no redirect artifact is emitted and `/` is the docs
  homepage directly (no redirect loop).
- The emitted root carries no template-authored copy beyond a minimal redirect
  notice.
- The previously-fixed leakage does not return: a build still emits no `/cv`,
  `/portfolio`, `/projects` or `/admin/*`.
- A consumer-supplied `static/index.html` still wins over whatever the template
  emits.

## Current downstream workaround

`SubZeroDev.WinGet` now carries this, which should become unnecessary once the
template handles it:

```html
<!-- docs/static/index.html -->
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <title>SubZeroDev.WinGet</title>
    <link rel="canonical" href="https://winget.subzerodev.com/docs/" />
    <meta http-equiv="refresh" content="0; url=/docs/" />
  </head>
  <body>
    <p>Redirecting to <a href="/docs/">the documentation</a>…</p>
  </body>
</html>
```

Files under `docs/static/` are copied to the build root, so this lands at `/`
without reintroducing a page component. Confirmed present in the CI artifact with
`url=/docs/`.

Note this is a per-consumer copy of template-level behaviour — the reason to fix it
upstream. If the template starts emitting its own root, consumers carrying this
file should be told to delete it, since a consumer `static/index.html` will
otherwise shadow the generated one (which is correct precedence, but means the
hardcoded `/docs/` here would survive a future `routeBasePath` change and break
silently).