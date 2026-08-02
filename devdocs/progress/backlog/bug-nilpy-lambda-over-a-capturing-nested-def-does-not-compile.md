---
track: N
prio: 50
type: bug
summary: "`def outer(base): def add(v): return v+base; g = lambda: add(10)` fails to COMPILE with `undefined variable (add)` — the transitive-capture path PyParseLambdaStub documents does not fire for this shape. Pre-existing, and independent of the body's shape."
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
