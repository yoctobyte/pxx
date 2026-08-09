---
prio: 40
track: N
type: bug
blocked-by: []
---

# A lambda whose body is another lambda dies at RUN time

- **Type:** bug (NilPy) — **Track N**
- **Found:** 2026-08-09 by a differential sweep of closures and nested defs.
- **Owner:** —

```python
add = lambda a: lambda b: a + b
print(add(3)(4))        # CPython 7
                        # pxx    pyeval: name not defined: lambda   (exit 1)
```

## Narrowed

| shape | result |
| --- | --- |
| `lambda a: lambda b: a + b` | **runtime failure** |
| `def outer(a): return lambda b: a + b` | works |
| `lambda a: a + 1` | works |

So it is exactly a lambda whose BODY is a lambda. The message comes from
`pyeval` — the inner lambda's source text reaches the interpreter, which has no
`lambda` keyword of its own.

## Not a surprise, but not tracked either

[[bug-nilpy-lambda-body-expression-around-a-call-cannot-call-a-def]] (done)
records that its step 2 — "subscripts, nested lambdas, comprehensions one at a
time" — was **deliberately not taken**, because those shapes had not been
measured against the capture scan under the lift predicate. So this is a known
unhandled shape; what it did not have is a ticket saying what it costs, which
is a runtime failure rather than a slow path.

It sits under [[feature-nilpy-lambda-compiled-closure]] (lambdas are interpreted
rather than compiled) but is worth its own row because the failure is not
performance: the program dies.

## Two routes

1. **Extend the lift predicate to a lambda-bodied lambda.** Two of the three
   questions are already answered, by reading rather than guessing:

   - **`PyLambdaTokText` CAN render it.** `lambda` lexes as a `tkIdent` in
     NilPy (the parser tests it with `CaseEqual(GetTokenStr(j+1), 'lambda')`),
     and `tkIdent` renders as its own text. So the unrenderable-token hazard
     that gates this predicate is not what stops the nested case.
   - **The predicate's "body must contain a CALL" requirement is what stops
     it.** `lambda a: lambda b: a + b` has no call anywhere in the outer body,
     so it is never lifted and falls to the interpreter — which is where the
     error comes from. That requirement exists because "a body without a call
     already works through the pyeval closure, and lifting it would be a
     behaviour change for no gain" — an assumption that is simply false for
     this shape, since pyeval cannot run it at all.
   - **Still open:** whether the capture scan sees the INNER lambda's free
     variables (here `a`, the outer's parameter). That is the part the done
     ticket said had not been measured.
2. **Teach `pyeval` the `lambda` keyword**, so the interpreted path stops being
   a dead end. Wider, and it helps every other shape that falls back.

Route 1 is narrower; route 2 removes a whole class of "falls back and then
fails". Whichever: the currying idiom is common in argument-adapter code
(`key=lambda a: lambda b: ...` shows up in callback plumbing).

## Gate
`.npy` diffed against CPython: the curried form invoked in one go
(`add(3)(4)`) and in two steps (`f = add(3); f(4)`), the inner lambda capturing
the outer's parameter, a three-level curry, and the two shapes that already work
as controls.
