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

### Who this actually affects — `routeBasePath` is already a parameter

`setup-docs.ps1` already exposes `-RouteBasePath` (#47), and it **already
defaults to `/`**. The `routeBasePath: 'docs'` in
`scripts/template/docusaurus.config.ts` is a substitution placeholder, not the
installed default — setup rewrites it with the effective value. There is also a
guard: when `-RouteBasePath` is not passed explicitly and a config already
exists, that project's current value wins, so re-running with `-Overwrite` to
pick up an upstream fix cannot move a project's URLs.

That scopes this defect more narrowly than it first appears:

| `routeBasePath` | What serves `/` | Affected? |
| --- | --- | --- |
| `/` (the default) | the docs index — `docs/docs/index.md`, generated from the README | **No.** Root resolves; nothing to fix |
| `docs` or any custom value | nothing | **Yes.** Root 404s, brand link breaks sitewide |

So a *fresh default install* is already correct, and the README already becomes
the root page. The consumers that broke — `SubZeroDev.WinGet`,
`SubZeroDev.GameEngine` — are on `routeBasePath: 'docs'`, either chosen
deliberately or preserved by the guard above from an install that predates #47.

This is why the work below is conditional on `routeBasePath !== '/'`: the `/`
case needs no new destination, because the docs index already *is* the root.

#### Align the template literal with the real default

**Decided:** change `scripts/template/docusaurus.config.ts` from
`routeBasePath: 'docs'` to `routeBasePath: '/'`.

The literal is a leftover from before #47, when there was no substitution and
the file was installed verbatim — which is why the two affected downstreams are
on `'docs'` at all. Now that setup substitutes it, the file reads as though
`'docs'` were the default when the default is `'/'`. That discrepancy is not
harmless: it is what made both the downstream report and the first pass of this
plan reason about the wrong default.

**Decided:** make the substitution regex-based *first*, then change the literal.
Not "same commit, carefully" — remove the coupling so it cannot recur.

The hazard is that the substitution key in `setup-docs.ps1` (`$configReplacements`,
~line 588) is the exact string `routeBasePath: 'docs'`, and `Copy-TemplateFile`
applies it with `String.Replace` (line 286), which **returns the string unchanged
when the key is absent** — no error, no warning. Change the template literal
alone and `-RouteBasePath` silently stops working while every install still
reports success. A literal key that has to match a literal in another file is a
coupling nobody can see from either side.

- [ ] Replace the `routeBasePath` entry with a regex substitution on
      `routeBasePath:\s*'[^']*'`, so the key matches whatever the template
      currently says. The "existing config wins" guard above already uses that
      exact pattern, so one shape serves both read and write.
- [ ] Only then change the template literal to `routeBasePath: '/'`. With the
      regex in place this is a content change that cannot break the mechanism.
- [ ] Escape `$` in the replacement value — `[regex]::Replace` treats it as a
      capture reference, unlike `String.Replace`. A `routeBasePath` will not
      normally contain one, but the helper should not depend on that.

**Implementation note.** `Copy-TemplateFile` applies every `-Replace` entry
through `String.Replace`, so a regex entry needs somewhere to live: either a
second parameter (`-RegexReplace`) alongside the literal hashtable, or handling
`routeBasePath` outside the helper. The first keeps one call site and is the
smaller change.

**Worth fixing the class, not just this case.** `title: ''` and `tagline: ''` are
literal keys with exactly the same failure mode — edit either placeholder in the
template and the substitution silently stops applying. Cheap systemic guard:

- [ ] Have `Copy-TemplateFile` warn (or throw) when a replacement key is not
      found in the content. Every one of these keys is expected to match exactly
      once; a miss is always a bug, never a valid state. This turns a whole class
      of silent breakage loud, and would have caught this one at authoring time.

### On adding an `index.md` under docs

**Needed — but as a landing page, not a redirect.** `/docs/` is directly
reachable: someone types it, or follows a bookmark or an old inbound link. For
every consumer on `routeBasePath: 'docs'` it resolves today, so it must keep
resolving. `docs/docs/index.md` stays; only its content changes, from a copy of
the README to a genuine docs landing page. Recorded in full under "No
duplication" above.

Redirect is the wrong shape regardless of the decision: a Markdown file cannot
redirect. What puts a page on that route is the `isCategoryIndex` convention
(`index.md` at the docs root — where setup already writes) or a doc with
`slug: '/'`. Both produce a page; neither produces a redirect.

With `routeBasePath: '/'` the question does not arise — docs are served from the
root, the README-derived index already occupies it, and `/docs/` is not a route
the site ever had.

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

**One path, not two** (decided 2026-07-28). Today `setup-docs.ps1` branches: a
README generates a page, no README writes a title-only stub. Both branches
disappear. Setup guarantees a README exists, then a single generation path runs
— and because the guarantee is "create only when absent", a project that already
has a README is untouched and reaches exactly the same code.

- [ ] **Ensure a README, then generate.** If `README.md` is absent at the project
      root, create it from `-Title` and `-Description` — project name, a
      sentence, a link to the docs. Never overwrite an existing one. Then run the
      normal generation path over it.
- [ ] **Delete the stub branch** in `setup-docs.ps1` (the
      `elseif (-not (Test-Path $indexPath))` block that writes a title-only
      `index.md`). With a README always present it is unreachable, and it was
      only ever a worse copy of the generator's output.
- [ ] Drop the "No README.md found; skipping homepage generation" warning with
      it — nothing is skipped any more.
- [ ] **Write the generated page to `docs/src/pages/index.md`** when
      `routeBasePath !== '/'`, so it routes at `/`. Keep `docs/docs/index.md` as
      the destination when `routeBasePath === '/'`, where the docs index *is*
      the root and a second root page would collide.
- [ ] Add a documentation link to the generated page, pointing at the **resolved
      first document**, not at bare `/docs/` — that path has no route by
      decision. Derive it rather than hardcoding, so it survives a
      `routeBasePath` change.
- [ ] **Rewrite `docs/docs/index.md` as a docs landing page** when
      `routeBasePath !== '/'` — project name, a line, links into the sections.
      Not the README, and not deleted: the file keeps `/docs/` resolving for the
      consumers who have it today.
- [ ] Point the `DocumentationRules.psd1` `GeneratedFiles` drift check at the new
      path, so the root page stays in sync with the README the way
      `docs/docs/index.md` does today.
- [ ] Confirm `.dockerignore` and `scripts/template/dockerignore` do not exclude
      the consumer's `docs/src/`, or the overlay never sees the file.

### No duplication: the README renders once

**Decided:** the README's *content* is served at exactly one URL — `/`.
`setup-docs.ps1` stops writing README content to `docs/docs/index.md`, so
consumers do not read the same text at both `/` and `/docs/`.

`docs/docs/index.md` is **not deleted** — it is rewritten as a docs landing page
(see below). Replacing its content rather than removing the file is what keeps
`/docs/` resolving for consumers who have it today.

**Decided (revised 2026-07-28):** `/docs/` gets a real landing page. An earlier
pass of this plan said it deliberately had none; that is reversed.

The reason is simple and decisive: **`/docs/` is a typeable URL, and for every
consumer on `routeBasePath: 'docs'` it resolves today** — it currently serves the
README-derived `docs/docs/index.md`. Removing that file without replacing it
would take a working URL and 404 it, which is the same class of regression this
whole document exists to fix. "Nothing links to it" is not a defence against
someone typing it, or against a bookmark, or an inbound link from before.

So the no-duplication rule stands, but it is about *content*, not about the
route: `/docs/` keeps a page, and that page stops being a copy of the README.

The distinction below still matters, because it is easy to assume Docusaurus
does more than it does — and it explains why the landing page has to be authored
or generated rather than expected.

**Docusaurus does not redirect `/docs/` to the first doc.** What it does have is
`getMainDocId` (`plugin-content-docs/lib/docs.js:203`), which resolves a
plugin's "main doc" as: the doc with `slug: '/'`, else **the first doc of the
first sidebar**, else any doc. That resolution is what a navbar
`type: 'docSidebar'` or `type: 'doc'` item links to — and the installed config
uses exactly that item type. So the navbar "Docs" link lands on the first
sidebar document, by its own URL, with no index page needed.

What it does *not* do is give the bare `/docs/` path a route. Typed directly, it
404s unless some doc occupies it. Two things put a doc there, both by
convention rather than redirect (`isCategoryIndex`, same file, line 226):
`index.md`, `readme.md`, or `<folder>/<folder>.md` at the docs root — their
slugs drop the `/index` suffix, so they land on the route base — or any doc with
`slug: '/'` in front matter.

So the navbar is fine either way — but a typed `/docs/` is not, and nothing in
Docusaurus will cover for it. The page has to exist.

**What goes there:** a docs landing page, generated by setup the same way the
root page is, with content that is *not* the README. Enough to orient someone
who typed the URL — the project name, a line, and links into the sections. Two
supported mechanisms put a file on that route, both by convention rather than
redirect: name it `index.md` at the docs root (the `isCategoryIndex` case), or
give any doc `slug: '/'`. The first is what setup already writes to, so the path
does not change — only the content does.

With `routeBasePath: '/'` this question does not arise: docs are at the root,
the README-derived index is already there, and `/docs/` is not a route the site
ever had.

### Watch for

- **Writing outside `docs/` is new**, but narrowly. `setup-docs.ps1` currently
  confines itself to the docs directory (plus workflows), and creating a root
  `README.md` widens that. No opt-out switch: "only when absent" is the guard.
  Setup never touches a README a project already has, and a project without one
  had nothing to lose. `-NoHomepage` still covers the case of wanting no
  generated page at all.
- **Do not readmit the demo pages.** This deliberately uses the same
  `src/pages` mechanism that caused the original leak. The distinction is
  ownership: the file comes from the *consumer's* `docs/`, and the image still
  ships none of its own. The existing leak warning in `docs-build.ps1` must keep
  firing for image-supplied pages, and the acceptance criteria below still
  require a build to emit no `/cv`, `/portfolio`, `/projects` or `/admin/*`.
- **Existing consumers already have `docs/docs/index.md`.** Setup rewrites it as
  the docs landing page rather than deleting it, so `/docs/` keeps resolving
  while the README stops being duplicated. The case to watch is a consumer who
  hand-edited that file: rewrite only when its content still matches what the
  generator produced, and leave an edited one alone.

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
  renders from it. An existing README is never overwritten, and reaches the same
  generation path as a created one — there is no second code path to diverge.
- The README's content is served at exactly one URL. `/docs/` does not repeat it.
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
