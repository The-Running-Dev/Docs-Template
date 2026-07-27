# Planning

Working documents for this repository's open problems. This directory exists
only on `feature/planning`; it is never merged to `main`, so plans stay out of
the published site and out of consumers' clones.

That is deliberate, and it is the fix for `TODO-Next.md` §7 — five planning
documents accumulating at the repository root, where a reader cannot tell which
of them describe work still to do. Plans belong here; `main` carries only
shipped code and published docs.

## One file, one unit of work

Each file is one problem, named for the problem, sized to one pull request. A
file carries everything a fix needs and nothing it does not:

```markdown
# <repo> — <what is wrong, in a sentence>

**Status:** Open | In progress (<branch or PR>) | Done (<PR>)
**Severity:** <how bad, and to whom>
**Labels:** <suggested GitHub labels>
**Found:** <when, and against which commit>

## Summary        — what is wrong and why it matters
## Evidence       — the output, the digest, the failing command
## Root cause     — why it happens, not just where
## Required fix   — worked steps, with code; options and a preference if the call is open
## Acceptance criteria — how the next person knows it is finished
```

Two or three findings may share a file when one pull request would fix them
together — `build-warnings.md` and `docs-drift.md` are grouped that way. Do not
group findings that would land in separate reviews.

There is deliberately **no index file**. An index is a second copy of every
entry, and it goes stale the first time a topic file is edited. The table below
is the index, and it lives in the one file nobody works inside.

## Current plans

| File | Status | What it covers |
| --- | --- | --- |
| `consumer-root-404.md` | Open | Consumer builds emit no root page after the `src/pages` leakage fix |
| `duplicate-homepage-route.md` | Open | `src/pages/index.md` and `index.tsx` both claim `/` |
| `test-health.md` | Open | `pnpm test` red on a fresh clone; `testing.md` thresholds disagree with the config |
| `committed-credentials.md` | Open | `cookies.txt` JWT and `api/test-login.json` are tracked in git |
| `build-warnings.md` | Open | Prebuild warns on every run; broken links cannot fail a build |
| `docs-drift.md` | Open | Stale 3.8.1 claims, undocumented components, uncategorized guides |

## Workflow

Planning lives on one branch; work happens on others. The loop below keeps them
in sync without either one blocking the other.

### 1. Plan

Findings land here first — from an audit, a consumer report, or a review.
Write the file before writing the fix, so the fix has acceptance criteria to
meet rather than a vibe to satisfy.

```bash
git checkout feature/planning
git pull origin feature/planning
# add or edit a topic file
git commit && git push -u origin feature/planning
```

### 2. Start work

Pull the latest plans, then branch the *work* off `main` — never off
`feature/planning`, or the plans ride along into the pull request.

```bash
git fetch origin
git checkout feature/planning && git pull origin feature/planning   # read the plan
git checkout -b fix/duplicate-homepage-route origin/main            # work branch
```

### 3. Work — read the plan without leaving the branch

The plan is on another branch, so a plain `cat` will not find it. Two ways
across, and the second is worth setting up once:

```bash
# quick read, no checkout
git show feature/planning:planning/duplicate-homepage-route.md

# permanent second checkout — both branches open at once, no stashing
git worktree add ../docs-planning feature/planning
```

With a worktree, `../docs-planning/planning/` is always the current plans while
your work branch stays checked out here. Update the plan mid-flight — new
evidence, a rejected option — without touching your working tree.

### 4. Finish

Open the pull request against `main`. Reference the plan by filename in the
description, and answer its acceptance criteria explicitly — that is what the
criteria were written for.

### 5. Update the plan

Back on `feature/planning` (or in the worktree), record the outcome:

- **Merged and criteria met** → set `**Status:** Done (#NN)` and add a one-line
  result. Keep the file for one cycle: the reasoning is what makes the *next*
  related bug diagnosable. #44 was only diagnosable because #42's record said
  what had already been tried.
- **Partly done** → strike the finished part, leave the rest Open, say which
  pull request did what.
- **Rejected or obsolete** → say why, then delete the file. Git history keeps
  it; the directory should show live work only.

### 6. Evaluate

Periodically — after a release, or after a batch of fixes:

- Re-run the audit commands (`pnpm install && pnpm test`, `pnpm run build`) and
  confirm the Done files' criteria still hold. A criterion that quietly stopped
  holding is a regression nobody filed.
- Delete Done files older than a cycle.
- Rebase this branch on `main` if it has drifted far enough to be confusing.
  Nothing here conflicts — `planning/` exists on no other branch — so this is
  housekeeping, not merge work.

## Rules

- **Never merge `feature/planning` into `main`.** It is a permanent side
  branch.
- **Never branch work off `feature/planning`.** Work branches start at
  `origin/main`.
- **Only `planning/` changes on this branch.** A code change here is a mistake;
  it belongs on a work branch.
