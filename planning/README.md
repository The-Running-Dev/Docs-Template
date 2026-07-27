# Planning

Working documents for this repository's open problems. Nothing here is
published; the branch exists so plans can be reviewed and versioned before any
fix lands.

## Convention

Two kinds of file live here, and the split is deliberate:

- **Audit indexes** (`template-todos.md`) — many findings, one file. Each
  entry is file-ready: evidence, root cause, a worked fix, acceptance
  criteria. Entries stay here while they are backlog.
- **Topic files** (`consumer-root-404.md`) — one finding, one file, named for
  the problem rather than the batch it arrived in. An entry graduates from an
  index to its own topic file (or a GitHub issue) the moment it accrues active
  work — decisions, new evidence, downstream workarounds. The index entry then
  shrinks to a link.

This mirrors how the repository already treats records elsewhere:
`TODO-Next.md` points at other documents instead of duplicating them.

## Current contents

| File | Kind | What it covers |
| --- | --- | --- |
| `template-todos.md` | Audit index | 2026-07-27 inspection: 4 bugs, 5 issues |
| `consumer-root-404.md` | Topic file | Consumer builds emit no root page after the `src/pages` leakage fix |
