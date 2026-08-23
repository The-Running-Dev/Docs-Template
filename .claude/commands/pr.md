---
description: Take the current branch's pull request to merge-ready — description, gates, then review threads
---

<!-- companion:declared:start -->
**Per-repo companion:** `.claude/commands/pr-local.md`. Read it now, if it exists — an absent,
empty, or frontmatter-only file is no companion, and this file then stands alone.
It may override: `vocabulary`, `extra-steps`, `gate-commands`, `tightened-authorization`. It may never override anything in
[`.claude/COMPANIONS.md`](../COMPANIONS.md) § *Never*, which is also where these categories are defined.
<!-- companion:declared:end -->

Take the work on the current branch to merge-ready, in three phases, in order.

**This command owns the sequence. It does not own the procedure of any phase it delegates.** Phase 2 is `.claude/commands/verify.md` and phase 3 is `.claude/commands/resolve.md`, run in full, in this same session. Those files stay the single home for how a gate is discovered and how a thread is classified — this one never restates them, because a second copy of a rule is a promise it will diverge (`AGENTS.md`, *Single ownership*). Both remain invocable on their own: `/verify` to run the gates against any tree, `/resolve` to work threads on a pull request this command did not open.

**This repository's convention outranks any default in this command.** They genuinely differ — one sibling enables auto-merge as standard practice, another forbids it outright, a third leaves every merge to its owner. **Read the repository's own instruction file before doing anything**, and follow what it says. If it is silent, open the PR and leave the merge alone.

> Three rules below — push before announcing, no AI attribution, and no deployed URL before the deploy succeeds — are stated canonically in `AGENTS.md` (*Git and delivery*, *House conventions*, *Verification*). They are repeated here because this file is injected on its own and the rules fire at exactly these moments. If they ever disagree, `AGENTS.md` is correct and this file has drifted.

## Phase 1 — the pull request and its description

```powershell
git status --short --branch
if (git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>$null) {
  git log --oneline '@{u}..HEAD'
} else {
  Write-Host "No upstream configured for this branch — push first: git push -u origin HEAD"
}
git diff --check
gh pr view --json number,isDraft,url,title 2>$null
```

- **Every commit must be pushed first.** Announcing a PR invites an immediate merge, and a commit pushed after that lands on a branch nobody merges. **Check for an upstream before running the ahead/behind comparison** — `@{u}..HEAD` on a branch with no upstream configured errors rather than reporting anything, so guard it as above and, where none is configured, state the next step (`git push -u origin HEAD`) rather than pushing on your own initiative; pushing still follows this repository's own authorization rule. Once an upstream exists, `@{u}..HEAD` must be empty before you announce anything.
- **Never open a PR from the default branch.** If that is where the work is, stop and say so — moving commits to a branch is the user's call.
- Stage by explicit named path. Never `git add -A`, `git add .`, or a bare directory.

**Never open a pull request as a draft.** A draft is invisible to the reviewers and CI gates that ignore drafts, which makes "opened" and "actually in review" two different states someone has to remember to reconcile. Open it ready.

**Check for a PR already open on this branch before creating one.** `/slice` and `/fix` open theirs when they finish (`.claude/commands/slice.md`, `.claude/commands/fix.md`). If `gh pr view` finds one, write the real description onto it and do not open a second. If none exists — work predating this convention, or `/pr` run standalone — open one; that write is carved out of the authorization rule (`AGENTS.md`, *Git and delivery*). Merging is not, and never becomes so here.

Same shape as an issue — human first, agent detail fenced:

```markdown
**What changed, and why.** Two or three sentences someone reviewing can follow without
reading the diff. State what was decided and why it was not the obvious alternative.

Closes #<n>

### Verified
Not yet run — the gates run next and this section is replaced with their report.

---
<details><summary><b>Agent detail</b></summary>
<!-- agent:start -->

- **Slice:** S3 — `design/30-slices.md` § S3 @ `a1b2c3d`
- **Criteria met:** S3.1, S3.2
- **Left undone:** S3.3 — <why>
<!-- agent:end -->
</details>
```

- Long-form reasoning belongs in the decision log or the plan, not the PR body. Say what changed and why; link the rest.
- **No AI attribution** — no `Co-Authored-By` naming an assistant, no "Generated with" footer.

## Phase 2 — the gates

**Run `.claude/commands/verify.md` in full**, against the branch and worktree this PR points at, then replace the description's `Verified` section with its report **verbatim** — the same three lists, not a summary. Restating it from memory is the fabricated gate result that command exists to prevent. `/verify` validates its own `.claude/verify-report.json` before rendering it (`tools/Test-VerifyReport.ps1`); a report that fails that validation is not copied into the PR — fix the artifact and re-render first.

- **Do not claim a check passed that did not run.** The did-not-run list goes into the description word for word, including the reason each entry did not run.
- **Do not fix a failing gate here.** That prohibition belongs to `/verify` and this command does not relax it by wrapping it — a failing gate ends in a decision put to the user, not a repair (`AGENTS.md`, *Working with me*).

## Phase 3 — review threads

**Check review *threads*, not requested reviewers.** An automated reviewer can leave threads that block merge and do **not** appear in `gh pr view --json reviewRequests,latestReviews`. If `required_review_thread_resolution` is on, the unresolved count *is* the merge blocker regardless of what the checks say.

**Run `.claude/commands/resolve.md` in full** — its query, its five classes, its fixed order of operations, its delegation. Fixing and resolving are delegated in this repository and need no separate ask (`AGENTS.md`, *Git and delivery*); `Ambiguous` threads still come to the user one at a time.

**This phase always runs — never leave it to a separate invocation.** Query the threads as soon as the PR is open and the `Verified` section is written. A PR opened ready starts its automated reviewers immediately, so "no threads yet" at the moment of opening means *not yet*, not *none*.

Where the query comes back empty, **give the automated reviewers one bounded wait rather than declaring the PR clean**: `pwsh -File tools/Wait-PullRequestCheck.ps1 -PullRequest <n> -HeadSha <pushed SHA>`, then re-query the threads once. Threads found on the re-query are classified and worked exactly as above.

**Then stop, whatever the result.** One wait, not a poll loop — phases 1 and 2 are minutes and a human reviewer is however long a human takes, and those are not the same wait. Report the check outcomes and the thread count, and say plainly that `/pr` (or `/resolve` on its own) picks this phase up again when later review arrives. Re-running `/pr` on a branch whose description and `Verified` section are already current is a no-op through phases 1 and 2 and lands straight here.

## Merging

**Merging is an external write and is not yours to do** unless this repository's instruction file explicitly delegates it. Where it does, follow that wording exactly — including which checks must be green first, and whether auto-merge is enabled against a specific head SHA.

Where it does not: report the check outcomes and the thread state, and stop.

**Never state a deployed URL** until the deploy for that exact merge commit reports success. A merged PR is not a deployed site.
