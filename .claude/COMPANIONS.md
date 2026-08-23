# Command cores and their per-repo companions

Every file in `.claude/commands/` ships as a **core**: a cross-repo file that a consuming
repository never edits. Where a repository genuinely needs a command to behave differently, it
writes a **companion** beside it — `.claude/commands/<name>-local.md` — and the core names
exactly what that companion is allowed to change.

This file is the mechanism. It is kit-owned and installed into every target, and it is the
single home for the category vocabulary, the never-list, and the absence rule. A core command
file names *which categories* apply to it; it does not restate any of what is below.

## The block is a declared region

A core's fenced companion block is a **declared** marked region, id `companion` — `AGENTS.md`
(*Marked regions*) owns what declared means and what the marker looks like, and neither is
restated here. In short: hand-authored, never written by a generator, checked for presence and
well-formedness the same as any other marked region.

## Why the split exists

`/install`, `INSTALL.md` and `/kit-sync` used to spend real effort reconciling a target's local
edits to installed command files on every install and every sync. Measured across eighteen
installed targets, that produced thirteen genuinely divergent command files in one repository —
each one a mixture of repository vocabulary, a different document map, and real per-command
specialization, none of which the kit wanted to overwrite and none of which the kit could
safely take.

A core the kit owns outright removes the reconciliation structurally rather than solving it
again on every pass. The specialization does not disappear; it moves somewhere the kit knows
not to touch.

## The three rules

1. **The core enumerates the categories its companion may override.** Anything not enumerated
   is not overridable, whether or not it appears in the never-list below.
2. **The core states what a companion may never change.** That statement is this file's
   *Never* section, referenced — never copied into a command.
3. **The core references its companion by path and does not inline its body.** An agent
   executing the command reads the companion at that path, at that moment. A core that
   quoted its companion's content would be a copy that rots.

## Categories

A companion is a Markdown file whose `##` headings are category ids from this table. Content
under a heading is that category's override. A heading that is not an id below is a defect —
`tools/Test-Companion.ps1` rejects it.

| Id | What it may override | Example |
|---|---|---|
| `vocabulary` | What this repository calls the things the command manipulates — the instruction file's name, the id scheme for units of work, the word for a unit of work | `AGENTS.md` is named `CLAUDE.md` here; slices are `units` and their ids are `W<n>`, not `S<n>` |
| `document-map` | Where a document the command reads or writes actually lives, and how to read it | The canonical design docs are compound files with marked blocks; generated pages under `docs/` are evidence only and never the side a drift resolves toward |
| `extra-steps` | Repository-specific steps to run **in addition to** the core's, and where in the core's sequence they belong | Regenerate the docs site after a design edit; run the codegen pass before the gates |
| `gate-commands` | The concrete commands a gate runs, where the core discovers rather than hardcodes them | `just verify` rather than the discovered `dotnet test` |
| `tightened-authorization` | A narrowing of what the command may do without asking | This repository resolves no review thread without a per-thread ask, overriding the batch |

Two properties of the table are load-bearing:

- **`tightened-authorization` tightens only.** A companion may require an ask the core does not.
  It may never remove one. A companion that widens an authorization is a defect, not a policy —
  the validator cannot detect intent, so this is the reviewer's check, and it is the reason the
  category is named for its direction rather than for its subject.
- **There is no `behaviour` category, and adding one is a decision, not an edit.** The five
  above are deliberately narrow. A repository that needs a command to *do something else* needs
  a different command, or an amendment to the core — not a companion.

## Never

No companion may change any of the following, in any command, under any category:

- **A stop condition or a refusal.** Where a core stops and asks, the companion cannot make it
  proceed. This is the whole reason the split is safe.
- **The shape of a report the command produces.** A report whose shape varies per repository is
  a report nothing can be checked against.
- **Which other commands it invokes, defers to, or refuses to run.** Command routing is the
  kit's, and a companion that redirected it would make the pipeline mean something different in
  each repository without saying so anywhere the kit can see.
- **Any rule in the repository's own instruction file.** That file already outranks a command
  by its own terms; a companion is not a second route to amending it.
- **Any widening of an authorization boundary** — see `tightened-authorization` above.
- **This mechanism.** A companion cannot declare new categories, exempt itself from the
  never-list, or point at a different companion.

A companion that attempts any of these is not an override the kit failed to allow for; it is a
signal that the core is wrong for this repository, and that belongs in the kit as an issue.

## Absence

**A companion that is missing, empty, or frontmatter-only is absent, not an override.** All
three are the same case and the command proceeds on its core alone, silently — an absent
companion is the normal state, not something to report.

- **Missing** — no file at `.claude/commands/<name>-local.md`.
- **Empty** — zero bytes, or nothing but whitespace.
- **Frontmatter-only** — nothing outside the leading `---`-fenced block except whitespace. This
  case exists because a stub written to reserve the path, or one whose content was deleted
  without deleting the file, must not read as an override of nothing.

A companion with headings but no content under them is **not** absent — an empty category is an
override that says "this category is deliberately blank here", which is a different claim from
having no companion. `tools/Test-Companion.ps1` reports it rather than silently accepting it.

## What this means for installing and syncing

Because the core is kit-owned outright, it needs no reconciliation:

- **The target's core file matches what it was last given** — take the kit's current version
  outright. No classification, no proposal, no fork. This is the steady state and it is what
  sixteen of eighteen measured targets already look like.
- **The target's core file was edited locally, and no companion exists for it** — the edit has
  not been migrated. It is reported as `Unmigrated-Blocked` and left alone. Moving it into a
  companion is the fix; overwriting it is not, because that edit is the accumulated knowledge
  the kit does not have. This is a one-time migration state, not an ongoing reconciliation.
- **A companion exists** — the companion is the target's, always, and no automated path reads,
  merges, rewrites or deletes it. The core beside it is still taken outright.

`tools/Sync-Kit.ps1` implements exactly this. `INSTALL.md` phase 1 folds its report into the
classification, and `/install-all` and `/kit-sync` inherit it unchanged.
