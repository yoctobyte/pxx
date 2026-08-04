---
track: N
prio: 50
type: bug
summary: "`def outer(base): def add(v): return v+base; g = lambda: add(10)` fails to COMPILE with `undefined variable (add)` — the transitive-capture path PyParseLambdaStub documents does not fire for this shape. Pre-existing, and independent of the body's shape."
status: done
owner: claude-AN
---

# a lambda over a sibling nested def that captures does not compile

- **Type:** bug (NilPy — compile error on valid code) — **Track N**
- **Found:** 2026-08-03 while widening the lambda-lift predicate
  ([[bug-nilpy-lambda-body-expression-around-a-call-cannot-call-a-def]]).
  **Pre-existing:** reproduced on `stable_linux_amd64/default/pinned`.

## Measured

```python
def outer(base):
    def add(v):
        return v + base
    g = lambda: add(10)
    return g()
print(outer(5))          # CPython 15
```

```
pascal26:4: error: undefined variable (add)
```

Identical on pinned, so it is not new. The failure does not depend on the
lambda body's shape: `lambda: add(10)` (a bare call, which the lift predicate
accepted long before the widening) fails exactly the same way.

## Why it is worth a ticket of its own

`PyParseLambdaStub`'s own comment says this case is handled:

> TRANSITIVE capture, the same rule a nested def already follows: the name is a
> sibling NESTED DEF, and calling it forwards ITS captures — which this lambda
> must therefore hold too. songformatter's redraw is exactly this:
> `cv.after(120, lambda: draw(cv.winfo_width()))`, where `draw` captures `self`

So the machinery exists and is exercised by real code — `self` capture through a
sibling nested def works. What fails here is capturing an enclosing
**parameter** (`base`) rather than `self`. Whatever distinguishes the two is the
bug, and the comment above is the place to start: `PyQualifyNested` /
`PyCapCount` resolve the sibling by its qualified name, and `base` has to reach
the lambda through `add`'s capture list.

## Note for whoever takes it

The widening in the sibling ticket moved this shape from a RUN-time failure
(`pyeval: unknown call: add()`, for the `add(10) + 1` spelling, which used to
fall to the interpreter) to this COMPILE-time error — the same error the bare
`add(10)` spelling already gave. That is consistency, not a new fault, and it is
recorded on that ticket. But it does mean a program that merely *built* before,
without ever invoking such a lambda, now fails to build. That is the whole
practical cost of this ticket staying open.

## Gate

A `.npy` diffed against CPython: the repro; the same with the lambda capturing
the parameter directly (`lambda: base + 1`, which should already work, as a
control); the documented `self`-through-a-sibling-def case as the other control;
and both lambda body shapes (bare call and expression-around-a-call).


## Resolved 2026-08-04 — it was never about capture

The ticket's framing ("what fails here is capturing an enclosing **parameter**
rather than `self`") is wrong, and the measurement that shows it is one line:

| shape | before |
| --- | --- |
| `g = lambda: add(10)`, `add` captures `base` | undefined variable (add) |
| `g = lambda: add(10)`, `add` captures **NOTHING** | **undefined variable (add)** |
| `call(lambda: add(10))` (argument position) | undefined variable (add) |
| `g = lambda: top_level(10)` | works |
| `def use(): return add(10)` (nested def, not lambda) | works |

A **non-capturing** sibling fails identically, so capture is not the axis at
all. The axis is only *"is the callee a sibling NESTED def"*.

### Cause: the lambda queue did not carry its nest prefix

A lifted lambda's body is compiled by `PyDrainPendingLambdas`, which runs after
the enclosing def's epilogue — by which point `PyNestPrefix` has been restored
to the *enclosing* scope's value. `PyQualifyNested` therefore had nothing to
qualify with and could not turn `add` into `outer.add`, so the name did not
resolve.

The nested-def queue sitting immediately beside it already solves this: it
records `PyPendNestPfx` per entry and restores it during its own drain. The
lambda queue now records `PyPendLamPfx` the same way, at both queue sites (the
parsed lambda and the hand-built callable-value wrapper), and restores it around
`PyCompileLambdaBody`. Symmetric with the code five lines above it.

### A shape that moved from LOUD to SILENT, deliberately, and its ticket

`class C: def run(self): def draw(v): return v + self.n; g = lambda: draw(10)`
used to fail to compile ("unresolved forward: draw"). It now compiles and
returns `None` where CPython returns 17.

That is a real downside and is not hidden: it is the **pre-existing** defect
[[bug-nilpy-nested-def-capturing-self-called-from-a-sibling-returns-nothing]],
which needs no lambda to reproduce and prints an empty line on `pinned` today:

```python
class C:
    def __init__(self): self.n = 7
    def run(self):
        def draw(v): return v + self.n
        def use():   return draw(10)
        return use()
```

So the lambda spelling now behaves exactly like the equivalent non-lambda
spelling, which is consistency rather than a new fault — and the separate ticket
carries a repro that is much easier to work on than the one it was found
through. The trade is seven lambda shapes made correct against one shape that
was already broken in its plain spelling.

### Verified

`test/test_nilpy_lambda_sibling_def.npy`, wired into `make test-nilpy`: all four
failing shapes (non-capturing, capturing, expression-around-the-call, argument
position), the three controls the ticket's gate asked for, and the method case
whose sibling does NOT capture `self`. Diffed against CPython, identical.
`tools/gate.sh quick` GREEN, self-host byte-identical.

## Log
- 2026-08-04 — resolved.
- 2026-08-04 — resolved, commit e4477b8f6.
