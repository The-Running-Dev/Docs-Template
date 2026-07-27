# Planning

Open problems for this repository. One file per problem, named for the problem,
sized to one pull request. Each file says what is wrong, how it was found, how
to fix it, and how to tell when it is fixed.

| File | Status | What it covers |
| --- | --- | --- |
| `consumer-root-404.md` | Open | Consumer builds emit no root page after the `src/pages` leakage fix |
| `duplicate-homepage-route.md` | Open | `src/pages/index.md` and `index.tsx` both claim `/` |
| `test-health.md` | Open | `pnpm test` red on a fresh clone; `testing.md` thresholds disagree with the config |
| `committed-credentials.md` | Open | `cookies.txt` JWT and `api/test-login.json` are tracked in git |
| `build-warnings.md` | Open | Prebuild warns on every run; broken links cannot fail a build |
| `docs-drift.md` | Open | Stale 3.8.1 claims, undocumented components, uncategorized guides |

When a fix ships, mark the file `Done (#NN)` and delete it once the reasoning
stops being useful. Git history keeps it either way.
