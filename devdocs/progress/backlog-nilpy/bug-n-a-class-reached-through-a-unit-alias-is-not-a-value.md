---
slug: bug-n-a-class-reached-through-a-unit-alias-is-not-a-value
track: N
type: bug
prio: 80
status: backlog
owner: ""
created: 2026-09-11
found: 2026-09-11
found-by: frankZ
tags: [nilpy, imports, values, silent-wrong-value, lekkerzeilen]
blocked-by: []
summary: "`from . import mod as backend` then `backend.SomeClass` COMPILES and is silently WRONG. Bound to a LOCAL it yields a raw address -- `w = backend.Widget` then `w.V` printed 5512600 against CPython's 1. Bound at MODULE scope it reads a constant correctly (42) and then raises `AttributeError: 'type' object has no attribute 'clear'` on a METHOD call CPython answers. No diagnostic in either case. THIS IS THE SEAM'S OWN SHAPE: lekkerzeilen/platform/__init__.py does `gl = _backend.gl` and every caller calls METHODS on `gl`, so the whole OpenGL facade is on the failing arm. AND IT CORRECTS A CLAIM ON [[bug-n-a-module-bound-by-an-import-is-not-a-value]]: that ticket's `every static row in the seam already passes` was measured by COMPILING and is a compile-only claim -- `gl = _backend.gl` compiles, and calling through it does not work. Found while checking whether a diagnostic's suggested workaround was true; it was not."
---

# The measurement

Compiler `16f9e6314ca0`, both rows against CPython in the same run.

```python
# pkg/two.py
class gl:
    VERSION = 42
    @staticmethod
    def clear():
        return "cleared"

# pkg/__init__.py
from . import two as backend
gl = backend.gl
def use_const(): return gl.VERSION
def use_call():  return gl.clear()
```

| row | pxx | CPython |
| --- | --- | --- |
| `gl.VERSION` | 42 | 42 |
| `gl.clear()` | `Unhandled exception: AttributeError: 'type' object has no attribute 'clear'` | `cleared` |

And the LOCAL binding is worse, because it does not raise:

```python
def direct():
    w = backend.Widget      # class Widget: V = 1
    return w.V
```

`direct 5512600` against CPython's `1` — **a raw address, no diagnostic**. Same
family as `math.pi` taken as a value printing an address
([[bug-n-a-stdlib-function-referenced-without-calling-it-is-not-a-value]]).

# Why it is ranked at 80 and not lower

It is on the demo's critical path and it is SILENT. `platform/__init__.py`
publishes the graphics facade with exactly this construct:

```python
gl = _backend.gl
open_window = _backend.open_window
```

and four other modules import `gl` from it and call methods on it. So the arm
that works (a constant read) is the one nobody uses and the arm that does not
is the entire OpenGL surface.

# How it was found, and the method is the transferable part

**By checking whether a diagnostic's suggested workaround was TRUE.** A new
error message for the `getattr`-over-a-unit-alias fold said *"write
`backend.Widget` directly"*. That advice was plausible, was written from the
knowledge that the construct COMPILES, and is wrong. Running it printed a raw
address.

**A diagnostic that recommends a silent wrong value is worse than one that
recommends nothing** — it converts a refusal the reader can see into a number
they cannot. The workaround was removed from the message before it shipped; what
the message says now is only what was verified, that a class reached through a
module alias is not a value here.

# The claim this corrects, and it is on a live ticket

[[bug-n-a-module-bound-by-an-import-is-not-a-value]] records, twice and from two
independent routes, that under the `from . import X as _backend` spelling
**"every static row in the seam already passes"** — `gl = _backend.gl`,
`open_window`, `_backend.probe()`. Both routes measured COMPILATION. Neither ran
the result. `gl = _backend.gl` does compile; calling through it does not work.

Nothing about those two derivations was careless — the question they were asked
was where the compile WALL goes, and a wall walk cannot see past the wall it is
reporting. But the sentence as written reads as a claim about the seam WORKING,
and the next reader would act on it. **A compile is not a run, and a fixture
that only compiles is the same animal as an assertion that cannot fail.**
