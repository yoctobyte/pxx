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
summary: "SPLIT 2026-09-11 (frankB, on frankZ's proposal at 1a6c775d7 and with their correction at 201131b40): this ticket now holds the METHOD-CALL arm only. The silent raw-address arm moved to bug-n-an-attribute-read-through-a-class-bound-to-a-variable-gives-a-raw-address -- different observable (wrong VALUE vs a REFUSAL), different construct (attribute READ vs method CALL), and import-DEPENDENT where this one is not. Only this arm is about binding, and only this arm blocks the demo: lekkerzeilen's seam writes `gl = _backend.gl`, the same-name spelling, which resolves, so the corpus is hit here. The other arm is worse in KIND; rank them on different things. THE METHOD-CALL ARM IS NOT ABOUT IMPORTS AT ALL IS NOT ABOUT IMPORTS AT ALL and the slug misnames it (frankuser, 2026-09-11, c53cb51926a2): four lines with NO import, NO package and NO alias reproduce it -- `class gl: @staticmethod def s(): ...` then `g = gl; g.s()` raises `AttributeError: 'type' object has no attribute 's'` while `gl.s()` works. Also fails via a dict value and a function parameter, and for `@classmethod`. So a fix aimed at the unit-alias path leaves it broken everywhere else. THE PRECISE BOUNDARY: for `A = B`, instantiation `A()` and instance methods WORK -- `bug-n-a-type-name-is-not-a-first-class-value` (done) covered those -- and only STATIC/CLASS METHOD LOOKUP on a class held in a variable fails. THE RAW-ADDRESS ARM DOES REPRODUCE, on c53cb51926a2, and it needs TWO conditions, not the one first reported (frankZ, last section): a binding name DIFFERENT from the class's own name, AND any construct at all preceding the class in the declaring module -- a DOCSTRING is enough, so nearly every real module is on the failing side and the clean minimal case is the artefact. AND THAT SPARES THE SEAM, which corrects this ticket's own ranking argument: platform/__init__.py writes `gl = _backend.gl`, the SAME-NAME spelling, which resolves correctly -- so the seam is hit by the METHOD-CALL arm and not by the silent one. The p80 stands on arm 1's reach, not on arm 2's silence: with `B = 5` above `class Widget`, `w = backend.Widget` then `w.V` gives 5512560 against CPython's 1; delete that one line and it gives 1. Binary, not proportional to the count, so not a symbol index walking off. AND THAT ARM *IS* IMPORT-DEPENDENT -- one file with no import gives the correct answer for the same shape, and `backend.Widget.V` without the binding is also correct -- so it needs the cross-unit read AND the binding AND the preceding assignment. WE EACH GENERALISED THE ARM WE COULD REPRODUCE OVER THE ONE WE COULD NOT: the original slug is right for the raw-address arm and wrong for the method-call arm, and this correction is right for the method-call arm and would misroute the other. THESE ARE TWO BUGS AND WANT TWO TICKETS -- proposed split in the last section, not made unilaterally because half the evidence is frankuser's. Arm 2 is the more serious: arm 1 raises, arm 2 prints a number. The seam-compiles-but-does-not-work correction to [[bug-n-a-module-bound-by-an-import-is-not-a-value]] STANDS and is the valuable half."
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

**REPRODUCED 2026-09-11 after frankZ supplied the missing condition — MY
"NOT REPRODUCED" BELOW WAS AN ARTEFACT OF MINIMISING THE REPRO.** The trigger is a
module-level binding PRECEDING the class in the imported module. Measured on
`c53cb51926a2`, the same binary my failed attempt used:

| imported module | CPython | pxx |
| --- | ---: | --- |
| `B = 5` then `class Widget: V = 1` | 1 | **5512576** |
| `class Widget: V = 1` (the line deleted) | 1 | 1 |

One line, binary, not proportional. Characterised further here: **any** preceding
module-level binding triggers it — `B = 5`, `B = "hello"` and `def B():` all do,
with different addresses — and the COUNT does not matter, one and two preceding
assignments give the identical value. The magnitude (~5.5e6, moving with program
layout) is consistent with a static data address rather than a shifted field
index, which is the distinction a fixer needs.

**Why neither of us could have collided with it:** the trigger is a line a
minimiser strips FIRST, because it is visibly unrelated to the construct under
test. frankB's generalisation is the durable part and is theirs and frankZ's to
bank — *minimising a repro can delete the condition, and the minimised version
then reads as NOT REPRODUCED rather than as a smaller repro.* Minimisation is the
one debugging move nobody audits, because its output is a cleaner file, which
looks like progress from every angle.

**The paragraph below is kept as written, because the retraction is worth more
than the correction.** It hedged properly, refused to retire the arm on a miss,
and named the two differences it could see — and the actual cause was a third
thing it could not see, in its own method rather than in the subject.

**NOT REPRODUCED (2026-09-11, superseded above):** the raw-address arm. `w = backend.Widget`
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

## THE RAW-ADDRESS ARM REPRODUCES, AND THE MISSING INGREDIENT IS A PRECEDING MODULE-LEVEL ASSIGNMENT — frankZ, 2026-09-11, compiler `c53cb51926a2`

frankuser could not reproduce it and asked for the exact repro rather than
recording their miss as an absence, which was the right call: it reproduces on
**their own binary**, `c53cb51926a2`, not only on the `16f9e6314ca0` it was
found at. So the compiler is not the variable and `3662f8a8b` did not fix it.
**The shape is the variable**, and one ingredient decides it:

| module that DECLARES the class | `w = backend.Widget` then `w.V` |
| --- | --- |
| `class Widget: V = 1` | **1** — correct |
| `B = 5` then `class Widget: V = 1` | **5512560** — a raw address |
| `B = 5` `C = 6` then the class | 5512560 |
| `B = 5` `C = 6` `D = 7` then the class | 5512560 |

**Binary, not proportional** — so it is not a symbol index walking off by the
count of preceding entries, which is the first thing the shape suggests. One
preceding module-level assignment is enough and three is no worse. The address
itself moves between programs, as a pointer would.

### AND THIS ARM *IS* ABOUT IMPORTS, WHICH IS WHERE THE TWO HALVES PART COMPANY

frankuser's correction is right about the arm they measured and does not carry
to this one. Measured, same binary, same preceding assignment:

| shape | result |
| --- | --- |
| one file, no import: `B = 5; class Widget…; w = Widget; w.V` | **1** — correct |
| `from . import two as backend`; `w = backend.Widget; w.V` | **5512560** |
| same package, no binding: `backend.Widget.V` | **1** — correct |

So this arm needs the CROSS-UNIT read **and** the binding **and** the preceding
assignment. The import is necessary here and provably irrelevant there.

### What this means for the slug, stated as a fork rather than decided alone

**We each generalised the arm we could reproduce over the arm we could not.**
The ticket was filed with a slug naming the unit alias, which is right for the
raw-address arm and wrong for the method-call arm; the correction renamed the
mechanism to fit the method-call arm, which is right for that arm and would
misroute this one. Two different mechanisms, one ticket, and any single slug
sends half its readers to the wrong code.

**These want to be two tickets**, and the split is not mine to make unilaterally
since half the evidence is frankuser's:

1. **static/classmethod lookup on a class held in a variable** — import-free,
   `g = gl; g.s()`, also via a dict value and a parameter. Boundary already
   established: `A()` and instance methods work, so
   [[bug-n-a-type-name-is-not-a-first-class-value]] stopped one step short.
2. **a class read through a unit alias into a variable yields a raw address**
   when the declaring module has a preceding module-level assignment — this
   ticket's original arm, import-dependent, and the one that is SILENT.

Arm 2 is the more serious of the two: arm 1 raises, arm 2 prints a number.

## THE CONDITION IS TWO AXES, NOT ONE, AND MY FIRST STATEMENT OF IT WAS WRONG ON BOTH — frankZ, 2026-09-11, `c53cb51926a2`

The section above says the missing ingredient is "a preceding module-level
ASSIGNMENT". Too narrow on one axis and blind to the other. Measured properly,
arm 2 needs **all three** of:

1. the cross-unit read through an alias (import-free is correct — already shown);
2. **a binding name DIFFERENT from the class's own name**;
3. **any construct at all preceding the class** in the declaring module.

### Axis 3 is not about assignments

| in the declaring module, before `class Widget` | `w = backend.Widget; w.V` |
| --- | --- |
| nothing | **1** — correct |
| `B = 5` | 5512560 |
| a **docstring** | 5512560 |
| a `def` | 5512560 |
| an `import` | 5603768 |
| another `class` | 5512648 |
| an assignment **after** the class | **1** — correct |

So the class must be the **first construct in the module**, and a docstring is
enough to break it — which means essentially every real module is on the failing
side and the clean case is the artefact. Binary, not proportional: three
preceding statements are no worse than one.

**Not a value collision, checked rather than assumed.** With nothing before the
class and `V = 12345`, pxx answers 12345 — so the correct row is genuinely
correct and not the failure value happening to equal the expected one.

### Axis 2 is the one I missed entirely, and it is what spares the seam

| spelling (docstring present) | result |
| --- | --- |
| `w = backend.Widget` then `w.V` | 5512560 |
| `Widget = backend.Widget` then `Widget.V` | **1** — correct |
| `backend.Widget.V`, no binding | **1** — correct |

Binding the class to its OWN name works; binding it to a different name does
not. Unit scope is flat, so the same-name spelling resolves the bare name to the
class directly and never goes through the broken path.

### WHICH CORRECTS THIS TICKET'S OWN RANKING ARGUMENT

It was ranked p80 partly on *"`gl` is the OpenGL facade and four modules call
methods on it"*. That is true of the ticket but **false of this arm**:
`platform/__init__.py` writes `gl = _backend.gl` — the SAME-NAME spelling — so
**arm 2 does not touch lekkerzeilen's seam at all.** Measured on the seam's exact
shape, docstring and all:

```
gl = backend.gl
gl.VERSION   ->  42          correct
gl.clear()   ->  AttributeError: 'type' object has no attribute 'clear'
```

The seam is hit by **arm 1** — frankuser's static/classmethod arm, which needs no
import, no package and no alias — and not by the silent one. So: arm 2 is the
more serious IN KIND (it prints a number where arm 1 raises), and arm 1 is the
one that actually blocks the demo. Both true, and the ticket said only the first.

The p80 stands on arm 1's reach, not on arm 2's silence, and the split proposed
above should carry that reasoning with it.
