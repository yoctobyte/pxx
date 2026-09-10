---
slug: bug-n-star-unpacking-is-rejected-at-a-method-call
track: N
type: bug
prio: 70
status: backlog
owner: ""
created: 2026-09-10
found-by: frankuser
tags: [nilpy, lekkerzeilen, unpacking]
blocked-by: []
summary: "`self.mark(*keep)` gives `*unpacking into Places.mark is not supported`. This is the SINGLE-STAR SIBLING of bug-n-double-star-unpacking-is-rejected-at-a-method-call, which is already filed for `**` at the same position -- so the double-case rule applies: whoever fixes either must grep for the other before closing, because one arm fixed alone is exactly the shape that leaves the second path broken. Blocks lekkerzeilen/ui.py, one of the 32 modules of the priority demo app."
---

# Measured 2026-09-10, compiler `b7745aaf0a59`

`lekkerzeilen/ui.py:414`:

```python
if keep is not None:
    self.mark(*keep)
```

`error: *unpacking into Places.mark is not supported`

# Why this is filed as a sibling and not as a new discovery

`bug-n-double-star-unpacking-is-rejected-at-a-method-call` records `**` being
refused at a method call. This is `*` at the same position. CLAUDE.md's rule is
explicit about this shape: *"Fixed one arm of a double case? Grep for the sibling
before closing."* Filing it separately is how the grep gets done in advance
rather than hoped for.

The right fix is probably one change covering both stars at a method call, and a
fix that lands only one should say in its resolution why.
