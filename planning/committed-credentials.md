# docs-template — debug credentials are tracked in git

**Status:** Done (#61)
**Severity:** high as hygiene, low as live risk — the token is expired and
localhost-scoped, but tracked credential files invite a live one next time
**Labels:** `bug`, `security`
**Found:** 2026-07-27 audit, against `main` at `3965669` (#47)

## Summary

Two credential-bearing debug files are tracked:

- **`cookies.txt`** (repository root) — a Netscape-format curl cookie jar
  holding a real `refresh_token` JWT for `localhost`, subject `admin-001`,
  HS256-signed, expired 2025-09-09. Tracked since #21 ("Improved CV, Projects
  Layout and UI").
- **`api/test-login.json`** — a curl request body containing
  `{"username": "admin", "password": "admin"}`.

Neither is referenced by any script. Both are leftovers from hand-testing the
API's auth flow.

Cost of leaving them: secret scanners flag the repository on every run, and the
precedent means the next debug session may commit a token that is *not*
expired.

## Required fix

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

3. **Rotate the signing secret if it is shared.** The JWT is HS256, so whatever
   `JWT_SECRET` signed it can mint new tokens. If that secret exists anywhere
   beyond a local default — a deployed environment, a shared `.env` — rotate it
   there. This is the real mitigation; deletion alone is not, because the value
   stays retrievable from history either way.

4. **History rewrite: probably not worth it.** The token is expired and
   localhost-only, so `git filter-repo` would cost every open branch and clone
   a re-sync for little gain. Rotation (step 3) covers the actual risk. Revisit
   only if a live secret is ever found.

5. Optionally run GitHub secret scanning to confirm nothing else of this kind
   is tracked.

## Acceptance criteria

- `git ls-files | grep -iE "cookie|token|login"` returns no credential files.
- `.gitignore` covers both paths.
- The API README says how to hand-test login without committing artifacts
  (for example, an untracked `test-login.local.json`).
