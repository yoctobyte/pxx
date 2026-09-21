---
slug: bug-n-a-run-time-dispatched-call-s-result-is-coerced-to-an-integer
title: a run-time dispatched call's result is coerced to an integer
summary: >
  RESOLVED 2026-09-21 — FIXED, AND NOT BY THIS TICKET'S WORK. Verified at
  5d8a0a60b and under pin v415's binary, so the fix is carried by the pin and is
  not inert. All five rows of the table below now match CPython, and the route
  was proven live rather than assumed: `--dce-why=pydyn_meth2` reports
  `pydyn_meth2 <- Sampler.t <- [vmt/rtti slot]`, and the "no class declares
  .m_dflt()" warning still fires, so the probe reaches the subject by the route
  under test. Extended past the filed table while the repro was in hand — list,
  dict, tuple, None and bool results are correct too, at arity 0 through 3. This
  repro is the one that still works; the near-identical one in
  bug-n-a-dynamically-dispatched-call-loses-its-return-kind-when-it-is-returned
  does NOT (its calls now resolve statically), and the two were closed together
  as one cause seen through different values. Closed with a regression guard,
  which is what was actually missing, in
  test_nilpy_a_call_through_a_variant_receiver_dispatches_on_the_real_class.npy,
  including the float and str rows this ticket's Gate required and a POSITIVE
  ROUTE ASSERTION. ORIGINAL REPORT BELOW, unedited.
  A method call dispatched on the receiver at run time (the open-world path,
  pydyn_meth<n>) returns a Variant, and the value is then read as an INTEGER.
  A float return truncates -- `return outside` with outside=77.5 answers 77 --
  and a STRING return raises `TypeError: expected a number, got str` naming a
  type the source never asks to convert. An int return is correct, which is
  what makes this look like it works. The call node is correctly tagged
  tyVariant by PyMakeDynMethCall, so the narrowing is downstream of it.
track: N
type: bug
prio: 84
owner: frankb-8e
status: done
---

## How it was reached

Uncovered by fixing
`bug-n-a-dynamically-dispatched-call-fills-its-defaults-from-another-class-signature`.

**IT WAS NOT REACHABLE BEFORE, AND THAT IS THE WHOLE REASON IT IS ONLY BEING
FILED NOW.** On the pre-fix compiler every row of the table below fails
IDENTICALLY and EARLIER, with `m_dflt() missing positional argument(s)` -- the
call never completed, so nothing ever marshalled a result. Measured both ways
in one session, same reduction, same tree, compiler stashed and rebuilt to get
the control (pre-fix `55cdf94233a9`, post-fix `54fa192dc21f`).

That is the honest shape of it: the defaults fix is a strict improvement that
made these calls RUN, and running them is what exposed the layer underneath.

## Repro

A package, because the receiver must have no static type at the call site --
which is what puts the call on the run-time path at all. `early.py` is parsed
first and declares nothing named `m_dflt`, so the scan finds no candidate,
warns, and defers to `pydyn_meth2`.

`pkg/early.py`:

```python
class Sampler:
    def __init__(self, g=None):
        self.g = g

    def t(self):
        return self.g.m_dflt(1, 2)
```

`pkg/late.py` -- vary ONLY the return:

```python
class Grid:
    def m_dflt(self, x, z, outside=77.5):
        return "CONST"          # ...and the variants in the table
```

`pkg/__init__.py`:

```python
from .early import Sampler
from .late import Grid


def run():
    print(Sampler(Grid()).t())
```

## The table

Call site held fixed at `self.g.m_dflt(1, 2)`; only the callee's return varies.

| callee returns | CPython | pxx @ 54fa192dc21f | pxx pre-fix |
| --- | --- | --- | --- |
| `"CONST"` | `CONST` | **TypeError: expected a number, got str** | missing-arg |
| `"d %r %r %r" % (x, z, outside)` | `d 1 2 77.5` | **TypeError: expected a number, got str** | missing-arg |
| `"d " + str(x) + " " + str(outside)` | `d 1 77.5` | **TypeError: expected a number, got str** | missing-arg |
| `outside` (a float, 77.5) | `77.5` | **77** | missing-arg |
| `42` | `42` | `42` | missing-arg |

Readings:

1. **The int row is the trap.** It is correct, it is the row anyone writes
   first, and it is correct for the wrong reason -- the value survives because
   the coercion is to its own type. An expected value that collides with the
   failure value is a row that cannot fail, and `42` is exactly that.
2. **The float row is the one that says what is happening.** `77.5 -> 77` is
   not a failed conversion, it is a SUCCESSFUL one to the wrong type. The
   string row is the same coercion meeting a value it cannot take, which is
   why it gets a diagnostic and the float row does not.
3. **It is not arity and it is not the callee's body.** Both were varied and
   neither moves it: 2 and 3 arguments behave the same, and a constant string
   fails exactly as a formatted one does.
4. **A MEASUREMENT THAT REACHED THE SUBJECT BY THE WRONG ROUTE SAID THIS WAS
   FINE.** A six-row matrix driven through a tuple of BOUND METHODS
   (`for tag, fn in (("a", s.a), ...)`) passed all six. A bound-method value is
   a different dispatch path, so the probe never reached the one under test --
   isolation guards the run, not the route. The rows above are called directly.

## Where to look

`PyMakeDynMethCall` tags its AN_CALL `tyVariant` and sets `LastExprTk` to
match, so the node is right when it is built. Suspect the RETURN typing of the
enclosing `def` (the value is `return`ed straight out of `t`), or the
assignment/print context narrowing a variant-typed call result. The float row
is the cheap discriminator -- anything that prints 77 has already chosen an
integer.

## Gate

`make test-nilpy` + self-host byte-identical, plus a `.npy` carrying the five
rows above with expectations from CPython. **The float row and a string row are
both required**; an int-only fixture passes on the unfixed compiler.

## Log
- 2026-09-14 -- filed while fixing the dynamic-default-signature bug, whose fix
  is what made the path reachable. Control measured against a stashed tree.
- 2026-09-21 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit c63455470.
