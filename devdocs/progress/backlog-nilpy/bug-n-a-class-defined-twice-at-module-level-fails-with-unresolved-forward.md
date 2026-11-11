---
slug: bug-n-a-class-defined-twice-at-module-level-fails-with-unresolved-forward
track: N
type: bug
prio: 35
status: backlog
owner: ""
created: 2026-11-11
found-by: claude (pxx session)
tags: [nilpy, classes, rebinding]
blocked-by: []
summary: "Two `class A:` statements in one module are a rebinding in Python: each `A()` after a statement builds THAT class. pxx refuses the program at the end with `error: unresolved forward: A.r`. Loud, so prio is moderate; found while writing a test that reused class names."
---

# A class defined twice at module level fails with `unresolved forward`

```python
class A:
    def r(self):
        return 1
print(A().r())
class A:
    def r(self):
        return 2
print(A().r())
```

CPython prints `1` then `2`. pxx (2026-11-11, master after ba3b84f1a2) stops at
compile time: `pascal26:9: error: unresolved forward: A.r`.

The same shape for a `def` was fixed by giving each def statement its own Proc
plus a positional binding rule (PyDefPosBeats / ProcPyDefTok). A class has no
such per-statement identity, so the second body's methods appear to land on
the first class's method shells and one shell is left without a body.

Not seen in the corpus. Found when a test file reused `Below`/`Above` across
two sections, so the cost so far is a confusing error on legal code.
