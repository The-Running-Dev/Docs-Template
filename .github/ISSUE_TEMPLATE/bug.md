---
name: Bug
about: Something behaves differently from what the contract, the docs, or a test says
title: ''
labels: bug
---

**Symptom** — one sentence someone else would recognise, told as what happened, not as a diagnosis: what you were doing, what you expected, what happened instead.

Observed on <branch, version, or environment>.

### Reproduce

1.
2.

### Done when

- [ ] A regression test fails without the fix and passes with it

---
<details><summary><b>Agent instructions</b></summary>
<!-- agent:start -->

**This issue is the specification.** A bug has no upstream design document, so unlike a
slice this block is the home rather than a pointer — it carries the constraints instead
of naming where they live.

- **Authority:** the failing test. If no test can express the symptom, say so *before* writing a fix — an unreproducible bug is a diagnosis task, not an implementation one.
- **Out of scope:** adjacent defects noticed while fixing this one. File them separately; do not widen the change.
- **Stop if:** the fix needs a contract, schema, or public-interface change. That is an amendment, not a bug fix.
- **Verify by reverting the fix** and confirming the test fails. A test that passes with and without the fix guards nothing.
- **Beware a fix that only changes the odds.** If the symptom was intermittent and is now "not reproducing", say over how many runs and what the cause was — a race hidden is not a race fixed.
<!-- agent:end -->
</details>
