---
description: Discover this repository's gates, run them, and report honestly what did and did not run
---

<!-- companion:declared:start -->
**Per-repo companion:** `.claude/commands/verify-local.md`. Read it now, if it exists — an absent,
empty, or frontmatter-only file is no companion, and this file then stands alone.
It may override: `vocabulary`, `extra-steps`, `gate-commands`. It may never override anything in
[`.claude/COMPANIONS.md`](../COMPANIONS.md) § *Never*, which is also where these categories are defined.
<!-- companion:declared:end -->

Run the checks this repository actually has, and report the result without softening it.

**`/pr` runs this as its gate phase**, against the branch and worktree its pull request points at, and writes the report below into that PR's `Verified` section **verbatim** — the same three lists, not a summary, rendered from a `.claude/verify-report.json` that `tools/Test-VerifyReport.ps1` has validated (see *Report*). This file owns the procedure; `/pr` owns only where the sequence sits. Invoked on its own, it does the same discovery and the same three lists against whatever tree is checked out, and writes to no pull request.

**The point of this command is the second half of its report — what did *not* run.** Silence is not success, and a gate that could not run is the most likely place a false "everything passes" comes from.

## Discover, do not assume

**A gate declares itself; this command does not go hunting for one.** A CI step that gates
this repository carries `# verification: true` as a plain YAML comment on the line
immediately above its `- name:` line, inside `.github/workflows/*.yml`. That is the flag —
not a prose reading of what a workflow "does", not a guess from file layout. Scan every
workflow file for that comment; each step it precedes is a discovered gate, named by the
step's own `name:`. **A step without the flag is not a gate this command owns**, even if it
happens to run something useful — do not add it to the report on your own judgement, and
do not drop the flag from a step that is still meant to gate the repository.

**Which steps carry the flag.** Flag a step when its failure means the *repository* is
broken, and its `run:` block translates to a local invocation. In practice that is the
typechecks, linters, test suites, parse checks, packaging assertions and smoke probes —
the steps that return a verdict on the tree. It is **not** checkout, toolchain setup,
dependency installation, credential preconditions, container start/stop, image save/load,
publishing or deployment steps, or `uses:`-only steps that run no command of their own.
Those can fail, and CI goes red when they do, but they fail as plumbing rather than as a
judgement on the code, and a report listing them describes the runner instead of the
repository. When a step both prepares and asserts, flag it only if the assertion is the
point of the step.


**Check the cache first.** `tools/Test-GatesCache.ps1 -RepoRoot <repo>` hashes the files
this discovery reads (every workflow's full content — so a flag added, moved, or removed
invalidates it same as any other step edit — plus `package.json`'s content and whether the
known build-script paths exist) and compares it to `.claude/gates.json`. `Fresh` means none
of those inputs have changed since the last discovery — skip straight to **Run** with the
gates it returns. `Stale` or `Missing` means discover as below, then call
`tools/Test-GatesCache.ps1 -Write -GatesJson '<the gates you found, as [{"name","command"}]>'`
before running them, so the next `/verify` on this tree does not re-derive the same answer.
The cache only remembers gates; it never decides what they are — that judgement stays here.

For each flagged step, read its `run:` block and translate it to the equivalent local
invocation — that translation is still genuine judgement, the flag only says *that* a step
is a gate, not *how* to reproduce it outside CI. This repository's current flagged steps and
their local equivalents:

| Flagged step (`.github/workflows/verify.yml`) | Run locally |
|---|---|
| `Parse-check PowerShell scripts` | Parse every `*.ps1` with `[System.Management.Automation.Language.Parser]::ParseFile`, as the step does |
| `Run Pester tests` | `Invoke-Pester -Path tools -Output Detailed -PassThru` |
| `Validate the core/companion split` | `./tools/Test-Companion.ps1` |
| `Check the design state against the tree` | `./tools/Test-DesignState.ps1` |

A repository can gain, lose, or rename flagged steps over time — re-derive this table from
the workflow files rather than trusting a memorized list; the four rows above describe this
repository's steps as of this writing, not a fixed schema.

**Two of those steps exit 2 as well as 0 and 1, and 2 is not a failure — it is the third
list.** `Test-Companion.ps1` and `Test-DesignState.ps1` both distinguish *ran and found
something* from *could not run at all*, and the exit code is how they say which: 0 is `Passed`,
1 is `Failed`, and **2 is `DidNotRun`, with the script's own could-not-evaluate reasons as the
`reason`**. Folding 2 into `Failed` loses the distinction the three lists exist for; folding it
into `Passed` is the substitution this whole command exists to prevent. Either way CI is red —
the workflow fails the step on 1 and 2 alike — and that is a separate question from which list
the gate belongs in here.

Then look for anything else the repository ships that is not CI-gated. These are optional —
worth running and worth naming if run, but their absence from CI means they never enter the
"did not run because it did not run" failure mode the flag exists to close:

```powershell
if (Test-Path package.json) { Get-Content package.json | Select-String '"scripts"' -Context 0,20 }
Get-ChildItem . -Include *.sln, *.csproj -Recurse -Depth 2
if (Test-Path build) { Get-ChildItem build -Filter *.ps1 }
Test-Path docs.ps1
```

Common shapes, none of them assumed:

| Found | Run |
|---|---|
| `package.json` scripts | `npm run check`, or `typecheck` / `lint` / `test` individually if there is no aggregate |
| `*.sln` or `*.csproj` | `dotnet build`, `dotnet test` |
| `build/Test-Documentation.ps1` | run it |
| `build/Test-DocumentationArtifact.ps1` | run it, after a production docs build |
| `docs.ps1` | `./docs.ps1 -BuildOnly` — **needs Docker** |
| any repository | `git diff --check`, `git status --short --branch` |

## Report

**Write the result as a structured artifact first, never the prose directly.** Same pattern as `Test-DesignDrift.ps1` (`AGENTS.md`, "structured artifact plus deterministic validator"): this command writes `.claude/verify-report.json` — one entry per discovered gate, `{"name", "status", "detail"|"reason"}` with `status` one of `Passed` / `Failed` / `DidNotRun` — and never edits a PR body or any other visible surface directly. Then run `tools/Test-VerifyReport.ps1` against it. `Valid` (exit 0) means every gate has exactly one outcome, every `Failed` gate carries real detail, and every `DidNotRun` gate carries a reason — render the three lists below from the artifact and proceed. `Invalid` or `NotEvaluated` (exit 1 or 2) means the report itself is malformed — fix the artifact, not the prose, and do not render or hand off a report that failed validation.

Three lists, rendered from the validated artifact. All three are required, and the second is the one that matters.

```
Ran and passed:   <gate> — <what it covered>
Ran and failed:   <gate> — <the actual output, not a summary>
Did not run:      <gate> — <why: tool missing, Docker down, no such script>
```

- **Every `# verification: true` step goes in exactly one of the three lists.** That is the
  point of discovering gates by flag instead of by looking: a flagged step cannot be
  silently absent from the report the way a gate nobody thought to search for could be.
  Cross-check the list you are about to write against the flags you found before finishing.
- **A gate that reported *could not evaluate* is named in the third list, never the first.**
  `Test-DesignState.ps1` exiting 2 means the design state was not read — an absent state set,
  an unparseable record, a projector that would not run, an unauthenticated `gh`. Its
  `reason` is the script's own could-not-evaluate output, quoted, not a paraphrase.
- **Quote failures.** Paste the failing output into the artifact's `detail` field. A summary of a failure is a claim about a failure — `Test-VerifyReport.ps1` rejects a `detail` too short to plausibly be pasted output.
- **Never write "all checks pass"** unless every discovered gate is in the first list. If anything is in the third list, the honest sentence names it: *"the three that ran passed; the documentation build did not run because Docker is unavailable."*
- **A gate that cannot run locally is not a gate you may report on.** Say so, and say that the corresponding CI check on the pull request is where the answer will come from.
- If CI runs a check you could not reproduce locally at all, name it explicitly rather than leaving it out.

## Then ask

**A failing gate ends in a decision, not a report** (`AGENTS.md`, *Working with me*). Do not start fixing. Present each failure with a recommendation — fix here, file an issue, or accept and explain — and what each costs.

A clean run needs no question. Say it is clean, name what ran, and stop.

## Never

- Do not fix a failure as part of this command. Verifying and repairing are different jobs, and doing both means the report describes a tree that no longer exists.
- Do not re-run a gate until it passes. If a check is flaky, that is a finding — say how many runs and what varied. **A fix that only changed the odds is not a fix.**
- Do not skip the full suite in favour of the tests you think are relevant.

## Re-run

Re-running this command itself (not an individual flaky gate, forbidden above) is expected —
`/pr` calls it fresh on every pass through its gate phase. Discovery is cache-assisted
(`tools/Test-GatesCache.ps1`, above) but the run and the report are not: every invocation
re-runs the full discovered set and reports fresh, never reusing a prior pass's pass/fail
verdict. A gate that passed last time is still run again, not assumed still green.
