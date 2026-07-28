# docs-template — nothing routes `/`, so consumers 404 at the root and carry a broken brand link on every page

**Status:** Open
**Severity:** **high.** Silently breaks the canonical URL of every consumer site
using the default `routeBasePath`, puts a broken link on every page of every
consumer site, and is **build-breaking** for any consumer that sets
`onBrokenLinks: 'throw'`
**Labels:** `bug`, `consumer-impact`
**Found:** follow-up to #44, verified against the CI-built Pages artifact for
`The-Running-Dev/SubZeroDev.WinGet`; navbar symptom found via
`The-Running-Dev/SubZeroDev.GameEngine` (deploy broken) and reproduced against
`SubZeroDev.WinGet` (silently affected)

Follow-up to the `src/pages` leakage fix. That fix is **confirmed working** — this
is the side effect it introduced.

## Summary

The previous fix removed `/template/src/pages/*` wholesale, which correctly
eliminated the leaked `/cv`, `/portfolio`, `/projects` and `/admin/projects`
routes. But `index.tsx` went with them, so a build now emits **no root page at
all**, while the installed config still serves everything under
`routeBasePath: 'docs'`.

One root cause, two symptoms — and the second is much larger than the first:

1. **The bare domain 404s.** For most consumers that is the advertised URL.
2. **The navbar brand links to `/` on every page**, including `404.html`. A
   consumer on the default `'warn'` publishes a site whose brand link is dead
   everywhere; a consumer on `'throw'` cannot build at all.

The installed config does not disable the classic preset's `pages` plugin, so it
scans `/template/src/pages/` and adopts whatever the image ships there. That
single fact produced both the original leak and, once the directory was removed,
this regression.

## Symptom 1 — nothing serves the bare domain

With the default `routeBasePath: 'docs'`, content lives at `/docs/*` and the bare
domain 404s. For most consumers the bare domain is the advertised URL — the thing
in the README, the repo's About field, and any existing inbound links — so the
fix trades a wrong homepage for a missing one.

### Evidence

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

### Reproduce

```bash
docker run --rm -v "$PWD:/work" -w /work \
  ghcr.io/the-running-dev/docs-template:latest \
  Invoke-DocsBuild -SourceDocs /work/docs -OutputPath /work/artifacts/docs

ls artifacts/docs/index.html   # absent
```

Then serve `artifacts/docs` and request `/` → 404.

## Symptom 2 — the navbar brand links to `/` on every page

This was masked until recently by the demo pages the image happened to ship. The
accidental upside of the leak was that `/` resolved, which hid this entirely.
Removing the pages — correct in itself — exposed the latent defect and broke a
downstream deploy **with no commit in the downstream repository**.

### Mechanism

Docusaurus's `Logo` component computes its target as `useBaseUrl(logo?.href || '/')`
and renders the wrapping `<Link>` **unconditionally** — only the image inside it is
conditional. Confirmed in
`node_modules/@docusaurus/theme-classic/lib/theme/Logo/index.js`:

```js
const logoLink = useBaseUrl(logo?.href || '/');
return (
  <Link to={logoLink} {...propsRest} {...(logo?.target && {target: logo.target})}>
    {logo && <LogoThemedImage logo={logo} alt={alt} imageClassName={imageClassName} />}
    {navbarTitle != null && <b className={titleClassName}>{navbarTitle}</b>}
  </Link>
);
```

The config `Invoke-SetupDocs` installs
(`scripts/template/docusaurus.config.ts`) sets neither `logo` nor `logo.href`, so
the link always targets `/`. It also ships `navbar.title: ''` — which is `!= null`,
so an empty `<b>` renders inside the link. The result is a link that is invisible
but present on every page.

Also relevant: that config declares no `plugins` and no redirects, so nothing else
supplies a `/` route.

### Reproduce

1. Install into a fresh repository with the defaults `Invoke-SetupDocs` produces.
2. Set `onBrokenLinks: 'throw'` in `docs/docusaurus.config.ts`.
3. Run `Invoke-DocsBuild`.

The build fails with one broken link per page, all targeting `/`:

```
Exhaustive list of all broken links found:
- Broken link on source page path = /404.html:
   -> linking to /
- Broken link on source page path = /docs/:
   -> linking to /
- Broken link on source page path = /docs/engine/architecture:
   -> linking to /
  … one per page …
```

With the default `'warn'` the same entries print as warnings and the build passes,
which is why this went unnoticed. `SubZeroDev.WinGet` is in exactly that state
today: it works, and its navbar brand is a dead link on every page.

### Evidence: same commit, opposite outcomes

`SubZeroDev.GameEngine`, commit `47342b3`, `docs-deploy.yml`, no repository change
between the two runs:

| Run | Base image digest | Result |
|---|---|---|
| [30303045991](https://github.com/The-Running-Dev/SubZeroDev.GameEngine/actions/runs/30303045991) | `sha256:5e18fd4b…` | success |
| [30310899953](https://github.com/The-Running-Dev/SubZeroDev.GameEngine/actions/runs/30310899953) | `sha256:2f0c9ad5…` | failure — 9 broken links to `/` |

Node `26.5.0` and Docusaurus `3.10.1` in both. Because the consumer workflows
track `:latest`, this arrives without a commit — a green `main` goes red on the
next run of unchanged code, which is expensive to diagnose from the consumer side.

## Why the previous spec allowed this

The earlier acceptance criteria said the root should be *"either empty-by-design or
a redirect."* Removing it satisfied the letter of that. In practice the
empty-by-design option is the wrong default: it only works for consumers whose
advertised URL already includes `/docs`, and nothing in the template steers them
there. Symptom 2 retires the option outright — "empty by design" is not available
when the theme links to `/` from every page. Treat this as a correction to that
criterion, not a new requirement.

## Decided approach — the consumer's README becomes the site root

**Decision (2026-07-28):** `/` serves the consumer's own `README.md`, and links
into `/docs`. Not a redirect, not template copy — the project's own front page.

This is strictly better than the redirect options below, because it satisfies
every constraint at once: it is a **real route** (so the broken-link checker
accepts it and a `'throw'` consumer builds), it carries **no template-authored
content** (it is the consumer's README), and it gives the bare domain something
worth serving rather than a bounce to `/docs`.

### What already exists

Most of the machinery is built:

- `ConvertTo-DocumentationHomepage.ps1` already converts a consumer's
  `README.md` into a Docusaurus page — front matter plus the README body, with
  absolute links to `-SiteUrl` rewritten to `-RouteBasePath` so one README is
  correct both on the code host and on the site.
- `setup-docs.ps1` already calls it during install, already falls back to a stub
  when there is no README, and already registers a drift check in
  `DocumentationRules.psd1` so the generated page cannot silently diverge from
  the README.
- **A consumer-supplied `src/pages` is already an anticipated case.**
  `docs-build.ps1` strips the image's `src/pages` *before* the overlay, and says
  why in as many words: "Checked before the overlay rather than after, so a
  consumer supplying their own `docs/src/pages` is not mistaken for the leak."
  The consumer's `docs/src/pages/index.md` therefore lands at
  `/template/src/pages/index.md` and routes at `/`. `scripts/template/Dockerfile`
  does the same strip-then-`COPY` for local preview, so both build paths agree.

### What is missing

The generated page goes to the wrong place, and the no-README path stops short:

1. **The homepage lands at `/docs/`, not `/`.** `setup-docs.ps1` writes the
   generated content to `$contentDir/index.md` — `docs/docs/index.md` — which
   under the installed default `routeBasePath: 'docs'` serves at `/docs/`. The
   README becomes the *docs* index, and the site root stays empty. This one
   destination is the whole defect.
2. **No README means no README is created.** With no `README.md`, setup warns and
   writes a title-only stub at `docs/docs/index.md`. The requirement is to create
   a real `README.md` at the **project root** — project name, a sentence, a link
   to the docs — and generate the root page from it, so the consumer ends up with
   a README they can grow rather than a stub buried in `docs/`.
3. **Nothing links the root to the docs.** A README rendered at `/` has no
   guaranteed path into `/docs`. The generated page needs a documentation link
   the consumer did not have to write.

### Work required

- [ ] Write the generated homepage to `docs/src/pages/index.md` when
      `routeBasePath !== '/'`, so it routes at `/`. Keep writing
      `docs/docs/index.md` when `routeBasePath === '/'`, where the docs index
      *is* the root and a second root page would collide.
- [ ] Add a documentation link to the generated page, derived from
      `-RouteBasePath` rather than hardcoded, so it survives a later change.
- [ ] On no README, create `README.md` at the project root from `-Title` and
      `-Description`, then generate from it by the normal path. Never overwrite
      an existing README.
- [ ] Point the `DocumentationRules.psd1` `GeneratedFiles` drift check at the new
      path, so the root page stays in sync with the README the way
      `docs/docs/index.md` does today.
- [ ] Confirm `.dockerignore` and `scripts/template/dockerignore` do not exclude
      the consumer's `docs/src/`, or the overlay never sees the file.

### Watch for

- **Writing outside `docs/` is new.** `setup-docs.ps1` currently confines itself
  to the docs directory (plus workflows). Creating a root `README.md` widens
  that. Worth an explicit switch — `-NoReadme`, mirroring `-NoHomepage` — so a
  consumer can decline.
- **Do not readmit the demo pages.** This deliberately uses the same
  `src/pages` mechanism that caused the original leak. The distinction is
  ownership: the file comes from the *consumer's* `docs/`, and the image still
  ships none of its own. The existing leak warning in `docs-build.ps1` must keep
  firing for image-supplied pages, and the acceptance criteria below still
  require a build to emit no `/cv`, `/portfolio`, `/projects` or `/admin/*`.
- **Existing consumers already have `docs/docs/index.md`.** Moving the
  destination leaves that file behind, where it will keep serving at `/docs/`
  and duplicate the root. Decide whether setup removes it, or whether the two
  coexist by design — the docs section arguably still wants its own landing page.

## Alternatives considered

Kept for the reasoning; the decided approach above supersedes them.

Constraints any fix must meet:

- Must **not** reintroduce branded template content. A redirect only — no
  "Welcome" page, no marketing copy, nothing carrying the consumer's `title` that
  the consumer did not write.
- Must be a no-op when `routeBasePath: '/'`, where the docs homepage is already the
  root and a redirect would loop.
- Must remain overridable: a consumer that wants a real landing page must be able
  to supply one without fighting an image file.
- **Must satisfy the broken-link checker, not just the browser.** Docusaurus
  resolves links against the route table, so only a real route fixes a `'throw'`
  consumer. This constraint is what reorders the options below.

### Implementation options

**A. Ship a redirecting `src/pages/index.tsx` in the *template*.** Forward `/` to
the docs base with a `meta refresh` in `<Head>` plus a `rel=canonical`. Like the
decided approach, this is a real route, so it fixes both `'warn'` and `'throw'`
consumers. Superseded because the page would be template-authored and would only
bounce the visitor onward, where the decided approach serves the consumer's own
README from a file the consumer owns and can edit.

Worth keeping in mind if the decided approach stalls: the mechanism is the same,
only the content and the owner differ. Prefer `<Head>` with a `meta refresh` over
`<Redirect>` from `@docusaurus/router` either way — `<Redirect>` is client-side and
emits an empty shell that only forwards after React hydrates.

**B. Give the navbar brand an explicit `href`.** Set `navbar.logo.href` to the docs
base in the installed config. This removes the broken link at its source, which is
the most honest fix for symptom 2 — but it does nothing for symptom 1, and
Docusaurus's types require `logo.src` alongside `href`, which forces a navbar image
on every consumer. That visible change to sites that deliberately have none is the
only reason it is not the recommendation. Viable as a companion to A, not a
replacement.

**C. `@docusaurus/plugin-client-redirects`.** Configure
`redirects: [{ from: '/', to: '/${routeBasePath}/' }]` when `routeBasePath !== '/'`.
Idiomatic and supported, but **unverified against the `'throw'` case**: it is not
currently a dependency, and whether its generated redirect registers a route the
broken-link checker accepts has not been confirmed. Verify that before preferring
it — this was the previous recommendation, and symptom 2 is why it no longer is.

**D. A static `index.html` in the template.** Simplest possible change — no React,
no build-time behaviour — but **does not help `'throw'` consumers**: a static file
is not a route.
Verified — [run 30315030056](https://github.com/The-Running-Dev/SubZeroDev.GameEngine/actions/runs/30315030056)
reproduced the failure exactly with the file in place. Good as a stopgap,
insufficient as the fix.

**E. Change the installed default to `routeBasePath: '/'`.** Removes the orphan root
entirely: the generated homepage becomes the site root, which also matches how
`ConvertTo-DocumentationHomepage.ps1` describes its own output ("the site
homepage"). Breaking for existing consumers — every `/docs/…` URL moves — so only
viable behind a flag or a major version.

### Acceptance criteria

- With default `routeBasePath: 'docs'`, a consumer build emits a root that
  resolves — request `/`, land on a page rendered from that project's
  `README.md`, carrying a working link to `/docs`.
- A project with no `README.md` gets one created at its root, and the site root
  renders from it. An existing README is never overwritten.
- A consumer that sets `onBrokenLinks: 'throw'` builds successfully with no
  authored changes.
- Editing the README and re-running the gate reports drift until the root page
  is regenerated, exactly as `docs/docs/index.md` behaves today.
- No page reports a broken link to `/`, including `404.html`.
- With `routeBasePath: '/'`, no redirect artifact is emitted and `/` is the docs
  homepage directly (no redirect loop).
- The emitted root carries no template-authored copy beyond a minimal redirect
  notice.
- The previously-fixed leakage does not return: a build still emits no `/cv`,
  `/portfolio`, `/projects` or `/admin/*`.
- A consumer-supplied `static/index.html` still wins over whatever the template
  emits.

## Guard against recurrence

Whichever option lands, **build the template's own site with `onBrokenLinks: 'throw'`
in CI.** This defect is invisible under the template's own `'warn'` default; a single
job would have caught it before publish, and would catch the next layout-level link
regression too.

`build-warnings.md` proposes the same change to this repository's `onBrokenLinks`
for its own reasons, including the one prerequisite: the five intentional demo links
on `/demos/404` must stop rendering through `@docusaurus/Link` first, or they fail
the build themselves. One change satisfies both files.

## Current downstream workarounds

Both should become unnecessary once the template handles this.

**`SubZeroDev.WinGet`** carries a static root file:

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
`url=/docs/`. It fixes the bare domain only — the navbar brand link is still dead on
every page of that site.

**`SubZeroDev.GameEngine`** ships the same static file *and* has relaxed
`onBrokenLinks` back to `'warn'` to match the template default. The cost is that its
markdown gate skips site-absolute targets — it defers them to Docusaurus's pass — so
those links are no longer gated anywhere.

Note these are per-consumer copies of template-level behaviour, which is the reason
to fix it upstream. If the template starts emitting its own root, consumers carrying
the static file should be told to delete it: a consumer `static/index.html` shadows
the generated one (correct precedence, but the hardcoded `/docs/` would survive a
future `routeBasePath` change and break silently). Once A or B ships, GameEngine can
delete its file and return to `'throw'`, and WinGet stops carrying a dead brand link.
