---
track: N
prio: 75
type: bug
blocked-by: []
summary: "`self.m(1, ui.ROW)` where `ui` is an imported MODULE gives `error: undefined variable (ui)`. The same argument inside any expression (`b=1 + ui.ROW`) compiles, and the same bare argument to a PLAIN FUNCTION compiles — it is a method/constructor call's argument path that resolves a bare `mod.ATTR` as a variable rather than as a module alias. THIS IS THE WALL ON THE lekkerzeilen CLOSURE (goal 4), reached 2026-09-12 at app.py:2959 (`leading=ui.ROW`) after the extended-slice fix moved the closure 599 lines. 29 `ui.` sites in app.py; also hits any `from . import (a, b, c)` module used this way."
---

# A bare `mod.ATTR` as a whole argument to a method is undefined

Found 2026-09-12 while walking the lekkerzeilen closure. Reduced to 11 lines:

```python
# pkg/ui.py:   PAD = 4 / ROW = 11
from . import ui

class App:
    def m(self, a, b=0, c=0):
        print(a, b, c)

    def go(self):
        self.m(1, b=ui.ROW)     # pascal26:8: error: undefined variable (ui)

App().go()
```

## What the probes separate

Measured against `compiler/pascal26` at `82215bad2750`:

| shape | result |
| --- | --- |
| `self.m(1, b=ui.ROW)` | **error: undefined variable (ui)** |
| `self.m(1, ui.ROW)` — positional | **error** |
| `self.m(1, ui.PAD, c=ui.ROW)` | **error** |
| `o = App(); o.m(1, b=ui.ROW)` — local receiver | **error** |
| `self.m(1, b=1 + ui.ROW)` — inside an expression | ok |
| `self.m(1, b=7)` / `b=z` (a local) | ok |
| `write(1, leading=ui.ROW)` — a PLAIN FUNCTION | ok |

So it is **not** about keyword arguments — that was the first hypothesis and the
positional row refutes it. The discriminator is a **bare `mod.ATTR` occupying a
whole argument** at a method/constructor call site. Wrapping it in any operator
moves it onto the ordinary expression path, which resolves the module alias
correctly; that is also why it survived so long, since most arguments are
expressions.

## Where to look

The method-call argument path parses a bare identifier specially — the
overload/methodref probe described in CLAUDE.md under "A SPECULATIVE PARSE AND
THE COMMITTED ONE CAN DISAGREE" (`ad7c03b03`, a bare METHOD name in argument
position) lives in the same place. A module alias is the sibling case: the
probe's reference door resolves `ui` against variables and user classes and
never asks the unit-alias table. Check the AST before blaming the lowering —
`PXXDBG=a.ast:<proc>` — because the failing read and the committed parse may
not be the same reading.

## A second pointer, and it names the likely mechanism

`undefined variable (<receiver>)` — the receiver rather than the attribute — is
the signature of a RECEIVER-resolution miss, and `compiler/pyparser.inc:1036`
records the same shape from a different cause: a class ALIAS resolved to the
right row and was then rejected by an exactness test that compared the declared
name against what the user wrote. The note there is worth reading before
reducing further, because it is the same diagnostic produced by a lookup that
found something and discarded it — not by a lookup that found nothing. Whether
a MODULE alias fails the same way is unmeasured; that is the first thing to
check, and `PXXDBG=a.ast:<proc>` on the failing method answers it without a
self-compile.

## Gate

A `.npy` under `test/nilpy_units` with a module constant read four ways: bare
positional, bare keyword, inside an expression, and through a plain function —
the last two are reach-checks that already pass, so if they fail the harness is
not reaching the fixture. The PINNED compiler must refuse the bare rows, which
is the positive control.
