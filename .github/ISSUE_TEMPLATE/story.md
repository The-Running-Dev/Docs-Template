---
name: Story
about: A change worth doing that is not a bug, and not a slice of an existing design
title: ''
labels: enhancement
---

**What changes, and for whom.** Two or three sentences. What can someone do afterwards that they cannot do now?

**Why now.** What makes this worth doing ahead of the other things.

### Done when

- [ ] <observable, checkable without judgement>

---
<details><summary><b>Agent instructions</b></summary>
<!-- agent:start -->

**This issue is the specification, for now.** A story has no upstream design document, so
unlike a slice this block is the home rather than a pointer — until the story grows into a
design cycle, at which point `design/` takes over and this issue stops governing.

- **Authority:** this issue, and only until it needs more. If it turns out to need a contract, a schema, or a public interface, **it is not a story** — stop and run `/brief-check`, and let it become a brief.
- **Stop if:** it needs more than one slice. Say so rather than growing the change inside one issue.
- **Check `design/` first.** If the design docs already govern the area this touches, they outrank this issue — work from them, not from here.
- **Do not** start implementation if there is no `Done when` a reader could check without judgement. Ask for one instead.
<!-- agent:end -->
</details>
