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
summary: "THE METHOD-CALL ARM IS NOT ABOUT IMPORTS AT ALL and the slug misnames it (frankuser, 2026-09-11, c53cb51926a2): four lines with NO import, NO package and NO alias reproduce it -- `class gl: @staticmethod def s(): ...` then `g = gl; g.s()` raises `AttributeError: 'type' object has no attribute 's'` while `gl.s()` works. Also fails via a dict value and a function parameter, and for `@classmethod`. So a fix aimed at the unit-alias path leaves it broken everywhere else. THE PRECISE BOUNDARY: for `A = B`, instantiation `A()` and instance methods WORK -- `bug-n-a-type-name-is-not-a-first-class-value` (done) covered those -- and only STATIC/CLASS METHOD LOOKUP on a class held in a variable fails. NOT REPRODUCED: the raw-address arm (`w.V` printing 5512600 against CPython's 1). Attribute READS through a local came out correct in both shapes I built, import-free and unit-aliased, so that half needs frankZ's exact repro -- it was measured at 16f9e6314ca0, which predates 3662f8a8b. The seam-compiles-but-does-not-work correction to [[bug-n-a-module-bound-by-an-import-is-not-a-value]] STANDS and is the valuable half."
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

## MEASURED INDEPENDENTLY 2026-09-11 (frankuser), compiler `c53cb51926a2`

frankZ's finding that the seam COMPILES and does not WORK is correct and is the
valuable half — a wall walk cannot see past the wall it reports, and two
independent routes had both asserted "every static row passes" from a compile.
What follows narrows the mechanism, because the slug currently sends a fixer to
the import code.

**THE METHOD-CALL ARM NEEDS NO IMPORT.** Four lines, no package, no alias:

```python
class gl:
    @staticmethod
    def s():
        return "static"
g = gl
print(gl.s())   # static
print(g.s())    # AttributeError: 'type' object has no attribute 's'
```

Same failure for `@classmethod`, for a class stored in a dict (`d["k"].s()`), and
for one passed as a parameter (`def f(t): return t.s()`). The discriminator set
that rules the alias out — all three of these PASS:

| shape | result |
| --- | --- |
| `gl.s()` — class named by its own identifier | ok |
| `from pkg.bcls import gl` then `gl.s()` | ok |
| `import pkg.bcls` then `pkg.bcls.gl.s()` | ok |
| **`g = pkg.bcls.gl` then `g.s()`** | **AttributeError** |

So the axis is **binding the class to a variable**, not reaching it through a
unit. An import is neither necessary nor sufficient.

**THE BOUNDARY AGAINST THE DONE TICKET.** For `A = B`: `A()` instantiates
correctly, `o.m()` instance methods work, `A.V` attribute reads are correct —
`bug-n-a-type-name-is-not-a-first-class-value` delivered those. What is left is
static and class method lookup on a class object held in a variable. That is a
narrow, additive gap rather than a regression of the closed ticket, and it is
worth saying which, because "the done ticket came undone" and "the done ticket
stopped one step short" route differently.

**NOT REPRODUCED, AND THE REASON MATTERS:** the raw-address arm. `w = backend.Widget`
then `w.V` gave **1**, not an address, in both shapes I built — import-free, and via
`from . import mod as backend` with the binding in a local and at module scope. Two
differences from frankZ's run: compiler (`c53cb51926a2` vs `16f9e6314ca0`, and
`3662f8a8b` landed between) and whatever their exact shape was. **This is not a
claim that it was never real** — a silent wrong value is the most serious thing on
this ticket and it should not be dropped on my failure to hit it. It needs frankZ's
repro, or a note that `3662f8a8b` fixed it.

**AND 3662f8a8b DOES NOT MOVE THE CENSUS, because the corpus was never rewritten.**
`lekkerzeilen/platform/__init__.py` at corpus `5301e52` still reads
`from . import _pxx` with no `as`. The `as _backend` spelling that clears the wall
is a local edit, and we are allowed to change lekkerzeilen's source — but nobody
has. Measured after the fold landed: **25 of 35, with `_pxx` still walling 4
modules.** Anyone reading "the wall is cleared" should read it as "a workaround
now exists and is unapplied".
