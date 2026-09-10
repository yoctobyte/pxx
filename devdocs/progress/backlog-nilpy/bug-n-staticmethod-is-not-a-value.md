---
slug: bug-n-staticmethod-is-not-a-value
track: N
type: bug
prio: 80
status: backlog
owner: ""
created: 2026-09-10
found-by: frankuser
tags: [nilpy, lekkerzeilen, values, builtins]
blocked-by: []
summary: "`clear = staticmethod(_unimplemented)` in a class body gives `undefined variable (staticmethod)`. It blocks BOTH modules of lekkerzeilen's portability seam (platform/__init__.py and platform/_pxx.py) and cascades to a third (bindings.py fails on `no member KEY_ESCAPE came of the qualifier platform` only because platform/__init__.py never compiled -- KEY_ESCAPE is defined there at line 35, so that row is NOT a separate resolver bug). Same family as bug-n-os-environ-and-os-sep-are-not-values and bug-n-a-stdlib-function-referenced-without-calling-it-is-not-a-value: a name reachable one way and not as a value. `staticmethod` is a BUILTIN rather than a stdlib member, so it is a third door on one concept, which normalise-dont-special-case names as the shape where the extra path is the one that stays broken."
---

# Measured 2026-09-10, compiler `b7745aaf0a59`, tree `3bebb551e`

```
lekkerzeilen/platform/__init__.py:31   undefined variable (staticmethod)
lekkerzeilen/platform/_pxx.py:31       undefined variable (staticmethod)
```

The idiom, from `_pxx.py` — a class used as a namespace whose members are
plain functions:

```python
class gl:
    clear_color = staticmethod(_unimplemented)
    clear       = staticmethod(_unimplemented)
```

# Why it is worth 80 rather than its module count

Two modules directly, three with the cascade — but they are **the portability
seam of the priority demo app**. Nothing above `platform/` can run until that
package compiles, so this is not 3-of-32, it is a gate on the whole program.

# The cascade, recorded so nobody files the symptom

`bindings.py` answering `no member KEY_ESCAPE came of the qualifier platform` is
**downstream of this ticket and not a bug of its own.** `KEY_ESCAPE = 27` is
defined in `platform/__init__.py:35`; the qualifier resolves to nothing because
that module failed to compile at line 31. A seat that files the `KEY_ESCAPE` row
separately is filing this ticket twice.

# Relationship to its two siblings — one concept, three doors

- `bug-n-os-environ-and-os-sep-are-not-values` — stdlib DATA attribute.
- `bug-n-a-stdlib-function-referenced-without-calling-it-is-not-a-value` —
  stdlib FUNCTION, uncalled.
- this one — a BUILTIN, uncalled.

Whoever takes one should read all three before choosing where to fix. Three
mechanisms serving one concept is what `root-cause-over-microfix.md` calls a
design flaw rather than three bugs.
