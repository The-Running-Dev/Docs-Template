# Decision log

Append-only. Newest at the top. The rejected alternatives are the point — without them, every future session relitigates the same choice.

### 2026-08-23 — Scoped kit install: gates and tracking only, no design-doc chain
Context: Installing SubZeroDev.AgentKit's `/verify`, `/pr`, `/resolve`, `/done`, `/track`, and `/install` for this repository's existing CI/PR/branch-hygiene workflow, without adopting the kit's `/design` → `/contract` → `/slices` planning chain. This repository already has its own mature `AGENTS.md`, its own CI (`ci.yml`, `test-and-coverage.yml`), and its own issue/PR conventions predating the kit.
Chosen: Install only `.claude/commands/{verify,pr,resolve,done,track,install}.md`, `.claude/COMPANIONS.md`, the tool scripts those six commands depend on, `.github/ISSUE_TEMPLATE/{bug,story}.md`, and this decision log (seeded with only its heading and `## Open`, no `00-brief.md`/`10-design.md`/`20-contract.md`/`30-slices.md`). `/track`'s slice-sync section (`design/30-slices.md`) has nothing to read and is a permanent no-op here by design; its `## Open` → issue sync is the part that is live. AGENTS.md gained a new appended section holding only the kit subsections these six commands reference by name, rather than the kit's full contract.
Rejected: (1) Full kit install including the design-doc chain — rejected because this repository's planning already happens outside `design/` (its own `TODO*.md`/`PRD.md`/`DOCS-BUILD-PLAN.md` files) and importing a second, unused planning surface would be exactly the duplication the kit's own contract forbids. (2) Skipping `design/` entirely, including `90-decisions.md` — rejected because `/track`'s `## Open` → issue sync is genuinely useful here and needs a home for it; a bare "no design/ at all" would make `/track` install with zero real function. (3) `/kit-sync`/`/install-all`'s standard reconciliation, which assumes a from-scratch full install — not run here since this is a deliberate partial install; a future `/install` re-run should treat the missing `00-brief.md`/`10-design.md`/`20-contract.md`/`30-slices.md` as intentionally absent per this entry, not as a gap to fill silently.
Reversibility: cheap — re-running `/install` and answering "yes, add the design chain" at that point is a normal upgrade, not an undo.

## Open
<A staging area, not a home. Things noticed mid-slice that were deliberately not acted on. `/track` turns each into a GitHub issue and removes it from here. An item that is a *decision* rather than a *todo* belongs below as an entry, not in an issue.>

---
